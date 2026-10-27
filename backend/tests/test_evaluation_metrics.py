"""Hand-computed tests for G5 metric primitives.

Every expected number here was derived independently (closed-form Wilson
formula, hand-counted confusion matrices) before the assertions were
written - the tests do not re-derive expectations from the implementation.
"""

import pytest

from app.services.evaluation_metrics import (
    accuracy_block,
    compute_full_metrics,
    confidence_reliability,
    conservation_metrics,
    dbh_metrics,
    latency_metrics,
    species_metrics,
    wilson_interval,
)


def _row(true=None, pred=None, **extra):
    return {"true_species": true, "pred_species": pred, **extra}


class TestWilsonInterval:
    def test_three_of_five(self):
        assert wilson_interval(3, 5) == [0.23072, 0.882382]

    def test_ten_of_ten(self):
        assert wilson_interval(10, 10) == [0.72246, 1.0]

    def test_zero_of_four(self):
        assert wilson_interval(0, 4) == [0.0, 0.4899]

    def test_zero_n_returns_none(self):
        assert wilson_interval(0, 0) is None
        assert wilson_interval(1, 0) is None

    def test_interval_contains_point_and_stays_in_unit_range(self):
        for correct, n in ((1, 3), (7, 9), (2, 20), (19, 20)):
            lo, hi = wilson_interval(correct, n)
            assert 0.0 <= lo <= correct / n <= hi <= 1.0


class TestAccuracyBlock:
    def test_zero_n_is_none_not_zero(self):
        block = accuracy_block(0, 0)
        assert block["accuracy"] is None
        assert block["accuracy_ci95"] is None
        assert block["n"] == 0

    def test_basic(self):
        block = accuracy_block(3, 5)
        assert block == {
            "accuracy": 0.6,
            "n": 5,
            "accuracy_ci95": [0.23072, 0.882382],
        }


HAND_ROWS = [
    _row("A", "A"),
    _row("A", "B"),
    _row("A", "A"),
    _row("B", "B"),
    _row("C", "A"),
    _row("C", None),
]


class TestSpeciesMetricsHandCounted:
    def setup_method(self):
        self.metrics, self.confusion = species_metrics(HAND_ROWS)

    def test_sample_counts(self):
        m = self.metrics
        assert m["n_total"] == 6
        assert m["n_scoreable"] == 5
        assert m["n_no_prediction"] == 1
        assert m["n_missing_true_label"] == 0
        assert m["coverage"] == 0.833333

    def test_accuracy_and_ci(self):
        assert self.metrics["accuracy"] == 0.6
        assert self.metrics["accuracy_ci95"] == [0.23072, 0.882382]

    def test_confusion_matrix(self):
        assert self.confusion["labels"] == ["A", "B", "C"]
        # rows = true, cols = predicted, order A, B, C
        assert self.confusion["counts"] == [
            [2, 1, 0],
            [0, 1, 0],
            [1, 0, 0],
        ]

    def test_per_class_metrics(self):
        by_class = {row["class"]: row for row in self.metrics["per_class"]}
        a, b, c = by_class["A"], by_class["B"], by_class["C"]

        assert a == {
            "class": "A", "support": 3, "predicted": 3,
            "tp": 2, "fp": 1, "fn": 1,
            "precision": 0.666667, "recall": 0.666667, "f1": 0.666667,
            "low_support": True,
        }
        assert b["precision"] == 0.5
        assert b["recall"] == 1.0
        assert b["f1"] == 0.666667
        assert b["predicted"] == 2  # tp 1 + one A->B false positive

        # Class C was never predicted: precision is reported as 0.0 but the
        # predicted=0 and support=1 counts make the absence visible.
        assert c["predicted"] == 0
        assert c["precision"] == 0.0
        assert c["recall"] == 0.0
        assert c["f1"] == 0.0

    def test_macro_and_weighted_averages(self):
        m = self.metrics
        assert m["macro_precision"] == 0.388889
        assert m["macro_recall"] == 0.555556
        assert m["macro_f1"] == 0.444445
        assert m["weighted_precision"] == 0.5
        assert m["weighted_recall"] == 0.6
        assert m["weighted_f1"] == 0.533334

    def test_low_support_flagging(self):
        # supports 3/1/1 are all below the threshold of 5
        assert self.metrics["n_low_support"] == 3
        assert self.metrics["low_support_threshold"] == 5
        assert self.metrics["n_classes"] == 3


class TestAbstentionAndMissingLabels:
    def test_abstention_is_not_correct_and_not_silent(self):
        metrics, _ = species_metrics([_row("A", None)])
        assert metrics["n_scoreable"] == 0
        assert metrics["n_no_prediction"] == 1
        assert metrics["accuracy"] is None  # NOT 0.0 and NOT 1.0
        assert metrics["accuracy_ci95"] is None
        assert metrics["coverage"] == 0.0

    def test_prediction_without_true_label_is_unscoreable(self):
        metrics, confusion = species_metrics([_row(None, "A")])
        assert metrics["n_scoreable"] == 0
        assert metrics["n_missing_true_label"] == 1
        assert metrics["accuracy"] is None
        assert confusion["labels"] == []

    def test_empty_rows(self):
        metrics, confusion = species_metrics([])
        assert metrics["n_total"] == 0
        assert metrics["accuracy"] is None
        assert metrics["coverage"] is None
        assert metrics["macro_f1"] is None
        assert metrics["per_class"] == []
        assert confusion == {"labels": [], "counts": []}


class TestCaseInsensitiveLabels:
    def test_variants_merge_into_one_class(self):
        metrics, confusion = species_metrics([
            _row("Narra", "NARRA"),
            _row("narra", "Narra"),
            _row("Narra", "Narra"),
        ])
        assert confusion["labels"] == ["Narra"]  # most frequent true variant
        assert confusion["counts"] == [[3]]
        assert metrics["accuracy"] == 1.0
        assert metrics["n_classes"] == 1


class TestConservationMetrics:
    def test_hand_counted(self):
        rows = [
            {"true_conservation": "Protected", "pred_conservation": "Protected"},
            {"true_conservation": "Protected", "pred_conservation": "Not Listed"},
            {"true_conservation": "Not Listed", "pred_conservation": None},
            {"true_conservation": None, "pred_conservation": "Endangered"},
        ]
        block = conservation_metrics(rows)
        assert block["n_total"] == 4
        assert block["n_no_prediction"] == 1
        assert block["n_scoreable"] == 2
        assert block["accuracy"] == 0.5
        lo, hi = block["accuracy_ci95"]
        assert lo <= 0.5 <= hi

    def test_no_scoreable_is_none(self):
        block = conservation_metrics([])
        assert block["accuracy"] is None
        assert block["accuracy_ci95"] is None
        assert block["n_scoreable"] == 0


class TestConfidenceReliability:
    def test_buckets_separate_confidence_from_accuracy(self):
        rows = [
            {"confidence_band": "High", "confidence_score": 0.9,
             "true_species": "A", "pred_species": "A"},
            {"confidence_band": "High", "confidence_score": 0.8,
             "true_species": "A", "pred_species": "B"},
            {"confidence_band": "high", "confidence_score": None,
             "true_species": "A", "pred_species": "A"},
            {"confidence_band": None, "confidence_score": None,
             "true_species": "B", "pred_species": None},
            {"confidence_band": "Certain", "confidence_score": 0.4,
             "true_species": "B", "pred_species": "B"},
        ]
        block = confidence_reliability(rows)
        by_bucket = {b["bucket"]: b for b in block["buckets"]}

        high = by_bucket["High"]
        assert high["n"] == 3
        assert high["n_scoreable"] == 3
        assert high["empirical_accuracy"] == 0.666667  # 2 of 3 correct
        assert high["mean_reported_confidence"] == 0.85  # (0.9+0.8)/2

        unreported = by_bucket["Unreported"]
        assert unreported["n"] == 1
        assert unreported["empirical_accuracy"] is None  # no scoreable rows
        assert unreported["mean_reported_confidence"] is None

        other = by_bucket["Other"]  # unknown band names collapse into Other
        assert other["n"] == 1
        assert other["empirical_accuracy"] == 1.0

        assert by_bucket["Medium"]["empirical_accuracy"] is None
        assert by_bucket["Low"]["empirical_accuracy"] is None

        # The bucket counts must cover every row exactly once.
        assert sum(b["n"] for b in block["buckets"]) == 5
        # And the note must keep confidence and accuracy distinct.
        assert "self-reported" in block["note"]
        assert "not an accuracy claim" in block["note"]


class TestDbhMetrics:
    def test_hand_counted_error(self):
        rows = [
            {"measured_dbh_cm": 10, "predicted_dbh_cm": 12,
             "dbh_pipeline": "yolov8_dbh"},
            {"measured_dbh_cm": 10, "predicted_dbh_cm": 8,
             "dbh_pipeline": "yolov8_dbh"},
            {"measured_dbh_cm": 20, "predicted_dbh_cm": 20,
             "dbh_pipeline": "yolov8_dbh"},
            {"measured_dbh_cm": 15, "predicted_dbh_cm": None,
             "dbh_pipeline": "yolov8_dbh"},
        ]
        block = dbh_metrics(rows)
        assert block["n"] == 3
        assert block["mae_cm"] == 1.333333
        assert block["rmse_cm"] == 1.632993
        assert block["bias_cm"] == 0.0
        assert block["rmse_cm"] >= block["mae_cm"]  # mathematical property
        assert block["pipeline"] == "yolov8_dbh"

    def test_zero_samples_is_none_not_zero(self):
        block = dbh_metrics([
            {"measured_dbh_cm": 10, "predicted_dbh_cm": None,
             "dbh_pipeline": None}
        ])
        assert block["n"] == 0
        assert block["mae_cm"] is None
        assert block["rmse_cm"] is None
        assert block["bias_cm"] is None


class TestLatencyMetrics:
    def test_nearest_rank_percentiles(self):
        block = latency_metrics([100, 200, 300, 400, 500])
        assert block == {
            "n": 5, "mean_ms": 300.0, "p50_ms": 300.0, "p95_ms": 500.0,
        }

    def test_junk_values_are_skipped(self):
        block = latency_metrics([None, "not-a-number", 100])
        assert block["n"] == 1
        assert block["mean_ms"] == 100.0

    def test_zero_samples_is_none(self):
        block = latency_metrics([])
        assert block == {"n": 0, "mean_ms": None, "p50_ms": None, "p95_ms": None}


class TestComputeFullMetrics:
    def test_complete_block(self):
        rows = [
            {
                "true_species": "Narra", "pred_species": "Narra",
                "true_conservation": "Protected", "pred_conservation": "Protected",
                "confidence_band": "High", "confidence_score": 0.91,
                "measured_dbh_cm": 30.0, "predicted_dbh_cm": 33.0,
                "dbh_pipeline": "gemini_dbh", "latency_ms": 2100,
            },
            {
                "true_species": "Molave", "pred_species": "Narra",
                "true_conservation": "Protected", "pred_conservation": "Not Listed",
                "confidence_band": None, "confidence_score": None,
                "measured_dbh_cm": 20.0, "predicted_dbh_cm": 18.0,
                "dbh_pipeline": "gemini_dbh", "latency_ms": 1500,
            },
        ]
        metrics, confusion = compute_full_metrics(rows)

        assert set(metrics) == {
            "species", "conservation", "confidence_reliability", "dbh", "latency_ms"
        }
        assert metrics["species"]["accuracy"] == 0.5
        assert metrics["conservation"]["accuracy"] == 0.5
        assert metrics["dbh"]["n"] == 2
        assert metrics["latency_ms"]["n"] == 2
        assert confusion["labels"] == ["Molave", "Narra"]
        # row Molave: misclassified as Narra. row Narra: correct (col 1).
        assert confusion["counts"] == [[0, 1], [0, 1]]

    def test_serializes_to_json(self):
        import json

        rows = [{"true_species": "A", "pred_species": "A", "latency_ms": 10}]
        metrics, confusion = compute_full_metrics(rows)
        assert json.loads(json.dumps({"metrics": metrics, "confusion": confusion}))
