from functools import lru_cache
import json
import logging
from math import cos, hypot, radians
from pathlib import Path
import re

import httpx


BOUNDARY_QUERY = "https://portal.georisk.gov.ph/arcgis/rest/services/PSA/Barangay/MapServer/4/query"
METERS_PER_DEGREE = 110_574
LOCAL_BOUNDARIES = Path(__file__).resolve().parents[2] / "data" / "panabo_barangays.geojson"
logger = logging.getLogger(__name__)


@lru_cache(maxsize=1)
def _read_local_boundaries(path: Path, modified_ns: int) -> list:
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    features = data.get("features") if data.get("type") == "FeatureCollection" else None
    if not isinstance(features, list) or not features:
        raise ValueError("Expected a nonempty GeoJSON FeatureCollection")
    return features


def _ring_position(ring, lat, lng, longitude_scale):
    """Return whether the fix is inside a ring and its distance to the edge."""
    inside = False
    distance = float("inf")
    points = [((x - lng) * longitude_scale, (y - lat) * METERS_PER_DEGREE)
              for x, y, *_ in ring]
    for (x, y), (end_x, end_y) in zip(points, points[1:] + points[:1]):
        dx, dy = end_x - x, end_y - y
        length_squared = dx * dx + dy * dy
        if length_squared:
            fraction = max(0, min(1, -(x * dx + y * dy) / length_squared))
            distance = min(distance, hypot(x + fraction * dx, y + fraction * dy))
        if (y > 0) != (end_y > 0) and x - y * dx / dy > 0:
            inside = not inside
    return inside, distance


def _match(features, lat, lng, accuracy_m, longitude_scale):
    matches = []
    for feature in features:
        geometry = feature["geometry"]
        polygons = geometry["coordinates"]
        if geometry["type"] == "Polygon":
            polygons = [polygons]
        elif geometry["type"] != "MultiPolygon":
            return {"status": "unavailable"}
        for polygon in polygons:
            exterior, *holes = [
                _ring_position(ring, lat, lng, longitude_scale) for ring in polygon
            ]
            if min(distance for _, distance in [exterior, *holes]) <= accuracy_m:
                return {"status": "uncertain"}
            if exterior[0] and not any(inside for inside, _ in holes):
                matches.append(feature["properties"])

    if len(matches) > 1:
        return {"status": "uncertain"}
    if not matches:
        return {"status": "unavailable"}
    match = matches[0]
    city = (match.get("city_name") or "").strip()
    if not city:
        return {"status": "unavailable"}
    if not re.search(r"\bpanabo\b", city, re.IGNORECASE):
        return {"status": "outside_panabo"}
    barangay = (match.get("brgy_name") or "").strip()
    if not barangay:
        return {"status": "unavailable"}
    return {
        "status": "resolved",
        "barangay": barangay,
        "city": "Panabo City",
        "province": "Davao del Norte",
    }


def resolve_barangay(lat: float, lng: float, accuracy_m: float) -> dict:
    # An uncertainty radius this large cannot fit within a Panabo barangay.
    # It also avoids sending an unbounded envelope to the boundary service.
    if accuracy_m >= 10_000:
        return {"status": "uncertain"}
    if not (7.0 <= lat <= 7.6 and 125.3 <= lng <= 126.0):
        return {"status": "outside_panabo"}
    longitude_scale = METERS_PER_DEGREE * cos(radians(lat))
    try:
        features = _read_local_boundaries(LOCAL_BOUNDARIES, LOCAL_BOUNDARIES.stat().st_mtime_ns)
        match = _match(features, lat, lng, accuracy_m, longitude_scale)
        if match["status"] != "unavailable":
            return match
    except FileNotFoundError:
        pass
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as exc:
        logger.warning("Panabo boundary file could not be used: %s", exc)

    dx, dy = accuracy_m / longitude_scale, accuracy_m / METERS_PER_DEGREE
    try:
        response = httpx.get(BOUNDARY_QUERY, params={
            "where": "1=1",
            "geometry": f"{lng - dx},{lat - dy},{lng + dx},{lat + dy}",
            "geometryType": "esriGeometryEnvelope",
            "spatialRel": "esriSpatialRelIntersects",
            "inSR": 4326,
            "outSR": 4326,
            "outFields": "city_name,brgy_name",
            "returnGeometry": "true",
            "f": "geojson",
        }, timeout=4)
        response.raise_for_status()
        data = response.json()
        if data.get("type") == "FeatureCollection" and not data.get("exceededTransferLimit"):
            return _match(data["features"], lat, lng, accuracy_m, longitude_scale)
        logger.warning("Barangay boundary service returned an unusable response")
    except (httpx.HTTPError, ValueError, KeyError, TypeError, AttributeError) as exc:
        logger.warning("Barangay boundary request failed: %s", type(exc).__name__)
    return {"status": "unavailable"}
