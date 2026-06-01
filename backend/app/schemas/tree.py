from pydantic import BaseModel
from typing import Optional
from datetime import date, datetime


class TreeCreate(BaseModel):
    common_name: str
    scientific_name: Optional[str] = None
    dbh_cm: Optional[float] = None
    height_m: Optional[float] = None
    biomass_kg: Optional[float] = None
    carbon_kg: Optional[float] = None
    health_status: str = "Healthy"
    barangay: Optional[str] = None
    city: Optional[str] = "Panabo City"
    province: Optional[str] = "Davao del Norte"
    lat: Optional[float] = None
    lng: Optional[float] = None
    photo_url: Optional[str] = None
    date_recorded: Optional[date] = None
    notes: Optional[str] = None


class TreeUpdate(BaseModel):
    common_name: Optional[str] = None
    scientific_name: Optional[str] = None
    dbh_cm: Optional[float] = None
    height_m: Optional[float] = None
    biomass_kg: Optional[float] = None
    carbon_kg: Optional[float] = None
    health_status: Optional[str] = None
    barangay: Optional[str] = None
    city: Optional[str] = None
    province: Optional[str] = None
    lat: Optional[float] = None
    lng: Optional[float] = None
    photo_url: Optional[str] = None
    qr_code_url: Optional[str] = None
    date_recorded: Optional[date] = None
    notes: Optional[str] = None


class TreeOut(BaseModel):
    id: int
    common_name: str
    scientific_name: Optional[str] = None
    dbh_cm: Optional[float] = None
    height_m: Optional[float] = None
    biomass_kg: Optional[float] = None
    carbon_kg: Optional[float] = None
    health_status: str
    barangay: Optional[str] = None
    city: Optional[str] = None
    province: Optional[str] = None
    lat: Optional[float] = None
    lng: Optional[float] = None
    photo_url: Optional[str] = None
    qr_code_url: Optional[str] = None
    date_recorded: Optional[date] = None
    notes: Optional[str] = None
    recorded_by_id: Optional[int] = None
    endangered_status: str = "Not Listed"
    status_code: str = "NL"
    protected: bool = False
    cutting_allowed: bool = True
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

    class Config:
        from_attributes = True
