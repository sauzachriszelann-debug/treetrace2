from typing import Optional

from pydantic import BaseModel


class EvaluationTestResultCreate(BaseModel):
    image_id: str
    actual_species: Optional[str] = None
    predicted_species: Optional[str] = None
    actual_conservation: Optional[str] = None
    predicted_conservation: Optional[str] = None
    actual_dbh_cm: Optional[float] = None
    predicted_dbh_cm: Optional[float] = None
    scan_success: bool = False
    app_success: bool = False
    latency_ms: Optional[float] = None


class EvaluationTestResultOut(EvaluationTestResultCreate):
    id: int

    class Config:
        from_attributes = True
