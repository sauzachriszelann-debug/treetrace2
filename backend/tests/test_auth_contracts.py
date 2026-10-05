from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy.exc import OperationalError

from app.db.database import get_db


def test_valid_credentials_return_a_token(client: TestClient) -> None:
    registration = client.post(
        "/api/auth/register",
        json={
            "full_name": "Auth Test User",
            "email": "auth-user@example.com",
            "password": "valid-test-password",
        },
    )
    assert registration.status_code == 201, registration.text

    response = client.post(
        "/api/auth/login",
        json={"email": "auth-user@example.com", "password": "valid-test-password"},
    )

    assert response.status_code == 200, response.text
    assert response.json()["access_token"]
    assert response.json()["token_type"] == "bearer"


def test_invalid_credentials_return_json_401(client: TestClient) -> None:
    response = client.post(
        "/api/auth/login",
        json={"email": "missing-user@example.com", "password": "invalid-password"},
    )

    assert response.status_code == 401
    assert response.json()["detail"] == "Invalid email or password"


def test_database_failure_returns_json_503(api_app: FastAPI) -> None:
    class UnavailableDatabase:
        def query(self, *_args, **_kwargs):
            raise OperationalError("SELECT 1", {}, RuntimeError("database unavailable"))

    api_app.dependency_overrides[get_db] = lambda: UnavailableDatabase()
    with TestClient(api_app) as client:
        response = client.post(
            "/api/auth/login",
            json={"email": "missing-user@example.com", "password": "invalid-password"},
        )

    assert response.status_code == 503
    assert response.json()["detail"] == (
        "Authentication service is temporarily unavailable. Please try again later."
    )
