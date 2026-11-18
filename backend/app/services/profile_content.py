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
    from app.services.species_reference import species_reference
    saved = saved_profile(tree)
    scientific = (tree.scientific_name or '').strip().lower()
    snapshot_matches = scientific and saved.get('scientific_name', '').strip().lower() == scientific
    facts = {**(saved if snapshot_matches else {}), **species_reference(tree.scientific_name)}
    return facts

def species_content(tree, wiki):
    wiki = clean_content(wiki)
    facts = species_facts(tree)
    scientific = (tree.scientific_name or '').strip().lower()
    if not facts:
        return wiki
    wiki['species_profile'] = facts
    wiki['reference_photos'] = facts.get('reference_photos', [])
    wiki['similar_species_records'] = facts.get('similar_species_records', [])
    wiki.setdefault('sources', {})['botanical'] = facts.get('botanical_source')
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
    # Remove generic provider guesses when using curated taxon facts.
    if facts.get('taxonomy_status'):
        basic.update(native_to=facts.get('native_to'), invasive_status='Not assessed',
                     mature_height=None, mature_spread=None, flowering_season=None, leaf_type=None)
        wiki['history_and_legends'] = None
        wiki['symbolism'] = None
        wiki['popular_questions'] = []
        wiki['uses'] = {'ecological': facts.get('uses')}
        wiki['name_story'] = facts.get('name_story')
        wiki['adaptation_strategies'] = facts.get('adaptation_strategies')
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


def original_ai_suggestion(db, tree):
    """Recover original evidence without modifying the tree or inventing a score."""
    import json
    import math
    from app.models.tree_submission import TreeSubmission
    from app.models.unknown_species import UnknownSpecies

    def checked(candidate):
        if not isinstance(candidate, dict):
            return None
        score = candidate.get('confidence_percent')
        if score is None:
            fraction = candidate.get('confidence_score', candidate.get('score'))
            if isinstance(fraction, (int, float)) and not isinstance(fraction, bool) and math.isfinite(fraction) and 0 <= fraction <= 1:
                score = fraction * 100
        if not isinstance(score, (int, float)) or isinstance(score, bool) or not math.isfinite(score) or not 0 <= score <= 100:
            return None
        try:
            return ScanProfile.model_validate({
                'confidence_percent': score,
                'common_name': candidate.get('common_name') or '',
                'scientific_name': candidate.get('scientific_name') or '',
            }).model_dump(exclude_none=True)
        except ValidationError:
            return None

    direct = checked(saved_profile(tree))
    if direct:
        return direct
    submission = db.query(TreeSubmission).filter(
        TreeSubmission.approved_tree_id == tree.id,
        TreeSubmission.status == 'approved',
    ).first()
    if submission is None:
        return None
    evidence = [submission.ai_candidates]
    if submission.source_unknown_species_id is not None:
        entry = db.query(UnknownSpecies).filter(UnknownSpecies.id == submission.source_unknown_species_id).first()
        if entry is not None:
            evidence.append(entry.ai_candidates)
    for raw in evidence:
        try:
            candidates = json.loads(raw) if isinstance(raw, str) else raw
        except (ValueError, TypeError):
            continue
        if isinstance(candidates, list) and candidates:
            suggestion = checked(candidates[0])
            if suggestion:
                return suggestion
    return None
