"""Offline synthetic geometry/contract checks; not field accuracy evidence."""
import asyncio
import base64
import io
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

import numpy as np
import pytest
from PIL import Image

from app.services import dbh_yolo as service


def photo(f35=35, orientation=None):
    image = Image.new("RGB", (640, 480), (20, 40, 60))
    exif = Image.Exif()
    if f35 is not None:
        exif[0xA405] = f35
    if orientation is not None:
        exif[0x0112] = orientation
    out = io.BytesIO()
    image.save(out, format="JPEG", exif=exif)
    return out.getvalue()


def trunk(left=270, right=370, base=400):
    mask = np.zeros((480, 640), dtype=bool)
    mask[30:base + 1, left:right] = True
    return mask


@pytest.fixture(autouse=True)
def no_network(monkeypatch):
    import socket
    def denied(*args, **kwargs):
        raise AssertionError("Network access is forbidden in Phase 1 tests")
    monkeypatch.setattr(socket.socket, "connect", denied)
    monkeypatch.setattr(socket, "create_connection", denied)


@pytest.fixture
def ready(monkeypatch):
    monkeypatch.setattr(service, "runtime_status", lambda: {"ready": True})
    monkeypatch.setattr(service, "_predict_masks", lambda image: [trunk()])
    monkeypatch.setattr(service, "CALIB", 1.0)


def measure(**kwargs):
    values = dict(camera_height_m=1.4, pitch_deg=0, f_px=800)
    values.update(kwargs)
    return service.measure_dbh_trunk(photo(), **values)


def assert_no_numbers(result):
    assert result["status"] in ("retake", "unavailable")
    for key in ("dbh_cm", "height_m", "width_px", "distance_m_used", "distance_estimate_m", "measurement_height_m"):
        assert result[key] is None, key


def test_disabled_and_missing_model_never_raise(monkeypatch, tmp_path):
    monkeypatch.delenv("DBH_TRUNK_ENABLED", raising=False)
    assert_no_numbers(service.measure_dbh_trunk(b"bad"))
    monkeypatch.setenv("DBH_TRUNK_ENABLED", "true")
    monkeypatch.setattr(service, "MODEL_PATH", tmp_path / "absent.pt")
    assert service.measure_dbh_trunk(b"bad")["status"] == "unavailable"


def test_missing_ultralytics_unavailable(monkeypatch):
    monkeypatch.setenv("DBH_TRUNK_ENABLED", "true")
    original = service.importlib.util.find_spec
    monkeypatch.setattr(service.importlib.util, "find_spec", lambda name: None if name == "ultralytics" else original(name))
    assert_no_numbers(service.measure_dbh_trunk(b"bad"))


@pytest.mark.parametrize("pitch", [None, float("nan"), float("inf"), True, 5.01, -6])
def test_bad_pitch_has_no_numbers(ready, pitch):
    result = measure(pitch_deg=pitch)
    assert_no_numbers(result)
    if isinstance(pitch, (int, float)) and not isinstance(pitch, bool) and np.isfinite(pitch) and abs(pitch) > 5:
        assert result["reason"] == "Hold the phone level"


@pytest.mark.parametrize("pitch", [-5, 0, 5])
def test_pitch_boundary_allowed(ready, pitch):
    assert measure(pitch_deg=pitch)["status"] == "ok"


@pytest.mark.parametrize("source", ["sensor", "ar"])
@pytest.mark.parametrize("distance", [1.0, 2.0, 4.0])
def test_near_and_far_sensor_formula(ready, source, distance):
    result = measure(distance_m=distance, distance_source=source)
    assert result["status"] == "ok"
    assert result["dbh_cm"] == pytest.approx(100 * distance / (800 - 50) * 100)
    assert result["distance_source"] == source
    assert result["needs_base_confirmation"] is False
    assert result["height_m"] is None


def test_base_scale_and_exact_preview_colours(ready):
    result = measure()
    assert result["status"] == "ok" and result["needs_base_confirmation"] is True
    assert result["distance_m_used"] == pytest.approx(1.4 * 800 / 160)
    assert result["dbh_cm"] == pytest.approx(100 * 7 / 750 * 100)
    preview = Image.open(io.BytesIO(base64.b64decode(result["preview_png"]))).convert("RGB")
    row = round(240 + 800 * (1.4 - 1.3) / 7)
    assert preview.size == (640, 480)
    assert preview.getpixel((0, row)) == (255, 255, 0)
    assert preview.getpixel((0, 400)) == (0, 255, 0)
    r, g, b = preview.getpixel((300, 100))
    assert r > g and r > b


def test_exif_diagonal_focal_and_orientation():
    image, focal = service._image_and_focal(photo(f35=35, orientation=6), None)
    assert image.size == (480, 640)
    assert focal == pytest.approx(35 * 800 / 43.267)


def test_missing_exif_requires_explicit_focal(ready):
    missing = service.measure_dbh_trunk(photo(None), pitch_deg=0)
    assert_no_numbers(missing)
    assert "EXIF" in missing["reason"]
    assert service.measure_dbh_trunk(photo(None), pitch_deg=0, f_px=800)["status"] == "ok"


@pytest.mark.parametrize("base", [240, 245, 477, 479])
def test_hidden_or_bottom_clipped_base_rejected(ready, monkeypatch, base):
    monkeypatch.setattr(service, "_predict_masks", lambda image: [trunk(base=base)])
    assert_no_numbers(measure())


def test_sensor_still_rejects_bottom_clipped_base(ready, monkeypatch):
    monkeypatch.setattr(service, "_predict_masks", lambda image: [trunk(base=479)])
    assert_no_numbers(measure(distance_m=2, distance_source="ar"))


@pytest.mark.parametrize("left,right", [(0, 300), (300, 640)])
def test_side_clipping_rejected(ready, monkeypatch, left, right):
    monkeypatch.setattr(service, "_predict_masks", lambda image: [trunk(left, right)])
    assert_no_numbers(measure())


def test_disconnected_pixels_are_not_counted_as_one_span(ready, monkeypatch):
    mask = trunk(200, 260)
    mask[30:401, 400:440] = True
    monkeypatch.setattr(service, "_predict_masks", lambda image: [mask])
    result = measure(distance_m=2, distance_source="sensor")
    assert result["width_px"] == 60
    assert result["dbh_cm"] == pytest.approx(60 * 2 / (800 - 30) * 100)


def test_largest_mask_selected(ready, monkeypatch):
    monkeypatch.setattr(service, "_predict_masks", lambda image: [trunk(100, 150), trunk()])
    assert measure()["width_px"] == 100


def test_no_trunk_and_too_few_rows(ready, monkeypatch):
    monkeypatch.setattr(service, "_predict_masks", lambda image: [])
    assert_no_numbers(measure())
    mask = np.zeros((480, 640), dtype=bool)
    mask[279:283, 270:370] = True
    mask[400, 270:370] = True
    monkeypatch.setattr(service, "_predict_masks", lambda image: [mask])
    result = measure(distance_m=2, distance_source="sensor")
    assert_no_numbers(result)
    assert "5 usable" in result["reason"]


def test_small_trunk_move_closer(ready, monkeypatch):
    monkeypatch.setattr(service, "_predict_masks", lambda image: [trunk(200, 239)])
    result = measure()
    assert_no_numbers(result)
    assert result["reason"] == "Move closer"


@pytest.mark.parametrize("kwargs", [dict(distance_m=-1, distance_source="ar"),
    dict(distance_m=2, distance_source="guess"), dict(distance_source="sensor"), dict(distance_source="guess"),
    dict(distance_m=float("inf"), distance_source="sensor"), dict(f_px=0),
    dict(camera_height_m=0), dict(f_px=40)])
def test_invalid_scale_and_geometry(ready, kwargs):
    assert_no_numbers(measure(**kwargs))


def test_calib_is_applied_only_as_multiplier(ready, monkeypatch):
    raw = measure()["dbh_cm"]
    monkeypatch.setattr(service, "CALIB", 1.1)
    assert measure()["dbh_cm"] == pytest.approx(raw * 1.1)


def test_letterbox_restored_to_original():
    padded = np.zeros((640, 640), dtype=float)
    padded[80:560, 200:400] = 1
    mask = service._original_mask(padded, 1280, 960)
    assert mask.shape == (960, 1280)
    assert service._row_width(mask, 100) == 400


def test_model_cached_once_and_predict_contract(ready, monkeypatch):
    import sys
    class Tensor:
        def __init__(self, value): self.value = np.asarray(value)
        def cpu(self): return self
        def numpy(self): return self.value
    prediction = SimpleNamespace(masks=SimpleNamespace(data=Tensor([trunk()])),
        boxes=SimpleNamespace(cls=Tensor([0])), names={0: "trunk"})
    calls = []
    class Model:
        def predict(self, image, **kwargs):
            assert kwargs["imgsz"] == 640 and kwargs["conf"] == .4
            assert image.shape == (480, 640, 3)
            return [prediction]
    def load(path):
        calls.append(path)
        return Model()
    monkeypatch.setitem(sys.modules, "ultralytics", SimpleNamespace(YOLO=load))
    monkeypatch.setattr(service, "_model", None)
    # Override the fixture stub specifically for this caching test.
    # Use the original function, since the fixture replaces the module symbol.
    ORIGINAL_PREDICT(Image.new("RGB", (640, 480)))
    ORIGINAL_PREDICT(Image.new("RGB", (640, 480)))
    assert len(calls) == 1


ORIGINAL_PREDICT = service._predict_masks


def run_inline(coroutine):
    """Run mocked, immediately completing awaits without opening event-loop sockets."""
    try:
        coroutine.send(None)
    except StopIteration as stopped:
        return stopped.value
    finally:
        coroutine.close()
    raise AssertionError("Unexpected asynchronous I/O in offline contract test")


async def inline_thread(function, *args, **kwargs):
    return function(*args, **kwargs)


@pytest.mark.parametrize("status", ["ok", "retake"])
def test_photo_pipeline_never_falls_through_on_success_or_retake(ready, status):
    from app.services import ai_identify
    answer = measure() if status == "ok" else service.failure("retake", "Move closer")
    with patch.object(service, "measure_dbh_trunk", return_value=answer) as call, \
         patch.object(ai_identify.asyncio, "to_thread", new=inline_thread), \
         patch.object(ai_identify, "_yolo_segmented_dbh", side_effect=AssertionError("legacy called")), \
         patch.object(ai_identify.httpx, "AsyncClient", side_effect=AssertionError("network called")):
        result = run_inline(ai_identify.measure_dbh_from_base64(
            base64.b64encode(photo()).decode(), pitch_deg=0, distance_m=2, distance_source="ar", f_px=800))
    assert result == answer
    assert call.call_args.kwargs["distance_source"] == "ar"


def test_unavailable_keeps_existing_legacy_path(ready):
    from app.services import ai_identify
    marker = {"dbh_cm": 44, "method": "existing legacy path"}
    with patch.object(service, "measure_dbh_trunk", return_value=service.failure("unavailable", "Missing model")), \
         patch.object(ai_identify.asyncio, "to_thread", new=inline_thread), \
         patch.object(ai_identify, "_yolo_segmented_dbh", new=AsyncMock(return_value=marker)), \
         patch.object(ai_identify.httpx, "AsyncClient", side_effect=AssertionError("network called")):
        assert run_inline(ai_identify.measure_dbh_from_base64(base64.b64encode(photo()).decode())) == marker


@pytest.mark.parametrize("multipart", [False, True])
def test_routes_forward_fields_and_pass_retakes_without_numbers(multipart):
    from app.api.routes import identify
    payload = dict(image_base64="cGhvdG8=", camera_height_m=1.6, pitch_deg=2,
                   distance_m=3, distance_source="ar", f_px=900)
    answer = service.failure("retake", "Hold the phone level")
    with patch.object(identify, "measure_dbh_from_base64", new=AsyncMock(return_value=answer)) as fn:
        if multipart:
            from starlette.datastructures import UploadFile, Headers
            file = SimpleNamespace(content_type="image/jpeg", read=AsyncMock(return_value=b"photo"))
            result = run_inline(identify.measure_dbh_file(file=file,
                reference_hint="No reference object provided.", method="test", known_distance_m=None,
                camera_height_m=1.6, pitch_deg=2, distance_m=3, distance_source="ar", f_px=900,
                _=SimpleNamespace(id=1)))
        else:
            result = run_inline(identify.measure_dbh(identify.MeasureDBHRequest(**payload), _=SimpleNamespace(id=1)))
    assert result == answer
    for key in ("camera_height_m", "pitch_deg", "distance_m", "distance_source", "f_px"):
        assert fn.call_args.kwargs[key] == payload[key]
    assert_no_numbers(result)


def test_upload_validation_does_not_become_numeric_fallback():
    from app.api.routes import identify
    from fastapi import HTTPException
    from starlette.datastructures import UploadFile, Headers
    file = UploadFile(io.BytesIO(b"not an image"), filename="file.txt", headers=Headers({"content-type": "text/plain"}))
    with pytest.raises(HTTPException) as error:
        run_inline(identify.measure_dbh_file(file=file, reference_hint="none", method="test",
            known_distance_m=None, camera_height_m=1.4, pitch_deg=0, distance_m=None,
            distance_source=None, f_px=None, _=SimpleNamespace(id=1)))
    assert error.value.status_code == 400


def test_real_service_error_preserves_flagged_legacy_fallback():
    from app.api.routes import identify
    with patch.object(identify, "measure_dbh_from_base64", new=AsyncMock(side_effect=RuntimeError("service failed"))):
        result = run_inline(identify.measure_dbh(identify.MeasureDBHRequest(image_base64="cGhvdG8="), _=SimpleNamespace(id=1)))
    assert result["fallback"] is True and result["dbh_cm"] == 25 and result["height_m"] == 8


def test_measurement_endpoints_keep_authentication():
    from app.api.routes.identify import router
    from app.core.security import get_current_user
    from fastapi.security import OAuth2PasswordBearer
    from fastapi import HTTPException
    from starlette.requests import Request
    for path in ("/measure-dbh", "/measure-dbh-file", "/measure-dbh-ar"):
        route = next(route for route in router.routes if route.path == path)
        assert any(dep.call is get_current_user for dep in route.dependant.dependencies)
    with pytest.raises(HTTPException) as error:
        run_inline(OAuth2PasswordBearer(tokenUrl="/api/auth/login")(Request({"type": "http", "headers": []})))
    assert error.value.status_code == 401


def test_calibration_does_not_use_eval_labels():
    import importlib.util
    from pathlib import Path
    spec = importlib.util.spec_from_file_location("dbh_check", Path(__file__).with_name("dbh_check.py"))
    checker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checker)
    records = [dict(file="calib.jpg", split="calib", accepted=True, status="ok", tape_dbh_cm=20, uncalibrated_dbh_cm=10),
               dict(file="eval.jpg", split="eval", accepted=True, status="ok", tape_dbh_cm=30, uncalibrated_dbh_cm=10),
               dict(file="tilted.jpg", split="eval", accepted=False, status="retake", tape_dbh_cm=25, uncalibrated_dbh_cm=None, reason="Hold the phone level", case="tilted")]
    report = checker.build_report(records)
    assert report["suggested_calib"] == 2
    assert report["eval_mean_percent_error"] == pytest.approx(100 / 3)
    assert report["retake_count"] == 1 and report["eval_accepted"] == 1
    assert report["eval_rejection_rate"] == .5
    records[1]["tape_dbh_cm"] = 1000
    assert checker.build_report(records)["suggested_calib"] == 2
    assert report["accuracy_claim_established"] is False


def test_validation_header_only_has_no_accuracy_claim():
    import importlib.util
    from pathlib import Path
    spec = importlib.util.spec_from_file_location("dbh_check_empty", Path(__file__).with_name("dbh_check.py"))
    checker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checker)
    report = checker.check(Path(__file__).resolve().parents[2] / "tests/tape.csv")
    assert report["eval_mean_percent_error"] is None
    assert report["suggested_calib"] is None
    assert len(report["missing_required_cases"]) == 5


def test_provided_distance_defaults_to_sensor_source(ready):
    result = measure(distance_m=2)
    assert result["status"] == "ok" and result["distance_source"] == "sensor"


def test_preserved_ar_pipeline_still_bypasses_legacy_and_photo_model():
    from app.services import ai_identify, dbh_yolo_ar_backup
    answer = dbh_yolo_ar_backup.failure("retake", "Depth uncertain")
    with patch.object(dbh_yolo_ar_backup, "measure_dbh_trunk", return_value=answer) as fn, \
         patch.object(ai_identify.asyncio, "to_thread", new=inline_thread), \
         patch.object(service, "measure_dbh_trunk", side_effect=AssertionError("new photo path used")), \
         patch.object(ai_identify, "_yolo_segmented_dbh", side_effect=AssertionError("legacy used")), \
         patch.object(ai_identify.httpx, "AsyncClient", side_effect=AssertionError("network used")):
        capture = object()
        result = run_inline(ai_identify.measure_dbh_from_base64("cGhvdG8=", ar_capture=capture))
    assert result == answer
    assert fn.call_args.args == (b"photo", capture)


def test_strict_file_route_never_uses_legacy_or_gemini():
    from app.api.routes import identify
    answer = service.failure("unavailable", "Model unavailable")
    file = SimpleNamespace(content_type="image/jpeg", read=AsyncMock(return_value=b"original-exif"))
    with patch.object(service, "measure_dbh_trunk", return_value=answer) as fn, \
         patch.object(identify.asyncio, "to_thread", new=inline_thread), \
         patch.object(identify, "measure_dbh_from_base64", side_effect=AssertionError("legacy used")):
        result = run_inline(identify.measure_dbh_file(file=file, method="yolo_trunk_v1",
            reference_hint="none", known_distance_m=None, camera_height_m=1.4,
            pitch_deg=2, distance_m=None, distance_source=None, f_px=3380,
            _=SimpleNamespace(id=1)))
    assert result == answer and result["dbh_cm"] is None
    assert fn.call_args.args == (b"original-exif",)
    assert fn.call_args.kwargs["f_px"] == 3380


def test_preview_is_bounded_without_changing_measurement_image():
    image = Image.new("RGB", (1800, 2400), (25, 50, 25))
    mask = np.zeros((2400, 1800), dtype=bool)
    mask[:, 800:1000] = True
    preview = Image.open(io.BytesIO(base64.b64decode(service._preview(image, mask, 1200, 2000))))
    assert max(preview.size) <= 1024
    assert image.size == (1800, 2400)
    assert mask.shape == (2400, 1800)
