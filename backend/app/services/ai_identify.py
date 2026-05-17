"""
AI Tree Identification Service - Full Pipeline
  1. Pl@ntNet API     — fast botanical ID (500/day free)
  2. Gemini Vision    — confirms species + DBH/height (1500/day free)
  3. Perenual API     — real care data, species details (100/day free)
  4. Trefle API       — botanical data, family, distribution (unlimited free)
  5. DENR species DB  — endangered/protected status (local)
"""
import base64
import httpx
import json
import re
import asyncio
from app.services.species_db import lookup_species

try:
    from app.core.config import settings
    PLANTNET_API_KEY = settings.PLANTNET_API_KEY
    GEMINI_API_KEY   = settings.GEMINI_API_KEY
    PERENUAL_API_KEY = settings.PERENUAL_API_KEY
    TREFLE_API_KEY   = settings.TREFLE_API_KEY
except Exception:
    import os
    PLANTNET_API_KEY = os.getenv("PLANTNET_API_KEY", "")
    GEMINI_API_KEY   = os.getenv("GEMINI_API_KEY", "")
    PERENUAL_API_KEY = os.getenv("PERENUAL_API_KEY", "")
    TREFLE_API_KEY   = os.getenv("TREFLE_API_KEY", "")

PLANTNET_URL = "https://my-api.plantnet.org/v2/identify/all"
GEMINI_URL   = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:generateContent"
PERENUAL_URL = "https://perenual.com/api"
TREFLE_URL   = "https://trefle.io/api/v1"
GBIF_MATCH_URL = "https://api.gbif.org/v1/species/match"

IDENTIFY_PROMPT = """\
You are Dr. Maria Santos, a senior botanist at DENR with 20 years identifying Philippine trees.

Carefully study every part of this image:
- Leaf shape, margin, venation, arrangement (opposite/alternate)
- Bark texture and colour (smooth, fissured, scaly, plated)
- Branch pattern and crown silhouette
- Fruit, flower, or seed pods if present
- Root system (buttress roots, stilt roots, etc.)
- Overall form (columnar, spreading, weeping)

Cross-reference against Philippine tree species databases.

Respond ONLY with a single valid JSON object — no text before or after, no markdown fences.

{
  "common_name": "most widely used Philippine common name",
  "scientific_name": "Genus species",
  "family": "plant family",
  "confidence": "High",
  "description": "3-4 sentences: species ecology, distribution in Philippines, importance",
  "estimated_dbh_cm": 35,
  "estimated_height_m": 12,
  "dbh_method": "brief note on how you estimated DBH",
  "distinguishing_features": "the 3 most diagnostic visual features",
  "look_alikes": "species this could be confused with and how to tell apart",
  "habitat": "natural habitat and range in Philippines",
  "uses": "timber, medicinal, food, ecological value",
  "is_tree": true,
  "not_identified": false
}

DBH ESTIMATION:
  Look for scale references: people (~170cm), motorcycles (~80cm), cars (~150cm), doors (~200cm).
  If NO scale reference: estimate from species maturity and crown size.
  Seedling ≤5cm | Juvenile 5-15cm | Sub-adult 15-35cm | Mature 35-70cm | Old-growth 70-200+cm
  estimated_dbh_cm should be a positive integer 1-300 only when the image gives enough visual cues. Use null when the image does not support a photo-specific estimate.

HEIGHT ESTIMATION:
  Shrub/small 2-6m | Medium 6-15m | Large 15-30m | Emergent 30-60m
  estimated_height_m should be a positive integer 1-80 only when the image gives enough visual cues. Use null when uncertain.

confidence: "High" >70% certain | "Medium" 40-70% | "Low" <40%
not_identified: true ONLY if no plant visible at all
"""


def _to_int(val, default: int, lo: int = 1, hi: int = 500) -> int:
    try:
        n = int(round(float(str(val))))
        return max(lo, min(hi, n if n > 0 else default))
    except (TypeError, ValueError):
        return default


def _optional_int(val, lo: int = 1, hi: int = 500) -> int | None:
    try:
        if val is None or str(val).strip().lower() in {"", "null", "none", "unknown"}:
            return None
        n = int(round(float(str(val))))
        return max(lo, min(hi, n)) if n > 0 else None
    except (TypeError, ValueError):
        return None


# ── 1. PlantNet ───────────────────────────────────────────────────────────────
async def _plantnet(image_bytes: bytes, content_type: str) -> dict | None:
    try:
        files  = {"images": ("tree.jpg", image_bytes, content_type)}
        params = {"api-key": PLANTNET_API_KEY, "lang": "en", "include-related-images": "false"}
        async with httpx.AsyncClient(timeout=20) as http:
            resp = await http.post(PLANTNET_URL, files=files, params=params)
        if resp.status_code != 200:
            return None
        data    = resp.json()
        results = data.get("results", [])
        if not results:
            return None
        best  = results[0]
        score = best.get("score", 0)
        if score < 0.04:
            return None
        sp          = best.get("species", {})
        sci_name    = sp.get("scientificNameWithoutAuthor", "")
        common_list = sp.get("commonNames", [])
        common_name = common_list[0] if common_list else sci_name.split()[0] if sci_name else ""
        family      = sp.get("family", {}).get("scientificNameWithoutAuthor", "")
        confidence  = "High" if score > 0.55 else "Medium" if score > 0.20 else "Low"
        return {
            "common_name":     common_name,
            "scientific_name": sci_name,
            "family":          family,
            "confidence":      confidence,
            "plantnet_score":  round(score, 4),
            "source":          "plantnet",
        }
    except Exception:
        return None


# ── 2. Gemini Vision ──────────────────────────────────────────────────────────
async def _gemini(image_b64: str, content_type: str, hint: dict | None) -> dict:
    if not GEMINI_API_KEY:
        return {
            "not_identified": True,
            "reason": "Gemini API key is not configured.",
            "possible_candidates": [],
        }

    prompt = IDENTIFY_PROMPT
    if hint:
        prompt += (
            f"\n\nPl@ntNet botanical database identifies this as "
            f"'{hint['scientific_name']}' (common: '{hint['common_name']}', "
            f"match score: {hint['plantnet_score']:.1%}). "
            "Use this as strong prior evidence. Confirm or correct it and fill EVERY field."
        )
    try:
        url     = f"{GEMINI_URL}?key={GEMINI_API_KEY}"
        payload = {
            "contents": [{
                "parts": [
                    {"text": prompt},
                    {"inline_data": {"mime_type": content_type, "data": image_b64}},
                ]
            }],
            "generationConfig": {"temperature": 0.1, "maxOutputTokens": 1200},
        }
        async with httpx.AsyncClient(timeout=30) as http:
            resp = await http.post(url, json=payload)
        if resp.status_code != 200:
            raise Exception(f"Gemini {resp.status_code}")
        raw = resp.json()["candidates"][0]["content"]["parts"][0]["text"].strip()
        raw = re.sub(r"^```(?:json)?\s*", "", raw, flags=re.MULTILINE)
        raw = re.sub(r"\s*```\s*$",       "", raw, flags=re.MULTILINE)
        result = json.loads(raw.strip())
        if result.get("not_identified"):
            return result
        result["estimated_dbh_cm"]   = _optional_int(result.get("estimated_dbh_cm"), 1, 300)
        result["estimated_height_m"] = _optional_int(result.get("estimated_height_m"), 1, 80)
        result.setdefault("common_name",            "Unknown Tree")
        result.setdefault("scientific_name",         "Unknown")
        result.setdefault("family",                  "Unknown")
        result.setdefault("confidence",              "Low")
        result.setdefault("description",             "")
        result.setdefault("distinguishing_features", "")
        result.setdefault("look_alikes",             "")
        result.setdefault("dbh_method",              "")
        result.setdefault("habitat",                 "Philippines")
        result.setdefault("uses",                    "")
        result.setdefault("is_tree",                 True)
        result["not_identified"] = False
        return result
    except json.JSONDecodeError:
        return {"not_identified": True, "reason": "AI returned unreadable response.", "possible_candidates": []}
    except Exception as e:
        return {"not_identified": True, "reason": f"AI error: {str(e)}", "possible_candidates": []}


# ── 3. Perenual — species care data ──────────────────────────────────────────
async def _perenual_care(scientific_name: str) -> dict | None:
    if not PERENUAL_API_KEY or not scientific_name:
        return None
    try:
        async with httpx.AsyncClient(timeout=15) as http:
            # Search for species
            resp = await http.get(
                f"{PERENUAL_URL}/species-list",
                params={"key": PERENUAL_API_KEY, "q": scientific_name}
            )
        if resp.status_code != 200:
            return None
        data = resp.json()
        results = data.get("data", [])
        if not results:
            return None
        species = results[0]
        return {
            "perenual_id":       species.get("id"),
            "watering":          species.get("watering", ""),
            "sunlight":          ", ".join(species.get("sunlight", [])) if isinstance(species.get("sunlight"), list) else species.get("sunlight", ""),
            "cycle":             species.get("cycle", ""),
            "maintenance":       species.get("maintenance", ""),
            "care_level":        species.get("care_level", ""),
            "growth_rate":       species.get("growth_rate", ""),
            "drought_tolerant":  species.get("drought_tolerant", False),
            "salt_tolerant":     species.get("salt_tolerant", False),
            "thorny":            species.get("thorny", False),
            "invasive":          species.get("invasive", False),
            "tropical":          species.get("tropical", False),
            "indoor":            species.get("indoor", False),
            "hardiness":         species.get("hardiness", {}),
            "flowers":           species.get("flowers", False),
            "flowering_season":  species.get("flowering_season", ""),
            "fruit":             species.get("fruit", False),
            "edible_fruit":      species.get("edible_fruit", False),
            "leaf":              species.get("leaf", True),
            "leaf_color":        species.get("leaf_color", []),
            "origin":            species.get("origin", []),
            "type":              species.get("type", ""),
            "description":       species.get("description", ""),
        }
    except Exception:
        return None


async def _perenual_care_guide(species_id: int) -> dict | None:
    if not PERENUAL_API_KEY or not species_id:
        return None
    try:
        async with httpx.AsyncClient(timeout=15) as http:
            resp = await http.get(
                f"{PERENUAL_URL}/species-care-guide-list",
                params={"key": PERENUAL_API_KEY, "species_id": species_id}
            )
        if resp.status_code != 200:
            return None
        data = resp.json()
        guides = data.get("data", [])
        if not guides:
            return None
        guide = guides[0]
        section_map = {}
        for section in guide.get("section", []):
            section_map[section.get("type", "")] = section.get("description", "")
        return section_map  # keys: watering, sunlight, pruning, fertilization
    except Exception:
        return None


# ── 4. Trefle — botanical data ────────────────────────────────────────────────
async def _trefle(scientific_name: str) -> dict | None:
    if not TREFLE_API_KEY or not scientific_name:
        return None
    try:
        async with httpx.AsyncClient(timeout=15) as http:
            resp = await http.get(
                f"{TREFLE_URL}/plants/search",
                params={"token": TREFLE_API_KEY, "q": scientific_name}
            )
        if resp.status_code != 200:
            return None
        data    = resp.json()
        results = data.get("data", [])
        if not results:
            return None
        plant = results[0]
        return {
            "trefle_id":          plant.get("id"),
            "common_name":        plant.get("common_name", ""),
            "scientific_name":    plant.get("scientific_name", ""),
            "family":             plant.get("family", ""),
            "family_common_name": plant.get("family_common_name", ""),
            "genus":              plant.get("genus", ""),
            "image_url":          plant.get("image_url", ""),
        }
    except Exception:
        return None


# ── GBIF taxonomy validation ─────────────────────────────────────────────────
async def _gbif_match(scientific_name: str) -> dict | None:
    """Validate a scientific name through GBIF. This is not photo AI."""
    if not scientific_name or scientific_name.lower() in {"unknown", "unknown tree"}:
        return None
    try:
        async with httpx.AsyncClient(timeout=10) as http:
            resp = await http.get(GBIF_MATCH_URL, params={"name": scientific_name})
        if resp.status_code != 200:
            return None
        data = resp.json()
        usage_key = data.get("usageKey")
        if not usage_key:
            return None
        return {
            "usage_key": usage_key,
            "accepted_usage_key": data.get("acceptedUsageKey"),
            "scientific_name": data.get("scientificName") or data.get("canonicalName"),
            "canonical_name": data.get("canonicalName"),
            "family": data.get("family"),
            "genus": data.get("genus"),
            "rank": data.get("rank"),
            "status": data.get("status"),
            "confidence": data.get("confidence"),
            "match_type": data.get("matchType"),
        }
    except Exception:
        return None


# ── Public wiki builder (called from /wiki route) ─────────────────────────────
async def get_species_wiki(common_name: str, scientific_name: str) -> dict:
    """
    Fetch rich species data from Perenual + Trefle.
    Returns structured wiki dict for the public tree profile.
    """
    perenual_data  = None
    perenual_guide = None
    trefle_data    = None

    # Run Perenual and Trefle in parallel
    search_name = scientific_name or common_name
    perenual_data, trefle_data = await asyncio.gather(
        _perenual_care(search_name),
        _trefle(search_name),
    )

    # Get care guide if we have a Perenual species ID
    if perenual_data and perenual_data.get("perenual_id"):
        perenual_guide = await _perenual_care_guide(perenual_data["perenual_id"])

    return _build_wiki(common_name, scientific_name, perenual_data, perenual_guide, trefle_data)


def _build_wiki(
    common_name: str,
    scientific_name: str,
    p: dict | None,       # perenual species data
    g: dict | None,       # perenual care guide sections
    t: dict | None,       # trefle data
) -> dict:
    """Merge API data into wiki structure."""

    # Basic info
    origin = p.get("origin", []) if p else []
    native_to = ", ".join(origin) if origin else "Philippines / Southeast Asia"

    basic_info = {
        "native_to":        native_to,
        "invasive_status":  "Invasive" if (p and p.get("invasive")) else "Native / Naturalized",
        "plant_type":       p.get("type", "Tree") if p else "Tree",
        "lifespan":         p.get("cycle", "Perennial") if p else "Perennial",
        "mature_height":    "10 to 30 meters",
        "mature_spread":    "5 to 15 meters",
        "leaf_type":        "Evergreen" if (p and p.get("tropical")) else "Evergreen / Semi-evergreen",
        "flowering_season": p.get("flowering_season", "March to June") if p else "March to June",
    }

    # Characteristics
    leaf_colors = p.get("leaf_color", []) if p else []
    characteristics = {
        "nativity": "4" if native_to != "Philippines / Southeast Asia" else "5",
        "flower":   "4" if (p and p.get("flowers")) else "3",
        "fruit":    "4" if (p and p.get("fruit")) else "3",
        "leaf_color": ", ".join(leaf_colors) if leaf_colors else "Dark green",
    }

    # Care profile
    watering   = p.get("watering", "Moderate") if p else "Moderate"
    sunlight   = p.get("sunlight", "Full Sun") if p else "Full Sun"
    care_level = p.get("care_level", p.get("maintenance", "Easy")) if p else "Easy"
    growth     = p.get("growth_rate", "") if p else ""
    hardiness  = p.get("hardiness", {}) if p else {}
    hardiness_str = f"Zone {hardiness.get('min', '10')} - {hardiness.get('max', '12')}" if hardiness else "Zone 10-12"

    care_profile = {
        "difficulty":       care_level or "Easy",
        "difficulty_note":  f"{'Fast' if growth == 'High' else 'Moderate'} growing tree, well-adapted to Philippine climate.",
        "watering":         watering or "Moderate",
        "watering_note":    g.get("watering", "Water deeply at the base. Young trees need more frequent watering.") if g else "Water deeply at the base. Young trees need more frequent watering.",
        "sunlight":         sunlight or "Full Sun",
        "sunlight_note":    g.get("sunlight", "Requires full sun for optimal growth.") if g else "Requires full sun for optimal growth.",
        "temperature":      "20°C to 35°C",
        "hardiness_zones":  hardiness_str,
        "soil":             "Well-draining loamy soil, slightly acidic to neutral (pH 6.0-7.0)",
        "fertilizer":       g.get("fertilization", "Balanced NPK fertilizer twice a year during growing season.") if g else "Balanced NPK fertilizer twice a year.",
    }

    # How-Tos
    watering_guide = g.get("watering", "") if g else ""
    sunlight_guide = g.get("sunlight", "") if g else ""
    pruning_guide  = g.get("pruning", "") if g else ""

    how_tos = [
        {
            "title": "How to water properly",
            "steps": [
                watering_guide[:120] if watering_guide else "Water deeply at the base of the tree, not the leaves.",
                "Water young trees 2-3 times per week; mature trees only during dry season.",
                "Check soil moisture — if top 2 inches are dry, water thoroughly.",
            ]
        },
        {
            "title": "How to prune",
            "steps": [
                pruning_guide[:120] if pruning_guide else "Prune dead or diseased branches first using clean, sharp tools.",
                "Remove crossing branches to improve air circulation.",
                "Best time to prune is after the rainy season (November to January).",
            ]
        },
        {
            "title": "How to propagate",
            "steps": [
                "Collect mature seeds during fruiting season.",
                "Soak seeds in water for 24 hours to improve germination rate.",
                "Plant in seedling bags with loamy soil; keep in partial shade until established.",
            ]
        },
    ]

    # Popular questions
    popular_questions = [
        {
            "q": f"How fast does {common_name} grow?",
            "a": f"{common_name} is a {(growth or 'moderate').lower()}-growing tree. Under good conditions it typically adds 1-2 meters per year when young.",
        },
        {
            "q": f"Is {common_name} drought tolerant?",
            "a": f"{'Yes, ' + common_name + ' has good drought tolerance once established.' if (p and p.get('drought_tolerant')) else common_name + ' prefers consistent moisture but can tolerate short dry periods once mature.'}",
        },
        {
            "q": f"Is {common_name} protected under Philippine law?",
            "a": "Many native Philippine trees are protected under DENR DAO 2017-11. Check with your local DENR office before cutting or transporting any tree.",
        },
    ]

    # Common problems
    common_problems = [
        {
            "name":        "Leaf Blight",
            "description": "Brown spots on leaves caused by fungal infection during wet season. Remove affected leaves and apply copper-based fungicide.",
            "severity":    "Medium",
        },
        {
            "name":        "Root Rot",
            "description": "Caused by overwatering or poor drainage. Ensure soil drains well and reduce watering frequency.",
            "severity":    "High",
        },
        {
            "name":        "Scale Insects",
            "description": "Small brown bumps on stems and leaves. Treat with neem oil or insecticidal soap spray.",
            "severity":    "Low",
        },
    ]

    # Uses
    description = p.get("description", "") if p else ""
    uses = {
        "timber":     f"{common_name} wood is valued for construction and furniture making." if not (p and p.get("indoor")) else None,
        "medicinal":  f"Bark and leaves of {common_name} are used in traditional Philippine herbal medicine.",
        "food":       f"Fruits are edible and consumed locally." if (p and p.get("edible_fruit")) else None,
        "ecological": f"{common_name} provides habitat for birds and insects, improves soil quality, sequesters carbon, and prevents erosion in Panabo City's urban forest.",
    }

    # Tagline
    family_name = t.get("family_common_name", "") if t else ""
    tagline = f"{common_name} — a resilient tree that has shaped the landscape and culture of the Philippine archipelago."

    return {
        "tagline":              tagline,
        "basic_info":           basic_info,
        "characteristics":      characteristics,
        "care_profile":         care_profile,
        "how_tos":              how_tos,
        "popular_questions":    popular_questions,
        "common_problems":      common_problems,
        "uses":                 uses,
        "adaptation_strategies": f"{common_name} thrives in Panabo City's tropical climate, tolerating heavy rainfall and dry spells. It is well-suited for urban planting, reforestation, and agroforestry integration in Davao del Norte.",
        "history_and_legends":  f"{common_name} has been part of Philippine culture for centuries. It appears in local folklore and has served communities as a source of timber, medicine, and shade across generations.",
        "name_story":           f"The name '{common_name}' reflects the tree's characteristics or its local significance. The scientific name '{scientific_name}' follows Linnaean taxonomy honoring the botanist who first formally described the species.",
        "symbolism":            f"{common_name} symbolizes strength, resilience, and the enduring bond between Filipinos and their natural environment. It represents the richness of Philippine biodiversity.",
        "sources":              {
            "perenual": bool(p),
            "trefle":   bool(t),
        },
    }


# ── Core identification pipeline ──────────────────────────────────────────────
async def identify_tree_from_base64(image_data: str, content_type: str = "image/jpeg") -> dict:
    image_bytes = base64.standard_b64decode(image_data)
    return await _pipeline(image_bytes, image_data, content_type)


async def identify_tree_from_url(image_url: str) -> dict:
    try:
        async with httpx.AsyncClient(timeout=30) as http:
            resp = await http.get(image_url)
            resp.raise_for_status()
            image_bytes  = resp.content
            content_type = resp.headers.get("content-type", "image/jpeg").split(";")[0]
        image_b64 = base64.standard_b64encode(image_bytes).decode()
        return await _pipeline(image_bytes, image_b64, content_type)
    except Exception as e:
        return {"not_identified": True, "reason": f"Failed to download image: {e}",
                "estimated_dbh_cm": None, "estimated_height_m": None}


DBH_MEASURE_PROMPT = """\
You are an expert Philippine forester measuring DBH from a field photo.

Estimate DBH (diameter at breast height) at 1.3 meters above ground.

Measurement context:
- Method: {method}
- Scale/reference: {reference_hint}
- User-entered camera distance: {known_distance}

Important rules:
- If a known reference object is visible near the trunk, use it as the primary scale.
- If user-entered camera distance is provided, use it as a secondary perspective cue.
- If no reference or distance is available, use ground perspective, camera height, nearby objects, trunk taper, and species maturity only. Mark confidence Low unless the photo has strong scale cues.
- Estimate camera-to-tree distance from the image, but be honest about uncertainty.
- DBH must be a positive number in centimeters.

Respond ONLY with valid JSON:
{
  "dbh_cm": 32.5,
  "height_m": 11.0,
  "confidence": "Low / Medium / High",
  "method": "brief method used",
  "analysis_notes": "2-3 sentences explaining scale cues, distance estimate, and uncertainty",
  "distance_estimate_m": 3.2,
  "accuracy_note": "expected error range, e.g. +/- 10-15 cm"
}
"""


async def measure_dbh_from_base64(
    image_data: str,
    content_type: str = "image/jpeg",
    reference_hint: str = "No reference object provided.",
    method: str = "Camera-assisted photo measurement",
    known_distance_m: float | None = None,
) -> dict:
    known_distance = (
        f"{known_distance_m:.2f} meters"
        if isinstance(known_distance_m, (int, float)) and known_distance_m > 0
        else "not provided"
    )
    prompt = (
        DBH_MEASURE_PROMPT
        .replace("{method}", method)
        .replace("{reference_hint}", reference_hint)
        .replace("{known_distance}", known_distance)
    )
    try:
        url = f"{GEMINI_URL}?key={GEMINI_API_KEY}"
        payload = {
            "contents": [{
                "parts": [
                    {"text": prompt},
                    {"inline_data": {"mime_type": content_type, "data": image_data}},
                ],
            }],
            "generationConfig": {"temperature": 0.1, "maxOutputTokens": 600},
        }
        async with httpx.AsyncClient(timeout=30) as http:
            resp = await http.post(url, json=payload)
        if resp.status_code != 200:
            raise Exception(f"Gemini {resp.status_code}")
        raw = resp.json()["candidates"][0]["content"]["parts"][0]["text"].strip()
        raw = re.sub(r"^```(?:json)?\s*", "", raw, flags=re.MULTILINE)
        raw = re.sub(r"\s*```\s*$", "", raw, flags=re.MULTILINE)
        result = json.loads(raw)
        result["dbh_cm"] = round(float(result.get("dbh_cm") or 0), 1)
        if result["dbh_cm"] <= 0:
            raise ValueError("Invalid DBH result")
        if result.get("height_m") is not None:
            result["height_m"] = round(float(result["height_m"]), 1)
        result.setdefault("confidence", "Low")
        result.setdefault("method", method)
        result.setdefault("analysis_notes", "")
        result.setdefault("distance_estimate_m", None)
        result.setdefault("accuracy_note", "+/- 20-30 cm without a clear scale reference")
        return result
    except Exception as e:
        return {
            "error": True,
            "detail": f"DBH analysis failed: {e}",
            "dbh_cm": 25.0,
            "height_m": None,
            "confidence": "Low",
            "method": method,
            "analysis_notes": "Fallback estimate only. Retake with A4 paper, ruler, or known distance for better accuracy.",
            "distance_estimate_m": known_distance_m,
            "accuracy_note": "+/- 30-50 cm fallback estimate",
        }


async def _pipeline(image_bytes: bytes, image_b64: str, content_type: str) -> dict:
    # Step 1 — PlantNet species hint
    pn = await _plantnet(image_bytes, content_type)

    # Step 2 — Gemini visual confirmation
    cl = await _gemini(image_b64, content_type, hint=pn)
    gemini_reason = cl.get("reason", "")

    # Step 3 — Merge species results
    if cl.get("not_identified"):
        if pn:
            cl = {
                **pn,
                "description": (
                    "Identified using PlantNet botanical image matching. "
                    "Detailed TreeTrace vision enrichment is unavailable right now."
                ),
                "distinguishing_features": "Based on visible leaf, crown, bark, flower, or fruit features in the uploaded photo.",
                "look_alikes":            "Use expert review when the image is unclear or visually similar to related species.",
                "dbh_method":             "Not estimated from this photo.",
                "habitat":                "Philippines / Southeast Asia",
                "uses":                   "Ecological value, shade, habitat, and carbon storage.",
                "is_tree":                True,
                "not_identified":         False,
                "confidence":             pn.get("confidence", "Low"),
                "estimated_dbh_cm":       None,
                "estimated_height_m":     None,
                "source":                 pn.get("source", "plantnet"),
                "ai_enrichment_available": False,
                "fallback":               True,
                "fallback_reason":        gemini_reason or "Detailed AI enrichment is unavailable.",
                "user_message": (
                    "Species match is based on PlantNet botanical image matching. "
                    "Gemini details are temporarily unavailable, so submit for expert review if unsure."
                ),
            }
        else:
            return {
                "not_identified":      True,
                "partial":             True,
                "reason":              cl.get("reason", "Species not identified."),
                "possible_candidates": cl.get("possible_candidates", []),
                "estimated_dbh_cm":    None,
                "estimated_height_m":  None,
                "common_name":         "",
                "scientific_name":     "",
            }

    # Prefer PlantNet species name when confident
    if pn and pn.get("confidence") in ("High", "Medium"):
        cl["common_name"]     = pn["common_name"]     or cl["common_name"]
        cl["scientific_name"] = pn["scientific_name"] or cl["scientific_name"]
        cl["family"]          = pn["family"]           or cl.get("family", "")
        cl["plantnet_score"]  = pn["plantnet_score"]
        cl["source"]          = "plantnet+gemini"
        cl["ai_enrichment_available"] = True
        if pn["confidence"] == "High":
            cl["confidence"] = "High"
    else:
        cl.setdefault("source", "gemini")
        cl.setdefault("ai_enrichment_available", True)

    gbif = await _gbif_match(cl.get("scientific_name", ""))
    if gbif:
        cl["gbif_validated"] = True
        cl["gbif_usage_key"] = gbif.get("usage_key")
        cl["gbif_match_type"] = gbif.get("match_type")
        cl["gbif_confidence"] = gbif.get("confidence")
        cl["gbif_status"] = gbif.get("status")
        if gbif.get("canonical_name"):
            cl["gbif_canonical_name"] = gbif["canonical_name"]
        if gbif.get("family") and not cl.get("family"):
            cl["family"] = gbif["family"]
    else:
        cl["gbif_validated"] = False

    return _enrich(cl)


def _enrich(result: dict) -> dict:
    common_name = result.get("common_name", "")
    scientific_name = result.get("scientific_name", "")
    info = lookup_species(common_name) or lookup_species(scientific_name)
    if info:
        result["endangered_status"] = info["status"]
        result["status_code"]       = info["status_code"]
        result["iucn_color"]        = info["iucn_color"]
        result["cutting_allowed"]   = info["cutting_allowed"]
        result["protected"]         = info["protected"]
    else:
        result["_needs_status_check"] = True
        result["_common_name"] = common_name
        result["_scientific_name"] = scientific_name
        result["endangered_status"] = "Not Listed"
        result["status_code"]       = "NL"
        result["iucn_color"]        = "#757575"
        result["cutting_allowed"]   = True
        result["protected"]         = False
    return result


# ── Updated pipeline with auto species check ──────────────────────────────────
async def _pipeline_with_status(image_bytes: bytes, image_b64: str, content_type: str) -> dict:
    """Full pipeline including automatic endangered status check."""
    result = await _pipeline(image_bytes, image_b64, content_type)

    # If needs async status check, do it now
    if result.get("_needs_status_check"):
        common_name     = result.pop("_common_name", "")
        scientific_name = result.pop("_scientific_name", "")
        result.pop("_needs_status_check", None)

        from app.services.species_db import auto_check_species
        info = await auto_check_species(common_name, scientific_name)
        result["endangered_status"] = info.get("status", "Not Listed")
        result["status_code"]       = info.get("status_code", "NL")
        result["iucn_color"]        = info.get("iucn_color", "#9e9e9e")
        result["cutting_allowed"]   = info.get("cutting_allowed", True)
        result["protected"]         = info.get("protected", False)
        result["status_source"]     = info.get("source", "default")

    return result
