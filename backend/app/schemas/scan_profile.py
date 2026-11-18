"""Public-safe scan snapshot. Never persist arbitrary provider/user payloads here."""
from typing import Optional
from pydantic import BaseModel, Field, ConfigDict
from app.schemas.tree_age import TreeAgeResponse

class ScanProfile(BaseModel):
    model_config = ConfigDict(extra='ignore')
    scientific_name: str = Field(default='', max_length=200)
    common_name: str = Field(default='', max_length=200)
    confidence_percent: Optional[float] = Field(None, ge=0, le=100, allow_inf_nan=False)
    family: Optional[str] = Field(None, max_length=200)
    description: Optional[str] = Field(None, max_length=3000)
    distinguishing_features: Optional[str] = Field(None, max_length=2000)
    look_alikes: Optional[str] = Field(None, max_length=2000)
    habitat: Optional[str] = Field(None, max_length=1000)
    uses: Optional[str] = Field(None, max_length=1500)
    adaptation_strategies: Optional[str] = Field(None, max_length=1500)
    name_story: Optional[str] = Field(None, max_length=1500)
    plant_type: Optional[str] = Field(None, max_length=300)
    lifespan: Optional[str] = Field(None, max_length=300)
    flower: Optional[str] = Field(None, max_length=500)
    fruit: Optional[str] = Field(None, max_length=500)
    estimated_dbh_cm: Optional[float] = Field(None, gt=0, le=300, allow_inf_nan=False)
    estimated_height_m: Optional[float] = Field(None, gt=0, le=80, allow_inf_nan=False)
    age_estimate: Optional[TreeAgeResponse] = None
