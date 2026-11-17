from pydantic import BaseModel


class SpeciesModelPrediction(BaseModel):
    model_name: str
    top_label: str | None = None
    score_percent: float | None = None
    error: str | None = None


class SpeciesComparisonResponse(BaseModel):
    selected_model: str
    results: list[SpeciesModelPrediction]
