"""Pydantic schemas for G4 tree submissions.

Reuses the exact validators that guard ``trees`` input (measurements must be
finite-positive, coordinates range-checked, server-derived biomass/carbon
rejected) so a submission can never carry data the tree schema would refuse.
"""

from datetime import date, datetime
from typing import Any, Optional
from uuid import UUID

from pydantic import BaseModel, field_validator

from app.schemas.tree import TreeMeasurementInput

_HEALTH_STATUSES = {"Healthy", "Fair", "Poor"}
_SOURCES = {"web_form", "mobile", "ai_identify"}


class _SubmissionFields(TreeMeasurementInput):
    """Shared payload fields; all optional because submission evidence may be
    incomplete. ``common_name`` becomes mandatory only at approval time."""

    common_name: Optional[str] = None
    scientific_name: Optional[str] = None
    dbh_cm: Optional[float] = None
    height_m: Optional[float] = None
    health_status: Optional[str] = "Healthy"
    barangay: Optional[str] = None
    city: Optional[str] = "Panabo City"
    province: Optional[str] = "Davao del Norte"
    lat: Optional[float] = None
    lng: Optional[float] = None
    photo_url: Optional[str] = None
    date_recorded: Optional[date] = None
    notes: Optional[str] = None

    @field_validator("common_name", "scientific_name", "barangay", "city", "province")
    @classmethod
    def blank_string_is_none(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        stripped = value.strip()
        return stripped or None

    @field_validator("health_status")
    @classmethod
    def validate_health_status(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return value
        normalized = value.strip().capitalize()
        if normalized not in _HEALTH_STATUSES:
            raise ValueError(
                f"health_status must be one of {sorted(_HEALTH_STATUSES)}"
            )
        return normalized


class TreeSubmissionCreate(_SubmissionFields):
    """Citizen/staff submission payload (POST /api/tree-submissions/)."""

    client_uuid: Optional[UUID] = None
    ai_candidates: Optional[list] = None
    source: Optional[str] = None

    @field_validator("source")
    @classmethod
    def validate_source(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        normalized = value.strip().lower()
        if normalized and normalized not in _SOURCES:
            raise ValueError(f"source must be one of {sorted(_SOURCES)}")
        return normalized or None


class TreeSubmissionOverrides(_SubmissionFields):
    """Reviewer corrections (approve-time overrides). Deliberately excludes
    identity/provenance fields: overrides can change record data, never
    client_uuid, source, or submission identity."""


class SubmissionLink(BaseModel):
    tree_id: int


class SubmissionReject(BaseModel):
    reason: str


class SubmissionOut(BaseModel):
    id: int
    client_uuid: Optional[str] = None
    status: str
    review_status: str
    source: Optional[str] = None
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
    date_recorded: Optional[date] = None
    notes: Optional[str] = None
    ai_candidates: Any = None
    review_overrides: Any = None
    reviewed_by_id: Optional[int] = None
    reviewed_by_name: Optional[str] = None
    review_reason: Optional[str] = None
    reviewed_at: Optional[datetime] = None
    approved_tree_id: Optional[int] = None
    source_unknown_species_id: Optional[int] = None
    submitted_by_id: Optional[int] = None
    submitted_by_name: Optional[str] = None
    submitted_by_email: Optional[str] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
