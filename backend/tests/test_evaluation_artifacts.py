"""Artifact validation tests: provenance, consistency, tampering, sanitization.

Each test proves one way a malicious, malformed, or accidental artifact is
rejected instead of being served as an official number.
"""

import gzip
import json
from pathlib import Path

import pytest

from app.services.evaluation_artifacts import (
    SCHEMA_VERSION,
    ArtifactValidationError,
    find_sensitive_content,
    validate_artifact,
    load_artifact,
    load_latest_run,
    list_runs,
    sanitize_raw,
    sha256_bytes,
    write_run,
)

from evaluation_fixtures import (
    build_artifact,
    fixture_rows,
    write_fixture_run,
)


def _issues(artifact, runs_dir, **kwargs):
    # In-memory artifacts have no sidecar on disk yet; structural checks run
    # with require_sidecar=False (write/load paths check the real file).
    kwargs.setdefault("require_sidecar", False)
    return validate_artifact(artifact, runs_dir=runs_dir, **kwargs)


class TestValidArtifacts:
    def test_valid_fixture_has_no_issues(self, tmp_path):
        artifact, _ = build_artifact()
        assert _issues(artifact, tmp_path, allow_fixture=True) == []

    def test_write_load_roundtrip(self, tmp_path):
        path = write_fixture_run(tmp_path)
        loaded = load_artifact(path, runs_dir=tmp_path, allow_fixture=True)
        assert loaded["schema_version"] == SCHEMA_VERSION
        assert loaded["metrics"]["species"]["n_total"] == 4
        assert (tmp_path / "20261021T120000Z-abcdef12.raw.json.gz").exists()

    def test_fixture_flag_blocks_default_serving(self, tmp_path):
        path = write_fixture_run(tmp_path, fixture=True)
        with pytest.raises(ArtifactValidationError, match="never served"):
            load_artifact(path, runs_dir=tmp_path)  # no allow_fixture
        # ...but the same file is loadable explicitly for tests.
        load_artifact(path, runs_dir=tmp_path, allow_fixture=True)


class TestProvenanceValidation:
    def test_wrong_schema_version(self, tmp_path):
        artifact, _ = build_artifact()
        artifact["schema_version"] = "g5.evalrun.v0"
        assert any("schema_version" in i for i in _issues(artifact, tmp_path, allow_fixture=True))

    def test_missing_git_commit(self, tmp_path):
        artifact, _ = build_artifact()
        del artifact["environment"]["git_commit"]
        issues = _issues(artifact, tmp_path, allow_fixture=True)
        assert any("environment.git_commit" in i for i in issues)

    def test_empty_components_list_rejected(self, tmp_path):
        artifact, _ = build_artifact()
        # A single component with a name is structurally valid by design
        # (availability varies per run); an empty list is not.
        artifact["model"]["components"] = [{"name": "plantnet"}]
        assert _issues(artifact, tmp_path, allow_fixture=True) == []
        artifact["model"]["components"] = []
        issues = _issues(artifact, tmp_path, allow_fixture=True)
        assert any("model.components" in i for i in issues)

    def test_training_overlap_blocks_the_run(self, tmp_path):
        artifact, _ = build_artifact()
        artifact["dataset"]["training_overlap_count"] = 3
        issues = _issues(artifact, tmp_path, allow_fixture=True)
        assert any("overlaps training data" in i for i in issues)

    def test_health_classifier_claim_rejected(self, tmp_path):
        artifact, _ = build_artifact()
        artifact["model"]["health_classifier"] = "cnn_health_v1"
        issues = _issues(artifact, tmp_path, allow_fixture=True)
        assert any("no" in i and "tree-health AI" in i for i in issues)

    def test_non_test_split_rejected(self, tmp_path):
        artifact, _ = build_artifact()
        artifact["dataset"]["split"] = "train"
        issues = _issues(artifact, tmp_path, allow_fixture=True)
        assert any("split" in i for i in issues)

    def test_bad_run_id(self, tmp_path):
        artifact, _ = build_artifact()
        artifact["run_id"] = "not-a-run-id"
        issues = _issues(artifact, tmp_path, allow_fixture=True)
        assert any("run_id" in i for i in issues)

    def test_filename_run_id_mismatch(self, tmp_path):
        path = write_fixture_run(tmp_path, run_id="20261021T120000Z-abcdef12")
        renamed = tmp_path / "20261022T120000Z-bbbbbbb2.json"
        path.rename(renamed)
        with pytest.raises(ArtifactValidationError, match="filename does not match"):
            load_artifact(renamed, runs_dir=tmp_path, allow_fixture=True)


class TestConsistencyTampering:
    def test_tampered_accuracy_rejected(self, tmp_path):
        artifact, _ = build_artifact()
        species = artifact["metrics"]["species"]
        species["accuracy"] = round(species["accuracy"] + 0.2, 6)
        issues = _issues(artifact, tmp_path, allow_fixture=True)
        assert any("accuracy" in i and "does not match" in i for i in issues)

    def test_tampered_macro_f1_rejected(self, tmp_path):
        artifact, _ = build_artifact()
        artifact["metrics"]["species"]["macro_f1"] = 0.999
        issues = _issues(artifact, tmp_path, allow_fixture=True)
        assert any("macro_f1" in i for i in issues)

    def test_tampered_confusion_totals_rejected(self, tmp_path):
        artifact, _ = build_artifact()
        counts = artifact["confusion_matrix"]["counts"]
        counts[0][0] += 2
        issues = _issues(artifact, tmp_path, allow_fixture=True)
        assert any("confusion_matrix" in i for i in issues)

    def test_image_count_vs_support_mismatch(self, tmp_path):
        artifact, _ = build_artifact()
        artifact["dataset"]["image_count"] = 99
        issues = _issues(artifact, tmp_path, allow_fixture=True)
        assert any("image_count" in i for i in issues)

    def test_sample_counts_must_sum(self, tmp_path):
        artifact, _ = build_artifact()
        artifact["metrics"]["species"]["n_no_prediction"] = 0  # covers one row
        issues = _issues(artifact, tmp_path, allow_fixture=True)
        assert any("must sum" in i for i in issues)

    def test_dbh_zero_n_with_zero_error_rejected(self, tmp_path):
        artifact, _ = build_artifact()
        dbh = artifact["metrics"]["dbh"]
        dbh.update({"n": 0, "mae_cm": 0.0, "rmse_cm": 0.0, "bias_cm": 0.0})
        issues = _issues(artifact, tmp_path, allow_fixture=True)
        assert any("must be null when n is 0" in i for i in issues)

    def test_reliability_note_tampering_rejected(self, tmp_path):
        artifact, _ = build_artifact()
        artifact["metrics"]["confidence_reliability"]["note"] = (
            "Confidence equals accuracy."
        )
        issues = _issues(artifact, tmp_path, allow_fixture=True)
        assert any("distinct" in i for i in issues)

    def test_per_class_accuracy_disagrees_with_confusion(self, tmp_path):
        artifact, _ = build_artifact()
        artifact["metrics"]["species"]["per_class"][0]["tp"] += 1
        issues = _issues(artifact, tmp_path, allow_fixture=True)
        assert len(issues) > 0


class TestRawSidecarValidation:
    def test_missing_sidecar(self, tmp_path):
        path = write_fixture_run(tmp_path)
        (tmp_path / "20261021T120000Z-abcdef12.raw.json.gz").unlink()
        with pytest.raises(ArtifactValidationError, match="not found"):
            load_artifact(path, runs_dir=tmp_path, allow_fixture=True)

    def test_sidecar_sha_mismatch(self, tmp_path):
        path = write_fixture_run(tmp_path)
        sidecar = tmp_path / "20261021T120000Z-abcdef12.raw.json.gz"
        other = gzip.compress(
            json.dumps({"schema_version": "g5.raw.v1", "run_id": "x",
                        "responses": {}}).encode(),
            mtime=0,
        )
        sidecar.write_bytes(other)
        with pytest.raises(ArtifactValidationError, match="sha256 mismatch"):
            load_artifact(path, runs_dir=tmp_path, allow_fixture=True)

    def test_path_traversal_filename_rejected(self, tmp_path):
        artifact, _ = build_artifact()
        artifact["raw_responses_ref"] = {
            "file": "../evil.json.gz", "sha256": "0" * 64,
        }
        issues = _issues(artifact, tmp_path, allow_fixture=True)
        assert any("bare filename" in i for i in issues)

    def test_write_refuses_api_key_in_raw(self, tmp_path):
        artifact, raw = build_artifact()
        raw["responses"]["IMG_001"]["raw"]["request_url"] = (
            "https://example.test/v1?key=" + "A" * 35
        )
        with pytest.raises(ArtifactValidationError, match="sanitization|sensitive"):
            write_run(artifact, raw, tmp_path, allow_fixture=True)

    def test_write_refuses_email_pii_in_raw(self, tmp_path):
        artifact, raw = build_artifact()
        raw["responses"]["IMG_001"]["raw"]["note"] = "labeled by juan@example.com"
        with pytest.raises(ArtifactValidationError, match="sensitive"):
            write_run(artifact, raw, tmp_path, allow_fixture=True)

    def test_write_refuses_location_keys_in_raw(self, tmp_path):
        artifact, raw = build_artifact()
        raw["responses"]["IMG_001"]["raw"]["lat"] = 7.2711
        with pytest.raises(ArtifactValidationError, match="sensitive key"):
            write_run(artifact, raw, tmp_path, allow_fixture=True)

    def test_sanitize_raw_passes_clean_payload(self):
        sanitize_raw({"results": [{"score": 0.61, "species": "Narra"}]})

    def test_find_sensitive_content_detects_bearer(self):
        issues = find_sensitive_content({"h": "Authorization: Bearer abcdef123456"})
        assert issues


class TestLoading:
    def test_empty_dir_returns_none(self, tmp_path):
        assert load_latest_run(tmp_path) == (None, None)

    def test_load_latest_returns_newest_valid(self, tmp_path):
        write_fixture_run(tmp_path, run_id="20261021T120000Z-aaaaaaaa")
        write_fixture_run(tmp_path, run_id="20261022T120000Z-bbbbbbbb")
        artifact, error = load_latest_run(tmp_path, allow_fixture=True)
        assert error is None
        assert artifact["run_id"] == "20261022T120000Z-bbbbbbbb"

    def test_newest_invalid_never_falls_back_to_older_run(self, tmp_path):
        write_fixture_run(tmp_path, run_id="20261021T120000Z-aaaaaaaa")
        write_fixture_run(tmp_path, run_id="20261022T120000Z-bbbbbbbb")
        # Tamper the newest artifact on disk.
        newest = tmp_path / "20261022T120000Z-bbbbbbbb.json"
        doc = json.loads(newest.read_text(encoding="utf-8"))
        doc["metrics"]["species"]["accuracy"] = 1.0
        newest.write_text(json.dumps(doc), encoding="utf-8")

        artifact, error = load_latest_run(tmp_path, allow_fixture=True)
        assert artifact is None
        assert error["state"] == "invalid_artifact"
        assert error["run_id"] == "20261022T120000Z-bbbbbbbb"
        assert error["issues"]

    def test_list_runs_marks_invalid_files(self, tmp_path):
        write_fixture_run(tmp_path, run_id="20261021T120000Z-aaaaaaaa")
        bad = tmp_path / "20261022T120000Z-bbbbbbbb.json"
        bad.write_text("{not json", encoding="utf-8")
        entries = list_runs(tmp_path, include_fixtures=True)
        states = {e["run_id"]: e["state"] for e in entries}
        assert states["20261022T120000Z-bbbbbbbb"] == "invalid"
        assert states["20261021T120000Z-aaaaaaaa"] == "evaluated"
        flagged = [e for e in entries if e["run_id"].endswith("aaaaaaaa")]
        assert flagged[0]["fixture"] is True

    def test_list_runs_excludes_fixtures_by_default(self, tmp_path):
        write_fixture_run(tmp_path, run_id="20261021T120000Z-aaaaaaaa")
        assert list_runs(tmp_path) == []  # official listing: fixtures skipped

    def test_list_runs_skips_foreign_json(self, tmp_path):
        (tmp_path / "notes.json").write_text("{}", encoding="utf-8")
        assert list_runs(tmp_path) == []

    def test_fixtures_never_count_as_official_latest(self, tmp_path):
        write_fixture_run(tmp_path, run_id="20261021T120000Z-aaaaaaaa")
        write_fixture_run(tmp_path, run_id="20261022T120000Z-bbbbbbbb")
        # Official path (no allow_fixture): only fixtures exist -> not evaluated.
        assert load_latest_run(tmp_path) == (None, None)

    def test_official_latest_skips_fixture_then_finds_real_run(self, tmp_path):
        write_fixture_run(tmp_path, run_id="20261021T120000Z-aaaaaaaa")
        write_fixture_run(tmp_path, run_id="20261022T120000Z-bbbbbbbb",
                          fixture=False)
        artifact, error = load_latest_run(tmp_path)
        assert error is None
        assert artifact["run_id"] == "20261022T120000Z-bbbbbbbb"
