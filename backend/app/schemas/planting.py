from datetime import datetime
from typing import Optional
from pydantic import BaseModel


class PlantingRecommendationCreate(BaseModel):
    species_name: str
    scientific_name: Optional[str] = None
    barangay: Optional[str] = None
    reason: Optional[str] = None
    photo_url: Optional[str] = None
    status: str = "recommended"
    planted: bool = False


class PlantingRecommendationUpdate(BaseModel):
    species_name: Optional[str] = None
    scientific_name: Optional[str] = None
    barangay: Optional[str] = None
    reason: Optional[str] = None
    photo_url: Optional[str] = None
    status: Optional[str] = None
    planted: Optional[bool] = None


class PlantingRecommendationOut(BaseModel):
    id: int
    species_name: str
    scientific_name: Optional[str] = None
    barangay: Optional[str] = None
    reason: Optional[str] = None
    photo_url: Optional[str] = None
    status: str
    planted: bool
    submitted_by_id: Optional[int] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

    class Config:
        from_attributes = True
