"""Metric samples from one tracked AR camera frame; no guessed scale."""
import math
from typing import Literal

from pydantic import BaseModel, Field, model_validator


class DepthSample(BaseModel):
    u: float = Field(ge=0, allow_inf_nan=False)
    v: float = Field(ge=0, allow_inf_nan=False)
    x: float = Field(allow_inf_nan=False)
    y: float = Field(allow_inf_nan=False)
    z: float = Field(allow_inf_nan=False)
    confidence: float = Field(ge=0, le=1, allow_inf_nan=False)


class ARDepthCapture(BaseModel):
    version: Literal[1] = 1
    source: Literal["arcore_raw_depth"]
    image_width: int = Field(ge=64, le=4096)
    image_height: int = Field(ge=64, le=4096)
    image_rotation_degrees: Literal[0, 90, 180, 270] = 0
    ground_y: float = Field(allow_inf_nan=False)
    tracking: Literal["tracking"]
    frame_timestamp_ns: int = Field(gt=0)
    depth_timestamp_ns: int = Field(gt=0)
    camera_distance_m: float = Field(ge=0.5, le=5, allow_inf_nan=False)
    samples: list[DepthSample] = Field(min_length=20, max_length=20000)

    @model_validator(mode="after")
    def validate_capture(self):
        if abs(self.frame_timestamp_ns - self.depth_timestamp_ns) > 100_000_000:
            raise ValueError("Depth and camera frame are out of sync; rescan.")
        for point in self.samples:
            if point.u >= self.image_width or point.v >= self.image_height:
                raise ValueError("Depth sample is outside the camera image.")
            if not math.isfinite(point.y - self.ground_y):
                raise ValueError("Invalid ground-relative height.")
        return self


class ARDBHRequest(BaseModel):
    image_base64: str = Field(min_length=1, max_length=12_000_000)
    capture: ARDepthCapture


class ARDBHResponse(BaseModel):
    status: Literal["ok", "retake", "unavailable"]
    dbh_cm: float | None = Field(default=None, ge=3, le=300, allow_inf_nan=False)
    height_m: None = None
    reason: str = ""
    method: Literal["yolo_trunk_v1_ar_depth"] = "yolo_trunk_v1_ar_depth"
    confidence: Literal["Low"] = "Low"
    quality: Literal["low", "experimental"] = "low"
    fallback: Literal[False] = False
    segmentation_used: bool = False
    measurement_height_m: Literal[1.3] = 1.3
    width_px: float | None = None
    distance_estimate_m: float | None = None
    analysis_notes: str = ""
    accuracy_note: str = "Experimental estimate; field accuracy has not yet been validated."
    point_count: int | None = None
    fit_rmse_m: float | None = None
    arc_degrees: float | None = None

    @model_validator(mode="after")
    def require_measurement_only_on_success(self):
        if (self.status == "ok") != (self.dbh_cm is not None):
            raise ValueError("Only successful AR scans may return a DBH measurement.")
        return self


class PhotoDBHRequest(BaseModel):
    """Original-photo contract; missing pitch is handled as retake by the service."""
    image_base64: str
    content_type: str = "image/jpeg"
    reference_hint: str = "No reference object provided."
    method: str = "Camera-assisted photo measurement"
    known_distance_m: float | None = None  # Legacy path only; not relabelled as a sensor reading.
    camera_height_m: float = 1.4
    pitch_deg: float | None = None
    distance_m: float | None = None
    distance_source: str | None = None
    f_px: float | None = None
