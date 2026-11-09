"""Offline deployment probe: synthetic inference, not a DBH/accuracy test.

Run from backend with DBH_TRUNK_ENABLED=true. No photos, downloads, API keys,
database writes or network calls. --bundle-dir checks an already-built function.
The installed environment is reported honestly; it is not a Vercel verification.
"""
import argparse
import contextlib
import hashlib
import importlib.metadata
import io
import json
import os
from pathlib import Path
import platform
import socket
import sys
import tempfile
import threading
import time
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

EXPECTED = {
    "torch": "2.12.0+cpu", "torchvision": "0.27.0+cpu",
    "ultralytics-opencv-headless": "8.3.243",
    "opencv-python-headless": "4.10.0.84", "numpy": "1.26.4",
}


def versions():
    result = {}
    for name in (*EXPECTED, "ultralytics", "opencv-python"):
        try:
            result[name] = importlib.metadata.version(name)
        except importlib.metadata.PackageNotFoundError:
            result[name] = None
    return result


def bundle_size(directory):
    path = Path(directory)
    if not path.is_dir():
        raise ValueError("Provide an existing built function directory.")
    return sum(p.stat().st_size for p in path.rglob("*") if p.is_file())


def probe(self_test=False, bundle_dir=None, memory_limit_mb=2048):
    from app.services import dbh_yolo
    status = dbh_yolo.runtime_status()
    installed = versions()
    report = {
        "configuration": status,
        "versions": installed,
        "deployment_profile_matches": all(installed[k] == v for k, v in EXPECTED.items())
            and installed["ultralytics"] is None and installed["opencv-python"] is None,
        "python": platform.python_version(), "platform": platform.system(),
        "device": "cpu", "inference_verified_here": False,
        "vercel_verified": False, "field_accuracy_verified": False,
        "peak_rss_bytes": None, "memory_target_bytes": memory_limit_mb * 1024 ** 2,
        "memory_headroom_bytes": None,
        "note": "Synthetic inference only; real-image and deployed Linux checks still required.",
    }
    if bundle_dir is not None:
        report["built_bundle_bytes"] = bundle_size(bundle_dir)
        report["requires_large_functions"] = report["built_bundle_bytes"] > 500 * 1024 ** 2
    if status["model_found"]:
        model_hash = hashlib.sha256()
        with dbh_yolo.MODEL_PATH.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                model_hash.update(block)
        report["model_sha256"] = model_hash.hexdigest()
        report["model_bytes"] = dbh_yolo.MODEL_PATH.stat().st_size
    if not self_test or not status["ready"]:
        return report

    peak = [0]
    finished = threading.Event()
    try:
        import psutil
        process = psutil.Process()
    except ImportError:
        process = None

    def sample_memory():
        while not finished.is_set():
            if process is not None:
                peak[0] = max(peak[0], process.memory_info().rss)
            finished.wait(0.02)

    def deny_network(*args, **kwargs):
        raise RuntimeError("Network is disabled in the runtime probe.")

    watcher = threading.Thread(target=sample_memory, daemon=True)
    watcher.start()
    started = time.perf_counter()
    try:
        # Settings/cache writes are isolated scratch, never a source/photo path.
        with tempfile.TemporaryDirectory(prefix="treetrace_runtime_") as scratch:
            with patch.dict(os.environ, {"YOLO_CONFIG_DIR": scratch,
                    "MPLCONFIGDIR": scratch, "YOLO_AUTOINSTALL": "false",
                    "YOLO_VERBOSE": "false", "OMP_NUM_THREADS": "2", "MKL_NUM_THREADS": "2"}), \
                 patch.object(socket.socket, "connect", deny_network), \
                 patch.object(socket.socket, "connect_ex", deny_network), \
                 patch.object(socket, "create_connection", deny_network), \
                 patch.object(socket, "getaddrinfo", deny_network), \
                 contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                from PIL import Image
                dbh_yolo._predict_masks(Image.new("RGB", (640, 640), (80, 80, 80)))
                model = dbh_yolo._model
                names = list(model.names.values())
                if model.task != "segment" or names != ["trunk"]:
                    raise ValueError("Packaged model must be segmentation with one trunk class.")
                report["task"] = model.task
                report["classes"] = names
                report["inference_verified_here"] = True
    except Exception as error:
        # Do not dump arbitrary provider bodies, local paths or credentials.
        report["probe_error_type"] = type(error).__name__
    finally:
        finished.set()
        watcher.join(timeout=1)
        report["probe_seconds"] = round(time.perf_counter() - started, 3)
        report["peak_rss_bytes"] = peak[0] or None
        if peak[0]:
            report["memory_headroom_bytes"] = report["memory_target_bytes"] - peak[0]
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--bundle-dir")
    args = parser.parse_args()
    try:
        report = probe(self_test=args.self_test, bundle_dir=args.bundle_dir)
    except Exception as error:
        print(json.dumps({"inference_verified_here": False, "probe_error_type": type(error).__name__}))
        return 2
    print(json.dumps(report, indent=2))
    if not report["configuration"]["ready"]:
        return 2
    if args.self_test and not report["inference_verified_here"]:
        return 2
    return 0 if report["deployment_profile_matches"] else 3


if __name__ == "__main__":
    raise SystemExit(main())
