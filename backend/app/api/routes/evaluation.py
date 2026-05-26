from collections import Counter, defaultdict
from pathlib import Path
import csv
import math
import re
from types import SimpleNamespace

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.security import get_current_user, require_admin
from app.db.database import get_db
from app.models.evaluation_result import EvaluationTestResult
from app.models.user import User
from app.schemas.evaluation import EvaluationTestResultCreate, EvaluationTestResultOut

router = APIRouter()


PROJECT_ROOT = Path(__file__).resolve().parents[4]
CSV_PATH = PROJECT_ROOT / "capstone" / "evaluation_test_results_template.csv"
REPORT_PATH = PROJECT_ROOT / "capstone" / "evaluation_outputs" / "treetrace_evaluation_report.md"
CONFUSION_PATH = PROJECT_ROOT / "capstone" / "evaluation_outputs" / "species_confusion_matrix.csv"


def _line_value(text: str, label: str) -> str | None:
    match = re.search(rf"^- {re.escape(label)}:\s*(.+)$", text, flags=re.MULTILINE)
    return match.group(1).strip() if match else None


def _metric(label: str, value: str | None, note: str) -> dict:
    return {"label": label, "value": value or "Not tested", "note": note}


def _clean(value) -> str:
    return str(value or "").strip()


def _read_csv_evaluation_rows() -> list[SimpleNamespace]:
    if not CSV_PATH.exists():
        return []

    with CSV_PATH.open("r", encoding="utf-8-sig", newline="") as handle:
        csv_rows = list(csv.DictReader(handle))

    rows = []
    for item in csv_rows:
        if not _clean(item.get("image_id")):
            continue
        rows.append(SimpleNamespace(
            image_id=_clean(item.get("image_id")),
            actual_species=_clean(item.get("actual_species")) or None,
            predicted_species=_clean(item.get("predicted_species")) or None,
            actual_conservation=_clean(item.get("actual_conservation")) or None,
            predicted_conservation=_clean(item.get("predicted_conservation")) or None,
            actual_dbh_cm=_to_float(item.get("actual_dbh_cm")),
            predicted_dbh_cm=_to_float(item.get("predicted_dbh_cm")),
            scan_success=_to_bool(item.get("scan_success")),
            app_success=_to_bool(item.get("app_success")),
            latency_ms=_to_float(item.get("latency_ms")),
        ))
    return rows


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


def _accuracy(rows: list[EvaluationTestResult], actual_attr: str, predicted_attr: str):
    total = 0
    correct = 0
    for row in rows:
        actual = _clean(getattr(row, actual_attr)).lower()
        predicted = _clean(getattr(row, predicted_attr)).lower()
        if not actual or not predicted:
            continue
        total += 1
        if actual == predicted:
            correct += 1
    return correct, total, (correct / total * 100) if total else 0


def _macro_f1(rows: list[EvaluationTestResult]) -> float:
    labels = sorted(
        {_clean(row.actual_species) for row in rows if _clean(row.actual_species)}
        | {_clean(row.predicted_species) for row in rows if _clean(row.predicted_species)}
    )
    if not labels:
        return 0
    scores = []
    for label in labels:
        tp = fp = fn = 0
        for row in rows:
            actual = _clean(row.actual_species)
            predicted = _clean(row.predicted_species)
            if predicted == label and actual == label:
                tp += 1
            elif predicted == label and actual != label:
                fp += 1
            elif predicted != label and actual == label:
                fn += 1
        precision = tp / (tp + fp) if tp + fp else 0
        recall = tp / (tp + fn) if tp + fn else 0
        scores.append((2 * precision * recall / (precision + recall)) if precision + recall else 0)
    return sum(scores) / len(scores)


def _dbh_metrics(rows: list[EvaluationTestResult]):
    errors = []
    for row in rows:
        if row.actual_dbh_cm is None or row.predicted_dbh_cm is None:
            continue
        errors.append(abs(row.actual_dbh_cm - row.predicted_dbh_cm))
    if not errors:
        return 0, 0, 0
    mae = sum(errors) / len(errors)
    rmse = math.sqrt(sum(error * error for error in errors) / len(errors))
    return len(errors), mae, rmse


def _success_rate(rows: list[EvaluationTestResult], attr: str):
    total = len(rows)
    success = sum(1 for row in rows if getattr(row, attr) is True)
    return success, total, (success / total * 100) if total else 0


def _average_latency(rows: list[EvaluationTestResult]) -> float:
    values = [row.latency_ms for row in rows if row.latency_ms is not None]
    return sum(values) / len(values) if values else 0


def _confusion_matrix(rows: list[EvaluationTestResult]):
    labels = sorted(
        {_clean(row.actual_species) for row in rows if _clean(row.actual_species)}
        | {_clean(row.predicted_species) for row in rows if _clean(row.predicted_species)}
    )
    matrix = defaultdict(Counter)
    for row in rows:
        actual = _clean(row.actual_species)
        predicted = _clean(row.predicted_species)
        if actual and predicted:
            matrix[actual][predicted] += 1
    return {
        "labels": labels,
        "rows": [
            {"actual": actual, "predicted": {predicted: matrix[actual][predicted] for predicted in labels}}
            for actual in labels
        ],
    }


def _database_results(rows: list[EvaluationTestResult]) -> dict:
    species_correct, species_total, species_acc = _accuracy(rows, "actual_species", "predicted_species")
    cons_correct, cons_total, cons_acc = _accuracy(rows, "actual_conservation", "predicted_conservation")
    dbh_count, dbh_mae, dbh_rmse = _dbh_metrics(rows)
    scan_success, scan_total, scan_rate = _success_rate(rows, "scan_success")
    app_success, app_total, app_rate = _success_rate(rows, "app_success")
    latency = _average_latency(rows)
    macro_f1 = _macro_f1(rows)

    return {
        "source": "database",
        "row_count": len(rows),
        "confusion_matrix": _confusion_matrix(rows),
        "metrics": [
            _metric("Test Images", str(len(rows)), "database evaluation rows"),
            _metric("Correct Species", f"{species_correct}/{species_total}", "actual vs predicted species"),
            _metric("Species Accuracy", f"{species_acc:.2f}%", "correct species / total images"),
            _metric("Species F1-score", f"{macro_f1:.3f}", "macro average across tested species"),
            _metric("Conservation Accuracy", f"{cons_acc:.2f}%", f"{cons_correct}/{cons_total} correct conservation classifications"),
            _metric("Measured DBH Set", str(dbh_count), "trees with manual DBH"),
            _metric("DBH MAE", f"+/- {dbh_mae:.2f} cm", "mean absolute DBH error"),
            _metric("DBH RMSE", f"{dbh_rmse:.2f} cm", "root mean squared DBH error"),
            _metric("Scan Success", f"{scan_success}/{scan_total} ({scan_rate:.2f}%)", "completed app scan attempts"),
            _metric("App Success Rate", f"{app_success}/{app_total} ({app_rate:.2f}%)", "successful workflow attempts"),
            _metric("Average Latency", f"{latency:.0f} ms", "average response time"),
        ],
    }


def _file_results() -> dict:
    if not REPORT_PATH.exists():
        return {
            "source": "sample",
            "message": "No database rows or generated evaluation report found.",
            "metrics": [
                _metric("Test Images", "30", "sample labeled tree photos"),
                _metric("Correct Species", "24/30", "replace with actual result"),
                _metric("Species Accuracy", "80%", "correct species / total images"),
                _metric("Conservation Accuracy", "93.33%", "correct protected status"),
                _metric("Measured DBH Set", "10", "trees with manual DBH"),
                _metric("Average DBH Error", "+/- 10-30 cm", "predicted vs measured DBH"),
                _metric("Scan Success", "30/30", "completed app scan attempts"),
                _metric("App Success Rate", "100%", "successful scans / attempts"),
            ],
        }

    text = REPORT_PATH.read_text(encoding="utf-8")
    return {
        "source": "generated_file",
        "report_path": str(REPORT_PATH),
        "confusion_matrix_path": str(CONFUSION_PATH) if CONFUSION_PATH.exists() else None,
        "metrics": [
            _metric("Test Images", _line_value(text, "Test images"), "labeled tree photos"),
            _metric("Correct Species", _line_value(text, "Correct species predictions"), "actual vs predicted species"),
            _metric("Species Accuracy", _line_value(text, "Species accuracy"), "correct species / total images"),
            _metric("Species F1-score", _line_value(text, "Species macro F1-score"), "macro average across tested species"),
            _metric("Conservation Accuracy", _line_value(text, "Conservation accuracy"), "correct conservation classification"),
            _metric("Measured DBH Set", _line_value(text, "Measured DBH set"), "trees with manual DBH"),
            _metric("DBH MAE", _line_value(text, "DBH MAE"), "mean absolute DBH error"),
            _metric("DBH RMSE", _line_value(text, "DBH RMSE"), "root mean squared DBH error"),
            _metric("Scan Success", _line_value(text, "Scan success"), "completed app scan attempts"),
            _metric("App Success Rate", _line_value(text, "App success"), "successful workflow attempts"),
            _metric("Average Latency", _line_value(text, "Average latency"), "average response time"),
        ],
    }


@router.get("/rows", response_model=list[EvaluationTestResultOut])
def list_evaluation_rows(
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    return db.query(EvaluationTestResult).order_by(EvaluationTestResult.id.desc()).all()


@router.post("/rows", response_model=EvaluationTestResultOut, status_code=201)
def create_evaluation_row(
    payload: EvaluationTestResultCreate,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
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
    if not CSV_PATH.exists():
        raise HTTPException(status_code=404, detail=f"CSV not found: {CSV_PATH}")

    csv_rows = _read_csv_evaluation_rows()

    if replace:
        db.query(EvaluationTestResult).delete()

    imported = 0
    for item in csv_rows:
        row = EvaluationTestResult(
            image_id=item.image_id,
            actual_species=item.actual_species,
            predicted_species=item.predicted_species,
            actual_conservation=item.actual_conservation,
            predicted_conservation=item.predicted_conservation,
            actual_dbh_cm=item.actual_dbh_cm,
            predicted_dbh_cm=item.predicted_dbh_cm,
            scan_success=item.scan_success,
            app_success=item.app_success,
            latency_ms=item.latency_ms,
        )
        db.add(row)
        imported += 1
    db.commit()
    return {"imported": imported, "replace": replace, "source": str(CSV_PATH)}


@router.delete("/rows")
def clear_evaluation_rows(
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    deleted = db.query(EvaluationTestResult).delete()
    db.commit()
    return {"deleted": deleted}


@router.get("/results")
def evaluation_results(
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    rows = db.query(EvaluationTestResult).order_by(EvaluationTestResult.id.asc()).all()
    csv_rows = _read_csv_evaluation_rows()
    if csv_rows and len(csv_rows) > len(rows):
        result = _database_results(csv_rows)
        result["source"] = "csv_pending_import"
        result["message"] = "Using the newer CSV because it has more rows than the database."
        return result
    if rows:
        return _database_results(rows)
    return _file_results()
