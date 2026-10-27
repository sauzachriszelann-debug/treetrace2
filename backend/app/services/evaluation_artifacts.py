"""G5 evaluation artifacts: assembly, sanitization, validation, loading.

Official TreeTrace evaluation results exist ONLY as versioned JSON
artifacts with a gzipped raw-response sidecar, committed to
``capstone/evaluation_outputs/runs/``. The API never computes metrics
from mutable data and never exposes a write path for runs: runs arrive
through code review like any other source change.

Trust model (G5 decisions 5, 9, 10, 11):

* ``validate_artifact`` checks internal consistency: every stored metric
  is recomputed from the stored counts, so a hand-edited number is
  rejected. Full verification against raw responses is
  ``verify_run`` (scripts/verify_run.py).
* Synthetic fixtures (``fixture: true``) are never served as official
  results unless a caller explicitly opts in (tests only).
* Artifacts whose dataset overlaps known training hashes are rejected:
  overlapping data blocks the run instead of silently being dropped.
* Raw sidecars must pass the credential/PII sanitizer; they never
  contain request URLs, headers, or keys.
* ``health_classifier`` must be the literal ``"none"``: TreeTrace has
  no tree-health AI classifier and no artifact may claim one.
"""

from __future__ import annotations

import gzip
import hashlib
import json
import re
from pathlib import Path
from typing import Any

from app.services.evaluation_metrics import (
    CONFIDENCE_RELIABILITY_NOTE,
    LOW_SUPPORT_THRESHOLD,
    _r6,
    wilson_interval,
)

SCHEMA_VERSION = "g5.evalrun.v1"
RAW_SCHEMA_VERSION = "g5.raw.v1"

REPO_ROOT = Path(__file__).resolve().parents[3]
RUNS_DIR = REPO_ROOT / "capstone" / "evaluation_outputs" / "runs"

RUN_ID_RE = re.compile(r"^\d{8}T\d{6}Z-[0-9a-f]{8}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")

VALID_STATES = ("evaluated", "unavailable", "no_data")
VALID_BUCKETS = ("High", "Medium", "Low", "Other", "Unreported")

# Sanitizer: these patterns must never appear inside a raw sidecar.
_CREDENTIAL_RES = [
    re.compile(r"AIza[0-9A-Za-z_\-]{35}"),                        # Google API key
    re.compile(r"(?i)\bapi[-_]?key\s*[=:]\s*[\"']?[A-Za-z0-9_\-]{6,}"),
    re.compile(r"(?i)\bbearer\s+[A-Za-z0-9._\-]{8,}"),
    re.compile(r"(?i)\bauthorization\s*[=:]"),
    re.compile(r"(?i)[?&]key=[A-Za-z0-9_\-]{6,}"),
    re.compile(r"(?i)[?&]token=[A-Za-z0-9._\-]{8,}"),
    re.compile(r"(?i)\bpassword\s*[=:]"),
    re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"),  # email PII
]
# JSON key names that indicate credentials or precise location data.
_SENSITIVE_KEYS = {
    "api_key", "apikey", "authorization", "token", "secret", "password",
    "lat", "lng", "latitude", "longitude",
}


class ArtifactValidationError(Exception):
    """Raised when an artifact fails validation; ``.issues`` names each failure."""

    def __init__(self, issues: list[str]):
        self.issues = list(issues)
        super().__init__(
            "unsafe evaluation artifact: " + "; ".join(self.issues)
        )


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(Path(path).read_bytes())


def _gzip_raw(raw_object: dict) -> bytes:
    """Deterministic gzip bytes for a raw object (mtime=0, sorted keys)."""
    return gzip.compress(
        json.dumps(raw_object, sort_keys=True, indent=1).encode("utf-8"),
        mtime=0,
    )


# ---------------------------------------------------------------------------
# Raw-response sanitization (shared by writer and validator)
# ---------------------------------------------------------------------------

def find_sensitive_content(obj: Any, path: str = "$") -> list[str]:
    """Return issue strings for credentials/PII/location found anywhere in obj."""
    issues: list[str] = []
    if isinstance(obj, dict):
        for key, value in obj.items():
            key_l = str(key).strip().lower()
            if key_l in _SENSITIVE_KEYS:
                issues.append(f"raw response exposes sensitive key {path}.{key}")
            issues.extend(find_sensitive_content(value, f"{path}.{key}"))
    elif isinstance(obj, list):
        for index, value in enumerate(obj):
            issues.extend(find_sensitive_content(value, f"{path}[{index}]"))
    elif isinstance(obj, str):
        for pattern in _CREDENTIAL_RES:
            if pattern.search(obj):
                issues.append(
                    f"raw response at {path} matches sensitive pattern "
                    f"{pattern.pattern!r}"
                )
                break
    return issues


def sanitize_raw(raw: Any) -> None:
    """Raise ValueError when a raw-response payload carries secrets or PII."""
    issues = find_sensitive_content(raw)
    if issues:
        raise ValueError("raw responses failed sanitization: " + "; ".join(issues))


# ---------------------------------------------------------------------------
# Assembly (single source of truth for artifact structure; used by the
# offline runner AND the test fixtures, so both stay identical)
# ---------------------------------------------------------------------------

def assemble_artifact(
    *,
    run_id: str,
    state: str,
    dataset: dict,
    model: dict,
    environment: dict,
    rows: list[dict],
    fixture: bool = False,
) -> tuple[dict, dict]:
    """Build (artifact, raw_object) from joined evaluation rows.

    ``rows`` follow the ``compute_full_metrics`` row format. The raw object
    stores per-image original responses for later recalculation without any
    external API call.
    """
    from app.services.evaluation_metrics import compute_full_metrics

    metrics, confusion = compute_full_metrics(rows)

    dataset_block = dict(dataset)
    dataset_block.setdefault("image_count", len(rows))
    support: dict[str, int] = {}
    for row in rows:
        true_label = str(row.get("true_species") or "").strip()
        if true_label:
            support[true_label] = support.get(true_label, 0) + 1
    dataset_block.setdefault("per_class_support", support)

    artifact = {
        "schema_version": SCHEMA_VERSION,
        "run_id": run_id,
        "state": state,
        "fixture": bool(fixture),
        "dataset": dataset_block,
        "model": model,
        "environment": environment,
        "metrics": metrics,
        "confusion_matrix": confusion,
        "raw_responses_ref": None,  # filled below from the raw sidecar bytes
    }
    raw_object = {
        "schema_version": RAW_SCHEMA_VERSION,
        "run_id": run_id,
        "responses": {
            str(row.get("image_id")): {
                # Ground truth (from the frozen manifest)
                "true_species": row.get("true_species"),
                "true_conservation": row.get("true_conservation"),
                "measured_dbh_cm": row.get("measured_dbh_cm"),
                # Prediction exactly as it was made at scan time (G5 decision 5)
                "predicted_species": row.get("pred_species"),
                "predicted_conservation": row.get("pred_conservation"),
                "confidence_band": row.get("confidence_band"),
                "confidence_score": row.get("confidence_score"),
                "predicted_dbh_cm": row.get("predicted_dbh_cm"),
                "dbh_pipeline": row.get("dbh_pipeline"),
                "latency_ms": row.get("latency_ms"),
                "prediction": row.get("prediction_snapshot"),
                # Original external API response, credentials-free
                "raw": row.get("raw"),
            }
            for row in rows
            if row.get("image_id") is not None
        },
    }
    raw_bytes = _gzip_raw(raw_object)
    artifact["raw_responses_ref"] = {
        "file": f"{run_id}.raw.json.gz",
        "sha256": sha256_bytes(raw_bytes),
    }
    return artifact, raw_object


def write_run(
    artifact: dict,
    raw_object: dict,
    runs_dir: Path | None = None,
    *,
    allow_fixture: bool = False,
) -> tuple[Path, Path]:
    """Validate and persist an artifact plus its gzipped raw sidecar."""
    runs_dir = Path(runs_dir) if runs_dir else RUNS_DIR
    runs_dir.mkdir(parents=True, exist_ok=True)

    run_id = artifact.get("run_id")
    if not isinstance(run_id, str) or not RUN_ID_RE.match(run_id):
        raise ArtifactValidationError(
            [f"run_id {run_id!r} does not match {RUN_ID_RE.pattern}"]
        )

    raw_bytes = _gzip_raw(raw_object)
    artifact["raw_responses_ref"] = {
        "file": f"{run_id}.raw.json.gz",
        "sha256": sha256_bytes(raw_bytes),
    }

    issues = validate_artifact(artifact, runs_dir=runs_dir, allow_fixture=allow_fixture,
                               raw_bytes=raw_bytes)
    if issues:
        raise ArtifactValidationError(issues)

    artifact_path = runs_dir / f"{run_id}.json"
    raw_path = runs_dir / f"{run_id}.raw.json.gz"
    artifact_path.write_text(
        json.dumps(artifact, sort_keys=True, indent=1) + "\n", encoding="utf-8"
    )
    raw_path.write_bytes(raw_bytes)
    return artifact_path, raw_path


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

def _is_int(value) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _is_number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _require_str(issues: list[str], obj: dict, key: str, where: str) -> None:
    value = obj.get(key)
    if not isinstance(value, str) or not value.strip():
        issues.append(f"{where}.{key} must be a non-empty string")


def _require_bool(issues: list[str], obj: dict, key: str, where: str) -> None:
    if not isinstance(obj.get(key), bool):
        issues.append(f"{where}.{key} must be a boolean")


def _validate_species(species: dict, image_count: int, issues: list[str]) -> None:
    where = "metrics.species"
    for key in ("n_total", "n_scoreable", "n_no_prediction", "n_missing_true_label",
                "n_classes", "n_low_support", "low_support_threshold"):
        if not _is_int(species.get(key)) or species.get(key) < 0:
            issues.append(f"{where}.{key} must be a non-negative integer")

    n_total = species.get("n_total")
    if not _is_int(n_total) or n_total != image_count:
        issues.append(
            f"{where}.n_total ({n_total}) must equal dataset.image_count "
            f"({image_count})"
        )
        return

    parts = [species.get("n_scoreable"), species.get("n_no_prediction"),
             species.get("n_missing_true_label")]
    if all(_is_int(p) for p in parts):
        if sum(parts) != n_total:
            issues.append(
                f"{where} sample counts ({parts}) must sum to n_total ({n_total})"
            )
    else:
        issues.append(f"{where} sample counts must be integers")
        return

    n_scoreable = species.get("n_scoreable")

    # Coverage must match the counts.
    expected_coverage = _r6(n_scoreable / n_total) if n_total else None
    if species.get("coverage") != expected_coverage:
        issues.append(
            f"{where}.coverage ({species.get('coverage')}) must equal "
            f"{expected_coverage} (scoreable/total)"
        )

    # Accuracy must match the per-class true positives, and CI must match.
    per_class = species.get("per_class")
    if not isinstance(per_class, list):
        issues.append(f"{where}.per_class must be a list")
        return
    if species.get("n_classes") != len(per_class):
        issues.append(f"{where}.n_classes must equal len(per_class)")

    correct = 0
    support_sum = 0
    seen_classes: set[str] = set()
    precisions, recalls, f1s, supports = [], [], [], []
    for entry in per_class:
        label = entry.get("class")
        if not isinstance(label, str) or not label:
            issues.append(f"{where}.per_class entry missing class label")
            continue
        if label in seen_classes:
            issues.append(f"{where}.per_class duplicate class {label!r}")
        seen_classes.add(label)
        for key in ("support", "predicted", "tp", "fp", "fn"):
            if not _is_int(entry.get(key)) or entry.get(key) < 0:
                issues.append(f"{where}.{label}.{key} must be a non-negative integer")
        tp, fp, fn = entry.get("tp", 0), entry.get("fp", 0), entry.get("fn", 0)
        support = entry.get("support", 0)
        predicted_count = entry.get("predicted")
        if all(_is_int(v) and v >= 0 for v in (tp, fp, fn, support, predicted_count)):
            correct += tp
            support_sum += support
            if predicted_count != tp + fp:
                issues.append(
                    f"{where}.{label}.predicted ({predicted_count}) must equal "
                    f"tp + fp ({tp + fp})"
                )
            if support != tp + fn:
                issues.append(
                    f"{where}.{label}.support ({support}) must equal tp + fn "
                    f"({tp + fn})"
                )
        low_expected = (
            _is_int(support) and support < species.get(
                "low_support_threshold", LOW_SUPPORT_THRESHOLD
            )
        )
        if entry.get("low_support") is not low_expected:
            issues.append(f"{where}.{label}.low_support flag inconsistent with support")
        for key in ("precision", "recall", "f1"):
            value = entry.get(key)
            if value is not None and not _is_number(value):
                issues.append(f"{where}.{label}.{key} must be a number")
        precisions.append(entry.get("precision") or 0.0)
        recalls.append(entry.get("recall") or 0.0)
        f1s.append(entry.get("f1") or 0.0)
        supports.append(support if _is_int(support) else 0)

    if support_sum != n_scoreable:
        issues.append(
            f"{where} per-class support sum ({support_sum}) must equal "
            f"n_scoreable ({n_scoreable})"
        )
    if species.get("n_low_support") != sum(
        1 for s in supports if s < species.get("low_support_threshold", LOW_SUPPORT_THRESHOLD)
    ):
        issues.append(f"{where}.n_low_support inconsistent with per-class support")

    # Recompute macro / weighted averages from the stored per-class values.
    if per_class:
        expected = {
            "macro_precision": _r6(sum(precisions) / len(precisions)),
            "macro_recall": _r6(sum(recalls) / len(recalls)),
            "macro_f1": _r6(sum(f1s) / len(f1s)),
        }
        weight_sum = sum(supports)
        if weight_sum:
            expected.update({
                "weighted_precision": _r6(
                    sum(p * s for p, s in zip(precisions, supports)) / weight_sum),
                "weighted_recall": _r6(
                    sum(r * s for r, s in zip(recalls, supports)) / weight_sum),
                "weighted_f1": _r6(
                    sum(f * s for f, s in zip(f1s, supports)) / weight_sum),
            })
        else:
            expected.update({
                "weighted_precision": None, "weighted_recall": None,
                "weighted_f1": None,
            })
    else:
        expected = {
            "macro_precision": None, "macro_recall": None, "macro_f1": None,
            "weighted_precision": None, "weighted_recall": None,
            "weighted_f1": None,
        }
    for key, value in expected.items():
        if species.get(key) != value:
            issues.append(
                f"{where}.{key} ({species.get(key)}) does not match recomputed "
                f"value ({value})"
            )

    # Accuracy and CI must match the counted correct predictions.
    if n_scoreable:
        expected_acc = _r6(correct / n_scoreable)
        if species.get("accuracy") != expected_acc:
            issues.append(
                f"{where}.accuracy ({species.get('accuracy')}) does not match "
                f"recomputed value ({expected_acc})"
            )
        expected_ci = wilson_interval(correct, n_scoreable)
        if species.get("accuracy_ci95") != expected_ci:
            issues.append(f"{where}.accuracy_ci95 does not match recomputed interval")
    else:
        if species.get("accuracy") is not None:
            issues.append(f"{where}.accuracy must be null when n_scoreable is 0")
        if species.get("accuracy_ci95") is not None:
            issues.append(f"{where}.accuracy_ci95 must be null when n_scoreable is 0")


def _validate_conservation(cons: dict, image_count: int, issues: list[str]) -> None:
    where = "metrics.conservation"
    n_total = cons.get("n_total")
    if n_total != image_count:
        issues.append(f"{where}.n_total must equal dataset.image_count")
    for key in ("n_scoreable", "n_no_prediction"):
        if not _is_int(cons.get(key)) or cons.get(key) < 0:
            issues.append(f"{where}.{key} must be a non-negative integer")
    n_scoreable = cons.get("n_scoreable")
    acc = cons.get("accuracy")
    ci = cons.get("accuracy_ci95")
    if not _is_int(n_scoreable):
        return
    if n_scoreable == 0:
        if acc is not None or ci is not None:
            issues.append(f"{where}: accuracy/CI must be null when n_scoreable is 0")
        return
    if not _is_number(acc) or not 0.0 <= acc <= 1.0:
        issues.append(f"{where}.accuracy must be a number in [0, 1]")
        return
    correct = round(acc * n_scoreable)
    if abs(acc - correct / n_scoreable) > 1e-6:
        issues.append(
            f"{where}.accuracy ({acc}) is not a whole ratio of "
            f"n_scoreable ({n_scoreable})"
        )
    if ci != wilson_interval(correct, n_scoreable):
        issues.append(f"{where}.accuracy_ci95 does not match recomputed interval")


def _validate_reliability(block: dict, species: dict, issues: list[str]) -> None:
    where = "metrics.confidence_reliability"
    if block.get("note") != CONFIDENCE_RELIABILITY_NOTE:
        issues.append(
            f"{where}.note must keep confidence and empirical accuracy distinct"
        )
    buckets = block.get("buckets")
    if not isinstance(buckets, list):
        issues.append(f"{where}.buckets must be a list")
        return
    names = [b.get("bucket") for b in buckets if isinstance(b, dict)]
    if names != list(VALID_BUCKETS):
        issues.append(f"{where}.buckets must be exactly {list(VALID_BUCKETS)}")
        return
    total_n = 0
    for bucket in buckets:
        n = bucket.get("n")
        n_scoreable = bucket.get("n_scoreable")
        if not _is_int(n) or n < 0 or not _is_int(n_scoreable) or n_scoreable < 0:
            issues.append(f"{where}.{bucket.get('bucket')} counts must be integers")
            return
        total_n += n
        mean_score = bucket.get("mean_reported_confidence")
        if mean_score is not None and not _is_number(mean_score):
            issues.append(f"{where}.{bucket.get('bucket')}.mean_reported_confidence invalid")
        empirical = bucket.get("empirical_accuracy")
        if n_scoreable == 0 and empirical is not None:
            issues.append(
                f"{where}.{bucket.get('bucket')}.empirical_accuracy must be null "
                "when n_scoreable is 0"
            )
        if n_scoreable and (not _is_number(empirical) or not 0 <= empirical <= 1):
            issues.append(
                f"{where}.{bucket.get('bucket')}.empirical_accuracy must be in [0, 1]"
            )
    if total_n != species.get("n_total"):
        issues.append(
            f"{where} bucket counts sum to {total_n}, must equal "
            f"n_total ({species.get('n_total')})"
        )


def _validate_dbh(dbh: dict, issues: list[str]) -> None:
    where = "metrics.dbh"
    n = dbh.get("n")
    if not _is_int(n) or n < 0:
        issues.append(f"{where}.n must be a non-negative integer")
        return
    values = (dbh.get("mae_cm"), dbh.get("rmse_cm"), dbh.get("bias_cm"))
    if n == 0:
        if any(v is not None for v in values):
            issues.append(
                f"{where}: MAE/RMSE/bias must be null when n is 0 (a missing "
                "measurement must not read as 0 cm error)"
            )
        return
    mae, rmse, bias = values
    if not all(_is_number(v) for v in values):
        issues.append(f"{where}: MAE/RMSE/bias must be numbers when n > 0")
        return
    if mae < 0 or rmse < 0:
        issues.append(f"{where}: MAE/RMSE must be non-negative")
    if rmse + 1e-9 < mae:
        issues.append(f"{where}.rmse_cm must be >= mae_cm")


def _validate_latency(latency: dict, issues: list[str]) -> None:
    where = "metrics.latency_ms"
    n = latency.get("n")
    if not _is_int(n) or n < 0:
        issues.append(f"{where}.n must be a non-negative integer")
        return
    values = (latency.get("mean_ms"), latency.get("p50_ms"), latency.get("p95_ms"))
    if n == 0:
        if any(v is not None for v in values):
            issues.append(f"{where}: percentiles must be null when n is 0")
        return
    if not all(_is_number(v) for v in values):
        issues.append(f"{where}: percentiles must be numbers when n > 0")
        return
    if latency.get("p50_ms") > latency.get("p95_ms"):
        issues.append(f"{where}.p50_ms must be <= p95_ms")


def _validate_confusion(confusion: dict, species: dict, issues: list[str]) -> None:
    where = "confusion_matrix"
    labels = confusion.get("labels")
    counts = confusion.get("counts")
    if not isinstance(labels, list) or not all(
        isinstance(x, str) and x for x in labels
    ):
        issues.append(f"{where}.labels must be a list of non-empty strings")
        return
    if len(set(labels)) != len(labels):
        issues.append(f"{where}.labels must be unique")
    if not isinstance(counts, list) or len(counts) != len(labels):
        issues.append(f"{where}.counts must be a square matrix over labels")
        return
    total = 0
    diagonal = 0
    for row in counts:
        if not isinstance(row, list) or len(row) != len(labels):
            issues.append(f"{where}.counts must be a square matrix over labels")
            return
        for cell in row:
            if not _is_int(cell) or cell < 0:
                issues.append(f"{where}.counts must hold non-negative integers")
                return
            total += cell
    for index in range(len(labels)):
        diagonal += counts[index][index]

    if total != species.get("n_scoreable"):
        issues.append(
            f"{where} total ({total}) must equal n_scoreable "
            f"({species.get('n_scoreable')})"
        )
    per_class = species.get("per_class") or []
    if [entry.get("class") for entry in per_class] != labels:
        issues.append(f"{where}.labels must match per_class order")
    n_scoreable = species.get("n_scoreable") or 0
    if n_scoreable:
        expected_correct = round((species.get("accuracy") or 0) * n_scoreable)
        if diagonal != expected_correct:
            issues.append(
                f"{where} diagonal ({diagonal}) must equal counted correct "
                f"predictions ({expected_correct})"
            )


def _validate_raw(
    artifact: dict,
    runs_dir: Path,
    issues: list[str],
    raw_bytes: bytes | None,
    require_sidecar: bool,
) -> None:
    where = "raw_responses_ref"
    ref = artifact.get("raw_responses_ref")
    if not isinstance(ref, dict):
        issues.append(f"{where} must be an object")
        return
    filename = ref.get("file")
    digest = ref.get("sha256")
    if not isinstance(filename, str) or (
        Path(filename).name != filename or "/" in filename or "\\" in filename
        or filename in (".", "..")
    ):
        issues.append(f"{where}.file must be a bare filename (got {filename!r})")
        return
    if not isinstance(digest, str) or not SHA256_RE.match(digest):
        issues.append(f"{where}.sha256 must be a 64-char lowercase hex digest")
        return

    run_id = artifact.get("run_id")
    expected_name = f"{run_id}.raw.json.gz"
    if filename != expected_name:
        issues.append(f"{where}.file must be {expected_name!r}, got {filename!r}")

    if raw_bytes is None and not require_sidecar:
        # In-memory artifact (pre-write validation): filename/digest format
        # is all that can be checked; existence and content come later.
        return

    raw_path = runs_dir / filename
    if raw_bytes is None:
        if not raw_path.exists():
            issues.append(f"{where}: sidecar {filename} not found in runs directory")
            return
        raw_bytes = raw_path.read_bytes()

    actual = sha256_bytes(raw_bytes)
    if actual != digest:
        issues.append(
            f"{where}.sha256 mismatch: stored {digest}, actual {actual} "
            "(sidecar modified or corrupt)"
        )
        return

    try:
        raw_object = json.loads(gzip.decompress(raw_bytes).decode("utf-8"))
    except Exception as exc:  # noqa: BLE001 - any decode failure is an issue
        issues.append(f"{where}: sidecar is not valid gzip JSON ({exc})")
        return
    if not isinstance(raw_object, dict):
        issues.append(f"{where}: sidecar root must be a JSON object")
        return
    if raw_object.get("schema_version") != RAW_SCHEMA_VERSION:
        issues.append(
            f"{where}: sidecar schema_version must be {RAW_SCHEMA_VERSION!r}"
        )
    if raw_object.get("run_id") != run_id:
        issues.append(f"{where}: sidecar run_id must equal artifact run_id")
    if not isinstance(raw_object.get("responses"), dict):
        issues.append(f"{where}: sidecar responses must be an object")
    issues.extend(
        f"raw sidecar {filename} {issue}"
        for issue in find_sensitive_content(raw_object)
    )


def validate_artifact(
    artifact: dict,
    *,
    runs_dir: Path | None = None,
    allow_fixture: bool = False,
    raw_bytes: bytes | None = None,
    require_sidecar: bool = True,
) -> list[str]:
    """Return a list of issues; empty list means the artifact is trustworthy."""
    runs_dir = Path(runs_dir) if runs_dir else RUNS_DIR
    issues: list[str] = []

    if not isinstance(artifact, dict):
        return ["artifact root must be a JSON object"]

    if artifact.get("schema_version") != SCHEMA_VERSION:
        issues.append(
            f"schema_version must be {SCHEMA_VERSION!r}, got "
            f"{artifact.get('schema_version')!r}"
        )

    run_id = artifact.get("run_id")
    if not isinstance(run_id, str) or not RUN_ID_RE.match(run_id):
        issues.append(f"run_id {run_id!r} does not match {RUN_ID_RE.pattern}")

    state = artifact.get("state")
    if state not in VALID_STATES:
        issues.append(f"state must be one of {list(VALID_STATES)}, got {state!r}")

    if not isinstance(artifact.get("fixture"), bool):
        issues.append("fixture must be a boolean")
    elif artifact.get("fixture") and not allow_fixture:
        issues.append(
            "synthetic fixture artifacts are never served as official results"
        )

    # dataset -------------------------------------------------------------
    dataset = artifact.get("dataset")
    dataset_ok = isinstance(dataset, dict)
    if not dataset_ok:
        issues.append("dataset must be an object")
    else:
        for key in ("name", "manifest_sha256", "label_source", "labeler",
                    "labeled_at", "split"):
            _require_str(issues, dataset, key, "dataset")
        sha = dataset.get("manifest_sha256")
        if isinstance(sha, str) and not SHA256_RE.match(sha):
            issues.append("dataset.manifest_sha256 must be a 64-char hex digest")
        if dataset.get("split") not in (None, "test"):
            issues.append("dataset.split must be 'test' (official runs evaluate the test split)")
        image_count = dataset.get("image_count")
        if not _is_int(image_count) or image_count <= 0:
            issues.append("dataset.image_count must be a positive integer")
            image_count = None
        support = dataset.get("per_class_support")
        if not isinstance(support, dict) or not all(
            isinstance(k, str) and _is_int(v) and v >= 0 for k, v in support.items()
        ):
            issues.append("dataset.per_class_support must map class -> non-negative int")
        elif image_count is not None and sum(support.values()) != image_count:
            issues.append(
                f"dataset.per_class_support sums to {sum(support.values())}, "
                f"must equal image_count ({image_count})"
            )
        _require_bool(issues, dataset, "training_hashes_available", "dataset")
        overlap = dataset.get("training_overlap_count")
        if not _is_int(overlap) or overlap < 0:
            issues.append("dataset.training_overlap_count must be a non-negative integer")
        elif overlap > 0:
            issues.append(
                f"dataset.training_overlap_count is {overlap}: evaluation data "
                "overlaps training data; this run is blocked until the overlap "
                "is resolved (overlaps must be reported, never silently dropped)"
            )

    # model ---------------------------------------------------------------
    model = artifact.get("model")
    if not isinstance(model, dict):
        issues.append("model must be an object")
    else:
        _require_str(issues, model, "pipeline", "model")
        components = model.get("components")
        if not isinstance(components, list) or not components:
            issues.append("model.components must be a non-empty list")
        else:
            for index, component in enumerate(components):
                if not isinstance(component, dict):
                    issues.append(f"model.components[{index}] must be an object")
                elif not isinstance(component.get("name"), str) or not component.get("name"):
                    issues.append(f"model.components[{index}].name must be a non-empty string")
        _require_bool(issues, model, "local_tflite_present", "model")
        _require_bool(issues, model, "yolo_dbh_enabled", "model")
        if model.get("health_classifier") != "none":
            issues.append(
                "model.health_classifier must be 'none': TreeTrace has no "
                "tree-health AI classifier and artifacts must not claim one"
            )

    # environment ---------------------------------------------------------
    environment = artifact.get("environment")
    if not isinstance(environment, dict):
        issues.append("environment must be an object")
    else:
        for key in ("git_commit", "runner", "python", "started_at", "finished_at"):
            _require_str(issues, environment, key, "environment")
        _require_bool(issues, environment, "external_api_calls", "environment")

    # metrics -------------------------------------------------------------
    metrics = artifact.get("metrics")
    image_count = dataset.get("image_count") if dataset_ok else None
    if not isinstance(metrics, dict):
        issues.append("metrics must be an object")
    elif not _is_int(image_count) or image_count <= 0:
        pass  # image_count already reported
    else:
        required_blocks = ("species", "conservation", "confidence_reliability",
                           "dbh", "latency_ms")
        missing = [b for b in required_blocks if not isinstance(metrics.get(b), dict)]
        if missing:
            issues.append(f"metrics missing blocks: {missing}")
        else:
            _validate_species(metrics["species"], image_count, issues)
            _validate_conservation(metrics["conservation"], image_count, issues)
            if isinstance(metrics["species"], dict):
                _validate_reliability(
                    metrics["confidence_reliability"], metrics["species"], issues
                )
            _validate_dbh(metrics["dbh"], issues)
            _validate_latency(metrics["latency_ms"], issues)

    # confusion matrix ----------------------------------------------------
    confusion = artifact.get("confusion_matrix")
    if not isinstance(confusion, dict):
        issues.append("confusion_matrix must be an object")
    elif isinstance(metrics, dict) and isinstance(metrics.get("species"), dict):
        _validate_confusion(confusion, metrics["species"], issues)

    # raw sidecar (always checked, so callers see every problem at once) ---
    _validate_raw(artifact, runs_dir, issues, raw_bytes, require_sidecar)

    return issues


def load_artifact(
    path: Path,
    *,
    runs_dir: Path | None = None,
    allow_fixture: bool = False,
) -> dict:
    """Load and validate a single artifact; raise ArtifactValidationError."""
    path = Path(path)
    runs_dir = Path(runs_dir) if runs_dir else path.parent
    try:
        artifact = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        raise ArtifactValidationError([f"{path.name}: unreadable JSON ({exc})"]) from exc
    if isinstance(artifact, dict) and artifact.get("run_id") != path.stem:
        raise ArtifactValidationError(
            [f"{path.name}: filename does not match run_id "
             f"{artifact.get('run_id')!r}"]
        )
    issues = validate_artifact(artifact, runs_dir=runs_dir, allow_fixture=allow_fixture)
    if issues:
        raise ArtifactValidationError(issues)
    return artifact


def list_runs(
    runs_dir: Path | None = None, *, include_fixtures: bool = False
) -> list[dict]:
    """Run summaries, newest first. Invalid files appear as state 'invalid'.

    Synthetic fixtures are excluded unless ``include_fixtures`` is set:
    official listings must never come from fixture artifacts (G5 point 9).
    """
    runs_dir = Path(runs_dir) if runs_dir else RUNS_DIR
    if not runs_dir.exists():
        return []
    entries: list[dict] = []
    for path in sorted(runs_dir.glob("*.json"), reverse=True):
        if not RUN_ID_RE.match(path.stem):
            continue
        try:
            artifact = load_artifact(path, runs_dir=runs_dir, allow_fixture=True)
        except ArtifactValidationError as exc:
            entries.append({
                "run_id": path.stem,
                "state": "invalid",
                "issues": exc.issues,
            })
            continue
        if artifact["fixture"] and not include_fixtures:
            continue
        dataset = artifact.get("dataset", {})
        model = artifact.get("model", {})
        species = artifact.get("metrics", {}).get("species", {})
        entries.append({
            "run_id": artifact["run_id"],
            "state": artifact["state"],
            "fixture": artifact["fixture"],
            "pipeline": model.get("pipeline"),
            "image_count": dataset.get("image_count"),
            "manifest_sha256": dataset.get("manifest_sha256"),
            "git_commit": artifact.get("environment", {}).get("git_commit"),
            "accuracy": species.get("accuracy"),
            "accuracy_ci95": species.get("accuracy_ci95"),
            "n_scoreable": species.get("n_scoreable"),
            "macro_f1": species.get("macro_f1"),
            "external_api_calls": artifact.get("environment", {}).get("external_api_calls"),
        })
    return entries


def rows_from_raw(raw_object: dict) -> list[dict]:
    """Rebuild evaluation rows from a raw sidecar (sorted by image_id).

    This is what makes historical metrics recalculable WITHOUT repeating
    any external API call (G5 decision 8): the sidecar holds both the
    ground truth and the prediction exactly as it was made.
    """
    responses = raw_object.get("responses") or {}
    rows: list[dict] = []
    for image_id in sorted(responses):
        entry = responses[image_id]
        if not isinstance(entry, dict):
            continue
        rows.append({
            "image_id": image_id,
            "true_species": entry.get("true_species"),
            "pred_species": entry.get("predicted_species"),
            "true_conservation": entry.get("true_conservation"),
            "pred_conservation": entry.get("predicted_conservation"),
            "confidence_band": entry.get("confidence_band"),
            "confidence_score": entry.get("confidence_score"),
            "measured_dbh_cm": entry.get("measured_dbh_cm"),
            "predicted_dbh_cm": entry.get("predicted_dbh_cm"),
            "dbh_pipeline": entry.get("dbh_pipeline"),
            "latency_ms": entry.get("latency_ms"),
            "prediction_snapshot": entry.get("prediction"),
            "raw": entry.get("raw"),
        })
    return rows


def recompute_from_raw(
    artifact: dict, raw_object: dict
) -> tuple[dict, dict]:
    """Recompute (metrics, confusion_matrix) purely from the raw sidecar."""
    from app.services.evaluation_metrics import compute_full_metrics

    return compute_full_metrics(rows_from_raw(raw_object))


def diff_metrics(stored, recomputed, path: str = "metrics") -> list[str]:
    """Deep-compare stored vs recomputed values; returns issue strings.

    Floats compare with a tight tolerance so identical computations that
    round-trip through JSON never report a false mismatch.
    """
    import math

    issues: list[str] = []
    if isinstance(stored, dict) and isinstance(recomputed, dict):
        for key in sorted(set(stored) | set(recomputed), key=str):
            child = f"{path}.{key}"
            if key not in stored:
                issues.append(f"{child} missing from stored artifact")
            elif key not in recomputed:
                issues.append(f"{child} not reproducible from raw sidecar")
            else:
                issues.extend(diff_metrics(stored[key], recomputed[key], child))
    elif isinstance(stored, list) and isinstance(recomputed, list):
        if len(stored) != len(recomputed):
            issues.append(
                f"{path} length {len(stored)} != recomputed {len(recomputed)}"
            )
            return issues
        for index, (a, b) in enumerate(zip(stored, recomputed)):
            issues.extend(diff_metrics(a, b, f"{path}[{index}]"))
    elif (
        isinstance(stored, (int, float)) and not isinstance(stored, bool)
        and isinstance(recomputed, (int, float)) and not isinstance(recomputed, bool)
    ):
        if not math.isclose(float(stored), float(recomputed), rel_tol=1e-9,
                            abs_tol=1e-9):
            issues.append(f"{path}: stored {stored!r} != recomputed {recomputed!r}")
    elif stored != recomputed:
        issues.append(f"{path}: stored {stored!r} != recomputed {recomputed!r}")
    return issues


def load_latest_run(
    runs_dir: Path | None = None, *, allow_fixture: bool = False
) -> tuple[dict | None, dict | None]:
    """Return ``(artifact, None)`` or ``(None, error_block)``.

    Fixture artifacts are skipped for official results (they are clearly
    marked non-official and can never be served as metrics). Among
    non-fixture candidates, the *newest* decides: if it fails validation
    the caller receives an error block instead of silently falling back to
    an older run, because hiding tampering behind stale numbers is exactly
    what G5 must never do.
    """
    runs_dir = Path(runs_dir) if runs_dir else RUNS_DIR
    if not runs_dir.exists():
        return None, None
    candidates = sorted(runs_dir.glob("*.json"), reverse=True)
    for path in [p for p in candidates if RUN_ID_RE.match(p.stem)]:
        if not allow_fixture:
            try:
                preview = json.loads(path.read_text(encoding="utf-8"))
            except Exception:  # noqa: BLE001 - unreadable file: let load report it
                preview = None
            if isinstance(preview, dict) and preview.get("fixture") is True:
                continue  # fixtures are never official results
        try:
            artifact = load_artifact(
                path, runs_dir=runs_dir, allow_fixture=allow_fixture
            )
        except ArtifactValidationError as exc:
            return None, {
                "state": "invalid_artifact",
                "run_id": path.stem,
                "reason": (
                    "The newest evaluation artifact failed validation. No metrics "
                    "are shown instead of falling back to older numbers."
                ),
                "issues": exc.issues,
            }
        return artifact, None
    return None, None
