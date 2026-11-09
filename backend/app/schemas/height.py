"""Sensor-only height contract. Invalid/missing measurements return retake."""
from typing import Literal
from pydantic import BaseModel, Field


class HeightRequest(BaseModel):
    pitch_deg: float | None = Field(default=None, strict=True)
    camera_height_m: float | None = Field(default=1.4, strict=True)
    distance_m: float | None = Field(default=None, strict=True)
    dbh_status: Literal["ok", "retake", "unavailable"] = "retake"
    base_confirmed: bool = False


class HeightResponse(BaseModel):
    status: Literal["ok", "retake"]
    height_m: float | None = None
    theta_top_deg: float | None = None
    distance_m: float | None = None
    quality: Literal["experimental", "low"]
    reason: str
    method: Literal["tilt_distance"]
    fallback: Literal[False] = False
    accuracy_note: str
