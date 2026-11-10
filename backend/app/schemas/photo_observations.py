"""Photo-only descriptions, deliberately separate from official health status."""
from typing import Literal
from pydantic import BaseModel, Field


class VisibleSign(BaseModel):
    code: Literal['leaf_discoloration', 'leaf_spots', 'leaf_holes', 'trunk_wound',
                  'dead_branches', 'fungal_growth', 'sap_flow']
    evidence: str = Field(min_length=1, max_length=300)


class PhotoObservations(BaseModel):
    status: Literal['observed', 'unclear', 'not_assessed'] = 'not_assessed'
    bark_appearance: Literal['Smooth', 'Rough', 'Ridged', 'Flaky', 'Unclear'] = 'Unclear'
    bark_evidence: str = ''
    visible_signs: list[VisibleSign] = Field(default_factory=list)
    no_visible_signs: bool = False
    needs_closeup: bool = True
    note: str = ('AI photo observations are unvalidated. They describe visible appearance, '
                 'not disease causes or overall tree health. Field review is required.')


def normalize_observations(raw):
    result = PhotoObservations()
    if not isinstance(raw, dict) or raw.get('photo_assessed') is not True:
        return result.model_dump()
    parts = raw.get('parts_visible')
    if not isinstance(parts, list) or not any(p in ('bark', 'leaves', 'crown') for p in parts):
        result.status = 'unclear'
        return result.model_dump()
    result.status = 'observed'
    bark = raw.get('bark_appearance')
    evidence = raw.get('bark_evidence')
    if ('bark' in parts and bark in ('Smooth', 'Rough', 'Ridged', 'Flaky')
            and isinstance(evidence, str) and evidence.strip()):
        result.bark_appearance = bark
        result.bark_evidence = evidence.strip()[:300]
    signs = raw.get('visible_signs')
    if isinstance(signs, list):
        seen = set()
        for sign in signs[:20]:
            if not isinstance(sign, dict):
                continue
            try:
                item = VisibleSign.model_validate(sign)
            except ValueError:
                continue
            if item.code not in seen and item.evidence.strip():
                result.visible_signs.append(item)
                seen.add(item.code)
        result.no_visible_signs = (not signs and raw.get('no_visible_signs') is True)
    result.needs_closeup = (raw.get('needs_closeup') is not False
                           or result.bark_appearance == 'Unclear')
    return result.model_dump()
