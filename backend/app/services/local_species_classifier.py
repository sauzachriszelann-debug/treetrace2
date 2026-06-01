from __future__ import annotations

from pathlib import Path
from typing import Any
import io

import numpy as np

from app.services.species_db import lookup_species


MODEL_DIR = Path(__file__).resolve().parents[2] / "models"
TFLITE_MODEL_PATH = MODEL_DIR / "best_model.tflite"
LABELS_PATH = MODEL_DIR / "labels.txt"

_INTERPRETER: Any | None = None
_INPUT_DETAILS: list[dict[str, Any]] | None = None
_OUTPUT_DETAILS: list[dict[str, Any]] | None = None
_LABELS: list[str] | None = None


def _load_tflite_interpreter():
    try:
        import tensorflow as tf

        return tf.lite.Interpreter(model_path=str(TFLITE_MODEL_PATH))
    except Exception:
        try:
            from tflite_runtime.interpreter import Interpreter

            return Interpreter(model_path=str(TFLITE_MODEL_PATH))
        except Exception as exc:
            raise RuntimeError(
                "Install tensorflow or tflite-runtime to use the local species model."
            ) from exc


def _ensure_loaded():
    global _INTERPRETER, _INPUT_DETAILS, _OUTPUT_DETAILS, _LABELS

    if _INTERPRETER is not None:
        return

    if not TFLITE_MODEL_PATH.exists() or not LABELS_PATH.exists():
        raise FileNotFoundError(
            "Missing backend/models/best_model.tflite or backend/models/labels.txt."
        )

    _LABELS = [
        line.strip()
        for line in LABELS_PATH.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    if not _LABELS:
        raise ValueError("labels.txt is empty.")

    _INTERPRETER = _load_tflite_interpreter()
    _INTERPRETER.allocate_tensors()
    _INPUT_DETAILS = _INTERPRETER.get_input_details()
    _OUTPUT_DETAILS = _INTERPRETER.get_output_details()


def local_species_model_status() -> dict:
    dependencies = {}
    for package, module_name in (
        ("Pillow", "PIL"),
        ("numpy", "numpy"),
        ("tensorflow", "tensorflow"),
        ("tflite-runtime", "tflite_runtime.interpreter"),
    ):
        try:
            __import__(module_name)
            dependencies[package] = True
        except Exception:
            dependencies[package] = False

    labels_count = 0
    if LABELS_PATH.exists():
        labels_count = len(
            [
                line
                for line in LABELS_PATH.read_text(encoding="utf-8").splitlines()
                if line.strip()
            ]
        )

    runtime_ready = dependencies["tensorflow"] or dependencies["tflite-runtime"]
    return {
        "ready": TFLITE_MODEL_PATH.exists() and LABELS_PATH.exists() and runtime_ready,
        "model_found": TFLITE_MODEL_PATH.exists(),
        "labels_found": LABELS_PATH.exists(),
        "labels_count": labels_count,
        "model_path": str(TFLITE_MODEL_PATH),
        "labels_path": str(LABELS_PATH),
        "dependencies": dependencies,
        "how_to_enable": (
            "Download best_model.tflite and labels.txt from Colab, then place both "
            "inside backend/models. Install tensorflow or tflite-runtime on the backend."
        ),
    }


def _confidence_label(score: float) -> str:
    if score >= 0.75:
        return "High"
    if score >= 0.45:
        return "Medium"
    return "Low"


def _preprocess_image(image_bytes: bytes) -> np.ndarray:
    from PIL import Image

    image = Image.open(io.BytesIO(image_bytes)).convert("RGB").resize((224, 224))
    array = np.asarray(image, dtype=np.float32)
    return np.expand_dims(array, axis=0)


def classify_species_from_image(image_bytes: bytes) -> dict:
    _ensure_loaded()
    assert _INTERPRETER is not None
    assert _INPUT_DETAILS is not None
    assert _OUTPUT_DETAILS is not None
    assert _LABELS is not None

    input_detail = _INPUT_DETAILS[0]
    output_detail = _OUTPUT_DETAILS[0]
    image = _preprocess_image(image_bytes)

    if input_detail["dtype"] == np.uint8:
        scale, zero_point = input_detail.get("quantization", (0, 0))
        if scale:
            image = image / scale + zero_point
        image = np.clip(image, 0, 255).astype(np.uint8)
    else:
        image = image.astype(input_detail["dtype"])

    _INTERPRETER.set_tensor(input_detail["index"], image)
    _INTERPRETER.invoke()
    predictions = _INTERPRETER.get_tensor(output_detail["index"])[0]

    top_index = int(np.argmax(predictions))
    score = float(predictions[top_index])
    common_name = _LABELS[top_index] if top_index < len(_LABELS) else f"Class {top_index}"
    info = lookup_species(common_name)

    top_predictions = []
    for idx in np.argsort(predictions)[::-1][:5]:
        label = _LABELS[int(idx)] if int(idx) < len(_LABELS) else f"Class {int(idx)}"
        top_predictions.append(
            {
                "common_name": label,
                "score": round(float(predictions[int(idx)]), 4),
                "confidence_percent": round(float(predictions[int(idx)]) * 100, 2),
            }
        )

    result = {
        "common_name": common_name,
        "scientific_name": info.get("scientific_name", "") if info else "",
        "family": info.get("family", "Unknown") if info else "Unknown",
        "confidence": _confidence_label(score),
        "confidence_score": round(score, 4),
        "confidence_percent": round(score * 100, 2),
        "description": (
            f"Identified by the TreeTrace local ResNet50 image classification model "
            f"trained on the project species dataset. Prediction score: {score:.2%}."
        ),
        "distinguishing_features": (
            "Prediction is based on visual image patterns learned from the local "
            "tree species dataset."
        ),
        "look_alikes": "Review the top predictions when confidence is Medium or Low.",
        "dbh_method": "Not estimated by the species classifier.",
        "habitat": "Philippines / local TreeTrace operational area",
        "uses": "Ecological value, shade, habitat support, and carbon storage.",
        "estimated_dbh_cm": None,
        "estimated_height_m": None,
        "is_tree": True,
        "not_identified": False,
        "source": "local_resnet50_tflite",
        "model_name": "ResNet50",
        "top_predictions": top_predictions,
    }

    if info:
        result["endangered_status"] = info["status"]
        result["status_code"] = info["status_code"]
        result["iucn_color"] = info["iucn_color"]
        result["cutting_allowed"] = info["cutting_allowed"]
        result["protected"] = info["protected"]
        result["status_source"] = info.get("source", "local species database")
    else:
        result["endangered_status"] = "Not Listed"
        result["status_code"] = "NL"
        result["iucn_color"] = "#757575"
        result["cutting_allowed"] = True
        result["protected"] = False
        result["status_source"] = "default"

    return result
