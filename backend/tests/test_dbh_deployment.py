"""Offline deployment/configuration checks; no Vercel or accuracy claims."""
import hashlib
import importlib.util
import json
from pathlib import Path
from unittest.mock import Mock

import pytest

BACKEND = Path(__file__).resolve().parents[1]
ROOT = BACKEND.parent
MODEL_HASH = "23833b4a12ba8175275a132c3c4dde87c90d2d3bedb127a49ee1dfce49793962"


@pytest.fixture(autouse=True)
def no_network(monkeypatch):
    import socket
    def denied(*args, **kwargs):
        raise AssertionError("Deployment tests must not use the network")
    monkeypatch.setattr(socket.socket, "connect", denied)
    monkeypatch.setattr(socket, "create_connection", denied)


def checker():
    spec = importlib.util.spec_from_file_location("dbh_runtime_probe", Path(__file__).with_name("check_dbh_runtime.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_only_new_trunk_model_is_newly_allowlisted():
    rules = (ROOT / ".gitignore").read_text(encoding="utf-8").splitlines()
    assert "backend/models/*.pt" in rules
    assert "!backend/models/tree_trunk_segmentation.pt" in rules
    assert "!backend/models/tree_trunk_dbh_v1.pt" in rules
    path = BACKEND / "models/tree_trunk_dbh_v1.pt"
    assert path.stat().st_size == 54846172
    assert hashlib.sha256(path.read_bytes()).hexdigest() == MODEL_HASH


def test_default_deployment_installs_the_cpu_headless_profile():
    requirements = (BACKEND / "requirements.txt").read_text()
    assert "-r requirements-yolo.txt" in requirements.splitlines()
    lines = (BACKEND / "requirements-yolo.txt").read_text().splitlines()
    assert "--extra-index-url https://download.pytorch.org/whl/cpu" in lines
    assert "torch==2.12.0+cpu" in lines
    assert "torchvision==0.27.0+cpu" in lines
    assert "ultralytics-opencv-headless==8.3.243" in lines
    assert "opencv-python-headless==4.10.0.84" in lines
    assert not any(line.startswith(("ultralytics==", "opencv-python==", "nvidia-")) for line in lines)


def test_vercel_entrypoint_models_and_runtime_limits():
    config = json.loads((BACKEND / "vercel.json").read_text())
    assert "builds" not in config  # Do not mix legacy builds with functions.
    assert config["framework"] == "fastapi" and config["fluid"] is True
    function = config["functions"]["app/main.py"]
    assert function["includeFiles"] == "models/tree_trunk_dbh_v1.pt"
    assert function["maxDuration"] == 300 and function["memory"] == 2048
    assert "tests/**" in function["excludeFiles"]
    assert ".env*" in function["excludeFiles"]
    assert "models/*.pt" not in function["excludeFiles"]
    assert config["routes"] == [{"src": "/(.*)", "dest": "app/main.py"}]
    assert config["env"]["YOLO_CONFIG_DIR"].startswith("/tmp/")
    # Enabling and beta eligibility require an explicit dashboard step/redeploy.
    assert "DBH_TRUNK_ENABLED" not in config["env"]


@pytest.mark.parametrize("enabled,model,dependencies", [
    (False, False, False), (True, False, True), (True, True, False), (True, True, True),
])
def test_authenticated_status_checks_configuration_without_loading_model(monkeypatch, enabled, model, dependencies):
    from app.api.routes.identify import dbh_trunk_status, router
    from app.core.security import get_current_user
    from app.services import dbh_yolo
    monkeypatch.setattr(dbh_yolo, "runtime_status", lambda: dict(
        enabled=enabled, model_found=model, dependencies_available=dependencies,
        ready=enabled and model and dependencies, validated_accuracy=False))
    load = Mock(side_effect=AssertionError("Status must not execute inference"))
    monkeypatch.setattr(dbh_yolo, "_predict_masks", load)
    result = dbh_trunk_status(_=object())
    assert result["configuration_ready"] == (enabled and model and dependencies)
    assert result["inference_verified"] is False and result["validated_accuracy"] is False
    assert result["model"] == "tree_trunk_dbh_v1.pt" and result["check_type"] == "configuration_only"
    assert result["reason"] and "ready" not in result
    load.assert_not_called()
    route = next(r for r in router.routes if r.path == "/dbh-trunk-status")
    assert any(d.call is get_current_user for d in route.dependant.dependencies)


def test_runtime_probe_does_not_infer_in_configuration_mode(monkeypatch, tmp_path):
    from app.services import dbh_yolo
    module = checker()
    monkeypatch.setattr(module, "versions", lambda: {**module.EXPECTED, "ultralytics": None, "opencv-python": None})
    monkeypatch.setattr(dbh_yolo, "runtime_status", lambda: {"ready": True, "model_found": False})
    load = Mock(side_effect=AssertionError("Unexpected model loading"))
    monkeypatch.setattr(dbh_yolo, "_predict_masks", load)
    report = module.probe()
    assert report["deployment_profile_matches"] is True
    assert report["inference_verified_here"] is False and report["vercel_verified"] is False
    assert report["peak_rss_bytes"] is None
    load.assert_not_called()
    (tmp_path / "small.bin").write_bytes(b"12345")
    assert module.bundle_size(tmp_path) == 5
    with pytest.raises(ValueError):
        module.bundle_size(tmp_path / "missing")


def test_missing_model_probe_does_not_fake_success(monkeypatch):
    from app.services import dbh_yolo
    module = checker()
    monkeypatch.setattr(dbh_yolo, "runtime_status", lambda: {"ready": False, "model_found": False})
    report = module.probe(self_test=True)
    assert not report["inference_verified_here"]
    assert "probe_seconds" not in report


@pytest.mark.parametrize("task,names,verified", [
    ("segment", {0: "trunk"}, True),
    ("detect", {0: "trunk"}, False),
    ("segment", {0: "cut", 1: "bound", 2: "side", 3: "trunk"}, False),
])
def test_probe_checks_task_and_single_class_before_claiming_inference(monkeypatch, task, names, verified):
    from types import SimpleNamespace
    from app.services import dbh_yolo
    module = checker()
    monkeypatch.setattr(dbh_yolo, "runtime_status", lambda: {"ready": True, "model_found": False})
    monkeypatch.setattr(dbh_yolo, "_model", SimpleNamespace(task=task, names=names))
    monkeypatch.setattr(dbh_yolo, "_predict_masks", lambda image: [])
    report = module.probe(self_test=True)
    assert report["inference_verified_here"] is verified
    assert report["vercel_verified"] is False and report["field_accuracy_verified"] is False
    if not verified:
        assert report["probe_error_type"] == "ValueError"
