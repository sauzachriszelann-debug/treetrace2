"""Offline contract tests. These do not establish visual prediction accuracy."""
import base64
import io
from tempfile import SpooledTemporaryFile
from unittest.mock import AsyncMock, Mock

import numpy as np
import pytest
from PIL import Image
from fastapi import HTTPException, UploadFile
from starlette.datastructures import Headers
from app.services import gallery_size_prediction as service
from app.services import ai_identify, dbh_yolo


@pytest.fixture(autouse=True)
def offline(monkeypatch):
    import socket
    monkeypatch.setattr(socket.socket, 'connect', Mock(side_effect=AssertionError('No external network')))
    async def inline_worker(function, *args):
        return function(*args)
    monkeypatch.setattr(service.asyncio, 'to_thread', inline_worker)


def immediate(coroutine):
    """Drive fully mocked awaits without Windows loopback socket/event-loop IO."""
    try:
        coroutine.send(None)
    except StopIteration as result:
        return result.value
    finally:
        coroutine.close()
    raise AssertionError('Unexpected real IO in isolated prediction test')



def memory_file(contents):
    stream = SpooledTemporaryFile(max_size=3_000_000)
    stream.write(contents)
    stream.seek(0)
    return stream


def photo():
    out = io.BytesIO()
    Image.new('RGB', (640, 480), (30, 100, 30)).save(out, format='JPEG')
    return out.getvalue()


@pytest.fixture
def model(monkeypatch):
    monkeypatch.setattr(dbh_yolo, 'runtime_status', lambda: {'ready': True})
    mask = np.zeros((480, 640), dtype=bool)
    mask[30:420, 270:370] = True
    predict = Mock(return_value=[mask])
    monkeypatch.setattr(dbh_yolo, '_predict_masks', predict)
    return predict


def reference():
    return {'assumption': 'Unmeasured tire size; perspective remains uncertain.',
            'reference': {'object': 'visible tire', 'dimension_m': 0.6, 'assumed': True}}


def run():
    return immediate(service.predict_gallery_size(photo(), 'image/jpeg')).model_dump()


def assert_not_measured(result):
    assert result['quality'] == 'unvalidated'
    assert result['validated_accuracy'] is False
    assert not {'dbh_cm', 'height_m', 'distance_m_used', 'carbon_kg'} & result.keys()


def test_model_detects_pixels_and_vision_predicts_separate_units(monkeypatch, model):
    provider = AsyncMock(return_value={
        'base_visible': True, 'top_visible': True,
        'dbh': {'value': 23.2, 'evidence': 'visible trunk and nearby scale cue', **reference()},
        'height': {'value': 9.4, 'evidence': 'visible tree and scale cue', **reference()},
    })
    monkeypatch.setattr(ai_identify, 'gallery_vision_prediction', provider)
    result = run()
    assert result['status'] == 'predicted'
    assert result['predicted_dbh_cm'] == 23
    assert result['predicted_height_m'] == 9
    assert result['trunk_width_px'] == 100  # Not converted to centimetres.
    assert len(result['assumptions']) == 2
    assert '0.6 m' in result['assumptions'][0]
    assert model.call_count == 1
    Image.open(io.BytesIO(base64.b64decode(result['preview_png']))).verify()
    prompt = provider.call_args.args[2]
    assert 'NOT metric scale' in prompt and 'bbox' in prompt
    assert_not_measured(result)


@pytest.mark.parametrize('value', [None, 0, -10, float('nan'), float('inf'), True, '23', 301])
def test_bad_values_never_become_defaults(monkeypatch, model, value):
    monkeypatch.setattr(ai_identify, 'gallery_vision_prediction', AsyncMock(return_value={
        'base_visible': True, 'top_visible': True,
        'dbh': {'value': value, 'evidence': 'cue', **reference()},
        'height': {'value': value, 'evidence': 'cue', **reference()}}))
    result = run()
    assert result['status'] == 'cannot_estimate'
    assert result['predicted_dbh_cm'] is None and result['predicted_height_m'] is None
    assert_not_measured(result)


@pytest.mark.parametrize('base,top,dbh,height', [(True, False, 20, None),
                                              (False, True, None, None),
                                              ('true', True, None, None)])
def test_hidden_parts_are_not_reconstructed(monkeypatch, model, base, top, dbh, height):
    monkeypatch.setattr(ai_identify, 'gallery_vision_prediction', AsyncMock(return_value={
        'base_visible': base, 'top_visible': top,
        'dbh': {'value': 20, 'evidence': 'cue', **reference()}, 'height': {'value': 10, 'evidence': 'cue', **reference()}}))
    result = run()
    assert result['predicted_dbh_cm'] == dbh and result['predicted_height_m'] == height


@pytest.mark.parametrize('raw', [None, [], {}, {'base_visible': True,
    'dbh': {'value': 20, 'evidence': ''}}])
def test_unavailable_or_unsupported_ai_never_fills_sizes(monkeypatch, model, raw):
    monkeypatch.setattr(ai_identify, 'gallery_vision_prediction', AsyncMock(return_value=raw))
    result = run()
    assert result['predicted_dbh_cm'] is None and result['predicted_height_m'] is None
    assert_not_measured(result)


@pytest.mark.parametrize('condition', ['disabled', 'no_trunk', 'clipped', 'broken'])
def test_no_trunk_evidence_never_calls_provider(monkeypatch, model, condition):
    provider = AsyncMock(side_effect=AssertionError('No prediction without trunk'))
    monkeypatch.setattr(ai_identify, 'gallery_vision_prediction', provider)
    if condition == 'disabled':
        monkeypatch.setattr(dbh_yolo, 'runtime_status', lambda: {'ready': False})
    elif condition == 'no_trunk':
        model.return_value = []
    elif condition == 'broken':
        model.side_effect = RuntimeError('unavailable')
    else:
        model.return_value[0][:, :300] = True
    result = run()
    provider.assert_not_called()
    assert result['predicted_dbh_cm'] is None
    assert result['predicted_height_m'] is None


def test_route_requires_authentication():
    from app.api.routes.identify import router
    from app.core.security import get_current_user, oauth2_scheme
    from starlette.requests import Request
    route = next(r for r in router.routes if r.path == '/gallery-size-prediction')
    assert any(d.call is get_current_user for d in route.dependant.dependencies)
    request = Request({'type': 'http', 'headers': [], 'method': 'POST',
                       'path': '/api/ai/gallery-size-prediction'})
    with pytest.raises(HTTPException) as error:
        immediate(oauth2_scheme(request))
    assert error.value.status_code == 401


@pytest.mark.parametrize('mime,contents,status', [('text/plain', b'bad', 400),
    ('image/jpeg', b'', 413), ('image/jpeg', b'x' * 2_000_001, 413)], ids=['bad-type', 'empty', 'too-large'])
def test_route_rejects_bad_upload_before_spending_quota(monkeypatch, mime, contents, status):
    from app.api.routes import identify
    quota = Mock()
    monkeypatch.setattr(identify, 'enforce_ai_limit', quota)
    file = UploadFile(memory_file(contents), headers=Headers({'content-type': mime}))
    with pytest.raises(HTTPException) as error:
        immediate(identify.gallery_size_prediction(file, object(), object()))
    assert error.value.status_code == status
    quota.assert_not_called()


def test_route_preserves_quota_and_prediction_contract(monkeypatch, model):
    from app.api.routes import identify
    quota = Mock()
    monkeypatch.setattr(identify, 'enforce_ai_limit', quota)
    monkeypatch.setattr(ai_identify, 'gallery_vision_prediction', AsyncMock(return_value=None))
    file = UploadFile(memory_file(photo()), headers=Headers({'content-type': 'image/jpeg'}))
    user, db = object(), object()
    result = immediate(identify.gallery_size_prediction(file, user, db))
    quota.assert_called_once_with(user, db)
    assert_not_measured(result.model_dump())


def test_missing_key_does_not_call_network(monkeypatch):
    monkeypatch.setattr(ai_identify, 'GEMINI_API_KEY', '')
    with pytest.raises(ai_identify.GalleryVisionError) as error:
        immediate(ai_identify.gallery_vision_prediction('fake', 'image/jpeg', 'prompt'))
    assert error.value.code == 'missing_key'


@pytest.mark.parametrize('status,text', [(200, '{"base_visible": false}'),
                                       (200, 'not JSON'), (429, '')])
def test_gallery_provider_uses_isolated_prompt_without_numeric_defaults(monkeypatch, status, text):
    from types import SimpleNamespace
    requests = []
    class Client:
        async def __aenter__(self):
            return self
        async def __aexit__(self, *args):
            return False
        async def post(self, url, json):
            requests.append(json)
            return SimpleNamespace(status_code=status, json=lambda: {
                'candidates': [{'content': {'parts': [{'text': text}]}}]})
    monkeypatch.setattr(ai_identify, 'GEMINI_API_KEY', 'test-only')
    monkeypatch.setattr(ai_identify, '_gemini_candidate_models', lambda: ['test-model', 'other-model'])
    monkeypatch.setattr(ai_identify.httpx, 'AsyncClient', lambda **kwargs: Client())
    if status == 200 and text.startswith('{'):
        result = immediate(ai_identify.gallery_vision_prediction('fake', 'image/jpeg', 'isolated gallery prompt'))
        assert result == {'base_visible': False}
    else:
        with pytest.raises(ai_identify.GalleryVisionError) as error:
            immediate(ai_identify.gallery_vision_prediction('fake', 'image/jpeg', 'isolated gallery prompt'))
        assert error.value.code == ('quota_exceeded' if status == 429 else 'invalid_response')
    assert len(requests) == 1
    assert requests[0]['contents'][0]['parts'][0]['text'] == 'isolated gallery prompt'
    assert requests[0]['generationConfig']['responseMimeType'] == 'application/json'


@pytest.mark.parametrize('body,code', [
    ({'candidates': []}, 'empty_response'),
    ({'promptFeedback': {'blockReason': 'SAFETY'}}, 'blocked_response'),
    ({'candidates': [{'finishReason': 'MAX_TOKENS'}]}, 'truncated_response'),
    ({'candidates': [{'finishReason': 'SAFETY'}]}, 'blocked_response'),
    ({'candidates': [{'content': {'parts': [{'thought': True, 'text': 'private'}]}}]}, 'empty_response'),
    ({'candidates': [{'content': {'parts': [{'text': '[]'}]}}]}, 'invalid_response'),
])
def test_response_diagnostics_are_specific(body, code):
    with pytest.raises(ai_identify.GalleryVisionError) as error:
        ai_identify._parse_gallery_vision_response(body)
    assert error.value.code == code


def test_response_parser_joins_text_parts_and_skips_thoughts():
    body = {'candidates': [{'finishReason': 'STOP', 'content': {'parts': [
        {'thought': True, 'text': 'not user output'}, {'inlineData': {}},
        {'text': '```json\n{"base_'}, {'text': 'visible": false}\n```'}]}}]}
    assert ai_identify._parse_gallery_vision_response(body) == {'base_visible': False}


@pytest.mark.parametrize('code', ['quota_exceeded', 'timeout', 'access_denied',
                                'invalid_response', 'truncated_response'])
def test_safe_failure_reason_reaches_card_without_numbers(monkeypatch, model, code):
    monkeypatch.setattr(ai_identify, 'gallery_vision_prediction',
                        AsyncMock(side_effect=ai_identify.GalleryVisionError(code)))
    result = run()
    assert result['status'] == 'unavailable'
    assert result['error_code'] == code
    assert result['reason'] == ai_identify.GalleryVisionError.REASONS[code]
    assert result['trunk_detected'] is True and result['preview_png']
    assert result['predicted_dbh_cm'] is None and result['predicted_height_m'] is None


@pytest.mark.parametrize('bad', [{}, {'object': 'tire', 'dimension_m': -1, 'assumed': True},
    {'object': '', 'dimension_m': .6, 'assumed': True},
    {'object': 'tire', 'dimension_m': .6, 'assumed': False}])
def test_prediction_requires_a_disclosed_reference_assumption(monkeypatch, model, bad):
    monkeypatch.setattr(ai_identify, 'gallery_vision_prediction', AsyncMock(return_value={
        'base_visible': True, 'top_visible': True,
        'dbh': {'value': 20, 'evidence': 'cue', 'assumption': 'uncertain', 'reference': bad},
        'height': {'value': 10, 'evidence': 'cue', 'assumption': 'uncertain', 'reference': bad}}))
    result = run()
    assert result['status'] == 'cannot_estimate'
    assert result['predicted_dbh_cm'] is None and result['predicted_height_m'] is None
    assert result['assumptions'] == []


@pytest.mark.parametrize('failure,code,expected_calls', [
    (401, 'access_denied', 1), (403, 'access_denied', 1),
    (400, 'request_rejected', 2), (404, 'model_unavailable', 2),
    (429, 'quota_exceeded', 1), (503, 'provider_busy', 1),
    ('timeout', 'timeout', 1), ('connect', 'connection_error', 1)])
def test_transport_failures_are_controlled_and_do_not_leak_secrets(monkeypatch, failure, code, expected_calls):
    import httpx
    from types import SimpleNamespace
    calls = []
    class Client:
        async def __aenter__(self):
            return self
        async def __aexit__(self, *args):
            return False
        async def post(self, url, json):
            calls.append(True)
            if failure == 'timeout':
                raise httpx.ReadTimeout('do-not-expose-secret-url')
            if failure == 'connect':
                raise httpx.ConnectError('do-not-expose-secret-url')
            return SimpleNamespace(status_code=failure)
    monkeypatch.setattr(ai_identify, 'GEMINI_API_KEY', 'do-not-expose-secret-key')
    monkeypatch.setattr(ai_identify, '_gemini_candidate_models', lambda: ['primary', 'secondary'])
    monkeypatch.setattr(ai_identify.httpx, 'AsyncClient', lambda **kwargs: Client())
    with pytest.raises(ai_identify.GalleryVisionError) as error:
        immediate(ai_identify.gallery_vision_prediction('fake', 'image/jpeg', 'prompt'))
    assert error.value.code == code
    assert len(calls) == expected_calls
    assert 'do-not-expose' not in str(error.value)
