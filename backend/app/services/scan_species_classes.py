SCAN_CLASSES = (
    "Acacia-Semanca",
    "Acacia mangium",
    "Cassia fistula",
    "Casuarina equisetifolia",
    "Eucalyptus",
    "Ficus benjamina",
    "Gmelina arborea",
    "Mangifera indica",
    "Polyalthia longifolia",
    "Pterocarpus indicus",
    "Samanea saman",
    "Spathodea campanulata",
    "Swietenia macrophylla",
    "Tabebuia rosea",
    "Terminalia catappa",
    "Vitex parviflora",
)

_ALIASES = {
    "acacia semanca": "acacia-semanca",
    "monoon longifolium": "polyalthia longifolia",
    "albizia saman": "samanea saman",
}


def scan_class(name):
    if not isinstance(name, str):
        return None
    name = " ".join(name.replace("_", " ").lower().split())
    name = _ALIASES.get(name, name)
    if name.startswith("eucalyptus "):
        name = "eucalyptus"
    return next((label for label in SCAN_CLASSES if label.lower() == name), None)


def unknown_scan(reason):
    return {
        "not_identified": True,
        "common_name": "Unknown species",
        "scientific_name": "",
        "confidence": "Low",
        "possible_candidates": [],
        "reason": reason,
    }


def restrict_scan_result(result):
    if result.get("not_identified"):
        return result
    name = result.get("scientific_name")
    if not name and result.get("source") == "local_resnet50_tflite":
        name = result.get("common_name")
    label = scan_class(name)
    if not label:
        return unknown_scan("This species is outside the trained classes. Submit for expert review.")
    if result.get("confidence") not in ("High", "Medium"):
        return unknown_scan("TreeTrace is unsure about this match. Submit for expert review.")
    return {**result, "trained_class": label}
