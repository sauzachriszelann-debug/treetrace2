from typing import Literal, Optional
from pydantic import BaseModel, Field


# Provider input contract: JSON mode alone does not require these fields.
def _metric_schema():
    return {
        'type': 'OBJECT',
        'properties': {
            'value': {'type': 'NUMBER', 'nullable': True},
            'evidence': {'type': 'STRING'},
            'assumption': {'type': 'STRING'},
            'reference': {
                'type': 'OBJECT', 'nullable': True,
                'properties': {
                    'object': {'type': 'STRING'},
                    'dimension_m': {'type': 'NUMBER'},
                    'assumed': {'type': 'BOOLEAN'},
                },
                'required': ['object', 'dimension_m', 'assumed'],
            },
            'reason_code': {'type': 'STRING', 'enum': [
                'predicted', 'no_reference', 'base_hidden', 'top_hidden',
                'dbh_obscured', 'perspective_uncertain', 'ambiguous_target',
                'cannot_estimate']},
        },
        'required': ['value', 'evidence', 'assumption', 'reference', 'reason_code'],
    }


GALLERY_VISION_RESPONSE_SCHEMA = {
    'type': 'OBJECT',
    'properties': {
        'dbh': _metric_schema(), 'height': _metric_schema(),
        'base_visible': {'type': 'BOOLEAN'},
        'top_visible': {'type': 'BOOLEAN'},
    },
    'required': ['dbh', 'height', 'base_visible', 'top_visible'],
}


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
    dbh_reason_code: Optional[str] = None
    dbh_reason: Optional[str] = None
    height_reason_code: Optional[str] = None
    height_reason: Optional[str] = None
    reason: str
    note: str = ('Unvalidated prediction; may be inaccurate. Experimental estimate: '
                 'validate DBH against tape and height against a clinometer.')
