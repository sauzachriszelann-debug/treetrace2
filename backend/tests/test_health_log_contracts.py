import pytest
from fastapi.testclient import TestClient

from app.models.user import UserRole


def test_admin_creates_valid_health_log(client: TestClient, create_tree, auth_as):
    tree = create_tree()
    admin_user = auth_as(UserRole.admin)
    response = client.post(
        "/api/health-logs/",
        json={
            "tree_id": tree["id"],
            "condition": "Fair",
            "assessed_date": "2026-10-05",
            "dbh_cm": 25.0,
            "height_m": 10.0,
        },
    )

    assert response.status_code == 201
    data = response.json()
    assert data["dbh_cm"] == 25.0
    assert data["height_m"] == 10.0
    assert data["assessed_by_id"] == admin_user.id


def test_field_worker_creates_health_log(client, create_tree, auth_as):
    tree = create_tree()
    field_worker_user = auth_as(UserRole.field_worker)
    response = client.post(
        "/api/health-logs/",
        json={
            "tree_id": tree["id"],
            "condition": "Fair",
            "assessed_date": "2026-10-05",
        },
    )

    assert response.status_code == 201
    assert response.json()["assessed_by_id"] == field_worker_user.id


def test_citizen_cannot_create_health_log(client, create_tree, auth_as):
    tree = create_tree()
    auth_as(UserRole.citizen)
    response = client.post(
        "/api/health-logs/",
        json={
            "tree_id": tree["id"],
            "condition": "Fair",
            "assessed_date": "2026-10-05",
        },
    )

    assert response.status_code == 403


@pytest.mark.parametrize("payload", [{}, {"dbh_cm": None, "height_m": None}])
def test_health_log_allows_unknown_measurements(client, create_tree, admin_user, payload):
    tree = create_tree()
    response = client.post(
        "/api/health-logs/",
        json={
            "tree_id": tree["id"],
            "condition": "Fair",
            "assessed_date": "2026-10-05",
            **payload,
        },
    )

    assert response.status_code == 201
    assert response.json()["dbh_cm"] is None
    assert response.json()["height_m"] is None


def test_health_log_accepts_positive_measurements(client, create_tree, admin_user):
    tree = create_tree()
    response = client.post(
        "/api/health-logs/",
        json={
            "tree_id": tree["id"],
            "condition": "Fair",
            "assessed_date": "2026-10-05",
            "dbh_cm": 31.5,
            "height_m": 12.25,
        },
    )

    assert response.status_code == 201
    assert response.json()["dbh_cm"] == 31.5
    assert response.json()["height_m"] == 12.25


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
def test_health_log_rejects_invalid_measurements(
    client, create_tree, admin_user, field, value
):
    tree = create_tree()
    response = client.post(
        "/api/health-logs/",
        json={
            "tree_id": tree["id"],
            "condition": "Fair",
            "assessed_date": "2026-10-05",
            field: value,
        },
    )

    assert response.status_code == 422


def test_health_log_updates_parent_tree_health_status(client, create_tree, admin_user):
    tree = create_tree()
    response = client.post(
        "/api/health-logs/",
        json={
            "tree_id": tree["id"],
            "condition": "Poor",
            "assessed_date": "2026-10-05",
        },
    )

    assert response.status_code == 201
    tree_response = client.get(f"/api/trees/{tree['id']}")
    assert tree_response.status_code == 200
    assert tree_response.json()["health_status"] == "Poor"
