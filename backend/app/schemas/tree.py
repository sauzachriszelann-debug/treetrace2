import math
from datetime import date, datetime
from typing import Any, Optional

from pydantic import BaseModel, field_validator, model_validator


class TreeMeasurementInput(BaseModel):
    @model_validator(mode="before")
    @classmethod
    def reject_client_derived_values(cls, values: Any) -> Any:
        if isinstance(values, dict):
            derived_fields = {"biomass_kg", "carbon_kg"} & values.keys()
            if derived_fields:
                fields = ", ".join(sorted(derived_fields))
                raise ValueError(f"{fields} are calculated by the server.")
        return values

    @field_validator("dbh_cm", "height_m", check_fields=False)
    @classmethod
    def validate_measurement(cls, value: Optional[float]) -> Optional[float]:
        if value is None:
            return value
        if not math.isfinite(value) or value <= 0:
            raise ValueError("must be a finite positive number")
        return value


class TreeCreate(TreeMeasurementInput):
    common_name: str
    scientific_name: Optional[str] = None
    dbh_cm: Optional[float] = None
    height_m: Optional[float] = None
    health_status: str = "Healthy"
    barangay: Optional[str] = None
    city: Optional[str] = "Panabo City"
    province: Optional[str] = "Davao del Norte"
    lat: Optional[float] = None
    lng: Optional[float] = None
    photo_url: Optional[str] = None
    date_recorded: Optional[date] = None
    notes: Optional[str] = None


class TreeUpdate(TreeMeasurementInput):
    common_name: Optional[str] = None
    scientific_name: Optional[str] = None
    dbh_cm: Optional[float] = None
    height_m: Optional[float] = None
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

    @model_validator(mode="after")
    def reject_explicit_null_measurements(self) -> "TreeUpdate":
        for field_name in ("dbh_cm", "height_m"):
            if field_name in self.model_fields_set and getattr(self, field_name) is None:
                raise ValueError(f"{field_name} cannot be null in a tree update.")
        return self


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


class PublicTreeOut(BaseModel):
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
    endangered_status: str = "Not Listed"
    status_code: str = "NL"
    protected: bool = False
    cutting_allowed: bool = True
    created_at: Optional[datetime] = None

    class Config:
        from_attributes = True
