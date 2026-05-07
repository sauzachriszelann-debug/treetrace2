from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from app.db.database import get_db
from app.models.tree import Tree
from app.models.user import User
from app.schemas.tree import TreeCreate, TreeUpdate, TreeOut
from app.core.security import get_current_user, require_admin

router = APIRouter()

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
    tree = Tree(**payload.model_dump(), recorded_by_id=current_user.id)
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
    for field, value in payload.model_dump(exclude_unset=True).items():
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
