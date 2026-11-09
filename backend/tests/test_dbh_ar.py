import asyncio
import base64
from types import SimpleNamespace
from unittest.mock import patch

import numpy as np
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.schemas.dbh import ARDepthCapture, ARDBHResponse
from app.services import dbh_yolo_ar_backup as dbh_yolo


def arc(diameter=0.4, count=100, span=130, noise=0):
    angle = np.deg2rad(np.linspace(-span / 2, span / 2, count))
    radius = diameter / 2
    points = np.column_stack((radius * np.sin(angle), 2 - radius * np.cos(angle)))
    return points + np.random.default_rng(42).normal(0, noise, points.shape)


def capture_dict():
    points = arc()
    return dict(version=1, source="arcore_raw_depth", image_width=640, image_height=480,
                ground_y=0, tracking="tracking", frame_timestamp_ns=1_000_000_000,
                depth_timestamp_ns=1_000_000_000, camera_distance_m=2,
                samples=[dict(u=200 + i * 2, v=240, x=p[0], y=1.3, z=p[1], confidence=.95)
                         for i, p in enumerate(points)])


@pytest.mark.parametrize("diameter", [0.1, 0.4, 1.2])
def test_known_metric_cylinder(diameter):
    measured, diagnostics = dbh_yolo.fit_cross_section(arc(diameter, noise=0.0002))
    assert measured == pytest.approx(diameter * 100, rel=.02)
    assert diagnostics["arc_degrees"] > 100


def test_metric_fit_is_invariant_to_world_origin_and_view_angle():
    points = arc()
    angle = .8
    rotation = np.array([[np.cos(angle), -np.sin(angle)], [np.sin(angle), np.cos(angle)]])
    measured, _ = dbh_yolo.fit_cross_section(points @ rotation + [1000, -2000])
    assert measured == pytest.approx(40, abs=.01)


@pytest.mark.parametrize("points", [arc(count=10), arc(span=15),
    np.column_stack((np.linspace(-.2, .2, 100), np.ones(100))),
    np.full((30, 2), np.nan)])
def test_insufficient_or_flat_depth_is_rejected(points):
    with pytest.raises(ValueError):
        dbh_yolo.fit_cross_section(points)


@pytest.mark.parametrize("field,value", [("ground_y", float("nan")),
    ("camera_distance_m", 0), ("depth_timestamp_ns", 1), ("image_rotation_degrees", 45)])
def test_invalid_capture_is_rejected(field, value):
    data = capture_dict()
    data[field] = value
    with pytest.raises(ValidationError):
        ARDepthCapture(**data)


def test_disabled_has_no_placeholder_numbers(monkeypatch):
    monkeypatch.delenv("DBH_TRUNK_ENABLED", raising=False)
    result = dbh_yolo.measure_dbh_trunk(b"invalid")
    assert result["status"] == "unavailable"
    assert result["dbh_cm"] is None and result["height_m"] is None


def test_missing_model_is_unavailable(monkeypatch, tmp_path):
    monkeypatch.setenv("DBH_TRUNK_ENABLED", "true")
    monkeypatch.setattr(dbh_yolo, "MODEL_PATH", tmp_path / "absent.pt")
    assert dbh_yolo.measure_dbh_trunk(b"invalid")["status"] == "unavailable"


def test_response_contract_forbids_measurements_on_failure():
    with pytest.raises(ValidationError):
        ARDBHResponse(status='retake', dbh_cm=25)
    with pytest.raises(ValidationError):
        ARDBHResponse(status='ok', dbh_cm=40, height_m=8)
    assert ARDBHResponse(**dbh_yolo.failure('retake', 'Rescan.')).dbh_cm is None


@pytest.mark.parametrize('rotation', [0, 90, 180, 270])
def test_segmentation_and_depth_end_to_end_without_loading_weights(monkeypatch, rotation):
    import cv2

    class Tensor:
        def __init__(self, value): self.value = np.asarray(value)
        def cpu(self): return self
        def numpy(self): return self.value

    mask = np.zeros((480, 640), dtype=np.float32)
    mask[40:-40, 150:450] = 1
    upright_mask = np.rot90(mask, -(rotation // 90))
    prediction = SimpleNamespace(masks=SimpleNamespace(data=Tensor([upright_mask])),
        boxes=SimpleNamespace(cls=Tensor([0])), names={0: "trunk"})
    class FakeModel:
        def predict(self, image, **kwargs):
            assert kwargs["imgsz"] == 640 and kwargs["conf"] == .4
            return [prediction]

    monkeypatch.setattr(dbh_yolo, "runtime_status", lambda: {"ready": True})
    monkeypatch.setattr(dbh_yolo, "_model", FakeModel())
    _, encoded = cv2.imencode('.jpg', np.zeros((480, 640, 3), dtype=np.uint8))
    capture = ARDepthCapture(**capture_dict())
    capture.image_rotation_degrees = rotation
    result = dbh_yolo.measure_dbh_trunk(encoded.tobytes(), capture)
    assert result["status"] == "ok"
    assert result["dbh_cm"] == pytest.approx(40, abs=.1)
    assert result["height_m"] is None and result["fallback"] is False
    for sample in capture.samples:
        sample.y = 2.3
    rejected = dbh_yolo.measure_dbh_trunk(encoded.tobytes(), capture)
    assert rejected["status"] == "retake" and rejected["dbh_cm"] is None


def test_ar_never_calls_old_yolo_or_gemini():
    from app.services.ai_identify import measure_dbh_from_base64
    with patch('app.services.ai_identify._yolo_segmented_dbh', side_effect=AssertionError("legacy used")), \
         patch('app.services.ai_identify.httpx.AsyncClient', side_effect=AssertionError("network used")), \
         patch.object(dbh_yolo, 'measure_dbh_trunk', return_value=dbh_yolo.failure('retake', 'Rescan.')):
        result = asyncio.run(measure_dbh_from_base64(base64.b64encode(b'photo').decode(),
            ar_capture=ARDepthCapture(**capture_dict())))
    assert result['status'] == 'retake' and result['dbh_cm'] is None


def test_ar_endpoint_auth_and_retakes():
    from app.api.routes.identify import router
    from app.core.security import get_current_user
    app = FastAPI()
    app.include_router(router, prefix='/api/ai')
    client = TestClient(app)
    body = {'image_base64': base64.b64encode(b'photo').decode(), 'capture': capture_dict()}
    assert client.post('/api/ai/measure-dbh-ar', json=body).status_code == 401
    app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(id=1)
    with patch.object(dbh_yolo, 'measure_dbh_trunk', return_value=dbh_yolo.failure('retake', 'Rescan.')):
        response = client.post('/api/ai/measure-dbh-ar', json=body)
    assert response.status_code == 200
    assert response.json()['status'] == 'retake'
    assert response.json()['dbh_cm'] is None and response.json()['height_m'] is None


@pytest.mark.parametrize('endpoint,file_upload', [('measure-dbh', False), ('measure-dbh-file', True)])
def test_legacy_endpoints_pass_through_retakes(endpoint, file_upload):
    from app.api.routes.identify import router
    from app.core.security import get_current_user
    from unittest.mock import AsyncMock
    app = FastAPI()
    app.include_router(router, prefix='/api/ai')
    app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(id=1)
    with patch('app.api.routes.identify.measure_dbh_from_base64',
               new=AsyncMock(return_value=dbh_yolo.failure('retake', 'Rescan.'))):
        client = TestClient(app)
        response = (client.post('/api/ai/' + endpoint, files={'file': ('scan.jpg', b'photo', 'image/jpeg')})
                    if file_upload else client.post('/api/ai/' + endpoint, json={'image_base64': 'cGhvdG8='}))
    assert response.json()['status'] == 'retake'
    assert response.json()['height_m'] is None
