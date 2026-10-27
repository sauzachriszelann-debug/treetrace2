"""Offline runner tests: overlap guard, prediction integrity, API refusal.

Requirement 11 (training/evaluation overlap blocks the run, never a silent
drop), requirement 10 (tamper detection end to end), and U3 (no external
API calls: the live path refuses without explicit opt-in).
"""

import hashlib
import json
from pathlib import Path

import pytest

import scripts.evaluate_species as runner
from scripts.evaluate_species import RunnerError, evaluate
from scripts.verify_run import verify_run
from scripts.recalculate_run import main as recalculate_main

MANIFEST_HEADER = (
    "image_id,image_sha256,image_ref,true_species_common,true_species_scientific,"
    "true_conservation,measured_dbh_cm,measured_height_m,labeler,labeled_at,split,notes\n"
)


def _sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def write_manifest(path: Path, rows: list[dict]) -> Path:
    lines = [MANIFEST_HEADER]
    for row in rows:
        lines.append(
            "{image_id},{sha},{ref},{species},{scientific},{conservation},"
            "{dbh},{height},{labeler},{labeled_at},{split},\n".format(
                image_id=row["image_id"],
                sha=row.get("image_sha256") or _sha(row["image_id"]),
                ref=row.get("image_ref", f"images/{row['image_id']}.jpg"),
                species=row["true_species_common"],
                scientific=row.get("scientific", "Genus species"),
                conservation=row.get("conservation", "Protected"),
                dbh=row.get("measured_dbh_cm", ""),
                height="",
                labeler="Test Labeler",
                labeled_at="2026-11-01",
                split=row.get("split", "test"),
            )
        )
    path.write_text("".join(lines), encoding="utf-8")
    return path


def write_predictions(path: Path, entries: list[dict]) -> Path:
    path.write_text(
        "".join(json.dumps(entry) + "\n" for entry in entries), encoding="utf-8"
    )
    return path


def default_rows():
    return [
        {"image_id": "IMG_001", "true_species_common": "Narra",
         "measured_dbh_cm": "30.0"},
        {"image_id": "IMG_002", "true_species_common": "Narra"},
        {"image_id": "IMG_003", "true_species_common": "Molave"},
    ]


def default_predictions():
    return [
        {"image_id": "IMG_001", "predicted_species": "Narra",
         "predicted_conservation": "Protected", "confidence_band": "High",
         "confidence_score": 0.9, "predicted_dbh_cm": 32.0,
         "dbh_pipeline": "gemini_dbh", "latency_ms": 1500.0,
         "raw": {"source": "plantnet", "score": 0.61}},
        {"image_id": "IMG_002", "predicted_species": "Molave",
         "predicted_conservation": "Protected", "confidence_band": "Medium",
         "confidence_score": 0.5, "latency_ms": 1900.0,
         "raw": {"source": "gemini"}},
        {"image_id": "IMG_003", "predicted_species": "Molave",
         "predicted_conservation": "Endangered", "confidence_band": "Low",
         "confidence_score": 0.3, "latency_ms": 2100.0,
         "raw": {"source": "gemini"}},
    ]


@pytest.fixture
def workspace(tmp_path):
    manifest = write_manifest(tmp_path / "manifest.csv", default_rows())
    predictions = write_predictions(
        tmp_path / "predictions.jsonl", default_predictions()
    )
    runs = tmp_path / "runs"
    return {
        "manifest": manifest,
        "predictions": predictions,
        "runs": runs,
        "tmp": tmp_path,
    }


def _run(workspace, **overrides):
    kwargs = dict(
        manifest_path=workspace["manifest"],
        predictions_path=workspace["predictions"],
        exclude_hashes_path=None,  # no training hash list in this workspace
        out_dir=workspace["runs"],
        labeler="Test Labeler",
        labeled_at="2026-11-01",
        run_id="20261101T120000Z-aaaaaaa1",
    )
    kwargs.update(overrides)
    return evaluate(**kwargs)


class TestOfflineRun:
    def test_successful_run_writes_valid_artifact(self, workspace):
        summary = _run(workspace)
        assert summary["state"] == "evaluated"
        assert summary["n_images"] == 3
        assert summary["external_api_calls"] is False
        assert summary["training_hashes_available"] is False

        artifact_path = workspace["runs"] / "20261101T120000Z-aaaaaaa1.json"
        assert artifact_path.exists()
        assert (workspace["runs"] / "20261101T120000Z-aaaaaaa1.raw.json.gz").exists()

        artifact = json.loads(artifact_path.read_text(encoding="utf-8"))
        species = artifact["metrics"]["species"]
        assert species["n_total"] == 3
        assert species["n_scoreable"] == 3
        assert species["accuracy"] == pytest.approx(2 / 3, abs=1e-6)
        assert artifact["model"]["health_classifier"] == "none"
        assert artifact["fixture"] is False
        assert artifact["dataset"]["labeler"] == "Test Labeler"

        # The written artifact passes full verification against its sidecar.
        assert verify_run(artifact_path, workspace["runs"]) == []

    def test_dry_run_writes_nothing(self, workspace):
        summary = _run(workspace, dry_run=True)
        assert summary["dry_run"] is True
        assert summary["artifact"] is None
        assert not workspace["runs"].exists()

    def test_unknown_pipeline_rejected(self, workspace):
        with pytest.raises(RunnerError, match="unknown pipeline"):
            _run(workspace, pipeline="resnet50")


class TestTrainingOverlapGuard:
    def test_overlap_blocks_run_and_reports_ids(self, workspace):
        overlapping_sha = _sha("IMG_002")  # IMG_002's manifest hash
        exclude = workspace["tmp"] / "training_hashes.txt"
        exclude.write_text(
            "# training set hashes\n" + overlapping_sha + "\n", encoding="utf-8"
        )

        with pytest.raises(RunnerError) as excinfo:
            _run(workspace, exclude_hashes_path=exclude)

        message = str(excinfo.value)
        assert "training/evaluation overlap" in message
        assert "IMG_002" in message
        assert "never silently" in message
        # Blocked: nothing was written.
        assert not workspace["runs"].exists()

    def test_clean_hashes_allow_run_and_record_availability(self, workspace):
        exclude = workspace["tmp"] / "training_hashes.txt"
        exclude.write_text(_sha("SOME_OTHER_IMAGE") + "\n", encoding="utf-8")

        summary = _run(workspace, exclude_hashes_path=exclude)
        assert summary["training_hashes_available"] is True
        assert summary["training_overlap_count"] == 0

        artifact = json.loads(
            (workspace["runs"] / "20261101T120000Z-aaaaaaa1.json").read_text(
                encoding="utf-8"
            )
        )
        assert artifact["dataset"]["training_hashes_available"] is True
        assert artifact["dataset"]["training_overlap_count"] == 0


class TestPredictionIntegrity:
    def test_missing_prediction_blocks_run(self, workspace):
        entries = default_predictions()[:-1]  # drop IMG_003
        write_predictions(workspace["predictions"], entries)
        with pytest.raises(RunnerError, match="missing predictions.*IMG_003"):
            _run(workspace)
        assert not workspace["runs"].exists()

    def test_unknown_prediction_blocks_run(self, workspace):
        entries = default_predictions() + [{"image_id": "IMG_999"}]
        write_predictions(workspace["predictions"], entries)
        with pytest.raises(RunnerError, match="not in the test manifest"):
            _run(workspace)
        assert not workspace["runs"].exists()

    def test_null_prediction_recorded_as_null(self, workspace):
        entries = default_predictions()
        entries[1]["predicted_species"] = None
        entries[1]["confidence_band"] = None
        write_predictions(workspace["predictions"], entries)

        summary = _run(workspace)
        assert summary["n_scoreable"] == 2  # abstention excluded, reported

        artifact = json.loads(
            (workspace["runs"] / "20261101T120000Z-aaaaaaa1.json").read_text(
                encoding="utf-8"
            )
        )
        species = artifact["metrics"]["species"]
        assert species["n_no_prediction"] == 1
        assert species["accuracy"] == pytest.approx(1.0)  # 2 of 2 scored

        sidecar = json.loads(
            __import__("gzip").decompress(
                (workspace["runs"] / "20261101T120000Z-aaaaaaa1.raw.json.gz")
                .read_bytes()
            ).decode()
        )
        assert sidecar["responses"]["IMG_002"]["predicted_species"] is None

    def test_non_test_rows_are_excluded_and_counted(self, workspace):
        rows = default_rows() + [
            {"image_id": "IMG_004", "true_species_common": "Narra",
             "split": "train"},
            {"image_id": "IMG_005", "true_species_common": "Molave",
             "split": "val"},
        ]
        write_manifest(workspace["manifest"], rows)
        summary = _run(workspace)
        assert summary["n_images"] == 3
        assert summary["excluded_non_test"] == 2

    def test_manifest_without_test_rows_rejected(self, workspace):
        rows = [{"image_id": "IMG_001", "true_species_common": "Narra",
                 "split": "train"}]
        write_manifest(workspace["manifest"], rows)
        with pytest.raises(RunnerError, match="no split='test' rows"):
            _run(workspace)

    def test_manifest_requires_hashes(self, workspace):
        bad = workspace["tmp"] / "bad.csv"
        bad.write_text(
            MANIFEST_HEADER + "IMG_001,not-a-hash,images/x.jpg,Narra,"
            "Genus species,Protected,,2026-11-01,test,\n",
            encoding="utf-8",
        )
        with pytest.raises(RunnerError, match="image_sha256"):
            _run(workspace, manifest_path=bad)


class TestExternalApiRefusal:
    def test_from_api_refused_without_flag(self, workspace, capsys):
        exit_code = runner.main([
            "--manifest", str(workspace["manifest"]),
            "--from-api",
            "--labeler", "Test", "--labeled-at", "2026-11-01",
        ])
        assert exit_code == 1
        err = capsys.readouterr().err
        assert "REFUSED" in err
        assert "--allow-external-api" in err
        assert not workspace["runs"].exists()

    def test_from_api_with_flag_never_runs_in_tests(self, workspace):
        # The API-mode code path exists, but building a predictor must not
        # import or call the network stack until invoked; tests always inject
        # an offline predictor instead.
        def fake_predictor(row):
            return {
                "predicted_species": row["true_species_common"],
                "predicted_conservation": "Protected",
                "confidence_band": "High",
                "confidence_score": 0.88,
                "predicted_dbh_cm": None,
                "dbh_pipeline": None,
                "latency_ms": 42.0,
                "prediction": {"common_name": row["true_species_common"]},
                "raw": {"source": "injected-fake"},
            }

        summary = _run(
            workspace,
            predictions_path=None,
            predictor=fake_predictor,
            external_api_calls=True,
        )
        assert summary["external_api_calls"] is True
        assert summary["metrics"]["accuracy"] == 1.0

    def test_source_exclusivity_enforced(self, workspace):
        def fake_predictor(row):  # pragma: no cover - never invoked
            return {}

        with pytest.raises(RunnerError, match="exactly one prediction source"):
            _run(
                workspace,
                predictor=fake_predictor,
                external_api_calls=True,
            )


class TestVerifyAndRecalculate:
    def test_verify_passes_for_honest_run(self, workspace):
        _run(workspace)
        artifact_path = workspace["runs"] / "20261101T120000Z-aaaaaaa1.json"
        assert verify_run(artifact_path, workspace["runs"]) == []

    def test_verify_detects_tampered_accuracy(self, workspace):
        _run(workspace)
        artifact_path = workspace["runs"] / "20261101T120000Z-aaaaaaa1.json"
        doc = json.loads(artifact_path.read_text(encoding="utf-8"))
        doc["metrics"]["species"]["accuracy"] = 0.99
        artifact_path.write_text(json.dumps(doc), encoding="utf-8")

        issues = verify_run(artifact_path, workspace["runs"])
        # Tampering trips BOTH the structural loader and the recompute diff.
        assert issues
        assert any("accuracy" in issue for issue in issues)

    def test_recalculate_reports_match_for_honest_run(self, workspace, capsys):
        _run(workspace)
        exit_code = recalculate_main([
            "20261101T120000Z-aaaaaaa1",
            "--runs-dir", str(workspace["runs"]),
        ])
        assert exit_code == 0
        out = capsys.readouterr().out
        assert "matches stored artifact metrics" in out

    def test_recalculate_fails_for_tampered_run(self, workspace, capsys):
        _run(workspace)
        artifact_path = workspace["runs"] / "20261101T120000Z-aaaaaaa1.json"
        doc = json.loads(artifact_path.read_text(encoding="utf-8"))
        doc["metrics"]["species"]["macro_f1"] = 1.0
        artifact_path.write_text(json.dumps(doc), encoding="utf-8")

        exit_code = recalculate_main([
            "20261101T120000Z-aaaaaaa1",
            "--runs-dir", str(workspace["runs"]),
        ])
        captured = capsys.readouterr()
        assert exit_code in (1, 2)
        assert "macro_f1" in captured.err
