"""G5 evaluation metric primitives.

Pure functions only: no I/O, no database, no network. Every function
takes labeled evaluation rows and returns plain dictionaries ready to be
serialized into a G5 evaluation artifact.

Honesty rules encoded here (G5 decisions 2, 7, 9):

* Every metric carries its sample count ``n``.
* When ``n == 0`` a metric is ``None`` - never ``0``. A missing
  measurement must not masquerade as a perfect or zero result.
* Confidence (the model's self-reported score) and empirical accuracy
  (measured correctness) are always separate values. They only appear
  side by side in ``confidence_reliability``, with an explicit note.
* Coverage (scoreable / total) is reported next to accuracy so a model
  that abstains cannot post a high accuracy on a small subset without
  the abstention being visible.
* Wilson 95% confidence intervals accompany accuracy so small samples
  are visibly uncertain.

Comparison rule: species/conservation labels are compared after
``strip()`` + ``casefold()`` so "Narra" and "narra " are one class; the
display label is the most frequent original variant among true labels
(ties broken lexicographically).
"""

from __future__ import annotations

import math
from collections import Counter

WILSON_Z = 1.96
LOW_SUPPORT_THRESHOLD = 5
CONFIDENCE_RELIABILITY_NOTE = (
    "Confidence is the model's self-reported score; empirical accuracy is "
    "measured correctness on labeled images. The two are related only by "
    "measurement - a confidence value is not an accuracy claim."
)

_RELIABILITY_BUCKETS = ("High", "Medium", "Low", "Other", "Unreported")


def _r6(value: float) -> float:
    return round(float(value), 6)


def _key(label: str | None) -> str | None:
    if label is None:
        return None
    stripped = str(label).strip()
    if not stripped:
        return None
    return stripped.casefold()


def wilson_interval(correct: int, n: int, z: float = WILSON_Z) -> list[float] | None:
    """Wilson score 95% confidence interval for a binomial proportion."""
    if n <= 0:
        return None
    p = correct / n
    z2 = z * z
    denominator = 1 + z2 / n
    center = (p + z2 / (2 * n)) / denominator
    half = (z * math.sqrt((p * (1 - p)) / n + z2 / (4 * n * n))) / denominator
    return [_r6(max(0.0, center - half)), _r6(min(1.0, center + half))]


def accuracy_block(correct: int, n: int) -> dict:
    """accuracy + Wilson CI; ``None`` values when ``n == 0``."""
    if n <= 0:
        return {"accuracy": None, "n": 0, "accuracy_ci95": None}
    return {
        "accuracy": _r6(correct / n),
        "n": int(n),
        "accuracy_ci95": wilson_interval(correct, n),
    }


def _prf(tp: int, fp: int, fn: int) -> tuple[float, float, float]:
    precision = tp / (tp + fp) if (tp + fp) else 0.0
    recall = tp / (tp + fn) if (tp + fn) else 0.0
    f1 = (2 * precision * recall / (precision + recall)) if (precision + recall) else 0.0
    return _r6(precision), _r6(recall), _r6(f1)


def species_metrics(rows: list[dict]) -> tuple[dict, dict]:
    """Species accuracy / per-class / macro / weighted metrics + confusion matrix.

    ``rows``: dicts with ``true_species`` and ``pred_species`` (str | None).
    Returns ``(metrics_block, confusion_matrix_block)``.
    """
    n_total = len(rows)
    n_no_prediction = 0
    n_missing_true = 0

    pairs: list[tuple[str, str]] = []  # (true_key, pred_key) scoreable

    for row in rows:
        true_key = _key(row.get("true_species"))
        pred_key = _key(row.get("pred_species"))
        if pred_key is None:
            n_no_prediction += 1
            if true_key is None:
                n_missing_true += 1
            continue
        if true_key is None:
            n_missing_true += 1
            # Prediction without a label cannot be scored (no ground truth).
            continue
        pairs.append((true_key, pred_key))

    n_scoreable = len(pairs)
    labels = sorted({true_key for true_key, _ in pairs} | {pred for _, pred in pairs})

    # Display label per casefold key: most frequent true variant, ties lexical.
    display: dict[str, str] = {}
    true_variant_counts: dict[str, Counter] = {}
    for row in rows:
        true_key = _key(row.get("true_species"))
        if true_key is None:
            continue
        true_variant_counts.setdefault(true_key, Counter())[
            str(row.get("true_species")).strip()
        ] += 1
    for key in labels:
        if key in true_variant_counts:
            display[key] = sorted(
                true_variant_counts[key].items(), key=lambda item: (-item[1], item[0])
            )[0][0]
        else:
            # Predicted-only class: show the first seen stripped variant.
            for row in rows:
                if _key(row.get("pred_species")) == key:
                    display[key] = str(row.get("pred_species")).strip()
                    break

    matrix: dict[str, Counter] = {t: Counter() for t in labels}
    for true_key, pred_key in pairs:
        matrix[true_key][pred_key] += 1

    per_class = []
    precisions, recalls, f1s, supports = [], [], [], []
    n_low_support = 0
    for key in labels:
        support = sum(matrix[key].values())
        tp = matrix[key][key]
        fp = sum(matrix[other][key] for other in labels if other != key)
        fn = sum(matrix[key][other] for other in labels if other != key)
        precision, recall, f1 = _prf(tp, fp, fn)
        low = support < LOW_SUPPORT_THRESHOLD
        if low:
            n_low_support += 1
        per_class.append(
            {
                "class": display[key],
                "support": int(support),
                "predicted": int(tp + fp),
                "tp": int(tp),
                "fp": int(fp),
                "fn": int(fn),
                "precision": precision,
                "recall": recall,
                "f1": f1,
                "low_support": bool(low),
            }
        )
        precisions.append(precision)
        recalls.append(recall)
        f1s.append(f1)
        supports.append(support)

    correct = sum(matrix[key][key] for key in labels)
    block = accuracy_block(correct, n_scoreable)
    coverage = _r6(n_scoreable / n_total) if n_total else None

    if labels:
        macro_p = _r6(sum(precisions) / len(precisions))
        macro_r = _r6(sum(recalls) / len(recalls))
        macro_f1 = _r6(sum(f1s) / len(f1s))
        weight_sum = sum(supports)
        if weight_sum:
            weighted_p = _r6(sum(p * s for p, s in zip(precisions, supports)) / weight_sum)
            weighted_r = _r6(sum(r * s for r, s in zip(recalls, supports)) / weight_sum)
            weighted_f1 = _r6(sum(f * s for f, s in zip(f1s, supports)) / weight_sum)
        else:
            weighted_p = weighted_r = weighted_f1 = None
    else:
        macro_p = macro_r = macro_f1 = None
        weighted_p = weighted_r = weighted_f1 = None

    metrics = {
        "n_total": int(n_total),
        "n_scoreable": int(n_scoreable),
        "n_no_prediction": int(n_no_prediction),
        "n_missing_true_label": int(n_missing_true),
        "coverage": coverage,
        "accuracy": block["accuracy"],
        "accuracy_ci95": block["accuracy_ci95"],
        "n_classes": int(len(labels)),
        "macro_precision": macro_p,
        "macro_recall": macro_r,
        "macro_f1": macro_f1,
        "weighted_precision": weighted_p,
        "weighted_recall": weighted_r,
        "weighted_f1": weighted_f1,
        "n_low_support": int(n_low_support),
        "low_support_threshold": int(LOW_SUPPORT_THRESHOLD),
        "per_class": per_class,
    }

    confusion = {
        "labels": [display[key] for key in labels],
        "counts": [
            [int(matrix[true_key][pred_key]) for pred_key in labels]
            for true_key in labels
        ],
        "index": {display[key]: i for i, key in enumerate(labels)},
    }
    # ``index`` is helper metadata; the wire format keeps labels+counts only.
    confusion.pop("index")
    return metrics, confusion


def conservation_metrics(rows: list[dict]) -> dict:
    """Accuracy of the conservation-status classification (separate from species)."""
    n_total = len(rows)
    n_no_prediction = 0
    correct = 0
    n_scoreable = 0
    for row in rows:
        true_key = _key(row.get("true_conservation"))
        pred_key = _key(row.get("pred_conservation"))
        if pred_key is None:
            n_no_prediction += 1
            continue
        if true_key is None:
            continue
        n_scoreable += 1
        if true_key == pred_key:
            correct += 1
    block = accuracy_block(correct, n_scoreable)
    return {
        "n_total": int(n_total),
        "n_no_prediction": int(n_no_prediction),
        "n_scoreable": int(n_scoreable),
        "accuracy": block["accuracy"],
        "accuracy_ci95": block["accuracy_ci95"],
    }


def confidence_reliability(rows: list[dict]) -> dict:
    """Reported-confidence buckets vs measured correctness.

    ``rows``: dicts with ``confidence_band``, ``confidence_score``,
    ``true_species``, ``pred_species``.
    """
    buckets: dict[str, dict] = {
        name: {"n": 0, "n_scoreable": 0, "n_correct": 0, "scores": []}
        for name in _RELIABILITY_BUCKETS
    }
    for row in rows:
        band_raw = row.get("confidence_band")
        if band_raw is None or not str(band_raw).strip():
            name = "Unreported"
        else:
            stripped = str(band_raw).strip()
            lowered = stripped.lower()
            if lowered == "high":
                name = "High"
            elif lowered == "medium":
                name = "Medium"
            elif lowered == "low":
                name = "Low"
            else:
                name = "Other"
        entry = buckets[name]
        entry["n"] += 1
        score = row.get("confidence_score")
        if score is not None:
            try:
                entry["scores"].append(float(score))
            except (TypeError, ValueError):
                pass
        true_key = _key(row.get("true_species"))
        pred_key = _key(row.get("pred_species"))
        if true_key is not None and pred_key is not None:
            entry["n_scoreable"] += 1
            if true_key == pred_key:
                entry["n_correct"] += 1

    out = []
    for name in _RELIABILITY_BUCKETS:
        entry = buckets[name]
        scores = entry["scores"]
        out.append(
            {
                "bucket": name,
                "n": int(entry["n"]),
                "n_scoreable": int(entry["n_scoreable"]),
                "mean_reported_confidence": _r6(sum(scores) / len(scores))
                if scores
                else None,
                "empirical_accuracy": _r6(entry["n_correct"] / entry["n_scoreable"])
                if entry["n_scoreable"]
                else None,
            }
        )
    return {"buckets": out, "note": CONFIDENCE_RELIABILITY_NOTE}


def dbh_metrics(rows: list[dict]) -> dict:
    """DBH error: MAE / RMSE / bias over rows with both values present."""
    errors = []
    for row in rows:
        actual = row.get("measured_dbh_cm")
        predicted = row.get("predicted_dbh_cm")
        if actual is None or predicted is None:
            continue
        try:
            a = float(actual)
            p = float(predicted)
        except (TypeError, ValueError):
            continue
        errors.append(p - a)

    n = len(errors)
    dbh_pipeline = rows[0].get("dbh_pipeline") if rows else None
    if n == 0:
        return {
            "n": 0,
            "mae_cm": None,
            "rmse_cm": None,
            "bias_cm": None,
            "pipeline": dbh_pipeline,
        }
    mae = sum(abs(e) for e in errors) / n
    rmse = math.sqrt(sum(e * e for e in errors) / n)
    bias = sum(errors) / n
    return {
        "n": int(n),
        "mae_cm": _r6(mae),
        "rmse_cm": _r6(rmse),
        "bias_cm": _r6(bias),
        "pipeline": dbh_pipeline,
    }


def _percentile(sorted_values: list[float], q: float) -> float:
    index = math.ceil(q * len(sorted_values)) - 1
    index = max(0, min(index, len(sorted_values) - 1))
    return sorted_values[index]


def latency_metrics(values: list) -> dict:
    """Latency summary; ``None`` fields when ``n == 0``."""
    clean = []
    for value in values:
        if value is None:
            continue
        try:
            clean.append(float(value))
        except (TypeError, ValueError):
            continue
    if not clean:
        return {"n": 0, "mean_ms": None, "p50_ms": None, "p95_ms": None}
    ordered = sorted(clean)
    return {
        "n": int(len(clean)),
        "mean_ms": _r6(sum(clean) / len(clean)),
        "p50_ms": _r6(_percentile(ordered, 0.50)),
        "p95_ms": _r6(_percentile(ordered, 0.95)),
    }


def compute_full_metrics(rows: list[dict]) -> tuple[dict, dict]:
    """Compute the complete metrics block + confusion matrix from joined rows.

    Each row: ``true_species``, ``pred_species``, ``true_conservation``,
    ``pred_conservation``, ``confidence_band``, ``confidence_score``,
    ``measured_dbh_cm``, ``predicted_dbh_cm``, ``dbh_pipeline``, ``latency_ms``.
    """
    species, confusion = species_metrics(rows)
    return (
        {
            "species": species,
            "conservation": conservation_metrics(rows),
            "confidence_reliability": confidence_reliability(rows),
            "dbh": dbh_metrics(rows),
            "latency_ms": latency_metrics([r.get("latency_ms") for r in rows]),
        },
        confusion,
    )
