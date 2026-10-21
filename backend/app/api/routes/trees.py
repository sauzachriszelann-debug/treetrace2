from fastapi import APIRouter, Depends, HTTPException, Query, Response
from sqlalchemy import or_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from typing import List, Optional
import csv
import io
import math
from app.db.database import get_db
from app.models.tree import Tree
from app.models.user import User
from app.schemas.tree import TreeCreate, TreeCreateOut, TreeUpdate, TreeOut
from app.core.security import get_current_user, require_admin
from app.services.species_db import lookup_species

router = APIRouter()


def _estimate_tree_carbon(dbh_cm: Optional[float], height_m: Optional[float]) -> tuple[Optional[float], Optional[float]]:
    if not dbh_cm or dbh_cm <= 0:
        return None, None
    height = height_m if height_m and height_m > 0 else 10.0
    wood_density = 0.6
    biomass = 0.0673 * ((wood_density * (dbh_cm ** 2) * height) ** 0.976)
    carbon = biomass * 0.47
    return round(biomass, 2), round(carbon, 2)


def _distance_km(a_lat: float, a_lng: float, b_lat: float, b_lng: float) -> float:
    radius = 6371.0
    d_lat = math.radians(b_lat - a_lat)
    d_lng = math.radians(b_lng - a_lng)
    lat1 = math.radians(a_lat)
    lat2 = math.radians(b_lat)
    h = (
        math.sin(d_lat / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin(d_lng / 2) ** 2
    )
    return radius * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h))

@router.get("/", response_model=List[TreeOut])
def list_trees(
    skip: int = Query(0, ge=0),
    limit: int = Query(200, ge=1, le=1000),
    health_status: Optional[str] = None,
    search: Optional[str] = None,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    """List all trees with optional search and health filter."""
    q = db.query(Tree)
    if health_status:
        q = q.filter(Tree.health_status == health_status)
    if search:
        pattern = f"%{search}%"
        q = q.filter(
            Tree.common_name.ilike(pattern)
            | Tree.scientific_name.ilike(pattern)
            | Tree.barangay.ilike(pattern)
        )
    return q.order_by(Tree.created_at.desc()).offset(skip).limit(limit).all()


@router.get("/reports/inventory.csv")
def export_inventory_csv(
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    trees = db.query(Tree).order_by(Tree.created_at.desc()).all()
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow([
        "ID",
        "Common Name",
        "Scientific Name",
        "Barangay",
        "Health Status",
        "DBH CM",
        "Height M",
        "Carbon KG",
        "Latitude",
        "Longitude",
        "Conservation Status",
        "Cutting Allowed",
        "Created At",
    ])
    for tree in trees:
        info = lookup_species(tree.common_name or "") or {}
        writer.writerow([
            tree.id,
            tree.common_name,
            tree.scientific_name or "",
            tree.barangay or "",
            tree.health_status,
            tree.dbh_cm or "",
            tree.height_m or "",
            tree.carbon_kg or "",
            tree.lat or "",
            tree.lng or "",
            info.get("status", "Not Listed"),
            "Yes" if info.get("cutting_allowed", True) else "No",
            tree.created_at.isoformat() if tree.created_at else "",
        ])

    return Response(
        content=output.getvalue(),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=treetrace_inventory.csv"},
    )


@router.get("/qr-print")
def qr_print_labels(
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    trees = db.query(Tree).order_by(Tree.common_name.asc()).all()
    return [
        {
            "id": tree.id,
            "common_name": tree.common_name,
            "scientific_name": tree.scientific_name,
            "barangay": tree.barangay,
            "qr_code_url": tree.qr_code_url,
            "public_url": f"/public/tree/{tree.id}",
        }
        for tree in trees
    ]


@router.get("/route-plan")
def route_plan(
    start_lat: Optional[float] = None,
    start_lng: Optional[float] = None,
    barangay: Optional[str] = None,
    health_status: Optional[str] = None,
    limit: int = Query(25, ge=1, le=100),
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    q = db.query(Tree).filter(Tree.lat.isnot(None), Tree.lng.isnot(None))
    if barangay:
        q = q.filter(Tree.barangay.ilike(f"%{barangay}%"))
    if health_status:
        q = q.filter(Tree.health_status == health_status)
    trees = q.limit(300).all()

    if start_lat is not None and start_lng is not None:
        trees.sort(key=lambda t: _distance_km(start_lat, start_lng, t.lat, t.lng))
    else:
        trees.sort(key=lambda t: (t.barangay or "", t.common_name or ""))

    route = []
    previous = None
    total_km = 0.0
    for order, tree in enumerate(trees[:limit], start=1):
        leg_km = 0.0
        if previous:
            leg_km = _distance_km(previous.lat, previous.lng, tree.lat, tree.lng)
            total_km += leg_km
        elif start_lat is not None and start_lng is not None:
            leg_km = _distance_km(start_lat, start_lng, tree.lat, tree.lng)
            total_km += leg_km
        route.append({
            "order": order,
            "tree_id": tree.id,
            "common_name": tree.common_name,
            "barangay": tree.barangay,
            "health_status": tree.health_status,
            "lat": tree.lat,
            "lng": tree.lng,
            "leg_km": round(leg_km, 3),
        })
        previous = tree

    return {
        "total_stops": len(route),
        "estimated_distance_km": round(total_km, 3),
        "route": route,
    }


def _normalize_name(value: Optional[str]) -> str:
    return (value or "").strip().lower()


def _normalize_coord(value: Optional[float]) -> Optional[float]:
    return None if value is None else round(float(value), 7)


def _identity_fingerprint(
    common_name: Optional[str],
    scientific_name: Optional[str],
    lat: Optional[float],
    lng: Optional[float],
    barangay: Optional[str],
) -> tuple:
    """Identity of a tree submission, used to detect client_uuid reuse.

    Deliberately excludes photo_url (every retry re-uploads and receives a
    fresh URL) and measurement/annotation fields (editable data, not
    identity). Any difference here means the UUID is being reused for a
    different tree and must surface as HTTP 409 - never a silent merge.
    """
    return (
        _normalize_name(common_name),
        _normalize_name(scientific_name),
        _normalize_coord(lat),
        _normalize_coord(lng),
        _normalize_name(barangay),
    )


_COMPARE_FIELDS = (
    "dbh_cm",
    "height_m",
    "health_status",
    "city",
    "province",
    "photo_url",
    "date_recorded",
    "notes",
)

# The single uniqueness object protecting trees.client_uuid (named constraint
# in app/models/tree.py; same-named unique index in
# backend/migrations/0001_add_trees_client_uuid.sql).
_CLIENT_UUID_CONSTRAINT = "ux_trees_client_uuid"


def _is_client_uuid_conflict(error: IntegrityError) -> bool:
    """True only for the trees.client_uuid uniqueness violation.

    PostgreSQL (production): SQLSTATE 23505 alone is NOT enough - the
    violated constraint/index must be the G2 idempotency one. Any other
    unique violation (or any other integrity failure) is unrelated and must
    propagate instead of being misread as a retryable UUID collision.

    SQLite (local tests): accept the table.column-scoped UNIQUE message for
    trees.client_uuid only.
    """
    original = getattr(error, "orig", None)
    if original is None:
        return False
    sqlstate = getattr(original, "pgcode", None)
    if sqlstate is not None:  # psycopg2 / psycopg3 carry the SQLSTATE here
        return sqlstate == "23505" and _CLIENT_UUID_CONSTRAINT in str(original)
    # SQLite raises e.g. "UNIQUE constraint failed: trees.client_uuid".
    return "UNIQUE constraint failed: trees.client_uuid" in str(original)


def _replayed_differences(existing: Tree, submitted: dict) -> dict:
    """Report non-identity differences between the stored tree and a replay.

    Differences are reported, never applied: an existing tree is never
    overwritten by an idempotent replay.
    """

    def norm_str(value):
        if hasattr(value, "value"):  # SQLAlchemy Enum members
            value = value.value
        text = (value or "").strip()
        return text or None

    def norm_num(value):
        return None if value is None else round(float(value), 2)

    def norm_date(value):
        return None if value is None else value.isoformat()

    converters = {
        "dbh_cm": norm_num,
        "height_m": norm_num,
        "health_status": norm_str,
        "city": norm_str,
        "province": norm_str,
        "photo_url": norm_str,
        "date_recorded": norm_date,
        "notes": norm_str,
    }
    differences = {}
    for field in _COMPARE_FIELDS:
        convert = converters[field]
        existing_value = convert(getattr(existing, field))
        submitted_value = convert(submitted.get(field))
        if existing_value != submitted_value:
            differences[field] = {
                "existing": existing_value,
                "submitted": submitted_value,
            }
    return differences


@router.post("/", response_model=TreeCreateOut, status_code=201)
def create_tree(
    payload: TreeCreate,
    response: Response,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Create a new tree record.

    Idempotent when the client supplies ``client_uuid``: a repeated request
    returns the already-created tree with HTTP 200 and an
    ``Idempotent-Replay: true`` header instead of creating a duplicate.
    """
    if current_user.role == "citizen":
        raise HTTPException(
            status_code=403,
            detail="Citizen accounts cannot add official inventory trees. Please submit the species for expert review instead.",
        )
    data = payload.model_dump()
    client_uuid = data.pop("client_uuid", None)
    client_uuid = str(client_uuid) if client_uuid is not None else None
    submitted = payload.model_dump(exclude={"client_uuid"})

    def replay(existing: Tree):
        # The route default is 201; an idempotent replay is an HTTP 200.
        response.status_code = 200
        response.headers["Idempotent-Replay"] = "true"
        body = TreeCreateOut.model_validate(existing).model_dump()
        body["idempotent_replay"] = True
        body["replayed_differences"] = _replayed_differences(existing, submitted)
        return body

    if client_uuid is not None:
        existing = (
            db.query(Tree).filter(Tree.client_uuid == client_uuid).first()
        )
        if existing is not None:
            if (
                _identity_fingerprint(
                    payload.common_name,
                    payload.scientific_name,
                    payload.lat,
                    payload.lng,
                    payload.barangay,
                )
                != _identity_fingerprint(
                    existing.common_name,
                    existing.scientific_name,
                    existing.lat,
                    existing.lng,
                    existing.barangay,
                )
            ):
                raise HTTPException(
                    status_code=409,
                    detail={
                        "message": (
                            "This submission key is already associated with a "
                            "different tree. Nothing was merged or overwritten."
                        ),
                        "existing_tree_id": existing.id,
                    },
                )
            return replay(existing)

    biomass, carbon = _estimate_tree_carbon(data.get("dbh_cm"), data.get("height_m"))
    data["biomass_kg"] = biomass
    data["carbon_kg"] = carbon
    data["client_uuid"] = client_uuid

    # The unique index on trees.client_uuid is the source of truth: two
    # concurrent requests cannot both insert the same key. The loser raises
    # IntegrityError after the winner commits; resolve it by returning the
    # winner's record (or 409 on a fingerprint mismatch).
    for attempt in range(2):
        try:
            tree = Tree(**data, recorded_by_id=current_user.id)
            db.add(tree)
            db.commit()
            db.refresh(tree)
            return tree
        except IntegrityError as exc:
            db.rollback()
            # Recover ONLY from the client_uuid uniqueness violation. Any
            # other integrity failure (unrelated constraint, wrong SQLSTATE,
            # wrong constraint name) is re-raised untouched.
            if client_uuid is None or not _is_client_uuid_conflict(exc):
                raise
            existing = (
                db.query(Tree).filter(Tree.client_uuid == client_uuid).first()
            )
            if existing is not None:
                if (
                    _identity_fingerprint(
                        payload.common_name,
                        payload.scientific_name,
                        payload.lat,
                        payload.lng,
                        payload.barangay,
                    )
                    != _identity_fingerprint(
                        existing.common_name,
                        existing.scientific_name,
                        existing.lat,
                        existing.lng,
                        existing.barangay,
                    )
                ):
                    raise HTTPException(
                        status_code=409,
                        detail={
                            "message": (
                                "This submission key is already associated with a "
                                "different tree. Nothing was merged or overwritten."
                            ),
                            "existing_tree_id": existing.id,
                        },
                    )
                return replay(existing)
            if attempt == 0:
                # The conflicting transaction aborted; retry the insert once.
                continue
            raise HTTPException(
                status_code=503,
                detail=(
                    "Could not uniquely record this submission. "
                    "Please retry with the same submission key."
                ),
            )


# ── Nearby matching suggestions (G3) ─────────────────────────────────────
_NEARBY_DEFAULT_RADIUS_M = 15.0
_NEARBY_MAX_RADIUS_M = 100.0
_NEARBY_DEFAULT_LIMIT = 5
_NEARBY_MAX_LIMIT = 10


@router.get("/nearby")
def nearby_trees(
    lat: float = Query(..., ge=-90, le=90),
    lng: float = Query(..., ge=-180, le=180),
    radius_m: float = Query(_NEARBY_DEFAULT_RADIUS_M, gt=0, le=_NEARBY_MAX_RADIUS_M),
    limit: int = Query(_NEARBY_DEFAULT_LIMIT, ge=1, le=_NEARBY_MAX_LIMIT),
    common_name: Optional[str] = None,
    scientific_name: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Advisory duplicate-prevention lookup (G3). Strictly read-only.

    Suggests existing trees near a proposed GPS point so staff can avoid
    registering the same physical tree twice. The result is advisory only:
    this endpoint never writes, and callers must never treat a match as a
    reason to merge, overwrite, delete, or reject a registration.

    Nearest-neighbor selection is exact and portable. The WHERE clause
    bounds the scan to a geographic box that provably contains the entire
    search circle (exact spherical bounds: |Δlat| ≤ r/R, and
    |Δlng| ≤ asin(sin(r/R)/cos(lat)), covering the antimeridian and pole
    cases), and every row in that box is then measured with the same
    haversine used by route-plan. Ordering and the limit are applied only
    AFTER exact distances are computed — sorted by unrounded distance with
    tree id as tie-break — so no candidate that is genuinely nearer can be
    dropped or misordered by an approximation before the final result set
    is selected.

    Trade-off: with no coordinate index (per approved design) this is a
    full sequential scan either way; dropping SQL ORDER BY/LIMIT only
    changes which rows are transferred (every in-box row — tens to a few
    hundred for a <=100 m urban box — instead of limit+5) and moves a
    trivial sort to Python. Sub-millisecond at inventory scale, in exchange
    for the exact guarantee. SQL-side exact haversine is not an option
    (SQLite in the test stack has no trig functions; PostgreSQL-only
    functions would break portability), and PostGIS is out of scope — no
    schema change is needed for this approach.
    """
    if current_user.role == "citizen":
        raise HTTPException(
            status_code=403,
            detail="Nearby suggestions are available to admins and field workers.",
        )

    # Bounding box: a proven superset of the search circle on the sphere
    # used by _distance_km (R = 6371 km). Any point within angular radius
    # gamma = r/R satisfies |Δlat| <= gamma (a meridian arc is the latitude
    # extreme), and maximising |Δlng| over the circle via the spherical law
    # of cosines gives |Δlng| <= asin(sin(gamma)/cos(lat)), or all
    # longitudes when the circle contains a pole. A 1e-9-degree epsilon
    # (~0.1 mm) absorbs floating-point noise so the box can never clip a
    # tree that is inside the radius.
    gamma = radius_m / 6371000.0
    box_dlat = math.degrees(gamma)
    cos_lat = math.cos(math.radians(lat))
    sin_dlng = math.sin(gamma) / max(cos_lat, 1e-12)
    if sin_dlng >= 1.0:
        box_dlng = 180.0  # circle contains a pole: every longitude qualifies
    else:
        box_dlng = math.degrees(math.asin(sin_dlng))
    epsilon = 1e-9
    box_lat_low = lat - box_dlat - epsilon
    box_lat_high = lat + box_dlat + epsilon
    box_lng_low = lng - box_dlng - epsilon
    box_lng_high = lng + box_dlng + epsilon

    lng_filter = Tree.lng.between(box_lng_low, box_lng_high)
    if box_lng_high > 180.0:
        # Box crosses the antimeridian: also match the wrapped segment.
        lng_filter = or_(
            lng_filter,
            Tree.lng.between(box_lng_low - 360.0, box_lng_high - 360.0),
        )
    elif box_lng_low < -180.0:
        lng_filter = or_(
            lng_filter,
            Tree.lng.between(box_lng_low + 360.0, box_lng_high + 360.0),
        )

    # No SQL ORDER BY / LIMIT here, deliberately: every row in the box must
    # be measured exactly before nearest-N truncation, so that an
    # approximation can never exclude a genuinely nearer tree.
    rows = (
        db.query(Tree)
        .filter(
            Tree.lat.isnot(None),
            Tree.lng.isnot(None),
            Tree.lat.between(box_lat_low, box_lat_high),
            lng_filter,
        )
        .all()
    )

    submitted_common = _normalize_name(common_name)
    submitted_sci = _normalize_name(scientific_name)
    has_submitted_species = bool(submitted_common or submitted_sci)

    measured = []
    for tree in rows:
        distance_m = _distance_km(lat, lng, tree.lat, tree.lng) * 1000.0
        if distance_m > radius_m:
            continue
        if not has_submitted_species:
            species_match = "unknown"
        else:
            same_common = bool(submitted_common) and (
                _normalize_name(tree.common_name) == submitted_common
            )
            same_sci = (
                bool(submitted_sci)
                and bool(tree.scientific_name)
                and _normalize_name(tree.scientific_name) == submitted_sci
            )
            species_match = "exact" if (same_common or same_sci) else "different"
        measured.append(
            (
                distance_m,
                tree.id,
                {
                    "tree_id": tree.id,
                    "common_name": tree.common_name,
                    "scientific_name": tree.scientific_name,
                    "distance_m": round(distance_m, 1),
                    "species_match": species_match,
                    "health_status": getattr(
                        tree.health_status, "value", tree.health_status
                    ),
                    "barangay": tree.barangay,
                    "created_at": tree.created_at.isoformat()
                    if tree.created_at
                    else None,
                },
            )
        )
    # Order by the exact unrounded distance (tree id breaks ties between
    # nearly equal candidates so the response is deterministic), and only
    # then truncate to the requested limit.
    measured.sort(key=lambda item: (item[0], item[1]))
    return [payload for _, _, payload in measured[:limit]]


@router.get("/{tree_id}", response_model=TreeOut)
def get_tree(
    tree_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    """Get a single tree by ID."""
    tree = db.query(Tree).filter(Tree.id == tree_id).first()
    if not tree:
        raise HTTPException(status_code=404, detail="Tree not found")
    return tree


@router.patch("/{tree_id}", response_model=TreeOut)
def update_tree(
    tree_id: int,
    payload: TreeUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Update a tree record."""
    if current_user.role == "citizen":
        raise HTTPException(
            status_code=403,
            detail="Citizen accounts cannot edit official inventory trees.",
        )
    tree = db.query(Tree).filter(Tree.id == tree_id).first()
    if not tree:
        raise HTTPException(status_code=404, detail="Tree not found")
    data = payload.model_dump(exclude_unset=True)
    dbh = data.get("dbh_cm", tree.dbh_cm)
    height = data.get("height_m", tree.height_m)
    if "dbh_cm" in data or "height_m" in data:
        biomass, carbon = _estimate_tree_carbon(dbh, height)
        data["biomass_kg"] = biomass
        data["carbon_kg"] = carbon
    for field, value in data.items():
        setattr(tree, field, value)
    db.commit()
    db.refresh(tree)
    return tree


@router.delete("/{tree_id}", status_code=204)
def delete_tree(
    tree_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    """Delete a tree record. Admin only."""
    tree = db.query(Tree).filter(Tree.id == tree_id).first()
    if not tree:
        raise HTTPException(status_code=404, detail="Tree not found")
    db.delete(tree)
    db.commit()


@router.get("/stats/summary")
def tree_stats(
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    """Return aggregated dashboard statistics."""
    trees = db.query(Tree).all()
    total = len(trees)
    healthy = sum(1 for t in trees if t.health_status == "Healthy")
    fair = sum(1 for t in trees if t.health_status == "Fair")
    poor = sum(1 for t in trees if t.health_status == "Poor")
    total_carbon = sum(t.carbon_kg or 0 for t in trees)
    gps_tagged = sum(1 for t in trees if t.lat and t.lng)
    return {
        "total": total,
        "healthy": healthy,
        "fair": fair,
        "poor": poor,
        "total_carbon_kg": round(total_carbon, 2),
        "gps_tagged": gps_tagged,
    }
