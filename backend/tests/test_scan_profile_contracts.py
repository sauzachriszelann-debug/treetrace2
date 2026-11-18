from unittest.mock import AsyncMock
from app.models.tree import Tree
from app.schemas.scan_profile import ScanProfile
from app.services.profile_content import species_content


def test_profile_filters_private_fields_and_reuses_saved_age(client, admin_user, db_session):
    response = client.post('/api/trees', json={
        'common_name': 'Pink poui', 'scientific_name': 'Tabebuia rosea',
        'dbh_cm': 15, 'height_m': 7, 'notes': 'PRIVATE FIELD NOTES',
        'scan_profile': {
            'common_name': 'Pink poui', 'scientific_name': 'Tabebuia rosea',
            'confidence_percent': 85.38, 'notes': 'NEVER PUBLIC',
            'age_estimate': {'status': 'estimated', 'scientific_name': 'Tabebuia rosea',
                'dimensions_source': 'ai_prediction', 'estimation_basis': 'ai_growth_guess',
                'growth_rates': {'dbh_cm_per_year': [0.8, 1.4, 2.0]},
                'reason': 'Unvalidated AI growth scenario'},
        },
    })
    assert response.status_code == 201, response.text
    result = client.get('/api/public/tree/' + str(response.json()['id']))
    assert result.status_code == 200
    body = result.json()
    assert body['scan_profile']['confidence_percent'] == 85.38
    assert 'NEVER PUBLIC' not in result.text and 'PRIVATE FIELD NOTES' not in result.text
    assert round(body['estimated_age_years']) == 11
    assert body['age_estimate']['estimation_basis'] == 'ai_growth_guess'
    assert body['species_profile']['family'] == 'Bignoniaceae'


def test_profile_removes_provider_diagnostics_and_uses_shared_botanical_facts():
    tree = Tree(common_name='Pink poui', scientific_name='Tabebuia rosea')
    wiki = species_content(tree, {'sources': {}, 'basic_info': {
        'lifespan': "Upgrade Plans To Premium/Supreme - subscription-api-pricing. I'm sorry"}})
    assert 'Upgrade' not in str(wiki)
    assert wiki['basic_info']['lifespan'] == 'Perennial'
    assert 'Tabebuia heterophylla' in wiki['similar_species']
    assert wiki['explore']['Name story']


def test_species_correction_never_relabels_old_ai_facts():
    tree = Tree(common_name='Narra', scientific_name='Pterocarpus indicus',
        scan_profile={'scientific_name': 'Tabebuia rosea', 'family': 'Bignoniaceae', 'confidence_percent': 85.38})
    assert tree.species_profile == {}
    assert tree.scan_profile['confidence_percent'] == 85.38


def test_scan_profile_schema_upgrade_is_idempotent(monkeypatch):
    from sqlalchemy import create_engine, text, inspect
    from app import main
    engine = create_engine('sqlite:///:memory:')
    with engine.begin() as conn:
        for table in ('trees', 'tree_submissions', 'unknown_species'):
            conn.execute(text(f'CREATE TABLE {table} (id INTEGER PRIMARY KEY)'))
    monkeypatch.setattr(main, 'engine', engine)
    for _ in range(2):
        main.sync_gps_accuracy_columns()
        main.sync_unknown_species_columns()
    for table in ('trees', 'tree_submissions', 'unknown_species'):
        assert 'scan_profile' in {column['name'] for column in inspect(engine).get_columns(table)}


def test_detail_recovers_original_confidence_from_approved_submission(client, admin_user, db_session):
    import json
    from app.models.tree_submission import TreeSubmission
    tree = Tree(common_name='Narra', scientific_name='Pterocarpus indicus')
    db_session.add(tree)
    db_session.flush()
    db_session.add(TreeSubmission(status='approved', approved_tree_id=tree.id,
        ai_candidates=json.dumps([{'common_name': 'Mango', 'scientific_name': 'Mangifera indica', 'confidence_percent': 21.16}])))
    db_session.commit()
    response = client.get(f'/api/trees/{tree.id}')
    assert response.status_code == 200
    body = response.json()
    assert body['common_name'] == 'Narra'
    assert body['original_ai_suggestion']['common_name'] == 'Mango'
    assert body['original_ai_suggestion']['confidence_percent'] == 21.16
    assert db_session.get(Tree, tree.id).scan_profile is None


def test_confidence_is_not_invented_for_manual_records(client, admin_user, db_session):
    tree = Tree(common_name='Manual tree')
    db_session.add(tree)
    db_session.commit()
    body = client.get(f'/api/trees/{tree.id}').json()
    assert body['original_ai_suggestion'] is None
