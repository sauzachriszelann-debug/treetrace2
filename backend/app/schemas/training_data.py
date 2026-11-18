from datetime import datetime
from pydantic import BaseModel, Field

class TrainingExample(BaseModel):
    id: str
    photo_url: str | None = None
    original_common_name: str | None = None
    original_scientific_name: str | None = None
    confidence_percent: float | None = None
    confirmed_common_name: str | None = None
    confirmed_scientific_name: str | None = None
    reviewer_id: int | None = None
    reviewer_name: str | None = None
    reviewed_at: datetime | None = None
    corrected: bool = False
    ready: bool = False
    issues: list[str] = Field(default_factory=list)

class TrainingDataList(BaseModel):
    total: int
    ready: int
    corrected: int
    items: list[TrainingExample]

class TrainingExportRequest(BaseModel):
    ids: list[str] = Field(min_length=1, max_length=20)
