from fastapi import APIRouter, Depends, UploadFile, File, HTTPException, Form
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional
from datetime import date
import base64
import json

from app.db.database import get_db
from app.models.user import User, UserRole
from app.models.unknown_species import UnknownSpecies
from app.core.security import get_current_user, require_admin
from app.services.ai_identify import identify_tree_from_url, _pipeline_with_status, measure_dbh_from_base64, get_dbh_runtime_status
from app.services.species_db import get_all_protected, lookup_species, PHILIPPINE_ENDANGERED_SPECIES

router = APIRouter()


@router.get("/dbh-status")
async def dbh_status():
    return get_dbh_runtime_status()

AI_DAILY_LIMITS = {
    "free": 10,
    "pro": 50,
    "professional": 50,
    "enterprise": None,
}

UNKNOWN_DAILY_LIMITS = {
    "free": 15,
    "pro": 100,
    "professional": 100,
    "enterprise": None,
}


def _normalize_plan(user: User) -> str:
    return (user.subscription_plan or "free").lower().strip()


def _reset_daily_usage_if_needed(user: User, db: Session):
    today = date.today()
    if user.ai_usage_date != today:
        user.ai_usage_date = today
        user.ai_identifications_today = 0
        user.unknown_submissions_today = 0
        db.commit()


def _usage_payload(user: User, limits: dict, counter_attr: str):
    if user.role in (UserRole.admin, UserRole.field_worker):
        return {
            "used_today": 0,
            "daily_limit": None,
            "remaining": None,
            "unlimited": True,
            "plan": "staff",
        }

    plan = _normalize_plan(user)
    daily_limit = limits.get(plan, limits["free"])
    used_today = getattr(user, counter_attr) or 0
    if daily_limit is None:
        return {
            "used_today": used_today,
            "daily_limit": None,
            "remaining": None,
            "unlimited": True,
            "plan": plan,
        }
    return {
        "used_today": used_today,
        "daily_limit": daily_limit,
        "remaining": max(daily_limit - used_today, 0),
        "unlimited": False,
        "plan": plan,
    }


def _enforce_limit(
    user: User,
    db: Session,
    *,
    limits: dict,
    counter_attr: str,
    feature_name: str,
):
    if user.role in (UserRole.admin, UserRole.field_worker):
        return

    _reset_daily_usage_if_needed(user, db)
    plan = _normalize_plan(user)
    daily_limit = limits.get(plan, limits["free"])
    if daily_limit is None:
        return

    used_today = getattr(user, counter_attr) or 0
    if used_today >= daily_limit:
        plan_label = (
            "Starter"
            if plan == "free"
            else "Professional"
            if plan in ("pro", "professional")
            else "Enterprise"
        )
        db.commit()
        raise HTTPException(
            status_code=402,
            detail=(
                f"You've used all {daily_limit} {feature_name} for today on the "
                f"{plan_label} plan. Upgrade for higher daily access."
            ),
        )

    setattr(user, counter_attr, used_today + 1)
    db.commit()


def enforce_ai_limit(user: User, db: Session):
    _enforce_limit(
        user,
        db,
        limits=AI_DAILY_LIMITS,
        counter_attr="ai_identifications_today",
        feature_name="AI identifications",
    )


def enforce_unknown_limit(user: User, db: Session):
    _enforce_limit(
        user,
        db,
        limits=UNKNOWN_DAILY_LIMITS,
        counter_attr="unknown_submissions_today",
        feature_name="unknown species submissions",
    )


@router.get("/usage")
def ai_usage(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _reset_daily_usage_if_needed(current_user, db)
    return {
        "ai": _usage_payload(current_user, AI_DAILY_LIMITS, "ai_identifications_today"),
        "unknown": _usage_payload(current_user, UNKNOWN_DAILY_LIMITS, "unknown_submissions_today"),
        "qr_scan": {"unlimited": True},
        "public_map": {"unlimited": True},
    }

@router.post("/identify")
async def identify_tree(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    enforce_ai_limit(current_user, db)
    if not (file.content_type or "").startswith("image/"):
        raise HTTPException(status_code=400, detail="File must be an image.")
    contents = await file.read()
    image_data = base64.standard_b64encode(contents).decode("utf-8")
    image_bytes = base64.standard_b64decode(image_data)
    try:
        result = await _pipeline_with_status(image_bytes, image_data, file.content_type)
        return result
    except Exception as exc:
        return {
            "not_identified": True,
            "common_name": "Unknown species",
            "scientific_name": "",
            "confidence": "Low",
            "possible_candidates": [],
            "reason": (
                "TreeTrace could not complete AI identification right now. "
                "You can still submit this photo for expert review."
            ),
            "debug_detail": str(exc),
        }

class IdentifyFromURLRequest(BaseModel):
    image_url: str


class MeasureDBHRequest(BaseModel):
    image_base64: str
    content_type: str = "image/jpeg"
    reference_hint: str = "No reference object provided."
    method: str = "Camera-assisted photo measurement"
    known_distance_m: Optional[float] = None


def _safe_dbh_estimate(reason: str, reference_hint: str, known_distance_m: Optional[float]):
    has_reference = reference_hint and "no reference" not in reference_hint.lower()
    has_distance = isinstance(known_distance_m, (int, float)) and known_distance_m > 0
    return {
        "dbh_cm": 25.0,
        "height_m": 8.0,
        "confidence": "Medium" if has_reference or has_distance else "Low",
        "method": "Safe DBH estimate",
        "analysis_notes": reason,
        "distance_estimate_m": known_distance_m if has_distance else None,
        "measurement_height_m": 1.3,
        "accuracy_note": "+/- 30-50 cm safe estimate. For accurate DBH, measure circumference at 1.3 meters and use DBH = circumference / pi.",
        "fallback": True,
    }

@router.post("/identify-url")
async def identify_from_url(
    payload: IdentifyFromURLRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    enforce_ai_limit(current_user, db)
    result = await identify_tree_from_url(payload.image_url)
    return result


@router.post("/measure-dbh")
async def measure_dbh(
    payload: MeasureDBHRequest,
    _: User = Depends(get_current_user),
):
    try:
        result = await measure_dbh_from_base64(
            payload.image_base64,
            payload.content_type,
            payload.reference_hint,
            payload.method,
            payload.known_distance_m,
        )
        if result.get("error"):
            return _safe_dbh_estimate(result.get("detail", "AI DBH analysis failed."), payload.reference_hint, payload.known_distance_m)
        return result
    except Exception as exc:
        return _safe_dbh_estimate(f"AI DBH analysis failed: {exc}", payload.reference_hint, payload.known_distance_m)


@router.post("/measure-dbh-file")
async def measure_dbh_file(
    file: UploadFile = File(...),
    reference_hint: str = Form("No reference object provided."),
    method: str = Form("Camera-assisted photo measurement"),
    known_distance_m: Optional[float] = Form(None),
    _: User = Depends(get_current_user),
):
    image_bytes = b""
    image_base64 = ""
    content_type = file.content_type or "image/jpeg"
    try:
        if not (file.content_type or "").startswith("image/"):
            raise HTTPException(status_code=400, detail="File must be an image.")
        image_bytes = await file.read()
        image_base64 = base64.standard_b64encode(image_bytes).decode("utf-8")

        result = await measure_dbh_from_base64(
            image_base64,
            content_type,
            reference_hint,
            method,
            known_distance_m,
        )
        if not result.get("error") and result.get("dbh_cm"):
            return result

        return _safe_dbh_estimate(
            result.get("detail", "Dedicated DBH analysis was not available.") if isinstance(result, dict) else "Dedicated DBH analysis was not available.",
            reference_hint,
            known_distance_m,
        )
    except Exception as exc:
        return _safe_dbh_estimate(
            f"AI measurement service was unavailable: {exc}",
            reference_hint,
            known_distance_m,
        )

@router.get("/species/{name}")
def lookup_species_endpoint(
    name: str,
    _: User = Depends(get_current_user),
):
    info = lookup_species(name)
    if not info:
        return {"found": False, "name": name}
    return {"found": True, "name": name, **info}

@router.get("/endangered")
def list_endangered(
    _: User = Depends(get_current_user),
):
    return get_all_protected()

@router.get("/community-structure")
def community_structure(
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    from app.models.tree import Tree
    from collections import defaultdict
    import math

    trees = db.query(Tree).all()
    barangay_map = defaultdict(lambda: {"total": 0, "species": defaultdict(int), "endangered": 0, "protected": 0})
    species_map = defaultdict(int)
    endangered_list = []

    for tree in trees:
        b = tree.barangay or "Unknown"
        barangay_map[b]["total"] += 1
        barangay_map[b]["species"][tree.common_name] += 1
        species_map[tree.common_name] += 1
        info = lookup_species(tree.common_name or "")
        if info and info["protected"]:
            barangay_map[b]["protected"] += 1
            if info["status_code"] in ("CR", "EN", "VU"):
                barangay_map[b]["endangered"] += 1
                endangered_list.append({
                    "tree_id": tree.id,
                    "common_name": tree.common_name,
                    "scientific_name": tree.scientific_name,
                    "barangay": b,
                    "photo_url": tree.photo_url,
                    "lat": tree.lat, "lng": tree.lng,
                    "status": info["status"],
                    "status_code": info["status_code"],
                    "iucn_color": info["iucn_color"],
                    "cutting_allowed": info["cutting_allowed"],
                })

    def shannon(species_counts: dict) -> float:
        total = sum(species_counts.values())
        if total == 0: return 0.0
        h = 0.0
        for count in species_counts.values():
            p = count / total
            if p > 0: h -= p * math.log(p)
        return round(h, 3)

    barangay_report = []
    for b, data in barangay_map.items():
        barangay_report.append({
            "barangay": b,
            "total_trees": data["total"],
            "species_count": len(data["species"]),
            "endangered_count": data["endangered"],
            "protected_count": data["protected"],
            "shannon_index": shannon(data["species"]),
            "top_species": sorted([{"name": k, "count": v} for k, v in data["species"].items()], key=lambda x: x["count"], reverse=True)[:5],
        })

    return {
        "total_trees": len(trees),
        "total_species": len(species_map),
        "total_endangered": len(endangered_list),
        "barangay_breakdown": sorted(barangay_report, key=lambda x: x["total_trees"], reverse=True),
        "species_distribution": sorted([{"name": k, "count": v} for k, v in species_map.items()], key=lambda x: x["count"], reverse=True),
        "endangered_trees": endangered_list,
    }

class UnknownSpeciesSubmit(BaseModel):
    photo_url: str
    barangay: Optional[str] = None
    location_description: Optional[str] = None
    possible_name: Optional[str] = None
    submitter_notes: Optional[str] = None
    ai_candidates: Optional[list] = None


class UnknownSpeciesReview(BaseModel):
    reviewed: bool = True
    identified_as: Optional[str] = None
    review_notes: Optional[str] = None


def _unknown_species_out(entry: UnknownSpecies):
    try:
        candidates = json.loads(entry.ai_candidates or "[]")
    except json.JSONDecodeError:
        candidates = []

    return {
        "id": entry.id,
        "photo_url": entry.photo_url,
        "location_description": entry.location_description,
        "barangay": entry.barangay,
        "submitter_notes": entry.submitter_notes,
        "possible_name": entry.possible_name,
        "ai_candidates": candidates,
        "reviewed": entry.reviewed,
        "review_notes": entry.review_notes,
        "identified_as": entry.identified_as,
        "submitted_by_id": entry.submitted_by_id,
        "submitted_by_name": entry.submitted_by.full_name if entry.submitted_by else None,
        "submitted_by_email": entry.submitted_by.email if entry.submitted_by else None,
        "created_at": entry.created_at,
        "updated_at": entry.updated_at,
        "review_status": (
            "identified"
            if entry.reviewed and entry.identified_as
            else "closed"
            if entry.reviewed
            else "pending"
        ),
    }

@router.post("/unknown-species")
def submit_unknown_species(
    payload: UnknownSpeciesSubmit,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    enforce_unknown_limit(current_user, db)
    entry = UnknownSpecies(
        photo_url=payload.photo_url,
        barangay=payload.barangay,
        location_description=payload.location_description,
        possible_name=payload.possible_name,
        submitter_notes=payload.submitter_notes,
        ai_candidates=json.dumps(payload.ai_candidates or []),
        submitted_by_id=current_user.id,
    )
    db.add(entry)
    db.commit()
    db.refresh(entry)
    return {"message": "Submitted for review", "id": entry.id}

@router.get("/unknown-species")
def list_unknown_species(
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    entries = db.query(UnknownSpecies).order_by(UnknownSpecies.created_at.desc()).all()
    return [_unknown_species_out(entry) for entry in entries]


@router.get("/my-unknown-species")
def list_my_unknown_species(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    entries = (
        db.query(UnknownSpecies)
        .filter(UnknownSpecies.submitted_by_id == current_user.id)
        .order_by(UnknownSpecies.created_at.desc())
        .all()
    )
    return [_unknown_species_out(entry) for entry in entries]


@router.put("/unknown-species/{entry_id}/review")
def review_unknown_species(
    entry_id: int,
    payload: UnknownSpeciesReview,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    entry = db.query(UnknownSpecies).filter(UnknownSpecies.id == entry_id).first()
    if not entry:
        raise HTTPException(status_code=404, detail="Unknown species submission not found")

    entry.reviewed = payload.reviewed
    entry.identified_as = payload.identified_as
    entry.review_notes = payload.review_notes
    db.commit()
    db.refresh(entry)
    return _unknown_species_out(entry)
