#!/usr/bin/env python3
"""Recalculate a G5 evaluation run's metrics from its raw-response sidecar.

Historical metrics are reproducible WITHOUT repeating any external API
call (G5 decision 8): the sidecar stores the ground truth, the prediction
exactly as it was made, and the original response.

Usage (from backend/):
  python scripts/recalculate_run.py <run_id | path/to/run.json> [--json]
"""

from __future__ import annotations

import argparse
import gzip
import json
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.services.evaluation_artifacts import (  # noqa: E402
    RUNS_DIR,
    ArtifactValidationError,
    diff_metrics,
    load_artifact,
    recompute_from_raw,
)


def _resolve_run(run_ref: str, runs_dir: Path) -> Path:
    candidate = Path(run_ref)
    if candidate.suffix == ".json" and candidate.exists():
        return candidate
    return runs_dir / f"{run_ref}.json"


def _load_raw(artifact_path: Path, artifact: dict) -> dict:
    sidecar = artifact_path.parent / artifact["raw_responses_ref"]["file"]
    return json.loads(gzip.decompress(sidecar.read_bytes()).decode("utf-8"))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run", help="run_id or artifact path")
    parser.add_argument("--runs-dir", default=str(RUNS_DIR))
    parser.add_argument("--json", action="store_true",
                        help="print only the recomputed metrics JSON")
    args = parser.parse_args(argv)

    runs_dir = Path(args.runs_dir)
    artifact_path = _resolve_run(args.run, runs_dir)
    if not artifact_path.exists():
        print(f"RUN NOT FOUND: {artifact_path}", file=sys.stderr)
        return 1

    try:
        artifact = load_artifact(artifact_path, runs_dir=runs_dir,
                                 allow_fixture=True)
        raw_object = _load_raw(artifact_path, artifact)
    except ArtifactValidationError as exc:
        print("ARTIFACT INVALID:\n  " + "\n  ".join(exc.issues), file=sys.stderr)
        return 1

    metrics, confusion = recompute_from_raw(artifact, raw_object)
    if args.json:
        print(json.dumps({"metrics": metrics, "confusion_matrix": confusion},
                         indent=2, sort_keys=True))
        return 0

    species = metrics["species"]
    print(f"Run {artifact['run_id']} (state={artifact['state']}, "
          f"fixture={artifact['fixture']})")
    print(f"  dataset       : {artifact['dataset']['name']} "
          f"(n={species['n_total']}, manifest {artifact['dataset']['manifest_sha256'][:12]}...)")
    print(f"  pipeline      : {artifact['model']['pipeline']}")
    print(f"  accuracy      : {species['accuracy']} "
          f"CI95={species['accuracy_ci95']} (n={species['n_scoreable']})")
    print(f"  macro F1      : {species['macro_f1']}")
    print(f"  weighted F1   : {species['weighted_f1']}")
    print(f"  coverage      : {species['coverage']} "
          f"(abstentions={species['n_no_prediction']})")

    issues = diff_metrics(
        artifact["metrics"], metrics
    ) + diff_metrics(artifact["confusion_matrix"], confusion, "confusion_matrix")
    if issues:
        print("\nDIFFERS FROM STORED ARTIFACT:", file=sys.stderr)
        for issue in issues:
            print(f"  {issue}", file=sys.stderr)
        return 2
    print("  matches stored artifact metrics.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
