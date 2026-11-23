"""Exercise real Panabo polygons through the write APIs, not a mocked geofence."""
from uuid import uuid4
import pytest
from fastapi import HTTPException
from app.api.routes import identify, tree_submissions
from app.models.tree import Tree
from app.models.tree_submission import TreeSubmission
from app.models.unknown_species import UnknownSpecies
from app.models.user import UserRole
from app.services import inventory_boundary as boundary

INSIDE = {'lat':7.311886, 'lng':125.67230}
OUTSIDE = {'lat':7.4475, 'lng':125.8078}  # Tagum; inside the old broad bounding box.

@pytest.fixture(autouse=True)
def include_review_routes(api_app):
    api_app.include_router(tree_submissions.router, prefix='/api/tree-submissions')
    api_app.include_router(identify.router, prefix='/api/ai')

@pytest.mark.parametrize('coords',[OUTSIDE, {'lat':0,'lng':0}, {'lat':14.60,'lng':120.98}])
def test_manual_or_offline_create_outside_panabo_is_rejected(client, admin_user, db_session, coords):
    response=client.post('/api/trees/',json={'common_name':'Narra', 'city':'Panabo City',
        'barangay':'New Visayas', 'client_uuid':str(uuid4()), **coords})
    assert response.status_code == 422
    assert 'outside the Panabo City' in response.json()['detail']
    assert db_session.query(Tree).count() == 0

@pytest.mark.parametrize('coords',[{}, {'lat':7.311886}, {'lng':125.6723}, {'lat':None,'lng':None}])
def test_new_inventory_requires_both_coordinates(client, admin_user, coords):
    response=client.post('/api/trees/',json={'common_name':'Narra',**coords})
    assert response.status_code == 422
    assert 'Both latitude and longitude' in response.json()['detail']

def test_inside_manual_coordinate_and_replay_are_valid(client, admin_user, db_session):
    payload={'common_name':'Narra','client_uuid':str(uuid4()), **INSIDE}
    first=client.post('/api/trees/',json=payload)
    assert first.status_code == 201, first.text
    again=client.post('/api/trees/',json=payload)
    assert again.status_code == 200
    assert again.json()['id'] == first.json()['id']
    assert db_session.query(Tree).count() == 1
    assert first.json()['gps_accuracy_m'] is None  # No invented GPS precision.

@pytest.mark.parametrize('change',[OUTSIDE, {'lat':None}, {'lng':None}, {'lng':125.8078}])
def test_patch_checks_effective_coordinates_and_keeps_original_on_failure(client, admin_user, db_session, change):
    first=client.post('/api/trees/',json={'common_name':'Narra',**INSIDE}).json()
    response=client.patch('/api/trees/'+str(first['id']),json=change)
    assert response.status_code == 422
    db_session.expire_all()
    row=db_session.get(Tree,first['id'])
    assert row.lat == INSIDE['lat'] and row.lng == INSIDE['lng']

def test_inside_partial_patch_and_non_location_legacy_edit(client, admin_user, db_session):
    row=Tree(common_name='Legacy',lat=OUTSIDE['lat'],lng=OUTSIDE['lng'])
    db_session.add(row);db_session.commit()
    response=client.patch('/api/trees/'+str(row.id),json={'notes':'Verify location in field'})
    assert response.status_code == 200
    first=client.post('/api/trees/',json={'common_name':'Narra',**INSIDE}).json()
    assert client.patch('/api/trees/'+str(first['id']),json={'lat':7.311887}).status_code == 200

def test_uncertainty_cannot_overlap_boundaries(client, admin_user):
    response=client.post('/api/trees/',json={'common_name':'Narra',**INSIDE,'gps_accuracy_m':10000})
    assert response.status_code == 422
    assert 'accuracy area crosses' in response.json()['detail']

def test_boundary_data_failure_is_closed_and_no_record_is_saved(client, admin_user, db_session, monkeypatch):
    def fail(*args): raise OSError('unavailable')
    monkeypatch.setattr(boundary,'_read_local_boundaries',fail)
    response=client.post('/api/trees/',json={'common_name':'Narra',**INSIDE})
    assert response.status_code == 503
    assert 'Nothing was saved' in response.json()['detail']
    assert db_session.query(Tree).count() == 0

def test_outside_pending_submission_rejected_before_quota(client, citizen_user, db_session):
    before=citizen_user.tree_submissions_today
    response=client.post('/api/tree-submissions/',json={'common_name':'Narra',**OUTSIDE})
    assert response.status_code == 422
    assert db_session.query(TreeSubmission).count() == 0
    db_session.refresh(citizen_user)
    assert citizen_user.tree_submissions_today == before

def test_photo_only_pending_requires_gps_at_approval_and_can_be_corrected(client, auth_as, db_session):
    auth_as(UserRole.citizen)
    submitted=client.post('/api/tree-submissions/',json={'common_name':'Narra'}).json()
    auth_as(UserRole.admin)
    url=f"/api/tree-submissions/{submitted['id']}/approve"
    for overrides in ({},OUTSIDE):
        response=client.post(url,json=overrides)
        assert response.status_code == 422
        assert db_session.query(Tree).count() == 0
        db_session.expire_all()
        assert db_session.get(TreeSubmission,submitted['id']).status == 'pending'
    approved=client.post(url,json=INSIDE)
    assert approved.status_code == 200, approved.text
    assert db_session.query(Tree).count() == 1

def test_legacy_outside_submission_cannot_be_approved(client, auth_as, db_session):
    submitter=auth_as(UserRole.citizen)
    row=TreeSubmission(common_name='Narra',submitted_by_id=submitter.id,status='pending',**OUTSIDE)
    db_session.add(row);db_session.commit();row_id=row.id
    auth_as(UserRole.admin)
    response=client.post(f'/api/tree-submissions/{row_id}/approve',json={})
    assert response.status_code == 422
    assert db_session.query(Tree).count() == 0

def test_unknown_photo_review_rejects_outside_coordinate_description(client, citizen_user, db_session):
    response=client.post('/api/ai/unknown-species',json={'photo_url':'https://example.test/tree.jpg',
        'location_description':f"{OUTSIDE['lat']}, {OUTSIDE['lng']}"})
    assert response.status_code == 422
    assert db_session.query(UnknownSpecies).count() == 0

def test_unknown_conversion_rechecks_legacy_outside_location(client, auth_as, db_session):
    submitter=auth_as(UserRole.citizen)
    entry=UnknownSpecies(photo_url='https://example.test/tree.jpg',submitted_by_id=submitter.id,
        location_description=f"{OUTSIDE['lat']}, {OUTSIDE['lng']}",reviewed=True,identified_as='Narra')
    db_session.add(entry);db_session.commit();entry_id=entry.id
    auth_as(UserRole.admin)
    response=client.post(f'/api/ai/unknown-species/{entry_id}/convert')
    assert response.status_code == 422
    assert db_session.query(TreeSubmission).count() == 0

def test_citizen_cannot_bypass_official_create_and_unauthenticated_is_denied(client, api_app, admin_user):
    api_app.dependency_overrides.clear()
    assert client.post('/api/trees/',json={'common_name':'Narra',**INSIDE}).status_code == 401

def test_exact_boundary_is_uncertain():
    features=boundary._read_local_boundaries(boundary.LOCAL_BOUNDARIES,boundary.LOCAL_BOUNDARIES.stat().st_mtime_ns)
    geometry=features[0]['geometry']; coords=geometry['coordinates']
    ring=coords[0] if geometry['type']=='Polygon' else coords[0][0]
    lng,lat=ring[0][:2]
    with pytest.raises(HTTPException) as error:
        boundary.validate_inventory_location(lat,lng)
    assert error.value.status_code == 422


def test_phone_fix_outside_bundled_city_is_reported_without_network(monkeypatch):
    from app.services import barangay_location
    def unexpected_network(*args, **kwargs):
        raise AssertionError("Complete local polygons should answer outside fixes")
    monkeypatch.setattr(barangay_location.httpx, "get", unexpected_network)
    assert barangay_location.resolve_barangay(7.460584, 125.6677, 23) == {"status": "outside_panabo"}


def test_retired_testing_flag_cannot_disable_geofence(monkeypatch):
    monkeypatch.setenv('TREETRACE_ALLOW_OUTSIDE_PANABO_TESTING', '1')
    with pytest.raises(HTTPException) as outside:
        boundary.validate_inventory_location(**OUTSIDE)
    assert outside.value.status_code == 422


def test_temporary_boundary_switch_allows_real_outside_gps(client, admin_user, monkeypatch):
    monkeypatch.setattr(boundary.settings, 'INVENTORY_BOUNDARY_TEST_BYPASS', True)
    lookup = client.get('/api/trees/barangay-location', params={**OUTSIDE, 'accuracy_m': 10})
    assert lookup.status_code == 200
    assert lookup.json() == {'status': 'unavailable'}
    created = client.post('/api/trees/', json={'common_name': 'Test tree', **OUTSIDE})
    assert created.status_code == 201, created.text
    assert created.json()['lat'] == OUTSIDE['lat']
    assert created.json()['lng'] == OUTSIDE['lng']
    with pytest.raises(HTTPException):
        boundary.validate_inventory_location(float('nan'), 125)
    monkeypatch.setattr(boundary.settings, 'INVENTORY_BOUNDARY_TEST_BYPASS', False)
    blocked = client.post('/api/trees/', json={'common_name': 'Blocked tree', **OUTSIDE})
    assert blocked.status_code == 422
