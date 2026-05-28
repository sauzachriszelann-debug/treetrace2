from fastapi import APIRouter, Depends, HTTPException, Query, Response
from sqlalchemy.orm import Session
from typing import List, Optional
import csv
import io
import math
from app.db.database import get_db
from app.models.tree import Tree
from app.models.user import User
from app.schemas.tree import TreeCreate, TreeUpdate, TreeOut
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


@router.post("/", response_model=TreeOut, status_code=201)
def create_tree(
    payload: TreeCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Create a new tree record."""
    if current_user.role == "citizen":
        raise HTTPException(
            status_code=403,
            detail="Citizen accounts cannot add official inventory trees. Please submit the species for expert review instead.",
        )
    data = payload.model_dump()
    if data.get("carbon_kg") is None:
        biomass, carbon = _estimate_tree_carbon(data.get("dbh_cm"), data.get("height_m"))
        data["biomass_kg"] = data.get("biomass_kg") or biomass
        data["carbon_kg"] = carbon
    tree = Tree(**data, recorded_by_id=current_user.id)
    db.add(tree)
    db.commit()
    db.refresh(tree)
    return tree


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
    if data.get("carbon_kg") is None and ("dbh_cm" in data or "height_m" in data):
        biomass, carbon = _estimate_tree_carbon(dbh, height)
        data["biomass_kg"] = data.get("biomass_kg") or biomass
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
