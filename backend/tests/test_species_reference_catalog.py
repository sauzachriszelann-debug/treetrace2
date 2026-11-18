"""Curated facts stay separate from uncertain predictions and tree observations."""
from pathlib import Path
from types import SimpleNamespace
import pytest
from app.services.scan_species_classes import SCAN_CLASSES, restrict_scan_result
from app.services.species_reference import SPECIES_REFERENCE, species_reference
from app.services.profile_content import species_content, species_facts

ROOT = Path(__file__).resolve().parents[2]

def test_catalog_covers_trained_labels_without_inventing_unverified_taxonomy():
    assert set(SPECIES_REFERENCE) == set(SCAN_CLASSES)
    unverified = species_reference('Acacia-Semanca')
    assert unverified['family'] is None
    assert not unverified['reference_photos']
    assert unverified['taxonomy_status'] == 'unverified'
    assert species_reference('Eucalyptus')['taxonomy_status'] == 'genus'

@pytest.mark.parametrize('label', [n for n in SCAN_CLASSES if n != 'Acacia-Semanca'])
def test_known_facts_and_photos_have_sources_and_bundled_assets(label):
    facts = species_reference(label)
    assert facts['family'] and facts['description'] and facts['botanical_source'].startswith('https:')
    assert facts['reference_photos'], label
    for group in [facts['reference_photos']] + [c['photos'] for c in facts.get('similar_species_records',[])]:
        assert group, label
        for photo in group:
            assert photo['license'] and photo['license_url'] and photo['author'] and photo['source_url']
            assert (ROOT / 'mobile' / photo['asset']).is_file()
            assert (ROOT / 'frontend/public' / photo['url'].lstrip('/')).is_file()
    for photo in facts['reference_photos']:
        assert photo['scientific_name'] == (label if label != 'Eucalyptus' else 'Eucalyptus deglupta')
    for record in facts.get('similar_species_records', []):
        assert all(photo['scientific_name'] == record['scientific_name'] for photo in record['photos'])

def test_enrichment_preserves_original_confidence_measurements_and_observations():
    original = dict(scientific_name='Gmelina arborea', common_name='Gmelina arborea',
                    confidence='High', confidence_percent=89.12, estimated_dbh_cm=23,
                    photo_observations={'bark_appearance':'Unclear'})
    enriched = restrict_scan_result(original)
    assert enriched['family'] == 'Lamiaceae'
    assert enriched['common_name'] == 'Gmelina'
    for key in ('confidence_percent','estimated_dbh_cm','photo_observations'):
        assert enriched[key] == original[key]
    assert 'family' not in original

def test_uncertain_and_outside_classes_never_receive_confident_species_references():
    assert restrict_scan_result({'scientific_name':'Mangifera indica','confidence':'Low'})['not_identified']
    assert 'reference_photos' not in restrict_scan_result({'scientific_name':'Mangifera indica','confidence':'Low'})
    assert not species_reference('made up tree')
    assert not species_reference('Eucalyptus globulus')  # Never silently substitute a genus example.

def test_saved_profile_uses_corrected_identity_not_stale_scan_reference():
    tree = SimpleNamespace(scientific_name='Gmelina arborea', scan_profile={
        'scientific_name':'Mangifera indica','family':'Anacardiaceae','description':'Old mango scan'})
    facts = species_facts(tree)
    assert facts['family'] == 'Lamiaceae'
    assert 'Old mango scan' not in facts['description']
    wiki = species_content(tree, {'basic_info':{'native_to':'Generic guess','mature_height':'30 m'}})
    assert wiki['basic_info']['native_to'] is None
    assert wiki['basic_info']['mature_height'] is None
    assert wiki['reference_photos'] == facts['reference_photos']
    assert wiki['similar_species_records'] == facts['similar_species_records']

def test_synonym_and_normalization_share_references_without_mutation():
    first = species_reference('  MONOON   LONGIFOLIUM ')
    assert first['family'] == 'Annonaceae'
    first['reference_photos'].clear()
    assert species_reference('Polyalthia longifolia')['reference_photos']
