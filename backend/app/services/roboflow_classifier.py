from __future__ import annotations

import io
from pathlib import Path
from threading import Lock

import torch
from PIL import Image, ImageOps
from torchvision import transforms
from torchvision.models import efficientnet_b0, mobilenet_v3_large, resnet50

MODEL_PATH = (
    Path(__file__).resolve().parents[2]
    / "models"
    / "roboflow_efficientnet"
    / "efficientnet_b0_best.pth"
)

_MODELS = {}
_LOCK = Lock()

_TRANSFORM = transforms.Compose([
    transforms.Resize((224, 224)),
    transforms.ToTensor(),
    transforms.Normalize(
        mean=[0.485, 0.456, 0.406],
        std=[0.229, 0.224, 0.225],
    ),
])


def _load_model(model_path, model_name, classes=None):
    with _LOCK:
        if model_path not in _MODELS:
            checkpoint = torch.load(
                model_path,
                map_location="cpu",
                weights_only=True,
            )

            if classes is None:
                classes = checkpoint["classes"]
                state = checkpoint.get("model_state_dict")
                if state is None:
                    state = checkpoint["state"]
            else:
                state = checkpoint

            if model_name == "MobileNetV3-Large":
                model = mobilenet_v3_large(weights=None)
                model.classifier[3] = torch.nn.Linear(model.classifier[3].in_features, len(classes))
            elif model_name == "ResNet50":
                model = resnet50(weights=None)
                model.fc = torch.nn.Linear(model.fc.in_features, len(classes))
            else:
                model = efficientnet_b0(weights=None)
                model.classifier[1] = torch.nn.Linear(model.classifier[1].in_features, len(classes))
            model.load_state_dict(state)
            model.eval()

            _MODELS[model_path] = model, classes
        return _MODELS[model_path]


def roboflow_model_status():
    return {
        "ready": MODEL_PATH.is_file(),
        "model_name": "EfficientNet-B0",
        "dataset": "Roboflow preliminary 10-class",
        "model_path": str(MODEL_PATH),
    }


def classify_roboflow_image(image_bytes: bytes, *, model_path=MODEL_PATH):
    return _classify(_image_tensor(image_bytes), model_path, "EfficientNet-B0")


def _image_tensor(image_bytes):

    with Image.open(io.BytesIO(image_bytes)) as opened:
        image = ImageOps.exif_transpose(opened).convert("RGB")

    return _TRANSFORM(image).unsqueeze(0)


def _classify(tensor, model_path, model_name, classes=None):
    model, classes = _load_model(model_path, model_name, classes)
    with torch.inference_mode():
        probabilities = torch.softmax(model(tensor), dim=1)[0]

    scores, indices = torch.topk(
        probabilities,
        k=min(5, len(classes)),
    )

    predictions = [
        {
            "common_name": classes[index.item()],
            "score": round(score.item(), 4),
            "confidence_percent": round(score.item() * 100, 2),
        }
        for score, index in zip(scores, indices)
    ]

    return {
        "common_name": predictions[0]["common_name"],
        "confidence_score": predictions[0]["score"],
        "confidence_percent": predictions[0]["confidence_percent"],
        "confidence": "Uncalibrated",
        "model_name": model_name,
        "source": "roboflow_efficientnet",
        "supported_classes": len(classes),
        "top_predictions": predictions,
    }


def compare_species_models(image_bytes, selected_path):
    tensor = _image_tensor(image_bytes)
    _, classes = _load_model(selected_path, "EfficientNet-B0")
    results = []
    for model_name, path, labels in (
        ("EfficientNet-B0", selected_path, None),
        ("MobileNetV3-Large", selected_path.with_name("MobileNetV3-Large.pt"), classes),
        ("ResNet50", selected_path.with_name("ResNet50.pt"), classes),
    ):
        try:
            prediction = _classify(tensor, path, model_name, labels)
            results.append({
                "model_name": model_name,
                "top_label": prediction["common_name"].replace("_", " "),
                "score_percent": prediction["confidence_percent"],
            })
        except (OSError, RuntimeError, ValueError, KeyError):
            results.append({"model_name": model_name, "error": "Model unavailable"})
    return results
