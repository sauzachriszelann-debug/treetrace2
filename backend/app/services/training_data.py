"""Read-only reviewed examples and bounded, reproducible photo exports."""
import csv
import hashlib
import io
import json
import math
import re
import warnings
import zipfile
from urllib.parse import urlparse, unquote

import httpx
from PIL import Image
from app.core.config import settings
from app.models.tree_submission import TreeSubmission
from app.models.unknown_species import UnknownSpecies
from app.models.user import User
from app.schemas.training_data import TrainingExample


def _object(raw):
    try:
        return json.loads(raw) if isinstance(raw, str) else raw
    except (ValueError, TypeError):
        return None


def photo_is_exportable(url):
    if not url or not settings.SUPABASE_URL:
        return False
    try:
        value, configured = urlparse(url), urlparse(settings.SUPABASE_URL)
        prefix = f'/storage/v1/object/public/{settings.SUPABASE_BUCKET_PHOTOS}/'
        return (value.scheme == 'https' and bool(configured.hostname) and value.hostname == configured.hostname
                and value.port in (None, 443) and not value.username and not value.password
                and unquote(value.path).startswith(prefix)
                and '..' not in unquote(value.path).split('/'))
    except ValueError:
        return False


def _prediction(snapshot, candidates):
    candidate = snapshot if isinstance(snapshot, dict) else {}
    values = _object(candidates)
    if not candidate.get('scientific_name') and isinstance(values, list) and values and isinstance(values[0], dict):
        candidate = values[0]
    score = candidate.get('confidence_percent')
    if score is None:
        fraction = candidate.get('confidence_score', candidate.get('score'))
        if isinstance(fraction, (int, float)) and not isinstance(fraction, bool) and math.isfinite(fraction) and 0 <= fraction <= 1:
            score = fraction * 100
    if not isinstance(score, (int, float)) or isinstance(score, bool) or not math.isfinite(score) or not 0 <= score <= 100:
        score = None
    return candidate.get('common_name'), candidate.get('scientific_name'), score


def reviewed_examples(db):
    # Confirmation and approval already contain the source of truth; no shadow dataset table.
    submissions = db.query(TreeSubmission).filter(TreeSubmission.status.in_(['approved', 'rejected', 'linked'])).all()
    converted = {row.source_unknown_species_id for row in submissions if row.source_unknown_species_id is not None}
    unknowns = db.query(UnknownSpecies).filter(UnknownSpecies.reviewed.is_(True), UnknownSpecies.identified_as.isnot(None)).all()
    unknown_by_id = {row.id: row for row in unknowns}
    records = []
    for row in submissions:
        if row.status != 'approved':
            continue
        overrides = _object(row.review_overrides) or {}
        if not isinstance(overrides, dict):
            overrides = {}
        origin = unknown_by_id.get(row.source_unknown_species_id)
        snapshot = row.scan_profile or (origin.scan_profile if origin else None)
        candidates = row.ai_candidates or (origin.ai_candidates if origin else None)
        records.append((f'submission:{row.id}', row.photo_url,
            overrides.get('common_name', row.common_name), overrides.get('scientific_name', row.scientific_name),
            row.reviewed_by_id, row.reviewed_at, row.submitted_by_id, snapshot, candidates))
    for row in unknowns:
        if row.id in converted or not (row.identified_as or '').strip():
            continue
        records.append((f'species:{row.id}', row.photo_url, row.identified_as, row.identified_scientific_name,
            row.reviewed_by_id, row.reviewed_at, row.submitted_by_id, row.scan_profile, row.ai_candidates))
    reviewer_ids = {row[4] for row in records if row[4] is not None}
    names = dict(db.query(User.id, User.full_name).filter(User.id.in_(reviewer_ids)).all()) if reviewer_ids else {}
    examples = []
    for key, photo, common, scientific, reviewer, reviewed_at, submitter, snapshot, candidates in records:
        common, scientific = (common or '').strip(), (scientific or '').strip()
        original_common, original_sci, confidence = _prediction(snapshot, candidates)
        issues = []
        if not common or not scientific:
            issues.append('Confirmed common and scientific names are required.')
        if reviewer is None or reviewed_at is None or reviewer not in names:
            issues.append('Reviewer/date not recorded. Confirm this species again in Tree Reviews.')
        if reviewer is not None and reviewer == submitter:
            issues.append('An independent reviewer must confirm this example.')
        if not photo_is_exportable(photo):
            issues.append('Photo must be in the configured TreeTrace photo storage.')
        original_label = (original_sci or original_common or '').strip().lower()
        final_labels = {scientific.lower(), common.lower()}
        examples.append(TrainingExample(id=key, photo_url=photo,
            original_common_name=original_common, original_scientific_name=original_sci,
            confidence_percent=confidence, confirmed_common_name=common or None,
            confirmed_scientific_name=scientific or None, reviewer_id=reviewer,
            reviewer_name=names.get(reviewer), reviewed_at=reviewed_at,
            corrected=bool(original_label and original_label not in {'unknown', 'unknown species'} and original_label not in final_labels), issues=issues, ready=not issues))
    # A source photo with contradictory expert labels must not be silently relabelled.
    labels = {}
    for row in examples:
        labels.setdefault(row.photo_url, set()).add((row.confirmed_scientific_name or '').lower())
    for row in examples:
        if row.photo_url and len(labels[row.photo_url]) > 1:
            row.issues.append('This photo has conflicting confirmed labels. Resolve the reviews before export.')
            row.ready = False
    return sorted(examples, key=lambda row: (row.reviewed_at.isoformat() if row.reviewed_at else '', row.id), reverse=True)


MANIFEST_FIELDS = ['id', 'photo_url', 'original_common_name', 'original_scientific_name',
    'confidence_percent', 'confirmed_common_name', 'confirmed_scientific_name',
    'reviewer_id', 'reviewer_name', 'reviewed_at', 'corrected', 'file', 'sha256', 'source_record_ids']

def manifest_csv(rows):
    stream = io.StringIO(newline='')
    writer = csv.DictWriter(stream, fieldnames=MANIFEST_FIELDS, extrasaction='ignore')
    writer.writeheader()
    for row in rows:
        # Avoid spreadsheet formula execution when a reviewed label is opened in Excel.
        writer.writerow({key: ("'" + str(value) if isinstance(value, str) and value.startswith(('=', '+', '-', '@', '\t', '\r')) else value)
                         for key, value in row.items()})
    return stream.getvalue()


def download_photo(url):
    if not photo_is_exportable(url):
        raise ValueError('untrusted_photo_source')
    with httpx.Client(timeout=10, follow_redirects=False) as client:
        with client.stream('GET', url) as response:
            response.raise_for_status()
            data = bytearray()
            for chunk in response.iter_bytes():
                data.extend(chunk)
                if len(data) > 5_000_000:
                    raise ValueError('photo_exceeds_5mb')
    with warnings.catch_warnings():
        warnings.simplefilter('error', Image.DecompressionBombWarning)
        with Image.open(io.BytesIO(data)) as image:
            if image.width * image.height > 25_000_000:
                raise ValueError('photo_dimensions_too_large')
            extension = {'JPEG': 'jpg', 'PNG': 'png', 'WEBP': 'webp'}.get(image.format)
            if extension is None:
                raise ValueError('unsupported_image_format')
            image.verify()
    return bytes(data), extension


def export_archive(examples):
    groups, failures = {}, []
    total_bytes = 0
    for index, example in enumerate(examples):
        try:
            data, extension = download_photo(example.photo_url)
            total_bytes += len(data)
            if total_bytes > 30_000_000:
                failures.extend({'id': row.id, 'reason': 'Export size limit reached. Export fewer photos.'} for row in examples[index:])
                break
            digest = hashlib.sha256(data).hexdigest()
            groups.setdefault(digest, []).append((example, data, extension))
        except (httpx.HTTPError, OSError, ValueError, Image.DecompressionBombError, Image.DecompressionBombWarning):
            failures.append({'id': example.id, 'reason': 'Photo could not be downloaded or validated.'})
    result = io.BytesIO()
    manifest = []
    with zipfile.ZipFile(result, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for digest, items in groups.items():
            if len({item[0].confirmed_scientific_name.strip().lower() for item in items}) > 1:
                failures.extend({'id': item[0].id, 'reason': 'Identical image bytes have conflicting labels.'} for item in items)
                continue
            row, data, extension = items[0]
            folder = re.sub(r'[^a-zA-Z0-9_-]+', '_', row.confirmed_scientific_name).strip('_')[:150] or 'species'
            path = f'images/{folder}/{digest}.{extension}'
            archive.writestr(path, data)
            manifest.append({**row.model_dump(mode='json'), 'file': path, 'sha256': digest,
                             'source_record_ids': '|'.join(item[0].id for item in items)})
        archive.writestr('manifest.csv', manifest_csv(manifest))
        archive.writestr('export_report.json', json.dumps({'requested': len(examples),
            'exported_images': len(manifest), 'failed_or_conflicting': failures}, indent=2))
        archive.writestr('README.txt', 'Expert-confirmed training candidates, not a trained model.\n'
            'Exact duplicate images are grouped by SHA-256; conflicting labels are excluded.\n'
            'Keep photo groups together when splitting data. Keep the existing test set untouched.\n'
            'Review image quality, then retrain and evaluate before replacing the deployed model.\n'
            'The manifest omits account email fields, GPS fields, and private review notes.\n'
            'Original photographs may retain their camera metadata.\n')
    return result.getvalue(), len(manifest), len(failures)
