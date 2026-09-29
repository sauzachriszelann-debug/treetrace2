"""Compute TreeTrace model evaluation metrics from a labeled CSV file.

Usage:
  python capstone/evaluate_treetrace_results.py capstone/evaluation_test_results_template.csv

CSV columns:
  image_id, actual_species, predicted_species,
  actual_conservation, predicted_conservation,
  actual_dbh_cm, predicted_dbh_cm,
  scan_success, app_success, latency_ms
"""

from __future__ import annotations

import csv
import math
import sys
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parent
OUTPUT_DIR = ROOT / "evaluation_outputs"


def clean(value: object) -> str:
    return str(value or "").strip()


def to_float(value: object) -> float | None:
    text = clean(value)
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def to_bool(value: object) -> bool:
    return clean(value).lower() in {"1", "true", "yes", "y", "success", "successful"}


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def accuracy(rows: list[dict[str, str]], actual_key: str, predicted_key: str) -> tuple[int, int, float]:
    total = 0
    correct = 0
    for row in rows:
        actual = clean(row.get(actual_key)).lower()
        predicted = clean(row.get(predicted_key)).lower()
        if not actual or not predicted:
            continue
        total += 1
        if actual == predicted:
            correct += 1
    return correct, total, (correct / total * 100) if total else 0.0


def classification_report(rows: list[dict[str, str]], actual_key: str, predicted_key: str):
    labels = sorted(
        {
            clean(row.get(actual_key))
            for row in rows
            if clean(row.get(actual_key))
        }
        | {
            clean(row.get(predicted_key))
            for row in rows
            if clean(row.get(predicted_key))
        }
    )
    counts = {}
    for label in labels:
        tp = fp = fn = 0
        for row in rows:
            actual = clean(row.get(actual_key))
            predicted = clean(row.get(predicted_key))
            if predicted == label and actual == label:
                tp += 1
            elif predicted == label and actual != label:
                fp += 1
            elif predicted != label and actual == label:
                fn += 1
        precision = tp / (tp + fp) if tp + fp else 0.0
        recall = tp / (tp + fn) if tp + fn else 0.0
        f1 = (2 * precision * recall / (precision + recall)) if precision + recall else 0.0
        counts[label] = {
            "precision": precision,
            "recall": recall,
            "f1": f1,
            "support": sum(1 for row in rows if clean(row.get(actual_key)) == label),
        }
    macro_f1 = sum(item["f1"] for item in counts.values()) / len(counts) if counts else 0.0
    return labels, counts, macro_f1


def confusion_matrix(rows: list[dict[str, str]], actual_key: str, predicted_key: str, labels: list[str]):
    matrix = defaultdict(Counter)
    for row in rows:
        actual = clean(row.get(actual_key))
        predicted = clean(row.get(predicted_key))
        if actual and predicted:
            matrix[actual][predicted] += 1
    return matrix


def dbh_metrics(rows: list[dict[str, str]]) -> tuple[int, float, float]:
    errors = []
    for row in rows:
        actual = to_float(row.get("actual_dbh_cm"))
        predicted = to_float(row.get("predicted_dbh_cm"))
        if actual is None or predicted is None:
            continue
        errors.append(abs(actual - predicted))
    if not errors:
        return 0, 0.0, 0.0
    mae = sum(errors) / len(errors)
    rmse = math.sqrt(sum(error * error for error in errors) / len(errors))
    return len(errors), mae, rmse


def average_latency(rows: list[dict[str, str]]) -> float:
    values = [to_float(row.get("latency_ms")) for row in rows]
    values = [value for value in values if value is not None]
    return sum(values) / len(values) if values else 0.0


def success_rate(rows: list[dict[str, str]], key: str) -> tuple[int, int, float]:
    total = sum(1 for row in rows if clean(row.get(key)))
    success = sum(1 for row in rows if to_bool(row.get(key)))
    return success, total, (success / total * 100) if total else 0.0


def write_confusion_csv(path: Path, labels: list[str], matrix) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["Actual / Predicted", *labels])
        for actual in labels:
            writer.writerow([actual, *[matrix[actual][predicted] for predicted in labels]])


def write_report(path: Path, lines: list[str]) -> None:
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: python capstone/evaluate_treetrace_results.py <results.csv>")
        return 2

    csv_path = Path(sys.argv[1])
    if not csv_path.exists():
        print(f"File not found: {csv_path}")
        return 2

    rows = read_rows(csv_path)
    OUTPUT_DIR.mkdir(exist_ok=True)

    species_correct, species_total, species_acc = accuracy(rows, "actual_species", "predicted_species")
    cons_correct, cons_total, cons_acc = accuracy(rows, "actual_conservation", "predicted_conservation")
    labels, per_species, macro_f1 = classification_report(rows, "actual_species", "predicted_species")
    matrix = confusion_matrix(rows, "actual_species", "predicted_species", labels)
    dbh_count, dbh_mae, dbh_rmse = dbh_metrics(rows)
    scan_success, scan_total, scan_rate = success_rate(rows, "scan_success")
    app_success, app_total, app_rate = success_rate(rows, "app_success")
    latency = average_latency(rows)

    confusion_path = OUTPUT_DIR / "species_confusion_matrix.csv"
    write_confusion_csv(confusion_path, labels, matrix)

    report_lines = [
        "# TreeTrace Evaluation Results",
        "",
        "## Summary",
        f"- Test images: {len(rows)}",
        f"- Correct species predictions: {species_correct}/{species_total}",
        f"- Species accuracy: {species_acc:.2f}%",
        f"- Species macro F1-score: {macro_f1:.3f}",
        f"- Correct conservation classifications: {cons_correct}/{cons_total}",
        f"- Conservation accuracy: {cons_acc:.2f}%",
        f"- Measured DBH set: {dbh_count}",
        f"- DBH MAE: +/- {dbh_mae:.2f} cm",
        f"- DBH RMSE: {dbh_rmse:.2f} cm",
        f"- Scan success: {scan_success}/{scan_total} ({scan_rate:.2f}%)",
        f"- App success: {app_success}/{app_total} ({app_rate:.2f}%)",
        f"- Average latency: {latency:.0f} ms",
        "",
        "## F1-score per Species",
        "| Species | Precision | Recall | F1-score | Support |",
        "|---|---:|---:|---:|---:|",
    ]
    for label, item in per_species.items():
        report_lines.append(
            f"| {label} | {item['precision']:.3f} | {item['recall']:.3f} | "
            f"{item['f1']:.3f} | {item['support']} |"
        )
    report_lines.extend(
        [
            "",
            "## Confusion Matrix",
            f"Saved as `{confusion_path.name}` in the same output folder.",
            "",
            "## Defense Note",
            "Use these values only after replacing the sample CSV rows with your group's actual test results.",
            "For YOLO mAP, use labeled YOLO validation images and run the command in `YOLO_MAP_INSTRUCTIONS.md`.",
        ]
    )

    report_path = OUTPUT_DIR / "treetrace_evaluation_report.md"
    write_report(report_path, report_lines)

    print(f"Report saved: {report_path}")
    print(f"Confusion matrix saved: {confusion_path}")
    print()
    print("\n".join(report_lines[:14]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
