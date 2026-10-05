import math
from typing import Optional
from datetime import date, datetime

from pydantic import BaseModel, field_validator


class HealthLogCreate(BaseModel):
    tree_id: int
    condition: str
    notes: Optional[str] = None
    assessed_date: date
    dbh_cm: Optional[float] = None
    height_m: Optional[float] = None
    photo_url: Optional[str] = None

    @field_validator("dbh_cm", "height_m")
    @classmethod
    def validate_measurement(cls, value: Optional[float]) -> Optional[float]:
        if value is None:
            return value
        if not math.isfinite(value) or value <= 0:
            raise ValueError("must be a finite positive number")
        return value


class HealthLogOut(BaseModel):
    id: int
    tree_id: int
    condition: str
    notes: Optional[str] = None
    assessed_date: date
    dbh_cm: Optional[float] = None
    height_m: Optional[float] = None
    photo_url: Optional[str] = None
    assessed_by_id: Optional[int] = None
    created_at: Optional[datetime] = None

    # Denormalized for display (populated by service)
    tree_common_name: Optional[str] = None
    assessed_by: Optional[str] = None

    class Config:
        from_attributes = True


class PublicHealthLogOut(BaseModel):
    condition: str
    assessed_date: date
