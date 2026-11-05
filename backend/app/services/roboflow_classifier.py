from __future__ import annotations

import io
from pathlib import Path
from threading import Lock

import torch
from PIL import Image, ImageOps
from torchvision import transforms
from torchvision.models import efficientnet_b0

MODEL_PATH = (
    Path(__file__).resolve().parents[2]
    / "models"
    / "roboflow_efficientnet"
    / "efficientnet_b0_best.pth"
)

_MODEL = None
_CLASSES = None
_LOCK = Lock()

_TRANSFORM = transforms.Compose([
    transforms.Resize((224, 224)),
    transforms.ToTensor(),
    transforms.Normalize(
        mean=[0.485, 0.456, 0.406],
        std=[0.229, 0.224, 0.225],
    ),
])


def _load_model():
    global _MODEL, _CLASSES

    if _MODEL is not None:
        return _MODEL, _CLASSES

    with _LOCK:
        if _MODEL is None:
            checkpoint = torch.load(
                MODEL_PATH,
                map_location="cpu",
                weights_only=True,
            )

            classes = checkpoint["classes"]
            model = efficientnet_b0(weights=None)
            model.classifier[1] = torch.nn.Linear(
                model.classifier[1].in_features,
                len(classes),
            )
            model.load_state_dict(checkpoint["model_state_dict"])
            model.eval()

            _MODEL = model
            _CLASSES = classes

    return _MODEL, _CLASSES


def roboflow_model_status():
    return {
        "ready": MODEL_PATH.is_file(),
        "model_name": "EfficientNet-B0",
        "dataset": "Roboflow preliminary 10-class",
        "model_path": str(MODEL_PATH),
    }


def classify_roboflow_image(image_bytes: bytes):
    model, classes = _load_model()

    with Image.open(io.BytesIO(image_bytes)) as opened:
        image = ImageOps.exif_transpose(opened).convert("RGB")

    tensor = _TRANSFORM(image).unsqueeze(0)

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
        "model_name": "EfficientNet-B0",
        "source": "roboflow_efficientnet",
        "supported_classes": len(classes),
        "top_predictions": predictions,
    }
