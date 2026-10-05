import math

import pytest
from fastapi.testclient import TestClient

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
