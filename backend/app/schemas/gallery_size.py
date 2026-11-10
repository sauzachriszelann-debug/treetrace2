from typing import Literal, Optional
from pydantic import BaseModel, Field


# Provider input contract: JSON mode alone does not require these fields.
def _metric_schema():
    return {
        'type': 'OBJECT',
        'properties': {
            'value': {'type': 'NUMBER', 'nullable': True},
            'evidence': {'type': 'STRING'},
            'uncertainty': {'type': 'STRING'},
            'reason_code': {'type': 'STRING', 'enum': [
                'predicted', 'insufficient_visual_evidence', 'base_hidden', 'top_hidden',
                'dbh_obscured', 'perspective_uncertain', 'ambiguous_target',
                'cannot_estimate']},
        },
        'required': ['value', 'evidence', 'uncertainty', 'reason_code'],
    }


GALLERY_VISION_RESPONSE_SCHEMA = {
    'type': 'OBJECT',
    'properties': {
        'dbh': _metric_schema(), 'height': _metric_schema(),
        'target_identified': {'type': 'BOOLEAN'},
        'base_visible': {'type': 'BOOLEAN'},
        'top_visible': {'type': 'BOOLEAN'},
        'same_tree_confirmed': {'type': 'BOOLEAN'},
    },
    'required': ['dbh', 'height', 'base_visible', 'top_visible', 'target_identified', 'same_tree_confirmed'],
}


class GallerySizeResponse(BaseModel):
    status: Literal['predicted', 'cannot_estimate', 'unavailable']
    method: Literal['gallery_yolo_vision_prediction'] = 'gallery_yolo_vision_prediction'
    label: Literal['AI-predicted size'] = 'AI-predicted size'
    quality: Literal['unvalidated'] = 'unvalidated'
    validated_accuracy: Literal[False] = False
    predicted_dbh_cm: Optional[float] = Field(None, gt=0, le=300)
    predicted_height_m: Optional[float] = Field(None, gt=0, le=80)
    needs_treetop_photo: bool = False
    treetop_photo_used: bool = False
    target_source: Literal['yolo', 'ai_visual', 'none'] = 'none'
    target_identified: bool = False
    detection_note: Optional[str] = None
    trunk_detected: bool = False
    trunk_width_px: Optional[float] = None
    preview_png: Optional[str] = None
    error_code: Optional[str] = None
    assumptions: list[str] = Field(default_factory=list)  # Legacy compatibility; left empty.
    prediction_basis: Literal['visual_appearance'] = 'visual_appearance'
    uncertainties: list[str] = Field(default_factory=list)
    dbh_reason_code: Optional[str] = None
    dbh_reason: Optional[str] = None
    height_reason_code: Optional[str] = None
    height_reason: Optional[str] = None
    reason: str
    note: str = ('Unvalidated prediction; may be inaccurate. Experimental estimate: '
                 'validate DBH against tape and height against a clinometer.')
