from typing import Literal

from pydantic import BaseModel, Field


class TreeAgeRequest(BaseModel):
    scientific_name: str = Field(min_length=1, max_length=200)
    dbh_cm: float | None = Field(default=None, gt=0, le=500, allow_inf_nan=False)
    height_m: float | None = Field(default=None, gt=0, le=150, allow_inf_nan=False)
    dimensions_source: Literal["ai_prediction", "measurement"] = "ai_prediction"


class GrowthSource(BaseModel):
    title: str
    url: str
    citation: str
    context: str
    reference_age_years: float | None = None
    dbh_cm: list[float] = Field(default_factory=list)
    height_m: list[float] = Field(default_factory=list)
    sample_size: int | None = None
    dbh_measurement_height_m: float | None = None


class GrowthRates(BaseModel):
    dbh_cm_per_year: list[float] | None = None
    height_m_per_year: list[float] | None = None


class TreeAgeResponse(BaseModel):
    status: Literal["estimated", "unavailable"]
    scientific_name: str
    dimensions_source: str
    min_years: int | None = None
    max_years: int | None = None
    dbh_age_years: float | None = None
    height_age_years: float | None = None
    dimensions_disagree: bool = False
    method: str = "linear_growth_scenario"
    validated: bool = False
    estimation_basis: Literal["published_growth", "ai_growth_guess"] = "published_growth"
    growth_rates: GrowthRates | None = None
    assumptions: str | None = None
    reason: str
    source: GrowthSource | None = None
