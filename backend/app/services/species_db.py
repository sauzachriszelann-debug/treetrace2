# Philippine Endangered Species Database
# Based on DENR DAO 2017-11 and IUCN Red List
# Auto-checks unknown species via Wikipedia API + Gemini

import httpx
import asyncio
import re

try:
    from app.core.config import settings
    GEMINI_API_KEY = settings.GEMINI_API_KEY
except Exception:
    import os
    GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")

# ── Local database (fast lookup, no API needed) ───────────────────────────────
PHILIPPINE_ENDANGERED_SPECIES = {
    # Critically Endangered
    "almaciga": {
        "scientific_name": "Agathis philippinensis",
        "status": "Critically Endangered",
        "status_code": "CR",
        "iucn_color": "#d32f2f",
        "protected": True,
        "description": "Ancient conifer tree, one of the most threatened in the Philippines.",
        "cutting_allowed": False,
    },
    "philippine teak": {
        "scientific_name": "Tectona philippinensis",
        "status": "Critically Endangered",
        "status_code": "CR",
        "iucn_color": "#d32f2f",
        "protected": True,
        "description": "Endemic Philippine teak, severely threatened by habitat loss.",
        "cutting_allowed": False,
    },
    "rafflesia": {
        "scientific_name": "Rafflesia speciosa",
        "status": "Critically Endangered",
        "status_code": "CR",
        "iucn_color": "#d32f2f",
        "protected": True,
        "description": "World's largest flower, endemic to the Philippines.",
        "cutting_allowed": False,
    },
    # Endangered
    "narra": {
        "scientific_name": "Pterocarpus indicus",
        "status": "Endangered",
        "status_code": "EN",
        "iucn_color": "#f57c00",
        "protected": True,
        "description": "National tree of the Philippines. Highly valued hardwood.",
        "cutting_allowed": False,
    },
    "molave": {
        "scientific_name": "Vitex parviflora",
        "status": "Endangered",
        "status_code": "EN",
        "iucn_color": "#f57c00",
        "protected": True,
        "description": "One of the four most valued Philippine hardwoods.",
        "cutting_allowed": False,
    },
    "ipil": {
        "scientific_name": "Intsia bijuga",
        "status": "Endangered",
        "status_code": "EN",
        "iucn_color": "#f57c00",
        "protected": True,
        "description": "Premium hardwood tree, heavily logged historically.",
        "cutting_allowed": False,
    },
    "dao": {
        "scientific_name": "Dracontomelon dao",
        "status": "Endangered",
        "status_code": "EN",
        "iucn_color": "#f57c00",
        "protected": True,
        "description": "Large canopy tree native to the Philippines.",
        "cutting_allowed": False,
    },
    "apitong": {
        "scientific_name": "Dipterocarpus grandiflorus",
        "status": "Endangered",
        "status_code": "EN",
        "iucn_color": "#f57c00",
        "protected": True,
        "description": "Important timber species of lowland dipterocarp forests.",
        "cutting_allowed": False,
    },
    "red lauan": {
        "scientific_name": "Shorea negrosensis",
        "status": "Endangered",
        "status_code": "EN",
        "iucn_color": "#f57c00",
        "protected": True,
        "description": "Major timber tree, severely depleted due to logging.",
        "cutting_allowed": False,
    },
    # Vulnerable
    "kamagong": {
        "scientific_name": "Diospyros philippinensis",
        "status": "Vulnerable",
        "status_code": "VU",
        "iucn_color": "#fbc02d",
        "protected": True,
        "description": "Philippine ebony, prized for extremely hard dark wood.",
        "cutting_allowed": False,
    },
    "batikuling": {
        "scientific_name": "Litsea leytensis",
        "status": "Vulnerable",
        "status_code": "VU",
        "iucn_color": "#fbc02d",
        "protected": True,
        "description": "Medium to large tree found in lowland forests.",
        "cutting_allowed": False,
    },
    "yakal": {
        "scientific_name": "Shorea astylosa",
        "status": "Vulnerable",
        "status_code": "VU",
        "iucn_color": "#fbc02d",
        "protected": True,
        "description": "Hard and durable timber, used in heavy construction.",
        "cutting_allowed": False,
    },
    "tindalo": {
        "scientific_name": "Afzelia rhomboidea",
        "status": "Vulnerable",
        "status_code": "VU",
        "iucn_color": "#fbc02d",
        "protected": True,
        "description": "Prized for fine-grained reddish-brown wood.",
        "cutting_allowed": False,
    },
    "mangkono": {
        "scientific_name": "Xanthostemon verdugonianus",
        "status": "Vulnerable",
        "status_code": "VU",
        "iucn_color": "#fbc02d",
        "protected": True,
        "description": "One of the hardest woods in the Philippines.",
        "cutting_allowed": False,
    },
    "dungon": {
        "scientific_name": "Heritiera sylvatica",
        "status": "Vulnerable",
        "status_code": "VU",
        "iucn_color": "#fbc02d",
        "protected": True,
        "description": "Medium to large tree of Philippine lowland forests.",
        "cutting_allowed": False,
    },
    # Least Concern
    "mahogany": {
        "scientific_name": "Swietenia macrophylla",
        "status": "Least Concern",
        "status_code": "LC",
        "iucn_color": "#388e3c",
        "protected": False,
        "description": "Widely planted timber tree, common in urban areas.",
        "cutting_allowed": True,
    },
    "mango": {
        "scientific_name": "Mangifera indica",
        "status": "Least Concern",
        "status_code": "LC",
        "iucn_color": "#388e3c",
        "protected": False,
        "description": "Common fruit tree, widely cultivated across the Philippines.",
        "cutting_allowed": True,
    },
    "coconut": {
        "scientific_name": "Cocos nucifera",
        "status": "Least Concern",
        "status_code": "LC",
        "iucn_color": "#388e3c",
        "protected": False,
        "description": "Tree of Life in the Philippines, extremely common.",
        "cutting_allowed": True,
    },
    "acacia": {
        "scientific_name": "Samanea saman",
        "status": "Least Concern",
        "status_code": "LC",
        "iucn_color": "#388e3c",
        "protected": False,
        "description": "Fast-growing shade tree, very common in streets and parks.",
        "cutting_allowed": True,
    },
    "langka": {
        "scientific_name": "Artocarpus heterophyllus",
        "status": "Least Concern",
        "status_code": "LC",
        "iucn_color": "#388e3c",
        "protected": False,
        "description": "Jackfruit tree, common fruit tree throughout the Philippines.",
        "cutting_allowed": True,
    },
    "banana": {
        "scientific_name": "Musa acuminata",
        "status": "Least Concern",
        "status_code": "LC",
        "iucn_color": "#388e3c",
        "protected": False,
        "description": "Common fruit plant found everywhere in the Philippines.",
        "cutting_allowed": True,
    },
    "gmelina": {
        "scientific_name": "Gmelina arborea",
        "status": "Least Concern",
        "status_code": "LC",
        "iucn_color": "#388e3c",
        "protected": False,
        "description": "Fast-growing plantation timber tree.",
        "cutting_allowed": True,
    },
    "falcata": {
        "scientific_name": "Falcataria moluccana",
        "status": "Least Concern",
        "status_code": "LC",
        "iucn_color": "#388e3c",
        "protected": False,
        "description": "Extremely fast-growing timber and pulpwood tree.",
        "cutting_allowed": True,
    },
    "santol": {
        "scientific_name": "Sandoricum koetjape",
        "status": "Least Concern",
        "status_code": "LC",
        "iucn_color": "#388e3c",
        "protected": False,
        "description": "Common tropical fruit tree in the Philippines.",
        "cutting_allowed": True,
    },
    "teak": {
        "scientific_name": "Tectona grandis",
        "status": "Least Concern",
        "status_code": "LC",
        "iucn_color": "#388e3c",
        "protected": False,
        "description": "Valuable timber tree widely planted in the Philippines.",
        "cutting_allowed": True,
    },
    # Kauri species (Agathis genus — all protected)
    "moore's kauri": {
        "scientific_name": "Agathis moorei",
        "status": "Vulnerable",
        "status_code": "VU",
        "iucn_color": "#fbc02d",
        "protected": True,
        "description": "Kauri conifer native to New Caledonia, related to Philippine Almaciga.",
        "cutting_allowed": False,
    },
    "kauri": {
        "scientific_name": "Agathis moorei",
        "status": "Vulnerable",
        "status_code": "VU",
        "iucn_color": "#fbc02d",
        "protected": True,
        "description": "Kauri conifer, member of the Agathis genus.",
        "cutting_allowed": False,
    },
    "new caledonian kauri": {
        "scientific_name": "Agathis moorei",
        "status": "Vulnerable",
        "status_code": "VU",
        "iucn_color": "#fbc02d",
        "protected": True,
        "description": "Kauri conifer native to New Caledonia.",
        "cutting_allowed": False,
    },
}

# ── Runtime cache (avoids repeated API calls) ─────────────────────────────────
_runtime_cache: dict = {}

# ── IUCN status code mapping ──────────────────────────────────────────────────
IUCN_MAP = {
    "extinct":                         ("EX", "#000000", False),
    "extinct in the wild":             ("EW", "#4a148c", False),
    "critically endangered":           ("CR", "#d32f2f", False),
    "endangered":                      ("EN", "#f57c00", False),
    "vulnerable":                      ("VU", "#fbc02d", False),
    "near threatened":                 ("NT", "#8bc34a", True),
    "conservation dependent":          ("CD", "#8bc34a", True),
    "least concern":                   ("LC", "#388e3c", True),
    "data deficient":                  ("DD", "#9e9e9e", True),
    "not evaluated":                   ("NE", "#9e9e9e", True),
    "not listed":                      ("NL", "#9e9e9e", True),
}

def _status_to_info(status_text: str) -> tuple:
    """Convert status text to (code, color, cutting_allowed)."""
    key = status_text.lower().strip()
    for k, v in IUCN_MAP.items():
        if k in key:
            return v
    return ("NL", "#9e9e9e", True)


# ── Wikipedia API check ───────────────────────────────────────────────────────
async def _check_wikipedia(name: str) -> dict | None:
    """Check Wikipedia for conservation status of any species."""
    try:
        # Try scientific name first, then common name
        search_names = [name.replace(" ", "_"), name.replace(" ", "%20")]
        for search in search_names:
            async with httpx.AsyncClient(timeout=10) as http:
                resp = await http.get(
                    f"https://en.wikipedia.org/api/rest_v1/page/summary/{search}",
                    headers={"User-Agent": "TreeTrace/1.0 (Panabo City Tree Inventory)"}
                )
            if resp.status_code != 200:
                continue

            data = resp.json()
            extract = data.get("extract", "").lower()

            # Look for IUCN status in the extract
            status_found = None
            for status_key in IUCN_MAP.keys():
                if status_key in extract:
                    status_found = status_key.title()
                    break

            if status_found:
                code, color, cutting = _status_to_info(status_found)
                protected = code in ("CR", "EN", "VU", "EW", "EX")
                return {
                    "status": status_found,
                    "status_code": code,
                    "iucn_color": color,
                    "cutting_allowed": cutting,
                    "protected": protected,
                    "description": data.get("extract", "")[:300],
                    "source": "wikipedia",
                }

        return None
    except Exception:
        return None


# ── Gemini API check ──────────────────────────────────────────────────────────
async def _check_gemini(common_name: str, scientific_name: str) -> dict | None:
    """Ask Gemini for conservation status of any species."""
    if not GEMINI_API_KEY:
        return None
    try:
        prompt = f"""You are a conservation biologist.
What is the IUCN Red List conservation status of:
Common name: {common_name}
Scientific name: {scientific_name}

Respond ONLY with valid JSON, no markdown:
{{
  "status": "Critically Endangered / Endangered / Vulnerable / Near Threatened / Least Concern / Data Deficient / Not Listed",
  "status_code": "CR / EN / VU / NT / LC / DD / NL",
  "protected": true or false,
  "cutting_allowed": true or false,
  "reason": "brief explanation why this status",
  "denr_protected": true or false (is it protected under Philippine DENR regulations?)
}}"""

        url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:generateContent?key={GEMINI_API_KEY}"
        payload = {
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {"temperature": 0.1, "maxOutputTokens": 300},
        }
        async with httpx.AsyncClient(timeout=15) as http:
            resp = await http.post(url, json=payload)
        if resp.status_code != 200:
            return None

        raw = resp.json()["candidates"][0]["content"]["parts"][0]["text"].strip()
        raw = re.sub(r"^```(?:json)?\s*", "", raw, flags=re.MULTILINE)
        raw = re.sub(r"\s*```\s*$",       "", raw, flags=re.MULTILINE)

        import json
        result = json.loads(raw.strip())
        code, color, _ = _status_to_info(result.get("status", ""))
        result["iucn_color"] = color
        if not result.get("status_code"):
            result["status_code"] = code
        result["source"] = "gemini"
        return result
    except Exception:
        return None


# ── GBIF check ────────────────────────────────────────────────────────────────
async def _check_gbif(scientific_name: str) -> dict | None:
    """Check GBIF for species taxonomy (no key needed)."""
    if not scientific_name:
        return None
    try:
        async with httpx.AsyncClient(timeout=10) as http:
            resp = await http.get(
                "https://api.gbif.org/v1/species",
                params={"name": scientific_name, "limit": 1},
                headers={"User-Agent": "TreeTrace/1.0"}
            )
        if resp.status_code != 200:
            return None
        data = resp.json()
        results = data.get("results", [])
        if not results:
            return None
        sp = results[0]
        threat = sp.get("threatStatuses", [])
        if threat:
            status_text = threat[0].replace("_", " ").title()
            code, color, cutting = _status_to_info(status_text)
            return {
                "status": status_text,
                "status_code": code,
                "iucn_color": color,
                "cutting_allowed": cutting,
                "protected": code in ("CR", "EN", "VU"),
                "source": "gbif",
            }
        return None
    except Exception:
        return None


# ── Auto-check any species ────────────────────────────────────────────────────
async def auto_check_species(common_name: str, scientific_name: str = "") -> dict:
    """
    Automatically check conservation status for ANY species.
    Pipeline: Local DB → Wikipedia → GBIF → Gemini
    Result is cached to avoid repeated API calls.
    """
    cache_key = f"{common_name.lower()}|{scientific_name.lower()}"
    if cache_key in _runtime_cache:
        return _runtime_cache[cache_key]

    # Step 1: Local DB (fastest)
    local = lookup_species(common_name)
    if local:
        _runtime_cache[cache_key] = local
        return local

    # Also check by scientific name in local DB
    if scientific_name:
        sci_lower = scientific_name.lower()
        for data in PHILIPPINE_ENDANGERED_SPECIES.values():
            if data["scientific_name"].lower() == sci_lower:
                _runtime_cache[cache_key] = data
                return data

    # Step 2: Wikipedia (free, no key, very reliable)
    search_name = scientific_name or common_name
    wiki = await _check_wikipedia(search_name)
    if wiki and wiki.get("status_code") not in ("NL", "NE", "DD"):
        result = {
            "scientific_name": scientific_name,
            "status": wiki["status"],
            "status_code": wiki["status_code"],
            "iucn_color": wiki["iucn_color"],
            "protected": wiki["protected"],
            "cutting_allowed": wiki["cutting_allowed"],
            "description": wiki.get("description", ""),
            "source": "wikipedia",
        }
        _runtime_cache[cache_key] = result
        return result

    # Step 3: GBIF (free, no key)
    if scientific_name:
        gbif = await _check_gbif(scientific_name)
        if gbif and gbif.get("status_code") not in ("NL", "NE", None):
            result = {
                "scientific_name": scientific_name,
                **gbif,
            }
            _runtime_cache[cache_key] = result
            return result

    # Step 4: Gemini (free, 1500/day)
    gemini = await _check_gemini(common_name, scientific_name)
    if gemini:
        result = {
            "scientific_name": scientific_name,
            "status": gemini.get("status", "Not Listed"),
            "status_code": gemini.get("status_code", "NL"),
            "iucn_color": gemini.get("iucn_color", "#9e9e9e"),
            "protected": gemini.get("protected", False),
            "cutting_allowed": gemini.get("cutting_allowed", True),
            "description": gemini.get("reason", ""),
            "source": "gemini",
        }
        _runtime_cache[cache_key] = result
        return result

    # Step 5: Default — not listed
    default = {
        "scientific_name": scientific_name,
        "status": "Not Listed",
        "status_code": "NL",
        "iucn_color": "#9e9e9e",
        "protected": False,
        "cutting_allowed": True,
        "description": "Conservation status not found in available databases.",
        "source": "default",
    }
    _runtime_cache[cache_key] = default
    return default


# ── Sync wrapper (for non-async code) ────────────────────────────────────────
def lookup_species(common_name: str) -> dict | None:
    """Fast local lookup only — no API calls."""
    key = common_name.lower().strip()
    if key in PHILIPPINE_ENDANGERED_SPECIES:
        return PHILIPPINE_ENDANGERED_SPECIES[key]
    for species_name, data in PHILIPPINE_ENDANGERED_SPECIES.items():
        if species_name in key or key in species_name:
            return data
        if data["scientific_name"].lower() in key.lower():
            return data
    return None


def get_all_protected() -> list:
    """Return all protected/endangered species."""
    return [
        {"common_name": k, **v}
        for k, v in PHILIPPINE_ENDANGERED_SPECIES.items()
        if v["protected"]
    ]