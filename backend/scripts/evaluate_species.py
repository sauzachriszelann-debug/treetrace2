#!/usr/bin/env python3
"""TreeTrace G5 offline evaluation runner.

Builds a versioned evaluation artifact (plus gzipped raw-response sidecar)
from a frozen, independently labeled test manifest.

Sources of predictions - exactly one required:

  --predictions FILE   (default, fully offline) evaluate pre-recorded
                       prediction JSONL; performs NO network calls.
  --from-api           run the live PlantNet/Gemini/GBIF pipeline. This is
                       refused unless --allow-external-api is also given.
                       G5 implementation phase U3 defers real API runs:
                       no external call is made by this build's tests or
                       by default invocations.

Overlap guard (requirement 11): if the manifest's image hashes overlap
the training-hash list (capstone/evaluation_exclude_hashes.txt when it
exists), the run is BLOCKED with a report - overlapping images are never
silently dropped.

Usage (from backend/):
  python scripts/evaluate_species.py --manifest ../capstone/evaluation_manifest.csv \
      --predictions preds.jsonl --labeler "Jane Doe" --labeled-at 2026-11-01 \
      --dry-run
"""

from __future__ import annotations

import argparse
import base64
import csv
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.services.evaluation_artifacts import (  # noqa: E402
    assemble_artifact,
    sha256_bytes,
    write_run,
)

REPO_ROOT = BACKEND_ROOT.parent
DEFAULT_RUNS_DIR = REPO_ROOT / "capstone" / "evaluation_outputs" / "runs"
DEFAULT_EXCLUDE_HASHES = REPO_ROOT / "capstone" / "evaluation_exclude_hashes.txt"

REQUIRED_COLUMNS = ("image_id", "image_sha256", "true_species_common", "split")
VALID_SPLITS = {"test", "val", "validation", "train"}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")

PREDICTION_FIELDS = (
    "predicted_species",
    "predicted_conservation",
    "confidence_band",
    "confidence_score",
    "predicted_dbh_cm",
    "dbh_pipeline",
    "latency_ms",
    "prediction",
    "raw",
)


class RunnerError(Exception):
    """Fatal, user-facing runner error (bad input, overlap, missing data)."""


# ---------------------------------------------------------------------------
# Manifest / predictions loading
# ---------------------------------------------------------------------------

def load_manifest(path: Path) -> tuple[list[dict], str]:
    """Parse and validate the frozen manifest. Returns (rows, file sha256)."""
    path = Path(path)
    if not path.exists():
        raise RunnerError(f"manifest not found: {path}")
    manifest_sha = sha256_bytes(path.read_bytes())

    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        header = reader.fieldnames or []
        missing = [c for c in REQUIRED_COLUMNS if c not in header]
        if missing:
            raise RunnerError(
                f"manifest is missing required columns: {missing} "
                f"(found: {header})"
            )
        rows = [dict(row) for row in reader]

    if not rows:
        raise RunnerError("manifest contains no rows")

    seen: set[str] = set()
    cleaned: list[dict] = []
    for index, row in enumerate(rows, start=2):  # line 1 is the header
        image_id = (row.get("image_id") or "").strip()
        if not image_id:
            raise RunnerError(f"manifest line {index}: image_id is empty")
        if image_id in seen:
            raise RunnerError(f"manifest line {index}: duplicate image_id {image_id!r}")
        seen.add(image_id)

        digest = (row.get("image_sha256") or "").strip().lower()
        if not SHA256_RE.match(digest):
            raise RunnerError(
                f"manifest line {index}: image_sha256 must be 64-char hex "
                f"(got {digest!r}) - hashes are required for leakage checks"
            )

        split = (row.get("split") or "").strip().lower()
        if split not in VALID_SPLITS:
            raise RunnerError(
                f"manifest line {index}: split must be one of "
                f"{sorted(VALID_SPLITS)} (got {split!r})"
            )

        true_species = (row.get("true_species_common") or "").strip()
        if split == "test" and not true_species:
            raise RunnerError(
                f"manifest line {index}: test rows need true_species_common "
                "(independent label)"
            )

        measured_dbh = (row.get("measured_dbh_cm") or "").strip()
        measured_dbh_value = None
        if measured_dbh:
            try:
                measured_dbh_value = float(measured_dbh)
            except ValueError as exc:
                raise RunnerError(
                    f"manifest line {index}: measured_dbh_cm is not a number "
                    f"({measured_dbh!r})"
                ) from exc

        cleaned.append({
            "image_id": image_id,
            "image_sha256": digest,
            "image_ref": (row.get("image_ref") or "").strip(),
            "true_species_common": true_species,
            "true_species_scientific": (row.get("true_species_scientific") or "").strip(),
            "true_conservation": (row.get("true_conservation") or "").strip() or None,
            "measured_dbh_cm": measured_dbh_value,
            "split": split,
        })
    return cleaned, manifest_sha


def load_predictions(path: Path) -> dict[str, dict]:
    """Load prediction JSONL: one object per image_id."""
    path = Path(path)
    if not path.exists():
        raise RunnerError(f"predictions file not found: {path}")
    predictions: dict[str, dict] = {}
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError as exc:
                raise RunnerError(
                    f"predictions line {line_number}: invalid JSON ({exc})"
                ) from exc
            image_id = str(entry.get("image_id") or "").strip()
            if not image_id:
                raise RunnerError(f"predictions line {line_number}: image_id missing")
            if image_id in predictions:
                raise RunnerError(
                    f"predictions line {line_number}: duplicate image_id {image_id!r}"
                )
            predictions[image_id] = entry
    return predictions


def load_training_hashes(path: Path | None) -> tuple[set[str], bool]:
    """Return (training_hashes, available). Absent file -> (empty, False)."""
    if path is None:
        return set(), False
    path = Path(path)
    if not path.exists():
        return set(), False
    hashes: set[str] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip().lower()
        if not line or line.startswith("#"):
            continue
        if SHA256_RE.match(line):
            hashes.add(line)
    return hashes, True


# ---------------------------------------------------------------------------
# Model / environment provenance
# ---------------------------------------------------------------------------

def _probe_local_tflite() -> bool:
    try:
        from app.services.local_species_classifier import local_species_model_status
        return bool(local_species_model_status().get("ready"))
    except Exception:  # noqa: BLE001 - absence must never crash the runner
        return False


def _probe_yolo_dbh() -> bool:
    try:
        from app.services.ai_identify import get_dbh_runtime_status
        return bool(get_dbh_runtime_status().get("ready"))
    except Exception:  # noqa: BLE001
        return False


def _gemini_prompt_sha256() -> str:
    try:
        from app.services.ai_identify import IDENTIFY_PROMPT
        return sha256_bytes(IDENTIFY_PROMPT.encode("utf-8"))
    except Exception:  # noqa: BLE001
        return "unknown"


def _gemini_model_id() -> str:
    try:
        from app.services.ai_identify import GEMINI_URL
        match = re.search(r"models/([^:]+)", GEMINI_URL)
        if match:
            return match.group(1)
    except Exception:  # noqa: BLE001
        pass
    return "gemini-2.0-flash-lite"


def build_model_block(pipeline: str) -> dict:
    components_by_pipeline = {
        "plantnet+gemini": [
            {"name": "plantnet", "api": "my-api.plantnet.org/v2/identify/all"},
            {
                "name": "gemini",
                "model_id": _gemini_model_id(),
                "prompt_sha256": _gemini_prompt_sha256(),
                "temperature": 0.1,
            },
            {"name": "gbif", "endpoint": "api.gbif.org/v1/species/match",
             "role": "taxonomy validation, not photo AI"},
        ],
        "plantnet-only": [
            {"name": "plantnet", "api": "my-api.plantnet.org/v2/identify/all"},
        ],
        "gemini-only": [
            {
                "name": "gemini",
                "model_id": _gemini_model_id(),
                "prompt_sha256": _gemini_prompt_sha256(),
                "temperature": 0.1,
            },
        ],
    }
    if pipeline not in components_by_pipeline:
        raise RunnerError(
            f"unknown pipeline {pipeline!r}; expected one of "
            f"{sorted(components_by_pipeline)}"
        )
    return {
        "pipeline": pipeline,
        "components": components_by_pipeline[pipeline],
        "confidence_buckets": {
            "plantnet": "score >0.55 High, >0.20 Medium, else Low",
            "gemini": "self-reported band: High >70%, Medium 40-70%, Low <40%",
            "local_tflite": "softmax >=0.75 High, >=0.45 Medium, else Low",
            "note": "Confidence values are model self-reports, not accuracy.",
        },
        "local_tflite_present": _probe_local_tflite(),
        "yolo_dbh_enabled": _probe_yolo_dbh(),
        "health_classifier": "none",
    }


def _git_commit() -> str:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=REPO_ROOT, capture_output=True, text=True, timeout=10,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:  # noqa: BLE001
        pass
    return "unknown"


# ---------------------------------------------------------------------------
# API-mode predictor (never invoked without explicit opt-in)
# ---------------------------------------------------------------------------

def build_api_predictor():
    """Return an async-pipeline-backed predictor. Network happens HERE only."""
    import time

    from app.services.ai_identify import _pipeline_with_status

    def predict(row: dict) -> dict:
        import asyncio

        image_ref = row.get("image_ref")
        if not image_ref:
            raise RunnerError(
                f"{row.get('image_id')}: --from-api requires a LOCAL image path "
                "in image_ref (images are not downloaded by the runner)"
            )
        image_path = Path(image_ref)
        if not image_path.exists():
            raise RunnerError(f"{row.get('image_id')}: image not found: {image_ref}")
        image_bytes = image_path.read_bytes()
        image_b64 = base64.standard_b64encode(image_bytes).decode()

        started = time.perf_counter()
        result = asyncio.run(
            _pipeline_with_status(image_bytes, image_b64, "image/jpeg")
        )
        latency_ms = (time.perf_counter() - started) * 1000

        not_identified = bool(result.get("not_identified"))
        predicted_species = None if not_identified else (
            (result.get("common_name") or "").strip() or None
        )
        predicted_conservation = None if not_identified else (
            result.get("endangered_status") or None
        )
        dbh_cm = result.get("estimated_dbh_cm")
        return {
            "predicted_species": predicted_species,
            "predicted_conservation": predicted_conservation,
            "confidence_band": result.get("confidence"),
            "confidence_score": (
                result.get("plantnet_score")
                if isinstance(result.get("plantnet_score"), (int, float))
                else None
            ),
            "predicted_dbh_cm": dbh_cm,
            "dbh_pipeline": "gemini_dbh" if dbh_cm is not None else None,
            "latency_ms": round(latency_ms, 3),
            "prediction": {
                "common_name": result.get("common_name"),
                "scientific_name": result.get("scientific_name"),
                "confidence": result.get("confidence"),
                "source": result.get("source"),
                "not_identified": not_identified,
            },
            "raw": result,
        }

    return predict


# ---------------------------------------------------------------------------
# Core evaluation
# ---------------------------------------------------------------------------

def evaluate(
    *,
    manifest_path: Path,
    predictions_path: Path | None = None,
    predictor=None,
    external_api_calls: bool = False,
    exclude_hashes_path: Path | None = DEFAULT_EXCLUDE_HASHES,
    out_dir: Path = DEFAULT_RUNS_DIR,
    pipeline: str = "plantnet+gemini",
    dataset_name: str | None = None,
    label_source: str = "human_independent",
    labeler: str,
    labeled_at: str,
    run_id: str | None = None,
    dry_run: bool = False,
) -> dict:
    """Build, validate, and (unless dry_run) persist one evaluation run."""
    sources = [bool(predictions_path), predictor is not None]
    if sum(sources) != 1:
        raise RunnerError("exactly one prediction source is required")

    manifest_rows, manifest_sha = load_manifest(Path(manifest_path))
    test_rows = [r for r in manifest_rows if r["split"] == "test"]
    excluded_non_test = len(manifest_rows) - len(test_rows)
    if not test_rows:
        raise RunnerError(
            "manifest contains no split='test' rows; official runs evaluate "
            "the frozen test split only"
        )

    # --- requirement 11: training/evaluation overlap must BLOCK the run ---
    training_hashes, training_available = load_training_hashes(exclude_hashes_path)
    if training_available and training_hashes:
        overlapping = [r for r in test_rows if r["image_sha256"] in training_hashes]
        if overlapping:
            ids = ", ".join(r["image_id"] for r in overlapping[:10])
            more = "" if len(overlapping) <= 10 else ", ..."
            raise RunnerError(
                f"training/evaluation overlap detected: {len(overlapping)} "
                f"test image(s) also appear in the training hash list "
                f"({ids}{more}). Overlaps are reported, never silently "
                "dropped, and they block this run until resolved by fixing "
                "the split."
            )

    # --- predictions -------------------------------------------------------
    if predictor is not None:
        prediction_map: dict[str, dict] = {}
        for row in test_rows:
            result = predictor(row)
            if not isinstance(result, dict):
                raise RunnerError(
                    f"predictor returned non-dict for {row['image_id']}"
                )
            prediction_map[row["image_id"]] = result
        external = bool(external_api_calls)
    else:
        prediction_map = load_predictions(Path(predictions_path))
        external = False

    missing = [r["image_id"] for r in test_rows if r["image_id"] not in prediction_map]
    if missing:
        raise RunnerError(
            f"missing predictions for {len(missing)} test image(s): "
            + ", ".join(missing[:10])
            + (", ..." if len(missing) > 10 else "")
        )
    unknown = [i for i in prediction_map if i not in {r["image_id"] for r in test_rows}]
    if unknown:
        raise RunnerError(
            f"predictions contain {len(unknown)} image_id(s) not in the test "
            "manifest: " + ", ".join(sorted(unknown)[:10])
        )

    # --- join ---------------------------------------------------------------
    rows: list[dict] = []
    for row in test_rows:
        prediction = prediction_map[row["image_id"]]
        entry = {
            "image_id": row["image_id"],
            "true_species": row["true_species_common"],
            "true_conservation": row["true_conservation"],
            "measured_dbh_cm": row["measured_dbh_cm"],
            "pred_species": _opt_str(prediction.get("predicted_species")),
            "pred_conservation": _opt_str(prediction.get("predicted_conservation")),
            "confidence_band": _opt_str(prediction.get("confidence_band")),
            "confidence_score": _opt_float(prediction.get("confidence_score")),
            "predicted_dbh_cm": _opt_float(prediction.get("predicted_dbh_cm")),
            "dbh_pipeline": _opt_str(prediction.get("dbh_pipeline")),
            "latency_ms": _opt_float(prediction.get("latency_ms")),
            "prediction_snapshot": prediction.get("prediction"),
            "raw": prediction.get("raw"),
        }
        rows.append(entry)

    started_at = datetime.now(timezone.utc)
    run_id = run_id or (
        started_at.strftime("%Y%m%dT%H%M%SZ") + "-" + manifest_sha[:8]
    )

    dataset = {
        "name": dataset_name or Path(manifest_path).stem,
        "manifest_sha256": manifest_sha,
        "split": "test",
        "label_source": label_source,
        "labeler": labeler,
        "labeled_at": labeled_at,
        "training_hashes_available": bool(training_available),
        "training_overlap_count": 0,  # non-zero overlap raised earlier
        "excluded_non_test_count": excluded_non_test,
    }
    model = build_model_block(pipeline)
    environment = {
        "git_commit": _git_commit(),
        "runner": "scripts/evaluate_species.py",
        "python": sys.version.split()[0],
        "started_at": started_at.isoformat(),
        "finished_at": datetime.now(timezone.utc).isoformat(),
        "external_api_calls": external,
    }

    artifact, raw_object = assemble_artifact(
        run_id=run_id,
        state="evaluated",
        dataset=dataset,
        model=model,
        environment=environment,
        rows=rows,
        fixture=False,
    )

    species = artifact["metrics"]["species"]
    summary = {
        "run_id": run_id,
        "state": artifact["state"],
        "dry_run": dry_run,
        "dataset": dataset["name"],
        "manifest_sha256": manifest_sha,
        "n_images": species["n_total"],
        "n_scoreable": species["n_scoreable"],
        "excluded_non_test": excluded_non_test,
        "training_hashes_available": training_available,
        "training_overlap_count": 0,
        "external_api_calls": external,
        "pipeline": pipeline,
        "metrics": {
            "accuracy": species["accuracy"],
            "accuracy_ci95": species["accuracy_ci95"],
            "macro_f1": species["macro_f1"],
            "weighted_f1": species["weighted_f1"],
            "n": species["n_scoreable"],
        },
        "artifact": None,
    }

    if dry_run:
        return summary

    artifact_path, raw_path = write_run(artifact, raw_object, Path(out_dir))
    summary["artifact"] = str(artifact_path)
    summary["raw_sidecar"] = str(raw_path)
    return summary


def _opt_str(value) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _opt_float(value) -> float | None:
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="TreeTrace G5 offline evaluation runner (no external API "
                    "calls unless --from-api --allow-external-api).",
    )
    parser.add_argument("--manifest", required=True,
                        help="Frozen test manifest CSV (split=test rows only)")
    parser.add_argument("--predictions",
                        help="Offline prediction JSONL (default source)")
    parser.add_argument("--from-api", action="store_true",
                        help="Use the live identification pipeline")
    parser.add_argument("--allow-external-api", action="store_true",
                        help="Required together with --from-api; makes real "
                             "external API calls and spends API credits")
    parser.add_argument("--exclude-hashes",
                        help=f"Training hash list (default: "
                             f"{DEFAULT_EXCLUDE_HASHES} when present)")
    parser.add_argument("--no-exclude-hashes", action="store_true",
                        help="Skip the training-overlap check (recorded in "
                             "the artifact as training_hashes_available=false)")
    parser.add_argument("--out-dir", default=str(DEFAULT_RUNS_DIR))
    parser.add_argument("--pipeline", default="plantnet+gemini",
                        choices=["plantnet+gemini", "plantnet-only", "gemini-only"])
    parser.add_argument("--name", help="Dataset name (default: manifest stem)")
    parser.add_argument("--label-source", default="human_independent")
    parser.add_argument("--labeler", required=True,
                        help="Who produced the independent labels")
    parser.add_argument("--labeled-at", required=True,
                        help="ISO date the labeling was completed")
    parser.add_argument("--dry-run", action="store_true",
                        help="Validate everything and print the summary, but "
                             "write no artifact")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.from_api and args.predictions:
        parser.error("--from-api and --predictions are mutually exclusive")
    if not args.from_api and not args.predictions:
        parser.error("provide --predictions FILE or --from-api")
    if args.from_api and not args.allow_external_api:
        print(
            "REFUSED: --from-api makes real external API calls (PlantNet, "
            "Gemini, GBIF) and spends API credits. Re-run with "
            "--allow-external-api to opt in explicitly. G5 phase U3 defers "
            "real evaluation runs.",
            file=sys.stderr,
        )
        return 1

    predictor = None
    if args.from_api:
        predictor = build_api_predictor()

    try:
        summary = evaluate(
            manifest_path=Path(args.manifest),
            predictions_path=Path(args.predictions) if args.predictions else None,
            predictor=predictor,
            external_api_calls=bool(args.from_api),
            exclude_hashes_path=(
                None if args.no_exclude_hashes
                else Path(args.exclude_hashes) if args.exclude_hashes
                else DEFAULT_EXCLUDE_HASHES
            ),
            out_dir=Path(args.out_dir),
            pipeline=args.pipeline,
            dataset_name=args.name,
            label_source=args.label_source,
            labeler=args.labeler,
            labeled_at=args.labeled_at,
            dry_run=bool(args.dry_run),
        )
    except RunnerError as exc:
        print(f"RUN FAILED: {exc}", file=sys.stderr)
        return 1

    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
