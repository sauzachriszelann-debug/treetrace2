"""Experimental photo DBH, not a validated forestry instrument.

Assumptions: level rear-camera shot (abs(pitch) <= 5 degrees), flat ground,
visible trunk-ground contact, correct camera height, roughly round trunk, and
original EXIF retained without stripping or recompression. A mask bottom alone
cannot establish true ground contact: camera-height scale requires a human base
confirmation. Validate estimates against tape DBH and clinometer height.

No photos are logged or written. No network calls or API keys are used here.
"""
import base64
import importlib.util
import io
import math
import os
from pathlib import Path
from threading import Lock

CALIB = 1.0
MODEL_PATH = Path(__file__).resolve().parents[2] / "models/tree_trunk_dbh_v1.pt"
_model = None
_lock = Lock()
ACCURACY_NOTE = ("Experimental estimate; validate DBH against tape and height "
                 "against a clinometer before field use.")


def failure(status, reason):
    """Failures carry no measurement or scale numbers, including diagnostic ones."""
    return dict(status=status, dbh_cm=None, height_m=None, width_px=None,
                distance_m_used=None, distance_source=None, quality="low",
                reason=reason, needs_base_confirmation=False, preview_png=None,
                method="yolo_trunk_v1", fallback=False, segmentation_used=False,
                distance_estimate_m=None, measurement_height_m=None,
                accuracy_note=ACCURACY_NOTE)


def runtime_status():
    enabled = os.getenv("DBH_TRUNK_ENABLED", "false").lower() == "true"
    try:
        dependencies = all(importlib.util.find_spec(name) is not None
                           for name in ("ultralytics", "cv2", "numpy", "torch", "PIL"))
    except (ImportError, ValueError, ModuleNotFoundError):
        dependencies = False
    found = MODEL_PATH.is_file()
    return dict(enabled=enabled, ready=enabled and found and dependencies,
                model_found=found, dependencies_available=dependencies,
                requires="level photo, focal length and sensor distance or confirmed base",
                validated_accuracy=False)


def _positive(value):
    return (isinstance(value, (int, float)) and not isinstance(value, bool)
            and math.isfinite(value) and value > 0)


def _image_and_focal(image_bytes, f_px):
    from PIL import Image, ImageOps
    with Image.open(io.BytesIO(image_bytes)) as original:
        exif = original.getexif()
        focal35 = exif.get(0xA405)
        if focal35 is None:
            try:
                focal35 = exif.get_ifd(0x8769).get(0xA405)
            except (AttributeError, KeyError, TypeError, ValueError):
                pass
        # Orient for display/rows but never rescale; the original bytes stay intact.
        image = ImageOps.exif_transpose(original).convert("RGB")
    width, height = image.size
    if f_px is not None:
        if not _positive(f_px):
            raise ValueError("Invalid focal length in pixels; use an original photo.")
        focal = float(f_px)
    else:
        try:
            focal35 = float(focal35)
        except (ValueError, TypeError, ZeroDivisionError):
            raise ValueError("EXIF focal length missing; capture an original photo.") from None
        if not _positive(focal35):
            raise ValueError("EXIF focal length missing; capture an original photo.")
        focal = focal35 * math.hypot(width, height) / 43.267
    if not _positive(focal):
        raise ValueError("Invalid focal length; capture an original photo.")
    return image, focal


def _original_mask(mask, width, height):
    """Undo YOLO letterboxing before restoring original upright photo dimensions."""
    import cv2
    import numpy as np
    mask = np.asarray(mask, dtype=np.float32)
    if mask.ndim != 2 or not mask.size or not np.isfinite(mask).all():
        raise ValueError("Trunk mask is invalid; retake the photo.")
    mh, mw = mask.shape
    if (mw, mh) != (width, height):
        gain = min(mw / width, mh / height)
        pad_x = (mw - width * gain) / 2
        pad_y = (mh - height * gain) / 2
        left, right = round(pad_x - 0.1), mw - round(pad_x + 0.1)
        top, bottom = round(pad_y - 0.1), mh - round(pad_y + 0.1)
        mask = mask[top:bottom, left:right]
        if not mask.size:
            raise ValueError("Trunk mask could not be restored; retake the photo.")
        mask = cv2.resize(mask, (width, height), interpolation=cv2.INTER_NEAREST)
    return mask > 0.5


def _predict_masks(image):
    import numpy as np
    from ultralytics import YOLO
    global _model
    # Cache once and serialize both model loading and inference.
    with _lock:
        if _model is None:
            _model = YOLO(str(MODEL_PATH))
        prediction = _model.predict(np.asarray(image)[:, :, ::-1].copy(), imgsz=640, conf=0.4,
                                    retina_masks=True, verbose=False, device="cpu", save=False, save_txt=False, save_crop=False)[0]
    if prediction.masks is None or prediction.boxes is None:
        return []
    width, height = image.size
    masks = prediction.masks.data.cpu().numpy()
    classes = prediction.boxes.cls.cpu().numpy()
    return [_original_mask(mask, width, height) for mask, cls in zip(masks, classes)
            if str(prediction.names.get(int(cls), "")).lower() == "trunk"]


def _row_width(mask, row):
    """Use a contiguous run, never the span across holes/disconnected pixels."""
    import numpy as np
    columns = np.flatnonzero(mask[row])
    if not len(columns):
        return None
    runs = np.split(columns, np.flatnonzero(np.diff(columns) > 1) + 1)
    # Longest visible contiguous run from the selected largest instance mask.
    run = max(runs, key=len)
    return len(run)


def _preview(image, mask, row, base_row):
    import numpy as np
    from PIL import Image, ImageDraw
    pixels = np.asarray(image).copy()
    pixels[mask] = (pixels[mask] * 0.5 + np.array([255, 0, 0]) * 0.5).astype("uint8")
    preview = Image.fromarray(pixels)
    # Display-only preview. Measurement pixels/focal scale and original EXIF
    # remain unchanged; full-resolution PNG responses can exceed proxy limits.
    preview.thumbnail((1024, 1024))
    row = round(row * preview.height / image.height)
    base_row = round(base_row * preview.height / image.height)
    draw = ImageDraw.Draw(preview)
    draw.line((0, row, preview.width - 1, row), fill=(255, 255, 0), width=2)
    draw.line((0, base_row, preview.width - 1, base_row), fill=(0, 255, 0), width=2)
    output = io.BytesIO()
    preview.save(output, format="PNG")
    return base64.b64encode(output.getvalue()).decode("ascii")


def measure_dbh_trunk(image_bytes, camera_height_m=1.4, pitch_deg=None,
                      distance_m=None, distance_source=None, f_px=None):
    """Estimate DBH from original-photo segmentation plus explicit metric scale.

    Sensor/AR distance must be to the visible trunk surface for this exact shot,
    not an unrelated point or camera-depth median. Without sensor scale the base
    geometry assumes flat ground and correct camera height, and MUST be confirmed
    by one user tap on the green preview line before any result is accepted.
    Missing pitch never silently becomes zero on this measured backend path.
    """
    status = runtime_status()
    if not status["ready"]:
        return failure("unavailable", "Trunk DBH is disabled or its model/dependencies are unavailable.")
    if (not isinstance(pitch_deg, (int, float)) or isinstance(pitch_deg, bool)
            or not math.isfinite(pitch_deg)):
        return failure("retake", "Phone pitch missing; retake with motion sensors enabled.")
    if abs(pitch_deg) > 5:
        return failure("retake", "Hold the phone level")
    if not _positive(camera_height_m):
        return failure("retake", "Camera height is invalid; check the saved setting.")
    if distance_m is not None and (not _positive(distance_m) or distance_source not in (None, "sensor", "ar")):
        return failure("retake", "Provide a positive trunk-surface distance with source sensor or ar.")
    if distance_m is None and distance_source in ("sensor", "ar"):
        return failure("retake", "The sensor distance is missing; retake the photo.")
    if distance_m is None and distance_source not in (None, "camera_height"):
        return failure("retake", "Distance source is invalid; retake the photo.")
    try:
        import numpy as np
        image, focal = _image_and_focal(image_bytes, f_px)
        width, height = image.size
        masks = _predict_masks(image)
        masks = [np.asarray(m, dtype=bool) for m in masks if np.any(m)]
        if not masks:
            return failure("retake", "No trunk found; retake with one visible trunk.")
        if any(m.shape != (height, width) for m in masks):
            raise ValueError("Trunk mask does not match the original photo.")
        mask = max(masks, key=lambda m: int(m.sum()))
        base_row = int(np.flatnonzero(mask.any(axis=1))[-1])
        # Even sensor-scaled shots need a visible base to identify breast height.
        # This geometric gate cannot prove ground contact; preview confirmation
        # below is mandatory whenever the base supplies scale.
        if base_row >= height - 3:
            return failure("retake", "Trunk base not visible; include ground below the trunk.")
        cy = height / 2
        needs_confirmation = distance_m is None
        if needs_confirmation:
            if base_row <= cy + 5:
                return failure("retake", "Trunk base not visible below the centre; retake the photo.")
            distance = camera_height_m * focal / (base_row - cy)
            source = "camera_height"
        else:
            distance = float(distance_m)
            source = distance_source or "sensor"
        if not _positive(distance):
            raise ValueError("Distance could not be calculated; retake the photo.")
        row = max(0, min(height - 1, round(cy + focal * (camera_height_m - 1.3) / distance)))
        widths = []
        for y in range(max(0, row - 8), min(height, row + 9)):
            if mask[y, 0] or mask[y, -1]:
                return failure("retake", "Trunk is clipped; keep both edges in the photo.")
            measured = _row_width(mask, y)
            if measured is not None:
                widths.append(measured)
        if len(widths) < 5:
            return failure("retake", "Fewer than 5 usable trunk rows; retake the photo.")
        w_px = float(np.median(widths))
        if w_px < 40:
            return failure("retake", "Move closer")
        denominator = focal - w_px / 2
        if denominator <= 0 or not _positive(CALIB):
            return failure("retake", "Trunk geometry is invalid; retake the photo.")
        dbh_cm = w_px * distance / denominator * 100 * CALIB
        if not _positive(dbh_cm):
            return failure("retake", "Diameter could not be calculated; retake the photo.")
        return dict(status="ok", dbh_cm=float(dbh_cm), height_m=None, width_px=w_px,
                    distance_m_used=distance, distance_source=source, quality="experimental",
                    reason="Confirm the green line is the true trunk base before use." if needs_confirmation else "",
                    needs_base_confirmation=needs_confirmation,
                    preview_png=_preview(image, mask, row, base_row),
                    method="yolo_trunk_v1", fallback=False, segmentation_used=True,
                    confidence="Low", distance_estimate_m=distance, measurement_height_m=1.3,
                    analysis_notes="Original-photo trunk segmentation with experimental metric scale.",
                    accuracy_note=ACCURACY_NOTE)
    except ValueError as exc:
        return failure("retake", str(exc))
    except Exception:
        # A failed active-model measurement must never fall into old AI guesses.
        return failure("retake", "Trunk processing failed; retake the original photo.")
