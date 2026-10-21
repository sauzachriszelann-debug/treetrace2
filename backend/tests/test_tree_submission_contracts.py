"""Contract tests for the G4 pending review and approval pipeline.

Covers: permissions, the state machine, idempotency and concurrency, the
separate daily quota (including replay-consumes-nothing), unknown-species
conversion, linking (many submissions per tree - safeguard A), reviewer
overrides (safeguard E), and structural separation from official inventory.
"""

import json
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event, func
from sqlalchemy.orm import sessionmaker

from app.api.routes import identify, trees, tree_submissions
from app.core.security import get_current_user
from app.db.database import Base, get_db
from app.models.tree import Tree
from app.models.tree_submission import TreeSubmission
from app.models.unknown_species import UnknownSpecies
from app.models.user import User, UserRole


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def g4_app(db_session):
    app = FastAPI()
    app.include_router(trees.router, prefix="/api/trees")
    app.include_router(tree_submissions.router, prefix="/api/tree-submissions")
    app.include_router(identify.router, prefix="/api/ai")

    def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    holder: dict = {}
    app.dependency_overrides[get_current_user] = lambda: holder["user"]
    app.g4_user_holder = holder
    try:
        yield app
    finally:
        app.dependency_overrides.clear()


@pytest.fixture
def g4_client(g4_app):
    with TestClient(g4_app) as client:
        yield client


@pytest.fixture
def g4_auth_as(g4_app, db_session):
    def set_user(role: UserRole, **attrs) -> User:
        user = User(
            full_name=f"{role.value} g4 user",
            email=(
                f"g4-{role.value}-{db_session.query(User).count()}"
                "@example.test"
            ),
            hashed_password="test-password-hash",
            role=role,
            is_active=True,
            **attrs,
        )
        db_session.add(user)
        db_session.commit()
        db_session.refresh(user)
        g4_app.g4_user_holder["user"] = user
        return user

    return set_user


@pytest.fixture
def submission_payload():
    return {
        "common_name": "Narra",
        "scientific_name": "Pterocarpus indicus",
        "barangay": "New Visayas",
        "lat": 7.45,
        "lng": 125.80,
        "dbh_cm": 20.0,
        "notes": "Citizen field note",
    }


def _create(client, payload=None, **extra):
    base = {"common_name": "Narra"} if payload is None else payload
    body = {**base, **extra}
    return client.post("/api/tree-submissions/", json=body)


def _make_unknown_entry(db_session, submitter, **attrs) -> UnknownSpecies:
    entry = UnknownSpecies(
        photo_url="https://example.test/unknown.jpg",
        barangay="New Visayas",
        location_description=attrs.pop("location_description", None),
        possible_name=attrs.pop("possible_name", None),
        submitter_notes=attrs.pop("submitter_notes", None),
        ai_candidates=attrs.pop("ai_candidates", None),
        submitted_by_id=submitter.id if submitter else None,
        **attrs,
    )
    db_session.add(entry)
    db_session.commit()
    db_session.refresh(entry)
    return entry


# ---------------------------------------------------------------------------
# Permissions
# ---------------------------------------------------------------------------

def test_unauthenticated_requests_are_rejected(db_session):
    app = FastAPI()
    app.include_router(tree_submissions.router, prefix="/api/tree-submissions")

    def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    client = TestClient(app)

    assert client.get("/api/tree-submissions/").status_code == 401
    assert client.get("/api/tree-submissions/my").status_code == 401
    assert client.post("/api/tree-submissions/", json={}).status_code == 401


def test_citizen_creates_pending_submission(
    g4_client, g4_auth_as, submission_payload
):
    g4_auth_as(UserRole.citizen)
    response = _create(g4_client, submission_payload)

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["status"] == "pending"
    assert body["source"] is None
    assert body["submitted_by_name"] == "citizen g4 user"
    assert body["approved_tree_id"] is None


def test_citizen_cannot_use_staff_endpoints(
    g4_client, g4_auth_as, submission_payload
):
    citizen = g4_auth_as(UserRole.citizen)
    submission_id = _create(g4_client, submission_payload).json()["id"]

    assert g4_client.get("/api/tree-submissions/").status_code == 403
    assert (
        g4_client.post(
            f"/api/tree-submissions/{submission_id}/approve", json={}
        ).status_code
        == 403
    )
    assert (
        g4_client.post(
            f"/api/tree-submissions/{submission_id}/reject",
            json={"reason": "no"},
        ).status_code
        == 403
    )
    assert (
        g4_client.post(
            f"/api/tree-submissions/{submission_id}/link",
            json={"tree_id": 1},
        ).status_code
        == 403
    )
    assert (
        g4_client.post(
            f"/api/tree-submissions/{submission_id}/reopen"
        ).status_code
        == 403
    )
    # /my remains reachable and scoped to the caller.
    assert g4_client.get("/api/tree-submissions/my").status_code == 200
    assert citizen.id is not None


@pytest.mark.parametrize("role", [UserRole.admin, UserRole.field_worker])
def test_staff_can_list_queue(g4_client, g4_auth_as, submission_payload, role):
    other = g4_auth_as(UserRole.citizen)
    _create(g4_client, submission_payload)
    g4_auth_as(role)

    response = g4_client.get("/api/tree-submissions/")
    assert response.status_code == 200
    assert len(response.json()) == 1


def test_my_submissions_scoped_to_caller(
    g4_client, g4_auth_as, submission_payload
):
    g4_auth_as(UserRole.citizen)
    _create(g4_client, submission_payload)

    g4_auth_as(UserRole.citizen)
    assert g4_client.get("/api/tree-submissions/my").json() == []


# ---------------------------------------------------------------------------
# Create: validation, idempotency, structural separation
# ---------------------------------------------------------------------------

def test_minimal_submission_is_allowed(g4_client, g4_auth_as):
    g4_auth_as(UserRole.citizen)
    response = _create(g4_client, {})
    assert response.status_code == 201, response.text
    assert response.json()["common_name"] is None


@pytest.mark.parametrize(
    "field,value",
    [
        ("lat", 999.0),
        ("lng", -181.0),
        ("dbh_cm", -5.0),
        ("carbon_kg", 12.0),  # server-derived, never accepted from clients
        ("health_status", "Magnificent"),
    ],
)
def test_invalid_submission_fields_rejected(
    g4_client, g4_auth_as, field, value
):
    g4_auth_as(UserRole.citizen)
    response = _create(g4_client, {field: value})
    assert response.status_code == 422


def test_idempotent_replay_same_client_uuid(
    g4_client, g4_auth_as, submission_payload
):
    g4_auth_as(UserRole.citizen)
    key = "11111111-2222-4333-8444-555555555555"

    first = _create(g4_client, submission_payload, client_uuid=key)
    second = _create(g4_client, submission_payload, client_uuid=key)

    assert first.status_code == 201
    assert second.status_code == 200
    assert second.headers["Idempotent-Replay"] == "true"
    assert first.json()["id"] == second.json()["id"]


def test_client_uuid_fingerprint_mismatch_is_409(
    g4_client, g4_auth_as, submission_payload
):
    g4_auth_as(UserRole.citizen)
    key = "11111111-2222-4333-8444-555555555555"

    first = _create(g4_client, submission_payload, client_uuid=key)
    other = {**submission_payload, "common_name": "Mahogany"}
    second = _create(g4_client, other, client_uuid=key)

    assert first.status_code == 201
    assert second.status_code == 409
    detail = second.json()["detail"]
    assert detail["existing_submission_id"] == first.json()["id"]


def test_pending_submission_invisible_to_inventory(
    g4_client, g4_auth_as, submission_payload
):
    g4_auth_as(UserRole.citizen)
    created = _create(g4_client, submission_payload)
    assert created.status_code == 201

    g4_auth_as(UserRole.admin)
    trees_list = g4_client.get("/api/trees/").json()
    stats = g4_client.get("/api/trees/stats/summary").json()
    nearby = g4_client.get(
        "/api/trees/nearby",
        params={"lat": submission_payload["lat"], "lng": submission_payload["lng"]},
    ).json()

    assert trees_list == []
    assert stats["total"] == 0
    assert nearby == [] or nearby.get("suggestions", []) == [] or nearby == []


# ---------------------------------------------------------------------------
# Daily quota (decision 10, safeguard B)
# ---------------------------------------------------------------------------

def test_citizen_quota_enforced(g4_client, g4_auth_as):
    g4_auth_as(UserRole.citizen)
    for index in range(10):
        response = _create(g4_client, {"common_name": f"Tree {index}"})
        assert response.status_code == 201, response.text

    blocked = _create(g4_client, {"common_name": "One too many"})
    assert blocked.status_code == 402
    assert "tree submissions" in blocked.json()["detail"]


def test_replay_does_not_consume_quota(
    g4_client, g4_auth_as, db_session, submission_payload
):
    citizen = g4_auth_as(UserRole.citizen)
    key = "11111111-2222-4333-8444-555555555555"
    assert (
        _create(g4_client, submission_payload, client_uuid=key).status_code
        == 201
    )

    # Exhaust the quota, then replay: replays must succeed without taking a
    # slot, while a fresh key is refused (safeguard B).
    db_session.query(User).filter(User.id == citizen.id).update(
        {User.tree_submissions_today: 10}
    )
    db_session.commit()

    replay = _create(g4_client, submission_payload, client_uuid=key)
    assert replay.status_code == 200
    assert replay.headers["Idempotent-Replay"] == "true"

    fresh = _create(g4_client, {"common_name": "Blocked"})
    assert fresh.status_code == 402


def test_staff_are_unlimited(g4_client, g4_auth_as):
    g4_auth_as(UserRole.field_worker)
    for index in range(12):
        response = _create(g4_client, {"common_name": f"Staff {index}"})
        assert response.status_code == 201


def test_quota_rolls_over_on_shared_date(
    g4_client, g4_auth_as, db_session
):
    citizen = g4_auth_as(UserRole.citizen)
    db_session.query(User).filter(User.id == citizen.id).update(
        {
            User.tree_submissions_today: 10,
            User.ai_usage_date: date.today() - timedelta(days=1),
        }
    )
    db_session.commit()

    response = _create(g4_client, {"common_name": "New day"})
    assert response.status_code == 201
    db_session.refresh(citizen)
    assert citizen.tree_submissions_today == 1


# ---------------------------------------------------------------------------
# State machine: approve / reject / link / reopen
# ---------------------------------------------------------------------------

def _pending_submission(g4_client, g4_auth_as, payload=None):
    g4_auth_as(UserRole.citizen)
    response = _create(g4_client, payload)
    assert response.status_code == 201, response.text
    return response.json()


def test_approve_creates_tree_atomically(
    g4_client, g4_auth_as, db_session, submission_payload
):
    submission = _pending_submission(g4_client, g4_auth_as, submission_payload)
    reviewer = g4_auth_as(UserRole.admin)

    response = g4_client.post(
        f"/api/tree-submissions/{submission['id']}/approve", json={}
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["submission"]["status"] == "approved"
    tree_id = body["submission"]["approved_tree_id"]
    assert tree_id == body["tree"]["id"]

    tree = db_session.query(Tree).filter(Tree.id == tree_id).one()
    assert tree.recorded_by_id == reviewer.id
    assert tree.client_uuid is None  # the G4 key belongs to the submission
    assert tree.common_name == "Narra"
    assert tree.carbon_kg and tree.carbon_kg > 0  # server-derived


def test_approve_twice_is_409_with_existing_tree(
    g4_client, g4_auth_as, submission_payload
):
    submission = _pending_submission(g4_client, g4_auth_as, submission_payload)
    g4_auth_as(UserRole.admin)

    first = g4_client.post(
        f"/api/tree-submissions/{submission['id']}/approve", json={}
    )
    second = g4_client.post(
        f"/api/tree-submissions/{submission['id']}/approve", json={}
    )

    assert first.status_code == 200
    assert second.status_code == 409
    detail = second.json()["detail"]
    assert detail["status"] == "approved"
    assert detail["approved_tree_id"] == first.json()["submission"]["approved_tree_id"]


def test_cannot_review_own_submission(
    g4_client, g4_auth_as, db_session
):
    staff = g4_auth_as(UserRole.field_worker)
    created = _create(g4_client, {"common_name": "Self review"})
    submission_id = created.json()["id"]

    approve = g4_client.post(
        f"/api/tree-submissions/{submission_id}/approve", json={}
    )
    reject = g4_client.post(
        f"/api/tree-submissions/{submission_id}/reject",
        json={"reason": "mine"},
    )
    assert approve.status_code == 403
    assert reject.status_code == 403
    assert "own submission" in reject.json()["detail"]

    # A different staff member can act.
    g4_auth_as(UserRole.admin)
    other = g4_client.post(
        f"/api/tree-submissions/{submission_id}/approve", json={}
    )
    assert other.status_code == 200


@pytest.mark.parametrize("role", [UserRole.admin, UserRole.field_worker])
def test_field_worker_and_admin_may_review(
    g4_client, g4_auth_as, submission_payload, role
):
    submission = _pending_submission(g4_client, g4_auth_as, submission_payload)
    g4_auth_as(role)
    response = g4_client.post(
        f"/api/tree-submissions/{submission['id']}/reject",
        json={"reason": "Needs a closer photo of the leaves."},
    )
    assert response.status_code == 200
    assert response.json()["status"] == "rejected"


def test_reject_requires_reason(g4_client, g4_auth_as, submission_payload):
    submission = _pending_submission(g4_client, g4_auth_as, submission_payload)
    g4_auth_as(UserRole.admin)

    blank = g4_client.post(
        f"/api/tree-submissions/{submission['id']}/reject",
        json={"reason": "   "},
    )
    assert blank.status_code == 422

    ok = g4_client.post(
        f"/api/tree-submissions/{submission['id']}/reject",
        json={"reason": "GPS too imprecise for inventory."},
    )
    assert ok.status_code == 200
    assert ok.json()["review_reason"] == "GPS too imprecise for inventory."
    assert ok.json()["reviewed_by_name"] == "admin g4 user"


def test_reopen_only_from_rejected(g4_client, g4_auth_as, submission_payload):
    first = _pending_submission(g4_client, g4_auth_as, submission_payload)
    second = _pending_submission(g4_client, g4_auth_as, submission_payload)
    third = _pending_submission(g4_client, g4_auth_as, submission_payload)
    g4_auth_as(UserRole.admin)

    # pending -> reopen is a conflict
    assert (
        g4_client.post(
            f"/api/tree-submissions/{first['id']}/reopen"
        ).status_code
        == 409
    )

    g4_client.post(
        f"/api/tree-submissions/{second['id']}/reject",
        json={"reason": "Duplicate of an older record."},
    )
    reopened = g4_client.post(
        f"/api/tree-submissions/{second['id']}/reopen"
    )
    assert reopened.status_code == 200
    body = reopened.json()
    assert body["status"] == "pending"
    assert body["reviewed_by_id"] is None
    # The previous rejection reason is retained as history.
    assert body["review_reason"] == "Duplicate of an older record."

    # approved is terminal: reopen is a conflict
    g4_client.post(
        f"/api/tree-submissions/{third['id']}/approve", json={}
    )
    assert (
        g4_client.post(
            f"/api/tree-submissions/{third['id']}/reopen"
        ).status_code
        == 409
    )


def test_link_records_existing_tree_without_creating_one(
    g4_client, g4_auth_as, db_session, submission_payload
):
    g4_auth_as(UserRole.admin)
    tree = g4_client.post("/api/trees/", json={"common_name": "Old Narra"})
    tree_id = tree.json()["id"]
    trees_before = db_session.query(func.count(Tree.id)).scalar()

    submission = _pending_submission(g4_client, g4_auth_as, submission_payload)
    g4_auth_as(UserRole.field_worker)
    response = g4_client.post(
        f"/api/tree-submissions/{submission['id']}/link",
        json={"tree_id": tree_id},
    )
    assert response.status_code == 200
    assert response.json()["status"] == "linked"
    assert response.json()["approved_tree_id"] == tree_id
    assert db_session.query(func.count(Tree.id)).scalar() == trees_before


def test_multiple_submissions_may_link_same_tree(
    g4_client, g4_auth_as, submission_payload
):
    """Safeguard A: linking is NOT unique - many submissions may reference
    the same existing tree. Only APPROVED rows are index-constrained."""
    g4_auth_as(UserRole.admin)
    tree_id = g4_client.post(
        "/api/trees/", json={"common_name": "Contested Narra"}
    ).json()["id"]

    first = _pending_submission(g4_client, g4_auth_as, submission_payload)
    second = _pending_submission(g4_client, g4_auth_as, submission_payload)
    g4_auth_as(UserRole.admin)

    one = g4_client.post(
        f"/api/tree-submissions/{first['id']}/link", json={"tree_id": tree_id}
    )
    two = g4_client.post(
        f"/api/tree-submissions/{second['id']}/link",
        json={"tree_id": tree_id},
    )
    assert one.status_code == 200
    assert two.status_code == 200
    assert one.json()["approved_tree_id"] == two.json()["approved_tree_id"]


def test_link_nonexistent_tree_is_404(g4_client, g4_auth_as, submission_payload):
    submission = _pending_submission(g4_client, g4_auth_as, submission_payload)
    g4_auth_as(UserRole.admin)
    response = g4_client.post(
        f"/api/tree-submissions/{submission['id']}/link",
        json={"tree_id": 99999},
    )
    assert response.status_code == 404


def test_linked_state_is_terminal(g4_client, g4_auth_as, submission_payload):
    g4_auth_as(UserRole.admin)
    tree_id = g4_client.post(
        "/api/trees/", json={"common_name": "Existing"}
    ).json()["id"]
    submission = _pending_submission(g4_client, g4_auth_as, submission_payload)
    g4_auth_as(UserRole.admin)
    g4_client.post(
        f"/api/tree-submissions/{submission['id']}/link", json={"tree_id": tree_id}
    )

    approve = g4_client.post(
        f"/api/tree-submissions/{submission['id']}/approve", json={}
    )
    reject = g4_client.post(
        f"/api/tree-submissions/{submission['id']}/reject",
        json={"reason": "changed mind"},
    )
    reopen = g4_client.post(
        f"/api/tree-submissions/{submission['id']}/reopen"
    )
    assert approve.status_code == 409
    assert reject.status_code == 409
    assert reopen.status_code == 409


def test_review_action_on_missing_submission_is_404(g4_client, g4_auth_as):
    g4_auth_as(UserRole.admin)
    assert (
        g4_client.post("/api/tree-submissions/424242/reopen").status_code
        == 404
    )


# ---------------------------------------------------------------------------
# Reviewer overrides (safeguard E)
# ---------------------------------------------------------------------------

def test_overrides_apply_without_touching_evidence(
    g4_client, g4_auth_as, db_session
):
    submission = _pending_submission(
        g4_client, g4_auth_as, {"barangay": "New Visayas", "lat": 7.45}
    )
    g4_auth_as(UserRole.admin)

    response = g4_client.post(
        f"/api/tree-submissions/{submission['id']}/approve",
        json={"common_name": "Narra", "dbh_cm": 33.5, "health_status": "Fair"},
    )
    assert response.status_code == 200, response.text
    body = response.json()

    tree = body["tree"]
    assert tree["common_name"] == "Narra"
    assert tree["dbh_cm"] == 33.5
    assert tree["health_status"] == "Fair"

    # Original evidence is untouched (write-once)...
    db_session.refresh(
        db_session.query(TreeSubmission).filter(
            TreeSubmission.id == submission["id"]
        ).one()
    )
    stored = (
        db_session.query(TreeSubmission)
        .filter(TreeSubmission.id == submission["id"])
        .one()
    )
    assert stored.common_name is None
    assert stored.dbh_cm is None
    # ...and the corrections are stored separately.
    assert json.loads(stored.review_overrides) == {
        "common_name": "Narra",
        "dbh_cm": 33.5,
        "health_status": "Fair",
    }


def test_override_with_derived_field_is_422(g4_client, g4_auth_as):
    submission = _pending_submission(g4_client, g4_auth_as)
    g4_auth_as(UserRole.admin)
    response = g4_client.post(
        f"/api/tree-submissions/{submission['id']}/approve",
        json={"carbon_kg": 99.0},
    )
    assert response.status_code == 422


def test_approve_without_any_common_name_is_422(g4_client, g4_auth_as):
    submission = _pending_submission(g4_client, g4_auth_as, {"barangay": "Mabuhay"})
    g4_auth_as(UserRole.admin)
    response = g4_client.post(
        f"/api/tree-submissions/{submission['id']}/approve", json={}
    )
    assert response.status_code == 422
    assert "common_name" in response.json()["detail"]


def test_invalid_override_measurement_is_422(g4_client, g4_auth_as):
    submission = _pending_submission(g4_client, g4_auth_as)
    g4_auth_as(UserRole.admin)
    response = g4_client.post(
        f"/api/tree-submissions/{submission['id']}/approve",
        json={"dbh_cm": -1.0},
    )
    assert response.status_code == 422


# ---------------------------------------------------------------------------
# Unknown-species conversion (Path B, safeguard C)
# ---------------------------------------------------------------------------

def test_convert_requires_identified_species(
    g4_client, g4_auth_as, db_session
):
    citizen = g4_auth_as(UserRole.citizen)
    entry = _make_unknown_entry(db_session, citizen)
    g4_auth_as(UserRole.admin)

    response = g4_client.post(f"/api/ai/unknown-species/{entry.id}/convert")
    assert response.status_code == 422
    assert "identified_as" in response.json()["detail"]


def test_convert_preserves_submitter_and_evidence(
    g4_client, g4_auth_as, db_session
):
    citizen = g4_auth_as(UserRole.citizen)
    entry = _make_unknown_entry(
        db_session,
        citizen,
        location_description="7.4500, 125.8000",
        submitter_notes="Big leaves near the plaza.",
        ai_candidates='[{"common_name": "Narra"}]',
    )
    # Admin identifies it through the EXISTING review endpoint first.
    g4_auth_as(UserRole.admin)
    review = g4_client.put(
        f"/api/ai/unknown-species/{entry.id}/review",
        json={"reviewed": True, "identified_as": "Narra", "review_notes": "ok"},
    )
    assert review.status_code == 200

    response = g4_client.post(f"/api/ai/unknown-species/{entry.id}/convert")
    assert response.status_code == 201, response.text
    body = response.json()

    assert body["status"] == "pending"
    assert body["source"] == "ai_identify"
    assert body["common_name"] == "Narra"
    assert body["photo_url"] == entry.photo_url
    assert body["lat"] == pytest.approx(7.45)
    assert body["lng"] == pytest.approx(125.80)
    # Safeguard C: the ORIGINAL submitter is preserved.
    assert body["submitted_by_id"] == citizen.id
    assert body["source_unknown_species_id"] == entry.id
    assert body["ai_candidates"] == [{"common_name": "Narra"}]
    assert "Big leaves" in body["notes"]

    # The unknown-species entry itself is never modified by conversion.
    db_session.refresh(entry)
    assert entry.identified_as == "Narra"  # set by review, not conversion
    assert entry.location_description == "7.4500, 125.8000"


def test_convert_is_replay_safe(
    g4_client, g4_auth_as, db_session
):
    citizen = g4_auth_as(UserRole.citizen)
    entry = _make_unknown_entry(db_session, citizen)
    g4_auth_as(UserRole.admin)
    g4_client.put(
        f"/api/ai/unknown-species/{entry.id}/review",
        json={"reviewed": True, "identified_as": "Narra"},
    )

    first = g4_client.post(f"/api/ai/unknown-species/{entry.id}/convert")
    second = g4_client.post(f"/api/ai/unknown-species/{entry.id}/convert")

    assert first.status_code == 201
    assert second.status_code == 200
    assert second.headers["Idempotent-Replay"] == "true"
    assert first.json()["id"] == second.json()["id"]
    assert (
        db_session.query(func.count(TreeSubmission.id)).scalar() == 1
    )


def test_convert_own_entry_forbidden(g4_client, g4_auth_as, db_session):
    admin = g4_auth_as(UserRole.admin)
    entry = _make_unknown_entry(db_session, admin, identified_as="Narra")

    response = g4_client.post(f"/api/ai/unknown-species/{entry.id}/convert")
    assert response.status_code == 403
    assert "own submission" in response.json()["detail"]


def test_convert_rejects_citizens(g4_client, g4_auth_as, db_session):
    citizen = g4_auth_as(UserRole.citizen)
    entry = _make_unknown_entry(db_session, citizen, identified_as="Narra")

    response = g4_client.post(f"/api/ai/unknown-species/{entry.id}/convert")
    assert response.status_code == 403


def test_convert_unknown_entry_is_404(g4_client, g4_auth_as):
    g4_auth_as(UserRole.admin)
    response = g4_client.post("/api/ai/unknown-species/424242/convert")
    assert response.status_code == 404


def test_converted_submission_flows_through_approval(
    g4_client, g4_auth_as, db_session
):
    citizen = g4_auth_as(UserRole.citizen)
    entry = _make_unknown_entry(
        db_session, citizen, location_description="not parseable"
    )
    g4_auth_as(UserRole.admin)
    g4_client.put(
        f"/api/ai/unknown-species/{entry.id}/review",
        json={"reviewed": True, "identified_as": "Narra"},
    )
    submission = g4_client.post(
        f"/api/ai/unknown-species/{entry.id}/convert"
    ).json()

    # Approving from a second, different reviewer (not the submitter).
    g4_auth_as(UserRole.field_worker)
    approved = g4_client.post(
        f"/api/tree-submissions/{submission['id']}/approve", json={}
    )
    assert approved.status_code == 200, approved.text
    tree = approved.json()["tree"]
    assert tree["common_name"] == "Narra"
    # Unparseable coordinates stay NULL - never guessed.
    assert tree["lat"] is None
    assert tree["lng"] is None


# ---------------------------------------------------------------------------
# Concurrency (safeguard B + duplicate-approval protection)
# ---------------------------------------------------------------------------

@pytest.fixture
def g4_concurrency(tmp_path):
    """File-based SQLite with per-request sessions and WAL, mirroring the
    conftest concurrency_app fixture, wired for the G4 routers."""
    engine = create_engine(
        f"sqlite:///{tmp_path / 'g4-concurrency.db'}",
        connect_args={"check_same_thread": False, "timeout": 30},
    )

    @event.listens_for(engine, "connect")
    def _set_sqlite_pragma(dbapi_connection, _connection_record):
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA journal_mode=WAL")
        cursor.execute("PRAGMA busy_timeout=30000")
        cursor.close()

    Base.metadata.create_all(bind=engine)
    TestSession = sessionmaker(autocommit=False, autoflush=False, bind=engine)

    app = FastAPI()
    app.include_router(trees.router, prefix="/api/trees")
    app.include_router(tree_submissions.router, prefix="/api/tree-submissions")

    def override_get_db():
        session = TestSession()
        try:
            yield session
        finally:
            session.close()

    app.dependency_overrides[get_db] = override_get_db

    setup = TestSession()
    citizen = User(
        full_name="Concurrency Citizen",
        email="concurrency-citizen@example.test",
        hashed_password="test-password-hash",
        role=UserRole.citizen,
        is_active=True,
    )
    admin = User(
        full_name="Concurrency Reviewer",
        email="concurrency-reviewer@example.test",
        hashed_password="test-password-hash",
        role=UserRole.admin,
        is_active=True,
    )
    setup.add_all([citizen, admin])
    setup.commit()
    setup.refresh(citizen)
    setup.refresh(admin)

    identity = {"user": citizen}
    app.dependency_overrides[get_current_user] = lambda: identity["user"]

    try:
        yield {
            "app": app,
            "identity": identity,
            "citizen": citizen,
            "admin": admin,
            "session": TestSession,
        }
    finally:
        app.dependency_overrides.clear()
        setup.close()
        engine.dispose()


def test_concurrent_same_uuid_creates_exactly_one_submission(g4_concurrency):
    app = g4_concurrency["app"]
    citizen = g4_concurrency["citizen"]
    key = "99999999-8888-4777-a666-555555555555"
    payload = {"common_name": "Narra", "client_uuid": key}

    def submit(_):
        client = TestClient(app)
        response = client.post("/api/tree-submissions/", json=payload)
        return response.status_code, response.headers.get("Idempotent-Replay")

    with ThreadPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(submit, range(6)))

    created = [status for status, _ in results if status == 201]
    replayed = [
        status
        for status, header in results
        if status == 200 and header == "true"
    ]
    assert len(created) == 1, results
    assert len(replayed) == 5, results

    session = g4_concurrency["session"]()
    try:
        assert (
            session.query(func.count(TreeSubmission.id)).scalar() == 1
        )
        stored = session.query(TreeSubmission).one()
        assert stored.client_uuid == key
        # Safeguard B: concurrent retries of the SAME submission consumed
        # exactly one quota slot, not six.
        assert (stored.submitted_by_id == citizen.id)
    finally:
        session.close()

    session = g4_concurrency["session"]()
    try:
        refreshed = session.query(User).filter(User.id == citizen.id).one()
        assert refreshed.tree_submissions_today == 1
    finally:
        session.close()


def test_concurrent_approve_only_one_wins(g4_concurrency):
    app = g4_concurrency["app"]
    identity = g4_concurrency["identity"]
    citizen = g4_concurrency["citizen"]
    admin = g4_concurrency["admin"]

    identity["user"] = citizen
    with TestClient(app) as client:
        created = client.post(
            "/api/tree-submissions/", json={"common_name": "Narra"}
        )
        assert created.status_code == 201, created.text
        submission_id = created.json()["id"]

    def approve(_):
        identity["user"] = admin
        client = TestClient(app)
        response = client.post(
            f"/api/tree-submissions/{submission_id}/approve", json={}
        )
        return response.status_code

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(approve, range(2)))

    assert sorted(results) == [200, 409], results

    session = g4_concurrency["session"]()
    try:
        submission = (
            session.query(TreeSubmission)
            .filter(TreeSubmission.id == submission_id)
            .one()
        )
        assert submission.status == "approved"
        # Exactly one tree exists: the losing approver's provisional tree
        # was rolled back with its failed compare-and-set.
        assert session.query(func.count(Tree.id)).scalar() == 1
    finally:
        session.close()
