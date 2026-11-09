from typing import Literal, Optional
from pydantic import BaseModel, Field


class GallerySizeResponse(BaseModel):
    status: Literal['predicted', 'cannot_estimate', 'unavailable']
    method: Literal['gallery_yolo_vision_prediction'] = 'gallery_yolo_vision_prediction'
    label: Literal['AI-predicted size'] = 'AI-predicted size'
    quality: Literal['unvalidated'] = 'unvalidated'
    validated_accuracy: Literal[False] = False
    predicted_dbh_cm: Optional[float] = Field(None, gt=0, le=300)
    predicted_height_m: Optional[float] = Field(None, gt=0, le=80)
    trunk_detected: bool = False
    trunk_width_px: Optional[float] = None
    preview_png: Optional[str] = None
    error_code: Optional[str] = None
    assumptions: list[str] = Field(default_factory=list)
    reason: str
    note: str = ('Unvalidated prediction; may be inaccurate. Experimental estimate: '
                 'validate DBH against tape and height against a clinometer.')
