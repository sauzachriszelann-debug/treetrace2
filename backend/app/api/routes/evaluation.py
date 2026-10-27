"""G5 evaluation API.

Official results come exclusively from validated, versioned artifacts in
``capstone/evaluation_outputs/runs/``. This API is READ-ONLY for runs:
there is no endpoint that creates or mutates an official run - runs land
through committed source changes so they are reviewable like any other
change (G5 decisions 9, 12).

The legacy ``evaluation_test_results`` table remains as operational
FIELD data: staff-captured rows with unverified provenance. They can be
listed, added, cleared and CSV-imported, but they never contribute to
official accuracy, precision, recall, F1-score, or DBH error metrics -
official metrics exist only inside artifacts.

Honesty guarantees (G5 decisions 2, 3):

* With no runs committed, ``/results`` returns ``state: "not_evaluated"``
  with NO numeric fields. The old fabricated sample (30 images / 80% /
  93.33%) is gone permanently.
* A newest-but-invalid artifact yields ``state: "invalid_artifact"`` with
  its validation issues - never a silent fallback to older numbers.
"""

from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.security import get_current_user, require_admin
from app.db.database import get_db
from app.models.evaluation_result import EvaluationTestResult
from app.models.user import User
from app.schemas.evaluation import EvaluationTestResultCreate, EvaluationTestResultOut
from app.api.routes.tree_submissions import require_staff
from app.services.evaluation_artifacts import (
    RUNS_DIR,
    RUN_ID_RE,
    ArtifactValidationError,
    list_runs,
    load_artifact,
    load_latest_run,
)

router = APIRouter()

CSV_PATH = (
    Path(__file__).resolve().parents[4]
    / "capstone"
    / "evaluation_test_results_template.csv"
)

FIELD_ROW_NOTE = (
    "Field-captured rows have unverified provenance: labels are entered by "
    "staff inside the app, not taken from the frozen test manifest. They are "
    "shown for operational review only and never contribute to official model "
    "accuracy, precision, recall, F1-score, or DBH error metrics."
)

NOT_EVALUATED_REASON = (
    "No committed evaluation run exists yet. Official metrics appear only "
    "after a reproducible run over the frozen, independently labeled test "
    "manifest is generated, validated, and committed."
)


def _clean(value) -> str:
    return str(value or "").strip()


def _to_float(value) -> float | None:
    text = _clean(value)
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def _to_bool(value) -> bool:
    return _clean(value).lower() in {"1", "true", "yes", "y", "success", "successful"}


def _field_rows_block(db: Session) -> dict:
    count = db.query(EvaluationTestResult).count()
    return {
        "count": int(count),
        "included_in_official_metrics": False,
        "note": FIELD_ROW_NOTE,
    }


# ---------------------------------------------------------------------------
# Official evaluation results (artifacts only, read-only)
# ---------------------------------------------------------------------------

@router.get("/results")
def evaluation_results(
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    """State-based official results. Never computed from mutable data."""
    artifact, error = load_latest_run(RUNS_DIR)
    field_rows = _field_rows_block(db)

    if error is not None:
        return {
            "state": "invalid_artifact",
            "reason": error["reason"],
            "run_id": error.get("run_id"),
            "issues": error.get("issues", []),
            "run": None,
            "field_rows": field_rows,
        }
    if artifact is None:
        return {
            "state": "not_evaluated",
            "reason": NOT_EVALUATED_REASON,
            "run": None,
            "field_rows": field_rows,
        }
    return {
        "state": artifact["state"],
        "reason": None,
        "issues": [],
        "run": artifact,
        "field_rows": field_rows,
    }


@router.get("/runs")
def list_evaluation_runs(_: User = Depends(get_current_user)):
    """Newest-first run summaries. Fixtures are never listed."""
    return list_runs(RUNS_DIR)


@router.get("/runs/{run_id}")
def get_evaluation_run(
    run_id: str,
    _: User = Depends(get_current_user),
):
    if not RUN_ID_RE.match(run_id):
        raise HTTPException(status_code=404, detail="Evaluation run not found.")
    path = RUNS_DIR / f"{run_id}.json"
    if not path.exists():
        raise HTTPException(status_code=404, detail="Evaluation run not found.")
    try:
        # No allow_fixture here: fixture artifacts are never official.
        return load_artifact(path, runs_dir=RUNS_DIR)
    except ArtifactValidationError as exc:
        raise HTTPException(
            status_code=422,
            detail={
                "message": "Evaluation run failed validation and is not served.",
                "issues": exc.issues,
            },
        ) from exc


# ---------------------------------------------------------------------------
# Field-captured rows (unverified provenance; staff-only; never official)
# ---------------------------------------------------------------------------

@router.get("/rows", response_model=list[EvaluationTestResultOut])
def list_evaluation_rows(
    db: Session = Depends(get_db),
    _: User = Depends(require_staff),
):
    """Field rows are staff-only operational data (G5 decision 11/12)."""
    return (
        db.query(EvaluationTestResult)
        .order_by(EvaluationTestResult.id.desc())
        .all()
    )


@router.post("/rows", response_model=EvaluationTestResultOut, status_code=201)
def create_evaluation_row(
    payload: EvaluationTestResultCreate,
    db: Session = Depends(get_db),
    _: User = Depends(require_staff),
):
    """Store a field-captured row VERBATIM.

    G5 decision 5: predicted values are persisted exactly as sent - they may
    be null when the model produced no prediction, and the server never
    substitutes ``actual_*`` values for missing predictions.
    """
    row = EvaluationTestResult(**payload.model_dump())
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


@router.post("/import-csv")
def import_evaluation_csv(
    replace: bool = True,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    """Import field rows from the CSV template into the (unofficial) table."""
    import csv

    if not CSV_PATH.exists():
        raise HTTPException(status_code=404, detail=f"CSV not found: {CSV_PATH}")

    with CSV_PATH.open("r", encoding="utf-8-sig", newline="") as handle:
        csv_rows = list(csv.DictReader(handle))

    rows = []
    for item in csv_rows:
        if not _clean(item.get("image_id")):
            continue
        rows.append(
            EvaluationTestResult(
                image_id=_clean(item.get("image_id")),
                actual_species=_clean(item.get("actual_species")) or None,
                predicted_species=_clean(item.get("predicted_species")) or None,
                actual_conservation=_clean(item.get("actual_conservation")) or None,
                predicted_conservation=_clean(item.get("predicted_conservation"))
                or None,
                actual_dbh_cm=_to_float(item.get("actual_dbh_cm")),
                predicted_dbh_cm=_to_float(item.get("predicted_dbh_cm")),
                scan_success=_to_bool(item.get("scan_success")),
                app_success=_to_bool(item.get("app_success")),
                latency_ms=_to_float(item.get("latency_ms")),
            )
        )

    if replace:
        db.query(EvaluationTestResult).delete()
    for row in rows:
        db.add(row)
    db.commit()
    return {"imported": len(rows), "replace": replace, "source": str(CSV_PATH)}


@router.delete("/rows")
def clear_evaluation_rows(
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    deleted = db.query(EvaluationTestResult).delete()
    db.commit()
    return {"deleted": deleted}
