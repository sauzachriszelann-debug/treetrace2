from unittest.mock import AsyncMock
import pytest
from app.schemas.photo_observations import normalize_observations
from app.services import ai_identify


def complete(**overrides):
    return dict(photo_assessed=True, parts_visible=['bark', 'leaves'],
                bark_appearance='Ridged', bark_evidence='Deep vertical grooves.',
                visible_signs=[], no_visible_signs=True, needs_closeup=False, **overrides)


def test_bark_texture_never_sets_health_or_disease():
    result = normalize_observations(complete())
    assert result['bark_appearance'] == 'Ridged'
    assert result['no_visible_signs'] is True
    assert not {'health_status', 'disease', 'treatment'} & result.keys()


@pytest.mark.parametrize('raw', [None, {}, {'photo_assessed': 'true'},
                               {'photo_assessed': True, 'parts_visible': []}])
def test_missing_evidence_does_not_mean_healthy(raw):
    result = normalize_observations(raw)
    assert result['status'] in ('not_assessed', 'unclear')
    assert result['no_visible_signs'] is False
    assert result['bark_appearance'] == 'Unclear'


def test_unseen_bark_and_disease_labels_are_discarded():
    raw = complete()
    raw.update(parts_visible=['leaves'], visible_signs=[
        {'code': 'Root Rot', 'evidence': 'guess'},
        {'code': 'leaf_holes', 'evidence': 'Several visible holes.'}])
    result = normalize_observations(raw)
    assert result['bark_appearance'] == 'Unclear'
    assert [s['code'] for s in result['visible_signs']] == ['leaf_holes']
    assert result['no_visible_signs'] is False


def test_invalid_findings_do_not_become_absence_of_symptoms():
    raw = complete()
    raw['visible_signs'] = [{'code': 'Disease', 'evidence': 'guess'}]
    assert normalize_observations(raw)['no_visible_signs'] is False


@pytest.mark.parametrize('gemini_species,expected', [('Alpha beta', True), ('Gamma delta', False)])
def test_reference_photos_follow_final_species(monkeypatch, gemini_species, expected):
    monkeypatch.setattr(ai_identify, '_plantnet', AsyncMock(return_value={
        'common_name': 'Example', 'scientific_name': 'Alpha beta',
        'confidence': 'Low', 'match_images': ['https://example.test/alpha.jpg']}))
    monkeypatch.setattr(ai_identify, '_gemini', AsyncMock(return_value={
        'common_name': 'Example', 'scientific_name': gemini_species}))
    monkeypatch.setattr(ai_identify, '_gbif_match', AsyncMock(return_value=None))
    monkeypatch.setattr(ai_identify, '_enrich', lambda result: result)
    coro = ai_identify._pipeline(b'photo', 'photo', 'image/jpeg')
    try:
        coro.send(None)
    except StopIteration as done:
        result = done.value
    finally:
        coro.close()
    assert bool(result['match_images']) is expected
    assert result['reference_scientific_name'] == (gemini_species if expected else None)


@pytest.mark.parametrize('local', [True, False])
def test_identify_endpoint_returns_validated_observations(monkeypatch, local):
    from tempfile import SpooledTemporaryFile
    from types import SimpleNamespace
    from fastapi import UploadFile
    from starlette.datastructures import Headers
    from app.api.routes import identify
    from app.models.user import UserRole
    payload = {'common_name': 'Example', 'scientific_name': 'Alpha beta'}
    if not local:
        payload['photo_observations'] = complete()
    monkeypatch.setattr(identify, '_get_local_species_classifier',
                        lambda: ((lambda _: payload), lambda: {'ready': True}) if local else (None, None))
    monkeypatch.setattr(identify, '_pipeline_with_status', AsyncMock(return_value=payload))
    stream = SpooledTemporaryFile(max_size=1000)
    stream.write(b'photo')
    stream.seek(0)
    upload = UploadFile(file=stream, filename='tree.jpg', headers=Headers({'content-type': 'image/jpeg'}))
    coro = identify.identify_tree(upload, current_user=SimpleNamespace(role=UserRole.field_worker), db=None)
    try:
        coro.send(None)
    except StopIteration as done:
        result = done.value
    finally:
        coro.close()
        stream.close()
    assert result['photo_observations']['status'] == ('not_assessed' if local else 'observed')
    assert 'health_status' not in result
