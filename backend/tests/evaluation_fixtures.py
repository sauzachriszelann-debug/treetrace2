"""Shared builders for G5 evaluation test fixtures.

Everything built here is SYNTHETIC and marked ``fixture: true`` so it can
never be served as an official result. The builders use the production
``assemble_artifact``/``write_run`` code path, which keeps test fixtures
structurally identical to real runs.
"""

from __future__ import annotations

from pathlib import Path

from app.services.evaluation_artifacts import assemble_artifact, write_run

MANIFEST_SHA256 = "a" * 64
PROMPT_SHA256 = "b" * 64


def fixture_rows() -> list[dict]:
    """Four synthetic labeled rows: 3 scoreable species, 1 abstention."""
    return [
        {
            "image_id": "IMG_001",
            "true_species": "Narra",
            "pred_species": "Narra",
            "true_conservation": "Protected",
            "pred_conservation": "Protected",
            "confidence_band": "High",
            "confidence_score": 0.91,
            "measured_dbh_cm": 30.0,
            "predicted_dbh_cm": 32.0,
            "dbh_pipeline": "gemini_dbh",
            "latency_ms": 2000.0,
            "prediction_snapshot": {"common_name": "Narra", "source": "plantnet+gemini"},
            "raw": {"source": "plantnet", "results": [{"score": 0.61}]},
        },
        {
            "image_id": "IMG_002",
            "true_species": "Narra",
            "pred_species": "Molave",
            "true_conservation": "Protected",
            "pred_conservation": "Protected",
            "confidence_band": "Medium",
            "confidence_score": 0.55,
            "measured_dbh_cm": 20.0,
            "predicted_dbh_cm": 18.0,
            "dbh_pipeline": "gemini_dbh",
            "latency_ms": 2500.0,
            "prediction_snapshot": {"common_name": "Molave", "source": "plantnet+gemini"},
            "raw": {"source": "gemini", "candidates": [{"finishReason": "STOP"}]},
        },
        {
            "image_id": "IMG_003",
            "true_species": "Molave",
            "pred_species": "Molave",
            "true_conservation": "Endangered",
            "pred_conservation": "Endangered",
            "confidence_band": "Low",
            "confidence_score": 0.40,
            "measured_dbh_cm": 15.0,
            "predicted_dbh_cm": 16.0,
            "dbh_pipeline": "gemini_dbh",
            "latency_ms": 1800.0,
            "prediction_snapshot": {"common_name": "Molave", "source": "gemini"},
            "raw": {"source": "gemini", "text": "molave identified"},
        },
        {
            "image_id": "IMG_004",
            "true_species": "Ilang-Ilang",
            "pred_species": None,
            "true_conservation": "Not Listed",
            "pred_conservation": None,
            "confidence_band": None,
            "confidence_score": None,
            "measured_dbh_cm": None,
            "predicted_dbh_cm": None,
            "dbh_pipeline": "gemini_dbh",
            "latency_ms": 900.0,
            "prediction_snapshot": None,
            "raw": {"not_identified": True, "reason": "no plant visible"},
        },
    ]


def fixture_dataset() -> dict:
    return {
        "name": "synthetic-fixture-set",
        "manifest_sha256": MANIFEST_SHA256,
        "split": "test",
        "label_source": "synthetic_fixture",
        "labeler": "backend tests",
        "labeled_at": "2026-10-21T00:00:00Z",
        "training_hashes_available": False,
        "training_overlap_count": 0,
    }


def fixture_model() -> dict:
    return {
        "pipeline": "plantnet+gemini",
        "components": [
            {"name": "plantnet", "api": "identify-all-v2"},
            {"name": "gemini", "model_id": "gemini-2.0-flash-lite",
             "prompt_sha256": PROMPT_SHA256, "temperature": 0.1},
            {"name": "gbif", "endpoint": "species/match"},
        ],
        "confidence_buckets": {"High": ">=0.55", "Medium": ">=0.20", "Low": "<0.20"},
        "local_tflite_present": False,
        "yolo_dbh_enabled": False,
        "health_classifier": "none",
    }


def fixture_environment() -> dict:
    return {
        "git_commit": "0000000000000000000000000000000000000000",
        "runner": "evaluation_fixtures",
        "python": "3.11",
        "started_at": "2026-10-21T12:00:00Z",
        "finished_at": "2026-10-21T12:00:04Z",
        "external_api_calls": False,
    }


def build_artifact(
    *,
    run_id: str = "20261021T120000Z-abcdef12",
    rows: list[dict] | None = None,
    fixture: bool = True,
    dataset: dict | None = None,
    model: dict | None = None,
    environment: dict | None = None,
    state: str = "evaluated",
) -> tuple[dict, dict]:
    """Return (artifact, raw_object) using the production assembler."""
    return assemble_artifact(
        run_id=run_id,
        state=state,
        dataset=dict(dataset or fixture_dataset()),
        model=dict(model or fixture_model()),
        environment=dict(environment or fixture_environment()),
        rows=list(rows if rows is not None else fixture_rows()),
        fixture=fixture,
    )


def write_fixture_run(
    runs_dir: Path,
    *,
    run_id: str = "20261021T120000Z-abcdef12",
    rows: list[dict] | None = None,
    fixture: bool = True,
    dataset: dict | None = None,
    model: dict | None = None,
    environment: dict | None = None,
    state: str = "evaluated",
) -> Path:
    """Assemble and persist a run; returns the artifact path."""
    artifact, raw = build_artifact(
        run_id=run_id, rows=rows, fixture=fixture, dataset=dataset,
        model=model, environment=environment, state=state,
    )
    artifact_path, _ = write_run(artifact, raw, runs_dir, allow_fixture=True)
    return artifact_path
