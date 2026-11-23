"""Fail-closed inventory geofence, shared by web/mobile/offline API writes.

Uses bundled barangay polygons, never a client-supplied city/barangay label or
an approximate bounding box. Photo-only review evidence can remain pending;
official inventory always requires a complete, verified coordinate pair.
"""
import math
from fastapi import HTTPException
from app.core.config import settings
from app.services.barangay_location import (
    LOCAL_BOUNDARIES, METERS_PER_DEGREE, _match, _read_local_boundaries,
)


def validate_inventory_location(lat, lng, accuracy_m=None, *, required=True):
    if lat is None and lng is None and not required:
        return None
    if lat is None or lng is None:
        raise HTTPException(422, 'Both latitude and longitude are required to verify the Panabo City inventory boundary.')
    values = (lat, lng) + (() if accuracy_m is None else (accuracy_m,))
    if any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) for v in values):
        raise HTTPException(422, 'Location coordinates and GPS accuracy must be finite numbers.')
    if not (-90 <= lat <= 90 and -180 <= lng <= 180) or (accuracy_m is not None and not 0 <= accuracy_m <= 10000):
        raise HTTPException(422, 'Location coordinates or GPS accuracy are outside their valid ranges.')
    if settings.INVENTORY_BOUNDARY_TEST_BYPASS:
        return None
    try:
        features = _read_local_boundaries(LOCAL_BOUNDARIES, LOCAL_BOUNDARIES.stat().st_mtime_ns)
        if any('panabo' not in (f.get('properties', {}).get('city_name') or '').lower() for f in features):
            raise ValueError('Unexpected city in bundled inventory boundary')
        if any(f.get('geometry', {}).get('type') not in ('Polygon', 'MultiPolygon') for f in features):
            raise ValueError('Invalid bundled inventory geometry')
        scale = METERS_PER_DEGREE * math.cos(math.radians(lat))
        point = _match(features, lat, lng, 0, scale)
        if point['status'] == 'unavailable' or point['status'] == 'outside_panabo':
            raise HTTPException(422, 'This location is outside the Panabo City inventory boundary. Choose a tree inside Panabo City.')
        if point['status'] != 'resolved':
            raise HTTPException(422, 'This location is on an uncertain boundary. Verify the tree location or capture GPS again.')
        if accuracy_m:
            match = _match(features, lat, lng, accuracy_m, scale)
            if match['status'] != 'resolved':
                raise HTTPException(422, 'The GPS accuracy area crosses a barangay or city boundary. Capture a more precise location before saving.')
        return point
    except HTTPException:
        raise
    except (OSError, ValueError, KeyError, TypeError, AttributeError, IndexError, ZeroDivisionError):
        raise HTTPException(503, 'The Panabo City boundary could not be verified. Nothing was saved; please try again later.') from None


def validate_review_location_description(description):
    """Check numeric 'lat, lng' evidence; ordinary landmark prose is not GPS."""
    parts = (description or '').split(',')
    if len(parts) != 2:
        return
    try:
        lat, lng = (float(part.strip()) for part in parts)
    except ValueError:
        return
    validate_inventory_location(lat, lng)
