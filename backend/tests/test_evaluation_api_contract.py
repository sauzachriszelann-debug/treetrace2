"""Contract tests for the G5 official evaluation API.

Covers: the honest not-evaluated state, artifact-backed evaluated state,
invalid-artifact surfacing, fixture exclusion, run listing/detail, and
the complete absence of the old fabricated sample numbers.
"""

from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api.routes import evaluation
from app.core.security import get_current_user
from app.db.database import get_db
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


def _authenticate_as(app: FastAPI, db_session, role: UserRole) -> User:
    user = User(
        full_name=f"{role.value} evaluation user",
        email=f"eval-{role.value}-{db_session.query(User).count()}@example.test",
        hashed_password="test-password-hash",
        role=role,
        is_active=True,
    )
    db_session.add(user)
    db_session.commit()
    db_session.refresh(user)
    app.dependency_overrides[get_current_user] = lambda: user
    return user


@pytest.fixture
def as_user(evaluation_app, db_session):
    def set_role(role: UserRole) -> User:
        return _authenticate_as(evaluation_app, db_session, role)

    return set_role


# ---------------------------------------------------------------------------
# Empty state: honest "not evaluated", zero fabricated values
# ---------------------------------------------------------------------------

class TestNotEvaluatedState:
    def test_empty_runs_dir_returns_not_evaluated(
        self, eval_client, as_user, runs_dir
    ):
        as_user(UserRole.citizen)
        response = eval_client.get("/api/evaluation/results")
        assert response.status_code == 200
        body = response.json()
        assert body["state"] == "not_evaluated"
        assert body["run"] is None
        assert "No committed evaluation run" in body["reason"]

    def test_no_numeric_metrics_in_empty_state(self, eval_client, as_user, runs_dir):
        as_user(UserRole.admin)
        text = eval_client.get("/api/evaluation/results").text
        # The historic fabricated fallback values must not exist anywhere.
        for forbidden in ("80%", "93.33%", '"accuracy"', "24/30", "sample labeled"):
            assert forbidden not in text

    def test_field_rows_block_present_and_marked_unofficial(
        self, eval_client, as_user, runs_dir
    ):
        as_user(UserRole.admin)
        body = eval_client.get("/api/evaluation/results").json()
        field_rows = body["field_rows"]
        assert field_rows["count"] == 0
        assert field_rows["included_in_official_metrics"] is False
        assert "never contribute" in field_rows["note"]

    def test_fixture_only_dir_is_not_evaluated(self, eval_client, as_user, runs_dir):
        write_fixture_run(runs_dir, fixture=True)
        as_user(UserRole.admin)
        body = eval_client.get("/api/evaluation/results").json()
        assert body["state"] == "not_evaluated"  # fixtures are never official


# ---------------------------------------------------------------------------
# Evaluated state: artifact-backed metrics with provenance
# ---------------------------------------------------------------------------

class TestEvaluatedState:
    @pytest.fixture(autouse=True)
    def _real_run(self, runs_dir):
        write_fixture_run(runs_dir, run_id="20261021T120000Z-fedcba98",
                          fixture=False)

    def test_evaluated_state_returns_run_with_metrics(self, eval_client, as_user):
        as_user(UserRole.citizen)
        body = eval_client.get("/api/evaluation/results").json()
        assert body["state"] == "evaluated"
        run = body["run"]
        assert run["schema_version"] == "g5.evalrun.v1"
        assert run["fixture"] is False
        assert run["metrics"]["species"]["n_total"] == 4
        assert run["metrics"]["species"]["accuracy"] is not None
        # Sample counts accompany the metrics (G5 decision 8).
        assert run["metrics"]["species"]["n_scoreable"] == 3
        assert run["confusion_matrix"]["labels"]
        # Provenance is present.
        assert run["dataset"]["manifest_sha256"]
        assert run["environment"]["git_commit"]
        assert run["model"]["pipeline"] == "plantnet+gemini"

    def test_confidence_note_keeps_confidence_distinct(
        self, eval_client, as_user
    ):
        as_user(UserRole.admin)
        body = eval_client.get("/api/evaluation/results").json()
        note = body["run"]["metrics"]["confidence_reliability"]["note"]
        assert "not an accuracy claim" in note

    def test_tampered_newest_artifact_is_surfaced_not_hidden(
        self, eval_client, as_user, runs_dir
    ):
        write_fixture_run(runs_dir, run_id="20261022T120000Z-11111111",
                          fixture=False)
        import json

        newest = runs_dir / "20261022T120000Z-11111111.json"
        doc = json.loads(newest.read_text(encoding="utf-8"))
        doc["metrics"]["species"]["accuracy"] = 0.99
        newest.write_text(json.dumps(doc), encoding="utf-8")

        as_user(UserRole.admin)
        body = eval_client.get("/api/evaluation/results").json()
        assert body["state"] == "invalid_artifact"
        # The older, valid run must NOT be silently served instead:
        # no run object at all, and the failing run is named.
        assert body["run"] is None
        assert body["run_id"] == "20261022T120000Z-11111111"
        assert body["issues"]
        assert "20261021T120000Z-fedcba98" not in eval_client.get(
            "/api/evaluation/results"
        ).text


# ---------------------------------------------------------------------------
# Runs listing and detail
# ---------------------------------------------------------------------------

class TestRunsEndpoints:
    @pytest.fixture(autouse=True)
    def _runs(self, runs_dir):
        write_fixture_run(runs_dir, run_id="20261021T120000Z-aaaaaaaa",
                          fixture=False)
        write_fixture_run(runs_dir, run_id="20261022T120000Z-bbbbbbbb",
                          fixture=True)

    def test_list_runs_excludes_fixtures(self, eval_client, as_user):
        as_user(UserRole.field_worker)
        runs = eval_client.get("/api/evaluation/runs").json()
        ids = [r["run_id"] for r in runs]
        assert ids == ["20261021T120000Z-aaaaaaaa"]
        assert runs[0]["image_count"] == 4

    def test_run_detail_returns_full_artifact(self, eval_client, as_user):
        as_user(UserRole.citizen)
        response = eval_client.get(
            "/api/evaluation/runs/20261021T120000Z-aaaaaaaa"
        )
        assert response.status_code == 200
        assert response.json()["metrics"]["species"]["macro_f1"] is not None

    def test_fixture_run_detail_never_served(self, eval_client, as_user):
        as_user(UserRole.admin)
        response = eval_client.get(
            "/api/evaluation/runs/20261022T120000Z-bbbbbbbb"
        )
        assert response.status_code == 422
        assert "never served" in str(response.json())

    def test_unknown_run_404(self, eval_client, as_user):
        as_user(UserRole.admin)
        response = eval_client.get(
            "/api/evaluation/runs/20990101T000000Z-deadbeef"
        )
        assert response.status_code == 404

    def test_malformed_run_id_404(self, eval_client, as_user):
        as_user(UserRole.admin)
        response = eval_client.get("/api/evaluation/runs/..%2F..%2Fetc")
        assert response.status_code == 404


# ---------------------------------------------------------------------------
# Authentication
# ---------------------------------------------------------------------------

class TestAuthentication:
    def test_anonymous_results_401(self, eval_client, runs_dir):
        assert eval_client.get("/api/evaluation/results").status_code == 401

    def test_anonymous_runs_401(self, eval_client, runs_dir):
        assert eval_client.get("/api/evaluation/runs").status_code == 401

    def test_citizens_may_read_official_results(self, eval_client, as_user, runs_dir):
        write_fixture_run(runs_dir, run_id="20261021T120000Z-aaaaaaaa",
                          fixture=False)
        as_user(UserRole.citizen)
        assert eval_client.get("/api/evaluation/results").status_code == 200
        assert eval_client.get("/api/evaluation/runs").status_code == 200
