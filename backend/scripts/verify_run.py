#!/usr/bin/env python3
"""Verify a G5 evaluation run end to end.

1. Structural validation (schema, provenance, internal consistency,
   credential-free raw sidecar) via the production loader.
2. Full recomputation of every metric from the raw sidecar, compared
   against the stored values - so a tampered number is always caught.

Exit codes: 0 = verified, 1 = validation failure, 2 = metric mismatch.

Usage (from backend/):
  python scripts/verify_run.py <run_id | path/to/run.json>
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


def verify_run(artifact_path: Path, runs_dir: Path) -> list[str]:
    """Return a list of problems; empty list means the run is verified."""
    try:
        artifact = load_artifact(artifact_path, runs_dir=runs_dir,
                                 allow_fixture=True)
    except ArtifactValidationError as exc:
        return [f"validation: {issue}" for issue in exc.issues]

    try:
        sidecar = artifact_path.parent / artifact["raw_responses_ref"]["file"]
        raw_object = json.loads(
            gzip.decompress(sidecar.read_bytes()).decode("utf-8")
        )
    except Exception as exc:  # noqa: BLE001
        return [f"raw sidecar unreadable: {exc}"]

    metrics, confusion = recompute_from_raw(artifact, raw_object)
    issues = diff_metrics(artifact["metrics"], metrics)
    issues += diff_metrics(
        artifact["confusion_matrix"], confusion, "confusion_matrix"
    )
    return [f"recompute: {issue}" for issue in issues]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run", help="run_id or artifact path")
    parser.add_argument("--runs-dir", default=str(RUNS_DIR))
    args = parser.parse_args(argv)

    runs_dir = Path(args.runs_dir)
    candidate = Path(args.run)
    artifact_path = (
        candidate if candidate.suffix == ".json" and candidate.exists()
        else runs_dir / f"{args.run}.json"
    )
    if not artifact_path.exists():
        print(f"RUN NOT FOUND: {artifact_path}", file=sys.stderr)
        return 1

    issues = verify_run(artifact_path, runs_dir)
    if not issues:
        print(f"OK: {artifact_path.name} verified against its raw sidecar.")
        return 0

    print(f"FAILED: {artifact_path.name}", file=sys.stderr)
    for issue in issues:
        print(f"  {issue}", file=sys.stderr)
    return 2 if any(i.startswith("recompute:") for i in issues) else 1


if __name__ == "__main__":
    raise SystemExit(main())
