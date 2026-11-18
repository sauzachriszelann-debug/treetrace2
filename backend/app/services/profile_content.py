"""Shared public species facts and safe display of saved scan evidence."""
from app.schemas.scan_profile import ScanProfile
from pydantic import ValidationError

BLOCKED = ('upgrade plans', 'subscription-api', 'api pricing', "i'm sorry", 'api error',
           'traceback', 'service unavailable', 'request failed', 'premium/supreme')

def clean_content(value):
    if isinstance(value, str):
        return None if any(word in value.lower() for word in BLOCKED) else value
    if isinstance(value, dict):
        return {key: clean_content(item) for key, item in value.items()}
    if isinstance(value, list):
        return [clean_content(item) for item in value]
    return value

def saved_profile(tree):
    try:
        return clean_content(ScanProfile.model_validate(tree.scan_profile or {}).model_dump(exclude_none=True))
    except ValidationError:
        return {}

def species_facts(tree):
    from app.services.local_species_classifier import SPECIES_REFERENCE
    saved = saved_profile(tree)
    scientific = (tree.scientific_name or '').strip().lower()
    snapshot_matches = scientific and saved.get('scientific_name', '').strip().lower() == scientific
    facts = {**(saved if snapshot_matches else {}), **SPECIES_REFERENCE.get(tree.scientific_name, {})}
    return facts

def species_content(tree, wiki):
    wiki = clean_content(wiki)
    facts = species_facts(tree)
    scientific = (tree.scientific_name or '').strip().lower()
    if not facts:
        return wiki
    wiki['species_profile'] = facts
    wiki['tagline'] = facts.get('description') or wiki.get('tagline')
    basic = wiki.setdefault('basic_info', {})
    basic['family'] = facts.get('family')
    basic['plant_type'] = facts.get('plant_type') or 'Tree / woody plant'
    basic['lifespan'] = facts.get('lifespan') or 'Perennial'
    wiki['characteristics'] = {
        'Plant type': basic['plant_type'], 'Life span': basic['lifespan'],
        'Flower': facts.get('flower'), 'Fruit': facts.get('fruit'),
        'Diagnostic features': facts.get('distinguishing_features'),
    }
    wiki['similar_species'] = facts.get('look_alikes')
    wiki['explore'] = {
        'Ecological uses': facts.get('uses'),
        'Adaptation strategies': facts.get('adaptation_strategies'),
        'Name story': facts.get('name_story'),
    }
    if scientific == 'tabebuia rosea':
        basic.update(native_to='Mexico to Venezuela and Ecuador', invasive_status='Not assessed',
                     mature_height='Up to 35 m (species reference, not this tree)',
                     leaf_type='Palmately compound with five leaflets', flowering_season='Varies with climate')
        wiki['characteristics'].update(Flower='Pink or white trumpet-shaped flowers',
                                      Fruit='Dry capsules containing winged seeds')
        wiki['explore']['Name story'] = "The species epithet rosea refers to rose-coloured flowers."
        wiki['explore']['Ecological uses'] = 'Planted for shade and ornamental flowers.'
        basic['mature_spread'] = None
        wiki.setdefault('sources', {})['botanical'] = facts.get('botanical_source')
        wiki['uses'] = {'ecological': facts.get('uses')}
        wiki['name_story'] = facts.get('name_story')
        wiki['adaptation_strategies'] = facts.get('adaptation_strategies')
        wiki['history_and_legends'] = None
        wiki['symbolism'] = None
        wiki['care_profile'] = {'difficulty': 'Not assessed', 'watering': 'Moderate', 'sunlight': 'Full sun'}
        wiki['popular_questions'] = []
    return clean_content(wiki)
