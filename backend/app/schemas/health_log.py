from pydantic import BaseModel
from typing import Optional
from datetime import date, datetime


class HealthLogCreate(BaseModel):
    tree_id: int
    condition: str
    notes: Optional[str] = None
    assessed_date: date
    dbh_cm: Optional[float] = None
    height_m: Optional[float] = None
    photo_url: Optional[str] = None


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
