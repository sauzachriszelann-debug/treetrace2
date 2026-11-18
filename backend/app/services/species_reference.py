"""One curated, sourced catalogue shared by identification and saved profiles."""
from copy import deepcopy
import json
from pathlib import Path

SPECIES_REFERENCE = json.loads(
    (Path(__file__).resolve().parents[2] / 'data/species_reference.json').read_text(encoding='utf-8')
)
_KEYS = {' '.join(key.lower().split()): key for key in SPECIES_REFERENCE}
_KEYS['monoon longifolium'] = 'Polyalthia longifolia'
_KEYS['albizia saman'] = 'Samanea saman'

def species_reference(name):
    if not isinstance(name, str):
        return {}
    key = _KEYS.get(' '.join(name.lower().split()))
    return deepcopy(SPECIES_REFERENCE.get(key, {}))

def enrich_species_reference(result):
    if result.get('not_identified'):
        return result
    reference = species_reference(result.get('scientific_name'))
    # Preserve the supplied name (including accepted synonyms), score and actual
    # observations. Taxon-level references never supply measurements or health.
    reference.pop('scientific_name', None)
    return {**result, **reference}
