import math
from datetime import date, datetime
from typing import Any, Optional
from uuid import UUID

from pydantic import BaseModel, ValidationInfo, field_validator, model_validator


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

    @field_validator("lat", "lng", check_fields=False)
    @classmethod
    def validate_coordinate(
        cls, value: Optional[float], info: ValidationInfo
    ) -> Optional[float]:
        """Allow missing coordinates, but reject invalid or out-of-range values.

        latitude must be within [-90, 90] and longitude within [-180, 180].
        Missing GPS is represented by None and is never invented here.
        Each side is validated independently: a partial coordinate (one side
        present, the other None) is permitted and the missing side stays None.
        """
        if value is None:
            return value
        if not math.isfinite(value):
            raise ValueError("must be a finite number")
        is_latitude = info.field_name == "lat"
        limit = 90.0 if is_latitude else 180.0
        if not -limit <= value <= limit:
            axis = "latitude" if is_latitude else "longitude"
            raise ValueError(f"{axis} must be between {-limit:.0f} and {limit:.0f}")
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
    client_uuid: Optional[UUID] = None


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
    client_uuid: Optional[str] = None
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


class TreeCreateOut(TreeOut):
    """Create response distinguishing a fresh 201 from an idempotent 200 replay."""

    idempotent_replay: bool = False
    replayed_differences: dict = {}
