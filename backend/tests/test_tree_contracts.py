import math
import threading

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.exc import IntegrityError

from app.models.user import UserRole


def test_admin_creates_valid_tree(client: TestClient, admin_user, tree_payload):
    response = client.post("/api/trees/", json=tree_payload)

    assert response.status_code == 201
    data = response.json()
    assert data["dbh_cm"] == 24.0
    assert data["height_m"] == 9.0
    assert data["biomass_kg"] is not None
    assert data["carbon_kg"] is not None
    assert data["recorded_by_id"] == admin_user.id


def test_field_worker_creates_valid_tree(client: TestClient, field_worker_user, tree_payload):
    response = client.post("/api/trees/", json=tree_payload)

    assert response.status_code == 201
    assert response.json()["recorded_by_id"] == field_worker_user.id


def test_citizen_cannot_create_tree(client: TestClient, citizen_user, tree_payload):
    response = client.post("/api/trees/", json=tree_payload)

    assert response.status_code == 403


@pytest.mark.parametrize("explicit_null", [False, True])
def test_tree_create_allows_unknown_measurements(
    client, admin_user, tree_payload, explicit_null
):
    payload = dict(tree_payload)
    payload.pop("dbh_cm")
    payload.pop("height_m")
    if explicit_null:
        payload.update({"dbh_cm": None, "height_m": None})

    response = client.post("/api/trees/", json=payload)

    assert response.status_code == 201
    data = response.json()
    assert data["dbh_cm"] is None
    assert data["height_m"] is None
    assert data["biomass_kg"] is None
    assert data["carbon_kg"] is None


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("dbh_cm", 0),
        ("height_m", 0),
        ("dbh_cm", -1),
        ("height_m", -1),
        ("dbh_cm", "NaN"),
        ("height_m", "NaN"),
        ("dbh_cm", "Infinity"),
        ("height_m", "Infinity"),
    ],
)
def test_tree_create_rejects_invalid_measurements(
    client, admin_user, tree_payload, field, value
):
    response = client.post("/api/trees/", json={**tree_payload, field: value})

    assert response.status_code == 422


@pytest.mark.parametrize("field", ["biomass_kg", "carbon_kg"])
def test_tree_create_rejects_client_derived_values(
    client, admin_user, tree_payload, field
):
    response = client.post("/api/trees/", json={**tree_payload, field: 999})

    assert response.status_code == 422


def test_tree_patch_omitted_measurements_preserves_derived_values(
    client: TestClient, create_tree, auth_as
):
    tree = create_tree()
    auth_as(UserRole.admin)

    response = client.patch(
        f"/api/trees/{tree['id']}", json={"common_name": "Updated Narra"}
    )

    assert response.status_code == 200
    data = response.json()
    assert data["dbh_cm"] == tree["dbh_cm"]
    assert data["height_m"] == tree["height_m"]
    assert data["biomass_kg"] == tree["biomass_kg"]
    assert data["carbon_kg"] == tree["carbon_kg"]


@pytest.mark.parametrize("field", ["dbh_cm", "height_m"])
def test_tree_patch_changed_measurement_recalculates_derived_values(
    client: TestClient, create_tree, auth_as, field
):
    tree = create_tree()
    auth_as(UserRole.admin)
    changed_value = tree[field] + 5

    response = client.patch(f"/api/trees/{tree['id']}", json={field: changed_value})

    assert response.status_code == 200
    data = response.json()
    assert data[field] == changed_value
    assert data["biomass_kg"] is not None
    assert data["carbon_kg"] is not None
    assert (data["biomass_kg"], data["carbon_kg"]) != (
        tree["biomass_kg"],
        tree["carbon_kg"],
    )


@pytest.mark.parametrize(
    "payload",
    [
        {"dbh_cm": None},
        {"height_m": None},
        {"dbh_cm": 0},
        {"height_m": 0},
        {"dbh_cm": -1},
        {"height_m": -1},
        {"dbh_cm": "NaN"},
        {"height_m": "NaN"},
        {"dbh_cm": "Infinity"},
        {"height_m": "Infinity"},
    ],
)
def test_tree_patch_rejects_invalid_measurements(client, create_tree, auth_as, payload):
    tree = create_tree()
    auth_as(UserRole.admin)

    response = client.patch(f"/api/trees/{tree['id']}", json=payload)

    assert response.status_code == 422


def test_citizen_cannot_patch_tree(client, create_tree, auth_as):
    tree = create_tree()
    auth_as(UserRole.citizen)

    response = client.patch(f"/api/trees/{tree['id']}", json={"common_name": "Nope"})

    assert response.status_code == 403


@pytest.mark.parametrize("role", [UserRole.admin, UserRole.field_worker])
def test_staff_can_patch_tree(client, create_tree, auth_as, role):
    tree = create_tree()
    auth_as(role)

    response = client.patch(
        f"/api/trees/{tree['id']}", json={"common_name": f"{role.value} update"}
    )

    assert response.status_code == 200
    assert response.json()["common_name"] == f"{role.value} update"


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("lat", 91),
        ("lat", -91),
        ("lat", 999),
        ("lng", 181),
        ("lng", -181),
        ("lng", -999),
        ("lat", "NaN"),
        ("lat", "Infinity"),
        ("lng", "NaN"),
        ("lng", "Infinity"),
    ],
)
def test_tree_create_rejects_invalid_coordinates(
    client, admin_user, tree_payload, field, value
):
    response = client.post("/api/trees/", json={**tree_payload, field: value})

    assert response.status_code == 422


@pytest.mark.parametrize(
    ("lat", "lng"),
    [
        (0.0, 0.0),
        (7.4333371, 125.8089195),
        (-90.0, -180.0),
        (90.0, 180.0),
    ],
)
def test_tree_create_allows_valid_coordinates(
    client, admin_user, tree_payload, lat, lng
):
    response = client.post(
        "/api/trees/", json={**tree_payload, "lat": lat, "lng": lng}
    )

    assert response.status_code == 201
    data = response.json()
    assert data["lat"] == lat
    assert data["lng"] == lng


def test_tree_create_allows_missing_coordinates(client, admin_user, tree_payload):
    response = client.post(
        "/api/trees/", json={**tree_payload, "lat": None, "lng": None}
    )

    assert response.status_code == 201
    data = response.json()
    assert data["lat"] is None
    assert data["lng"] is None


@pytest.mark.parametrize(("present", "absent"), [("lat", "lng"), ("lng", "lat")])
def test_tree_create_allows_partial_coordinates(
    client, admin_user, tree_payload, present, absent
):
    """A tree may be recorded with only one coordinate side; the other stays None."""
    value = 7.4333371 if present == "lat" else 125.8089195

    response = client.post(
        "/api/trees/", json={**tree_payload, present: value, absent: None}
    )

    assert response.status_code == 201
    data = response.json()
    assert data[present] == value
    assert data[absent] is None


@pytest.mark.parametrize(("field", "value"), [("lat", 999), ("lng", -999)])
def test_tree_patch_rejects_invalid_coordinates(client, create_tree, auth_as, field, value):
    tree = create_tree()
    auth_as(UserRole.admin)

    response = client.patch(f"/api/trees/{tree['id']}", json={field: value})

    assert response.status_code == 422


def _uuid_payload(tree_payload, client_uuid, **overrides):
    return {**tree_payload, "client_uuid": str(client_uuid), **overrides}


def test_tree_create_with_client_uuid_is_idempotent(client, admin_user, tree_payload):
    client_uuid = "7d9f6f9a-1c2d-4e5f-8a9b-0c1d2e3f4a5b"

    first = client.post("/api/trees/", json=_uuid_payload(tree_payload, client_uuid))
    second = client.post("/api/trees/", json=_uuid_payload(tree_payload, client_uuid))

    assert first.status_code == 201
    assert second.status_code == 200
    assert first.json()["id"] == second.json()["id"]
    assert second.headers.get("idempotent-replay") == "true"
    body = second.json()
    assert body["idempotent_replay"] is True
    assert body["replayed_differences"] == {}
    assert len(client.get("/api/trees/").json()) == 1


def test_tree_repeat_uuid_survives_retries(client, admin_user, tree_payload):
    client_uuid = "11111111-2222-4333-8444-555555555555"

    responses = [
        client.post("/api/trees/", json=_uuid_payload(tree_payload, client_uuid))
        for _ in range(3)
    ]

    assert [r.status_code for r in responses] == [201, 200, 200]
    assert len({r.json()["id"] for r in responses}) == 1


def test_tree_create_rejects_uuid_reuse_with_different_identity(
    client, admin_user, tree_payload
):
    client_uuid = "aaaa1111-2222-4333-8444-555555555555"
    first = client.post("/api/trees/", json=_uuid_payload(tree_payload, client_uuid))
    assert first.status_code == 201

    conflict = client.post(
        "/api/trees/",
        json=_uuid_payload(tree_payload, client_uuid, common_name="Molave"),
    )

    assert conflict.status_code == 409
    detail = conflict.json()["detail"]
    assert detail["existing_tree_id"] == first.json()["id"]
    stored = client.get(f"/api/trees/{first.json()['id']}").json()
    assert stored["common_name"] == "Narra"  # nothing merged or overwritten


def test_tree_create_rejects_uuid_reuse_with_different_location(
    client, admin_user, tree_payload
):
    client_uuid = "aaaa2222-2222-4333-8444-555555555555"
    first = client.post(
        "/api/trees/",
        json=_uuid_payload({**tree_payload, "lat": 7.4, "lng": 125.8}, client_uuid),
    )
    assert first.status_code == 201

    moved = client.post(
        "/api/trees/",
        json=_uuid_payload({**tree_payload, "lat": 7.5, "lng": 125.9}, client_uuid),
    )

    assert moved.status_code == 409


def test_replay_reports_differences_without_overwriting(client, admin_user, tree_payload):
    client_uuid = "bbbb1111-2222-4333-8444-555555555555"
    created = client.post(
        "/api/trees/",
        json=_uuid_payload({**tree_payload, "lat": 7.4, "lng": 125.8}, client_uuid),
    )
    assert created.status_code == 201
    tree_id = created.json()["id"]

    replay = client.post(
        "/api/trees/",
        json=_uuid_payload(
            {
                **tree_payload,
                "lat": 7.4,
                "lng": 125.8,
                "dbh_cm": 26.5,
                "height_m": 11.0,
                "health_status": "Fair",
                "notes": "Corrected after re-measurement",
                "date_recorded": "2026-10-21",
                "photo_url": "https://example.test/retry.jpg",
            },
            client_uuid,
        ),
    )

    assert replay.status_code == 200
    differences = replay.json()["replayed_differences"]
    assert set(differences) == {
        "dbh_cm",
        "height_m",
        "health_status",
        "notes",
        "date_recorded",
        "photo_url",
    }
    assert differences["dbh_cm"] == {"existing": 24.0, "submitted": 26.5}

    stored = client.get(f"/api/trees/{tree_id}").json()
    assert stored["dbh_cm"] == 24.0  # never overwritten by a replay
    assert stored["health_status"] == "Healthy"
    assert stored["notes"] == "Internal field note"


def test_replay_normalizes_equivalent_submissions(client, admin_user, tree_payload):
    client_uuid = "bbbb2222-2222-4333-8444-555555555555"
    created = client.post("/api/trees/", json=_uuid_payload(tree_payload, client_uuid))
    assert created.status_code == 201

    replay = client.post(
        "/api/trees/",
        json=_uuid_payload(
            {**tree_payload, "common_name": "  narra  ", "dbh_cm": 24.00},
            client_uuid,
        ),
    )

    assert replay.status_code == 200
    assert replay.json()["replayed_differences"] == {}


def test_tree_create_rejects_malformed_client_uuid(client, admin_user, tree_payload):
    response = client.post(
        "/api/trees/", json=_uuid_payload(tree_payload, "not-a-uuid")
    )

    assert response.status_code == 422


def test_tree_create_without_uuid_keeps_legacy_behavior(client, admin_user, tree_payload):
    first = client.post("/api/trees/", json=tree_payload)
    second = client.post("/api/trees/", json=tree_payload)

    assert first.status_code == 201
    assert second.status_code == 201
    assert first.json()["id"] != second.json()["id"]


def test_concurrent_identical_uuid_creates_single_tree(concurrency_app, tree_payload):
    """Smoke-level concurrency check.

    Runs against file-based SQLite, which serializes writes; this exercises
    the IntegrityError recovery path end-to-end but is NOT proof of
    PostgreSQL concurrency semantics. Verify those against a staging copy
    using the recipe in backend/migrations/0001_add_trees_client_uuid.sql.
    """
    client_uuid = "cccc1111-2222-4333-8444-555555555555"
    payload = _uuid_payload(tree_payload, client_uuid)
    barrier = threading.Barrier(2)
    responses = []

    def worker():
        with TestClient(concurrency_app, raise_server_exceptions=False) as thread_client:
            barrier.wait()
            responses.append(thread_client.post("/api/trees/", json=payload))

    threads = [threading.Thread(target=worker) for _ in range(2)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=60)

    assert len(responses) == 2
    statuses = sorted(r.status_code for r in responses)
    assert statuses == [200, 201], [r.text for r in responses]
    assert len({r.json()["id"] for r in responses}) == 1

    with TestClient(concurrency_app) as verify_client:
        stored = verify_client.get("/api/trees/").json()
        assert len(stored) == 1


# ── IntegrityError classification (G2 correction) ─────────────────────────


class _PgError(Exception):
    """Stand-in for a psycopg UniqueViolation carrying a SQLSTATE."""

    def __init__(self, message: str, sqlstate: str | None):
        super().__init__(message)
        if sqlstate is not None:
            self.pgcode = sqlstate


def _pg_integrity_error(message: str, sqlstate: str) -> IntegrityError:
    return IntegrityError("INSERT INTO trees ...", {}, _PgError(message, sqlstate))


def _sqlite_integrity_error(message: str) -> IntegrityError:
    return IntegrityError("INSERT INTO trees ...", {}, Exception(message))


def test_classifier_accepts_postgres_client_uuid_unique_violation():
    from app.api.routes.trees import _is_client_uuid_conflict

    error = _pg_integrity_error(
        'duplicate key value violates unique constraint "ux_trees_client_uuid"',
        "23505",
    )

    assert _is_client_uuid_conflict(error) is True


def test_classifier_rejects_postgres_23505_from_other_constraints():
    """SQLSTATE 23505 alone must NOT be treated as a UUID conflict."""
    from app.api.routes.trees import _is_client_uuid_conflict

    error = _pg_integrity_error(
        'duplicate key value violates unique constraint "users_email_key"',
        "23505",
    )

    assert _is_client_uuid_conflict(error) is False


def test_classifier_rejects_other_sqlstates_even_on_client_uuid_constraint():
    from app.api.routes.trees import _is_client_uuid_conflict

    error = _pg_integrity_error(
        'check constraint "trees_client_uuid_check" is violated', "23514"
    )

    assert _is_client_uuid_conflict(error) is False


def test_classifier_accepts_sqlite_client_uuid_message():
    from app.api.routes.trees import _is_client_uuid_conflict

    error = _sqlite_integrity_error("UNIQUE constraint failed: trees.client_uuid")

    assert _is_client_uuid_conflict(error) is True


def test_classifier_rejects_sqlite_unrelated_unique_violations():
    from app.api.routes.trees import _is_client_uuid_conflict

    error = _sqlite_integrity_error("UNIQUE constraint failed: users.email")

    assert _is_client_uuid_conflict(error) is False


def test_classifier_rejects_integrity_error_without_original():
    from app.api.routes.trees import _is_client_uuid_conflict

    assert _is_client_uuid_conflict(IntegrityError("INSERT ...", {}, None)) is False


@pytest.mark.parametrize(
    ("original_message", "sqlstate"),
    [
        # Unrelated SQLite unique violation (local test database).
        ("UNIQUE constraint failed: users.email", None),
        # PostgreSQL 23505 but a different constraint.
        (
            'duplicate key value violates unique constraint "users_email_key"',
            "23505",
        ),
        # Right constraint name, wrong SQLSTATE.
        (
            'duplicate key value violates unique constraint "ux_trees_client_uuid"',
            "23514",
        ),
    ],
)
def test_unrelated_integrity_errors_are_not_recovered(
    client, admin_user, tree_payload, db_session, monkeypatch, original_message, sqlstate
):
    """Unrelated integrity failures must propagate, never be answered with
    the replay/409/503 responses reserved for client_uuid conflicts."""
    original = (
        _PgError(original_message, sqlstate)
        if sqlstate
        else Exception(original_message)
    )

    def failing_commit(*args, **kwargs):
        raise IntegrityError("INSERT INTO trees ...", {}, original)

    monkeypatch.setattr(db_session, "commit", failing_commit)

    with pytest.raises(IntegrityError):
        client.post(
            "/api/trees/",
            json=_uuid_payload(
                tree_payload, "eeee1111-2222-4333-8444-555555555555"
            ),
        )


def test_unrelated_integrity_errors_propagate_without_client_uuid(
    client, admin_user, tree_payload, db_session, monkeypatch
):
    def failing_commit(*args, **kwargs):
        raise _sqlite_integrity_error("NOT NULL constraint failed: trees.common_name")

    monkeypatch.setattr(db_session, "commit", failing_commit)

    with pytest.raises(IntegrityError):
        client.post("/api/trees/", json=tree_payload)
