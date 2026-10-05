from fastapi.testclient import TestClient

from app.core.security import get_current_user


def test_public_tree_response_uses_limited_schema(client: TestClient, create_tree):
    tree = create_tree(notes="Internal only")
    client.app.dependency_overrides.pop(get_current_user, None)

    response = client.get(f"/api/public/tree/{tree['id']}")

    assert response.status_code == 200
    data = response.json()
    assert data["id"] == tree["id"]
    assert data["common_name"] == "Narra"
    assert data["dbh_cm"] == 24.0
    assert data["height_m"] == 9.0
    assert "notes" not in data
    assert "recorded_by_id" not in data


def test_public_health_log_response_excludes_staff_fields(
    client: TestClient, create_tree, create_health_log
):
    tree = create_tree(notes="Internal tree note")
    create_health_log(
        tree["id"],
        notes="Internal health note",
        dbh_cm=30.0,
        height_m=10.0,
        photo_url="https://example.test/private.jpg",
    )
    client.app.dependency_overrides.pop(get_current_user, None)

    response = client.get(f"/api/public/tree/{tree['id']}/health-logs")

    assert response.status_code == 200
    data = response.json()
    assert data == [{"condition": "Fair", "assessed_date": "2026-10-05"}]
    assert "notes" not in data[0]
    assert "assessed_by_id" not in data[0]
    assert "assessed_by" not in data[0]
    assert "email" not in data[0]
    assert "dbh_cm" not in data[0]
    assert "height_m" not in data[0]
    assert "photo_url" not in data[0]
