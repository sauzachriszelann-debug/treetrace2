from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from app.db.database import get_db
from app.models.health_log import HealthLog
from app.models.tree import Tree
from app.models.user import User
from app.schemas.health_log import HealthLogCreate, HealthLogOut
from app.core.security import get_current_user

router = APIRouter()


def _enrich(log: HealthLog, db: Session) -> dict:
    """Add denormalized fields for display."""
    data = {
        "id": log.id,
        "tree_id": log.tree_id,
        "condition": log.condition,
        "notes": log.notes,
        "assessed_date": log.assessed_date,
        "dbh_cm": log.dbh_cm,
        "height_m": log.height_m,
        "photo_url": log.photo_url,
        "assessed_by_id": log.assessed_by_id,
        "created_at": log.created_at,
        "tree_common_name": log.tree.common_name if log.tree else None,
        "assessed_by": (
            log.assessor.full_name or log.assessor.email
            if log.assessor else None
        ),
    }
    return data


@router.get("/", response_model=List[HealthLogOut])
def list_health_logs(
    tree_id: Optional[int] = None,
    skip: int = Query(0, ge=0),
    limit: int = Query(200, ge=1, le=1000),
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    """List health logs, optionally filtered by tree_id."""
    q = db.query(HealthLog)
    if tree_id is not None:
        q = q.filter(HealthLog.tree_id == tree_id)
    logs = q.order_by(HealthLog.created_at.desc()).offset(skip).limit(limit).all()
    return [_enrich(log, db) for log in logs]


@router.post("/", response_model=HealthLogOut, status_code=201)
def create_health_log(
    payload: HealthLogCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Create a health assessment log and update the tree's health_status."""
    if current_user.role == "citizen":
        raise HTTPException(
            status_code=403,
            detail="Citizen accounts cannot add official health assessments.",
        )
    tree = db.query(Tree).filter(Tree.id == payload.tree_id).first()
    if not tree:
        raise HTTPException(status_code=404, detail="Tree not found")

    log = HealthLog(
        **payload.model_dump(),
        assessed_by_id=current_user.id,
    )
    db.add(log)

    # Keep tree health status in sync
    tree.health_status = payload.condition
    db.commit()
    db.refresh(log)
    return _enrich(log, db)


@router.get("/{log_id}", response_model=HealthLogOut)
def get_health_log(
    log_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    log = db.query(HealthLog).filter(HealthLog.id == log_id).first()
    if not log:
        raise HTTPException(status_code=404, detail="Health log not found")
    return _enrich(log, db)


@router.delete("/{log_id}", status_code=204)
def delete_health_log(
    log_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role == "citizen":
        raise HTTPException(
            status_code=403,
            detail="Citizen accounts cannot delete official health assessments.",
        )
    log = db.query(HealthLog).filter(HealthLog.id == log_id).first()
    if not log:
        raise HTTPException(status_code=404, detail="Health log not found")
    db.delete(log)
    db.commit()
