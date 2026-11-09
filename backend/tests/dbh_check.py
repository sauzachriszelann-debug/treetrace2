"""Offline tape validation. Never tunes on eval labels or writes source images."""
import argparse
import csv
import json
import math
from pathlib import Path
import statistics
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.services import dbh_yolo

REQUIRED = {"file", "tape_dbh_cm", "camera_height_m", "pitch_deg", "distance_m",
            "clinometer_height_m", "split"}
REQUIRED_CASES = {"near", "far", "tilted", "hidden_base", "clipped_trunk"}


def number(value, optional=False):
    if value is None or str(value).strip() == "":
        if optional:
            return None
        raise ValueError("Required measurement is empty")
    parsed = float(value)
    if not math.isfinite(parsed):
        raise ValueError("Dataset values must be finite")
    return parsed


def build_report(records, calibration_override=None):
    """Records contain UNCALIBRATED predictions; only calib labels set the factor."""
    calibration = [r for r in records if r["split"] == "calib" and r.get("accepted")]
    suggested = (statistics.mean(r["tape_dbh_cm"] / r["uncalibrated_dbh_cm"] for r in calibration)
                 if calibration else None)
    factor = calibration_override if calibration_override is not None else suggested
    if factor is None:
        factor = dbh_yolo.CALIB
    if not math.isfinite(factor) or factor <= 0:
        raise ValueError("CALIB must be positive and finite")
    evaluated = []
    for record in records:
        item = dict(record)
        item["calibrated_dbh_cm"] = None
        item["percent_error"] = None
        if item.get("accepted"):
            item["calibrated_dbh_cm"] = item["uncalibrated_dbh_cm"] * factor
            item["percent_error"] = abs(item["calibrated_dbh_cm"] - item["tape_dbh_cm"]) / item["tape_dbh_cm"] * 100
        evaluated.append(item)
    eval_rows = [r for r in evaluated if r["split"] == "eval"]
    accepted_eval = [r for r in eval_rows if r.get("accepted")]
    errors = [r["percent_error"] for r in accepted_eval]
    rejected = [r for r in evaluated if r["status"] == "retake"]
    cases = {r.get("case", "") for r in evaluated}
    missing = sorted(REQUIRED_CASES - cases)
    expected = [r for r in evaluated if r.get("expected_status")]
    expected_failures = [r["file"] for r in expected if r["status"] != r["expected_status"]]
    case_evidence = {}
    for case in sorted(REQUIRED_CASES):
        rows = [r for r in evaluated if r.get("case") == case]
        case_evidence[case] = {"samples": len(rows), "statuses": [r["status"] for r in rows],
                               "reasons": [r.get("reason", "") for r in rows]}
    return dict(calib_samples=len(calibration), suggested_calib=suggested, applied_calib=factor,
        calibration_source="override" if calibration_override is not None else "calib_split" if suggested is not None else "configured_constant",
        eval_total=len(eval_rows), eval_accepted=len(accepted_eval),
        eval_rejection_rate=(sum(r["status"] == "retake" for r in eval_rows) / len(eval_rows) if eval_rows else None),
        eval_mean_percent_error=statistics.mean(errors) if errors else None,
        eval_median_percent_error=statistics.median(errors) if errors else None,
        eval_max_percent_error=max(errors) if errors else None,
        retake_count=len(rejected), unavailable_count=sum(r["status"] == "unavailable" for r in evaluated),
        pending_base_confirmations=sum(r["status"] == "pending_base_confirmation" for r in evaluated),
        missing_required_cases=missing, expected_status_failures=expected_failures,
        case_evidence=case_evidence,
        accuracy_claim_established=False,
        note="Experimental estimates. Validate against tape DBH and clinometer height. Synthetic or empty data do not establish field accuracy.",
        records=evaluated)


def check(manifest, calibration_override=None):
    manifest = Path(manifest).resolve()
    records = []
    with manifest.open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        if not REQUIRED.issubset(reader.fieldnames or []):
            raise ValueError("Missing CSV columns: " + ", ".join(sorted(REQUIRED - set(reader.fieldnames or []))))
        for row in reader:
            if not any((v or "").strip() for v in row.values()):
                continue
            split = row["split"].strip()
            if split not in ("calib", "eval"):
                raise ValueError("Every row must have split calib or eval")
            tape = number(row["tape_dbh_cm"])
            if tape <= 0:
                raise ValueError("Tape DBH must be positive")
            file = (manifest.parent / row["file"]).resolve()
            if file.suffix.lower() not in (".jpg", ".jpeg", ".png", ".webp", ".tif", ".tiff"):
                raise ValueError("Dataset file must be an image")
            distance = number(row.get("distance_m"), optional=True)
            # The required CSV has no source column. An explicitly supplied
            # distance is operator-provided scale, not labelled AR automatically.
            source = row.get("distance_source", "").strip() or ("sensor" if distance is not None else None)
            previous = dbh_yolo.CALIB
            try:
                dbh_yolo.CALIB = 1.0
                result = dbh_yolo.measure_dbh_trunk(file.read_bytes(),
                    camera_height_m=number(row["camera_height_m"]),
                    pitch_deg=number(row["pitch_deg"], optional=True),
                    distance_m=distance, distance_source=source)
            finally:
                dbh_yolo.CALIB = previous
            accepted = result["status"] == "ok"
            status = result["status"]
            reason = result.get("reason", "")
            if accepted and result.get("needs_base_confirmation") and row.get("base_confirmed", "").strip().lower() not in ("true", "yes", "1"):
                accepted = False
                if row.get("base_confirmed", "").strip().lower() in ("false", "no", "0"):
                    status = "retake"
                    reason = "Operator rejected the green line: trunk base is not confirmed visible."
                else:
                    status = "pending_base_confirmation"
                    reason = "Operator must verify the preview's green line before accepting this base-scaled sample."
            records.append(dict(file=row["file"], split=split, tape_dbh_cm=tape,
                uncalibrated_dbh_cm=result.get("dbh_cm") if accepted else None,
                accepted=accepted, status=status, reason=reason,
                case=row.get("case", "").strip(), expected_status=row.get("expected_status", "").strip(),
                clinometer_height_m=number(row.get("clinometer_height_m"), optional=True)))
    return build_report(records, calibration_override)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", nargs="?", default=str(Path(__file__).resolve().parents[2] / "tests/tape.csv"))
    parser.add_argument("--calib", type=float, default=None, help="Explicit multiplier; otherwise derive from calib rows only")
    args = parser.parse_args()
    print(json.dumps(check(args.manifest, args.calib), indent=2, allow_nan=False))


if __name__ == "__main__":
    main()
