import io
import json
import zipfile
from datetime import datetime, timezone
from unittest.mock import Mock
import pytest
from PIL import Image
from app.api.routes import training_data, identify
from app.models.user import User, UserRole
from app.models.unknown_species import UnknownSpecies
from app.models.tree_submission import TreeSubmission
from app.services import training_data as service
BASE = '/api/admin/training-data'
PHOTO = 'https://project.supabase.test/storage/v1/object/public/tree-photos/tree.jpg'

@pytest.fixture(autouse=True)
def routes(api_app, monkeypatch):
    api_app.include_router(training_data.router, prefix=BASE)
    api_app.include_router(identify.router, prefix='/api/ai')
    monkeypatch.setattr(service.settings, 'SUPABASE_URL', 'https://project.supabase.test')
    monkeypatch.setattr(service.settings, 'SUPABASE_BUCKET_PHOTOS', 'tree-photos')

def example(db, reviewer=None, **values):
    submitter = User(full_name='Recorder', email=f'recorder-{db.query(User).count()}@example.test', hashed_password='test', role=UserRole.field_worker)
    db.add(submitter); db.flush()
    data = dict(photo_url=PHOTO, reviewed=True, identified_as='Narra', identified_scientific_name='Pterocarpus indicus', submitted_by_id=submitter.id,
        reviewed_by_id=reviewer.id if reviewer else None, reviewed_at=datetime.now(timezone.utc) if reviewer else None,
        ai_candidates=json.dumps([{'common_name': 'Mango', 'scientific_name': 'Mangifera indica', 'confidence_percent': 21.16}]),
        submitter_notes='PRIVATE NOTE', review_notes='PRIVATE REVIEW')
    data.update(values)
    row = UnknownSpecies(**data); db.add(row); db.commit(); return row

def photo():
    out = io.BytesIO(); Image.new('RGB', (30, 30), 'green').save(out, format='JPEG'); return out.getvalue()

def test_auth_required(client):
    assert client.get(BASE).status_code == 401
    assert client.get(BASE + '/manifest.csv').status_code == 401
    assert client.post(BASE + '/export', json={'ids': ['species:1']}).status_code == 401

@pytest.mark.parametrize('role', [UserRole.citizen, UserRole.field_worker])
def test_admin_only(client, auth_as, role):
    auth_as(role)
    assert client.get(BASE).status_code == 403
    assert client.get(BASE + '/manifest.csv').status_code == 403
    assert client.post(BASE + '/export', json={'ids': ['species:1']}).status_code == 403

def test_correction_and_audit_are_automatic_without_private_notes(client, admin_user, db_session):
    row = example(db_session, admin_user)
    data = client.get(BASE).json()
    assert data['total'] == data['ready'] == data['corrected'] == 1
    value = data['items'][0]
    assert value['id'] == f'species:{row.id}' and value['original_common_name'] == 'Mango'
    assert value['confidence_percent'] == 21.16 and value['confirmed_scientific_name'] == 'Pterocarpus indicus'
    assert value['reviewer_name'] == admin_user.full_name and value['reviewed_at']
    assert 'PRIVATE' not in str(data) and admin_user.email not in str(data)

def test_unresolved_and_legacy_are_not_exportable(client, admin_user, db_session):
    example(db_session, admin_user, reviewed=False)
    example(db_session, admin_user, identified_as=None)
    legacy = example(db_session)
    data = client.get(BASE).json()
    assert data['total'] == 1 and data['ready'] == 0
    assert client.post(BASE + '/export', json={'ids': [f'species:{legacy.id}']}).status_code == 422

def test_confirm_records_reviewer_and_reopen_removes_example(client, admin_user, db_session):
    row = example(db_session, reviewed=False)
    result = client.put(f'/api/ai/unknown-species/{row.id}/review', json={'reviewed': True, 'identified_as': 'Narra', 'identified_scientific_name': 'Pterocarpus indicus'})
    assert result.status_code == 200, result.text
    assert result.json()['reviewed_by_id'] == admin_user.id and result.json()['reviewed_at']
    assert client.get(BASE).json()['ready'] == 1
    assert client.put(f'/api/ai/unknown-species/{row.id}/review', json={'reviewed': False}).status_code == 200
    assert client.get(BASE).json()['total'] == 0

def test_approved_conversion_is_one_example_with_final_label(client, admin_user, db_session):
    row = example(db_session, admin_user)
    db_session.add(TreeSubmission(status='approved', source_unknown_species_id=row.id, photo_url=PHOTO, common_name='Mango', scientific_name='Mangifera indica',
        review_overrides=json.dumps({'common_name': 'Narra', 'scientific_name': 'Pterocarpus indicus'}),
        reviewed_by_id=admin_user.id, reviewed_at=datetime.now(timezone.utc), submitted_by_id=row.submitted_by_id))
    db_session.commit()
    data = client.get(BASE).json()
    assert data['total'] == data['ready'] == 1
    assert data['items'][0]['id'].startswith('submission:') and data['items'][0]['confirmed_common_name'] == 'Narra'

def test_conflicting_labels_on_same_photo_not_ready(client, admin_user, db_session):
    example(db_session, admin_user)
    example(db_session, admin_user, identified_as='Mango', identified_scientific_name='Mangifera indica')
    assert client.get(BASE).json()['ready'] == 0

def test_zip_deduplicates_bytes_and_preserves_source_ids(client, admin_user, db_session, monkeypatch):
    first = example(db_session, admin_user)
    second = example(db_session, admin_user, photo_url=PHOTO.replace('tree.jpg','copy.jpg'))
    monkeypatch.setattr(service, 'download_photo', lambda url: (photo(), 'jpg'))
    response = client.post(BASE + '/export', json={'ids': [f'species:{first.id}', f'species:{second.id}']})
    assert response.status_code == 200 and response.headers['x-exported-images'] == '1'
    with zipfile.ZipFile(io.BytesIO(response.content)) as archive:
        assert len([n for n in archive.namelist() if n.startswith('images/')]) == 1
        manifest = archive.read('manifest.csv').decode()
        assert 'Pterocarpus indicus' in manifest and f'species:{first.id}' in manifest and f'species:{second.id}' in manifest
        assert 'PRIVATE' not in manifest

def test_same_bytes_with_conflicting_labels_are_excluded(client, admin_user, db_session, monkeypatch):
    first = example(db_session, admin_user)
    second = example(db_session, admin_user, photo_url=PHOTO.replace('tree.jpg','other.jpg'), identified_as='Mango', identified_scientific_name='Mangifera indica')
    monkeypatch.setattr(service, 'download_photo', lambda url: (photo(), 'jpg'))
    response = client.post(BASE + '/export', json={'ids': [f'species:{first.id}', f'species:{second.id}']})
    with zipfile.ZipFile(io.BytesIO(response.content)) as archive:
        assert not any(n.startswith('images/') for n in archive.namelist())
        assert len(json.loads(archive.read('export_report.json'))['failed_or_conflicting']) == 2

def test_failed_photo_reported_not_false_success(client, admin_user, db_session, monkeypatch):
    row = example(db_session, admin_user)
    monkeypatch.setattr(service, 'download_photo', Mock(side_effect=ValueError('missing')))
    response = client.post(BASE + '/export', json={'ids': [f'species:{row.id}']})
    assert response.headers['x-exported-images'] == '0'
    with zipfile.ZipFile(io.BytesIO(response.content)) as archive:
        assert json.loads(archive.read('export_report.json'))['failed_or_conflicting']

@pytest.mark.parametrize('url', ['http://127.0.0.1/a','https://project.supabase.test.evil.test/storage/v1/object/public/tree-photos/a.jpg',
    'https://project.supabase.test:bad/storage/v1/object/public/tree-photos/a.jpg','https://project.supabase.test/storage/v1/object/public/tree-photos/../private.jpg'])
def test_untrusted_export_sources_blocked(url):
    assert not service.photo_is_exportable(url)
    with pytest.raises(ValueError): service.download_photo(url)

def test_search_pagination_and_csv(client, admin_user, db_session):
    example(db_session, admin_user)
    assert client.get(BASE, params={'q':'Mango','limit':1,'offset':1}).json()['items'] == []
    result = client.get(BASE + '/manifest.csv')
    assert 'Pterocarpus indicus' in result.text and 'PRIVATE' not in result.text and admin_user.email not in result.text
    assert client.post(BASE + '/export', json={'ids':['species:1'] * 21}).status_code == 422


def test_real_downloader_validates_photo_and_rejects_redirect(monkeypatch):
    import httpx
    original_client = httpx.Client
    transport = httpx.MockTransport(lambda request: httpx.Response(200, content=photo()))
    monkeypatch.setattr(service.httpx, 'Client', lambda **kwargs: original_client(transport=transport, **kwargs))
    data, extension = service.download_photo(PHOTO)
    assert data == photo() and extension == 'jpg'
    transport = httpx.MockTransport(lambda request: httpx.Response(302, headers={'location': 'http://127.0.0.1/private'}))
    with pytest.raises(httpx.HTTPStatusError): service.download_photo(PHOTO)


def test_real_downloader_rejects_non_image_and_oversize(monkeypatch):
    import httpx
    original_client = httpx.Client
    for content in [b'not an image', b'x' * 5_000_001]:
        transport = httpx.MockTransport(lambda request: httpx.Response(200, content=content))
        monkeypatch.setattr(service.httpx, 'Client', lambda **kwargs: original_client(transport=transport, **kwargs))
        with pytest.raises((ValueError, OSError)): service.download_photo(PHOTO)


def test_csv_labels_are_not_spreadsheet_formulas():
    result = service.manifest_csv([{'confirmed_common_name': '=1+1'}])
    assert "'=1+1" in result
