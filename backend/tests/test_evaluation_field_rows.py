"""Field-row tests: role permissions and scan-time prediction preservation.

G5 decision 5 (predictions stored verbatim, never defaulted to ground
truth), U1 (field rows are unverified and excluded from official
metrics), and requirement 12 (role-based authorization).
"""

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api.routes import evaluation
from app.core.security import get_current_user
from app.db.database import get_db
from app.models.evaluation_result import EvaluationTestResult
from app.models.unknown_species import UnknownSpecies  # noqa: F401  (FK target for create_all)
from app.models.user import User, UserRole

from evaluation_fixtures import write_fixture_run


@pytest.fixture
def evaluation_app(db_session):
    app = FastAPI()
    app.include_router(evaluation.router, prefix="/api/evaluation")

    def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    try:
        yield app
    finally:
        app.dependency_overrides.clear()


@pytest.fixture
def runs_dir(tmp_path, monkeypatch):
    monkeypatch.setattr(evaluation, "RUNS_DIR", tmp_path)
    return tmp_path


@pytest.fixture
def eval_client(evaluation_app):
    with TestClient(evaluation_app) as client:
        yield client


@pytest.fixture
def as_user(evaluation_app, db_session):
    def set_role(role: UserRole) -> User:
        user = User(
            full_name=f"{role.value} field user",
            email=f"field-{role.value}-{db_session.query(User).count()}@example.test",
            hashed_password="test-password-hash",
            role=role,
            is_active=True,
        )
        db_session.add(user)
        db_session.commit()
        db_session.refresh(user)
        evaluation_app.dependency_overrides[get_current_user] = lambda: user
        return user

    return set_role


def _row_payload(**overrides):
    payload = {
        "image_id": "FIELD_1",
        "actual_species": "Narra",
        "predicted_species": "Molave",
        "actual_conservation": "Protected",
        "predicted_conservation": "Protected",
        "actual_dbh_cm": 30.0,
        "predicted_dbh_cm": 27.5,
        "scan_success": True,
        "app_success": True,
        "latency_ms": 2100.0,
    }
    payload.update(overrides)
    return payload


class TestRolePermissions:
    def test_anonymous_cannot_list_or_post(self, eval_client, runs_dir):
        assert eval_client.get("/api/evaluation/rows").status_code == 401
        assert (
            eval_client.post("/api/evaluation/rows", json=_row_payload()).status_code
            == 401
        )

    def test_citizen_cannot_read_field_rows(self, eval_client, as_user, runs_dir):
        as_user(UserRole.citizen)
        assert eval_client.get("/api/evaluation/rows").status_code == 403

    def test_citizen_cannot_create_field_rows(self, eval_client, as_user, runs_dir):
        as_user(UserRole.citizen)
        response = eval_client.post("/api/evaluation/rows", json=_row_payload())
        assert response.status_code == 403

    def test_citizen_cannot_delete_or_import(self, eval_client, as_user, runs_dir):
        as_user(UserRole.citizen)
        assert eval_client.delete("/api/evaluation/rows").status_code == 403
        assert (
            eval_client.post("/api/evaluation/import-csv").status_code == 403
        )

    def test_field_worker_can_create_and_list(
        self, eval_client, as_user, runs_dir
    ):
        as_user(UserRole.field_worker)
        created = eval_client.post(
            "/api/evaluation/rows", json=_row_payload()
        )
        assert created.status_code == 201, created.text
        listed = eval_client.get("/api/evaluation/rows")
        assert listed.status_code == 200
        assert len(listed.json()) == 1

    def test_admin_can_delete(self, eval_client, as_user, runs_dir):
        as_user(UserRole.field_worker)
        eval_client.post("/api/evaluation/rows", json=_row_payload())
        as_user(UserRole.admin)  # re-authenticates the override
        response = eval_client.delete("/api/evaluation/rows")
        assert response.status_code == 200
        assert response.json()["deleted"] == 1

    def test_admin_import_without_csv_is_404_not_fake_data(
        self, eval_client, as_user, runs_dir
    ):
        as_user(UserRole.admin)
        response = eval_client.post("/api/evaluation/import-csv")
        assert response.status_code == 404
        assert "CSV not found" in response.json()["detail"]


class TestPredictionPreservation:
    def test_null_prediction_is_stored_null_not_actual(
        self, eval_client, as_user, runs_dir, db_session
    ):
        as_user(UserRole.field_worker)
        payload = _row_payload(
            predicted_species=None,
            predicted_conservation=None,
            predicted_dbh_cm=None,
            scan_success=False,
            app_success=True,
        )
        created = eval_client.post("/api/evaluation/rows", json=payload)
        assert created.status_code == 201, created.text
        body = created.json()
        assert body["predicted_species"] is None
        assert body["predicted_conservation"] is None
        assert body["predicted_dbh_cm"] is None
        assert body["actual_species"] == "Narra"  # labels intact

        # Persisted exactly, at the database level too.
        row = db_session.query(EvaluationTestResult).one()
        assert row.predicted_species is None
        assert row.predicted_dbh_cm is None
        assert row.actual_species == "Narra"

    def test_prediction_differing_from_actual_roundtrips(
        self, eval_client, as_user, runs_dir
    ):
        as_user(UserRole.field_worker)
        body = eval_client.post(
            "/api/evaluation/rows",
            json=_row_payload(predicted_species="Molave"),
        ).json()
        assert body["predicted_species"] == "Molave"
        assert body["actual_species"] == "Narra"

    def test_wrong_prediction_is_not_corrected_server_side(
        self, eval_client, as_user, runs_dir
    ):
        as_user(UserRole.admin)
        # A deliberately wrong prediction must survive untouched.
        body = eval_client.post(
            "/api/evaluation/rows",
            json=_row_payload(
                predicted_species="Ilang-Ilang",
                predicted_dbh_cm=1.0,
            ),
        ).json()
        assert body["predicted_species"] == "Ilang-Ilang"
        assert body["predicted_dbh_cm"] == 1.0


class TestFieldRowsNeverBecomeOfficialMetrics:
    def test_results_stay_not_evaluated_despite_field_rows(
        self, eval_client, as_user, runs_dir
    ):
        as_user(UserRole.field_worker)
        for index in range(3):
            eval_client.post(
                "/api/evaluation/rows",
                json=_row_payload(image_id=f"FIELD_{index}"),
            )

        body = eval_client.get("/api/evaluation/results").json()
        # U1: field rows are visible as a count, never as computed metrics.
        assert body["state"] == "not_evaluated"
        assert body["run"] is None
        assert body["field_rows"]["count"] == 3
        assert body["field_rows"]["included_in_official_metrics"] is False

    def test_official_metrics_unchanged_by_field_rows(
        self, eval_client, as_user, runs_dir
    ):
        write_fixture_run(runs_dir, run_id="20261021T120000Z-aaaaaaaa",
                          fixture=False)
        as_user(UserRole.field_worker)
        eval_client.post("/api/evaluation/rows", json=_row_payload())

        body = eval_client.get("/api/evaluation/results").json()
        assert body["state"] == "evaluated"
        # Metrics come from the artifact's 4-image dataset, not 5 rows.
        assert body["run"]["metrics"]["species"]["n_total"] == 4
        assert body["field_rows"]["count"] == 1
