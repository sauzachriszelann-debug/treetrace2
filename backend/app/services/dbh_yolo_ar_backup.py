"""Experimental reference-free DBH: trunk segmentation + metric AR depth.

Fits a horizontal circular cross-section, rather than interpreting mask pixels
as centimeters. This assumes an approximately vertical, circular trunk and a
local level ground plane. Quality gates are engineering checks, NOT validated
accuracy bounds. Images/samples are processed in memory and never logged.
"""
import importlib.util
import os
from pathlib import Path
from threading import Lock

MODEL_PATH = Path(__file__).resolve().parents[2] / "models/tree_trunk_dbh_v1.pt"
_model = None
_lock = Lock()


def failure(status, reason):
    return {"status": status, "reason": reason, "dbh_cm": None,
            "height_m": None, "confidence": "Low", "quality": "low",
            "method": "yolo_trunk_v1_ar_depth", "measurement_height_m": 1.3,
            "fallback": False, "segmentation_used": False}


def runtime_status():
    enabled = os.getenv("DBH_TRUNK_ENABLED", "false").lower() == "true"
    dependencies = all(importlib.util.find_spec(m) is not None
                       for m in ("ultralytics", "cv2", "numpy", "torch"))
    return {"enabled": enabled, "ready": enabled and MODEL_PATH.is_file() and dependencies,
            "model_found": MODEL_PATH.is_file(), "dependencies_available": dependencies,
            "requires": "tracked AR raw depth and ground plane",
            "validated_accuracy": False}


def fit_cross_section(points):
    """Return diameter and residual diagnostics; reject unstable/flat arcs."""
    import numpy as np

    points = np.asarray(points, dtype=float)
    if len(points) < 20 or not np.isfinite(points).all():
        raise ValueError("Not enough reliable trunk depth. Move slowly around the trunk and rescan.")
    # Center first to avoid numerical loss when the AR origin is far away.
    origin = points.mean(axis=0)
    local = points - origin
    keep = np.ones(len(local), dtype=bool)
    for _ in range(4):
        selected = local[keep]
        matrix = np.column_stack((2 * selected, np.ones(len(selected))))
        solution, _, rank, _ = np.linalg.lstsq(matrix, (selected ** 2).sum(axis=1), rcond=None)
        if rank < 3 or np.linalg.cond(matrix) > 500:
            raise ValueError("Trunk curvature is unclear. Scan from a closer position.")
        center = solution[:2]
        squared_radius = solution[2] + float(center @ center)
        if squared_radius <= 0:
            raise ValueError("Trunk shape could not be measured. Rescan.")
        radius = float(np.sqrt(squared_radius))
        residual = np.abs(np.linalg.norm(local - center, axis=1) - radius)
        threshold = max(0.005, min(0.02, float(np.median(residual[keep])) * 3))
        keep = residual <= threshold
        if keep.sum() < 20 or keep.mean() < 0.7:
            raise ValueError("Depth is noisy or the trunk is irregular. Rescan in better light.")
    # Refit the final inlier set, then require a meaningful observed arc.
    selected = local[keep]
    matrix = np.column_stack((2 * selected, np.ones(len(selected))))
    solution = np.linalg.lstsq(matrix, (selected ** 2).sum(axis=1), rcond=None)[0]
    center = solution[:2]
    radius = float(np.sqrt(max(0, solution[2] + center @ center)))
    diameter = radius * 2
    if not 0.03 <= diameter <= 3:
        raise ValueError("Diameter is outside the supported range. Rescan.")
    angles = np.sort(np.arctan2(selected[:, 1] - center[1], selected[:, 0] - center[0]))
    gaps = np.diff(np.r_[angles, angles[0] + 2 * np.pi])
    coverage = float(2 * np.pi - gaps.max())
    rmse = float(np.sqrt(np.mean((np.linalg.norm(selected - center, axis=1) - radius) ** 2)))
    if coverage < np.deg2rad(50) or rmse > min(0.015, diameter * 0.05):
        raise ValueError("Not enough stable trunk curvature. Move closer and rescan.")
    # Agreement between alternating samples is a simple stability gate.
    radii = []
    for subset in (selected[::2], selected[1::2]):
        a = np.column_stack((2 * subset, np.ones(len(subset))))
        s = np.linalg.lstsq(a, (subset ** 2).sum(axis=1), rcond=None)[0]
        radii.append(float(np.sqrt(max(0, s[2] + s[:2] @ s[:2]))))
    if abs(radii[0] - radii[1]) > radius * 0.1:
        raise ValueError("Measurement is unstable. Move slowly and rescan.")
    return diameter * 100, {"point_count": int(keep.sum()), "fit_rmse_m": round(rmse, 5),
                            "arc_degrees": round(float(np.rad2deg(coverage)), 1)}


def measure_dbh_trunk(image_bytes, capture=None):
    status = runtime_status()
    if not status["ready"]:
        return failure("unavailable", "Automatic DBH is not enabled or its model dependencies are unavailable.")
    if capture is None:
        return failure("retake", "Use the guided depth scanner; an ordinary photo has no metric scale.")
    try:
        import cv2
        import numpy as np
        from ultralytics import YOLO

        image = cv2.imdecode(np.frombuffer(image_bytes, dtype=np.uint8), cv2.IMREAD_COLOR)
        if image is None:
            return failure("retake", "The camera image could not be read. Rescan.")
        height, width = image.shape[:2]
        if (width, height) != (capture.image_width, capture.image_height):
            return failure("retake", "Camera and depth coordinates do not match. Rescan.")
        turns = capture.image_rotation_degrees // 90
        upright = np.ascontiguousarray(np.rot90(image, -turns))
        model_height, model_width = upright.shape[:2]
        global _model
        with _lock:
            if _model is None:
                _model = YOLO(str(MODEL_PATH))
            result = _model.predict(upright, imgsz=640, conf=0.4, verbose=False, device="cpu")[0]
        if result.masks is None or result.boxes is None:
            return failure("retake", "No trunk found. Aim at one trunk and rescan.")
        candidates = []
        for mask, cls in zip(result.masks.data.cpu().numpy(), result.boxes.cls.cpu().numpy()):
            if str(result.names.get(int(cls), "")).lower() == "trunk":
                # Ultralytics masks are letterboxed; remove padding before resizing.
                mh, mw = mask.shape
                gain = min(mw / model_width, mh / model_height)
                px, py = (mw - model_width * gain) / 2, (mh - model_height * gain) / 2
                mask = mask[round(py - 0.1):mh - round(py + 0.1),
                            round(px - 0.1):mw - round(px + 0.1)]
                mask = cv2.resize(mask, (model_width, model_height), interpolation=cv2.INTER_NEAREST) > 0.5
                mask = np.rot90(mask, turns)
                candidates.append(mask)
        if not candidates:
            return failure("retake", "No trunk found. Aim at one trunk and rescan.")
        mask = max(candidates, key=lambda m: int(m.sum()))
        upright_mask = np.rot90(mask, -turns)
        if upright_mask[:, :3].any() or upright_mask[:, -3:].any():
            return failure("retake", "The trunk is clipped. Include its full width and rescan.")
        if not mask[height // 2, width // 2]:
            return failure("retake", "Center the trunk in the scanner and rescan.")
        # Erode boundaries so background depth does not contaminate the fit.
        interior = cv2.erode(mask.astype("uint8"), np.ones((3, 3), dtype="uint8"))
        points = []
        pixels = []
        for sample in capture.samples:
            u, v = int(sample.u), int(sample.v)
            if (sample.confidence >= 0.7 and interior[v, u]
                    and abs(sample.y - capture.ground_y - 1.3) <= 0.08):
                points.append((sample.x, sample.z))
                pixels.append((u, v))
        dbh_cm, diagnostics = fit_cross_section(points)
        return {"status": "ok", "dbh_cm": round(dbh_cm, 1), "height_m": None,
                "width_px": max(p[0] for p in pixels) - min(p[0] for p in pixels),
                "method": "yolo_trunk_v1_ar_depth", "quality": "experimental",
                "confidence": "Low", "reason": "", "fallback": False,
                "segmentation_used": True, "measurement_height_m": 1.3,
                "distance_estimate_m": capture.camera_distance_m,
                "analysis_notes": "Trunk mask plus AR depth at 1.3 m above the selected local ground plane.",
                "accuracy_note": "Experimental estimate; field accuracy has not yet been validated.",
                **diagnostics}
    except ValueError as exc:
        return failure("retake", str(exc))
    except Exception:
        return failure("unavailable", "Automatic DBH processing is unavailable. Please try again later.")
