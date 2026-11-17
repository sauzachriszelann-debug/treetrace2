from fastapi import APIRouter, Depends, UploadFile, File, HTTPException, Form, Response
from starlette.datastructures import UploadFile as StarletteUploadFile
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field
from typing import Optional
from datetime import date, datetime, timezone
import base64
import asyncio
import json

from app.db.database import get_db
from app.models.tree_submission import TreeSubmission
from app.models.user import User, UserRole
from app.models.unknown_species import UnknownSpecies
from app.schemas.dbh import ARDBHRequest, ARDBHResponse, PhotoDBHRequest as MeasureDBHRequest
from app.schemas.height import HeightRequest, HeightResponse
from app.schemas.gallery_size import GallerySizeResponse
from app.schemas.tree import TreeMeasurementInput
from app.schemas.tree_age import TreeAgeRequest, TreeAgeResponse
from app.schemas.species_comparison import SpeciesComparisonResponse
from app.core.security import get_current_user, require_admin
from app.api.routes.trees import _estimate_tree_carbon
from app.api.routes.tree_submissions import (
    TREE_SUBMISSION_DAILY_LIMITS,
    require_staff,
    submission_out,
)
from app.services.scan_species_classes import restrict_scan_result
from app.services.ai_identify import identify_tree_from_url, _pipeline_with_status, measure_dbh_from_base64, get_dbh_runtime_status
# from app.services.local_species_classifier import (
#     classify_species_from_image,
#     local_species_model_status,
# )

def _get_local_species_classifier():
    try:
        from app.services.local_species_classifier import (
            classify_species_from_image,
            local_species_model_status,
        )
        return classify_species_from_image, local_species_model_status
    except Exception:
        return None, None

from app.services.species_db import get_all_protected, lookup_species, PHILIPPINE_ENDANGERED_SPECIES

router = APIRouter()


@router.post("/estimate-age", response_model=TreeAgeResponse)
async def estimate_age(payload: TreeAgeRequest, _: User = Depends(get_current_user)):
    from app.services.tree_age import estimate_tree_age, estimate_ai_tree_age
    result = estimate_tree_age(payload)
    if result.status == "estimated" or (payload.dbh_cm is None and payload.height_m is None):
        return result
    try:
        return await estimate_ai_tree_age(payload)
    except Exception:
        return TreeAgeResponse(status="unavailable", scientific_name=payload.scientific_name,
            dimensions_source=payload.dimensions_source, estimation_basis="ai_growth_guess",
            reason="AI growth estimate could not complete. Check AI access or try again later.")


@router.get("/dbh-trunk-status")
def dbh_trunk_status(_: User = Depends(get_current_user)):
    """Configuration checks only: never load weights or claim verified inference."""
    from app.services.dbh_yolo import runtime_status
    status = runtime_status()
    configuration_ready = status.pop("ready", False)
    reasons = []
    if not status.get("enabled"):
        reasons.append("Set DBH_TRUNK_ENABLED=true for this deployment.")
    if not status.get("model_found"):
        reasons.append("The deployed tree_trunk_dbh_v1.pt model is missing.")
    if not status.get("dependencies_available"):
        reasons.append("The deployed CPU YOLO dependencies are missing.")
    return {
        **status, "model": "tree_trunk_dbh_v1.pt", "device": "cpu",
        "method": "yolo_trunk_v1", "configuration_ready": configuration_ready,
        "inference_verified": False, "check_type": "configuration_only",
        "reason": " ".join(reasons) if reasons else
            "Configuration found. Run an inference probe before field use.",
    }



@router.post("/measure-height", response_model=HeightResponse)
def measure_height(payload: HeightRequest, _: User = Depends(get_current_user)):
    from app.services.height_tilt import measure_height as calculate
    return calculate(**payload.model_dump())


@router.get("/dbh-ar-status")
async def dbh_ar_status(_: User = Depends(get_current_user)):
    from app.services.dbh_yolo_ar_backup import runtime_status
    return runtime_status()


@router.post("/measure-dbh-ar", response_model=ARDBHResponse)
async def measure_dbh_ar(payload: ARDBHRequest, _: User = Depends(get_current_user)):
    # Dedicated contract: no reference objects, Gemini or placeholder values.
    return await measure_dbh_from_base64(
        payload.image_base64, ar_capture=payload.capture,
    )


@router.get("/dbh-status")
async def dbh_status():
    return get_dbh_runtime_status()


# @router.get("/species-model-status")
# async def species_model_status():
#    return local_species_model_status()

@router.get("/species-model-status")
async def species_model_status():
    _, get_status = _get_local_species_classifier()
    if get_status is None:
        return {
            "enabled": False,
            "ready": False,
            "reason": "Local species model dependencies are unavailable.",
        }
    return get_status()


AI_DAILY_LIMITS = {
    "free": None,
    "pro": None,
    "professional": None,
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
        # G4: all three counters roll over together on the shared date.
        user.tree_submissions_today = 0
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
        "tree_submissions": _usage_payload(
            current_user,
            TREE_SUBMISSION_DAILY_LIMITS,
            "tree_submissions_today",
        ),
        "qr_scan": {"unlimited": True},
        "public_map": {"unlimited": True},
    }

@router.post("/gallery-size-prediction", response_model=GallerySizeResponse)
async def gallery_size_prediction(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    treetop_file: Optional[UploadFile] = File(None),
    treebase_file: Optional[UploadFile] = File(None),
):
    # Authenticated, display-only predictions.
    if file.content_type not in ("image/jpeg", "image/png", "image/webp"):
        raise HTTPException(status_code=400, detail="Use JPEG, PNG or WebP.")
    contents = await file.read(2_000_001)
    if not contents or len(contents) > 2_000_000:
        raise HTTPException(status_code=413, detail="Prediction photo must be at most 2 MB.")
    supplements = {}
    for name, photo in (("treetop", treetop_file), ("treebase", treebase_file)):
        if not isinstance(photo, StarletteUploadFile):
            continue
        if photo.content_type not in ("image/jpeg", "image/png", "image/webp"):
            raise HTTPException(status_code=400, detail=f"Use JPEG, PNG or WebP for the {name} photo.")
        extra_contents = await photo.read(2_000_001)
        if not extra_contents or len(extra_contents) > 2_000_000:
            raise HTTPException(status_code=413, detail=f"The {name} photo must be at most 2 MB.")
        supplements[f"{name}_bytes"] = extra_contents
        supplements[f"{name}_content_type"] = photo.content_type
    from app.services.gallery_size_prediction import predict_gallery_size
    return await predict_gallery_size(contents, file.content_type, **supplements)


@router.post("/compare-species-models", response_model=SpeciesComparisonResponse)
async def compare_species_model_predictions(
    file: UploadFile = File(...),
    _current_user: User = Depends(get_current_user),
):
    from app.services.local_species_classifier import (
        TRIAL_MODEL_PATH, local_species_model_status, species_trial_enabled,
    )

    if not species_trial_enabled():
        raise HTTPException(status_code=404, detail="Local model comparison is disabled.")
    if not (file.content_type or "").startswith("image/"):
        raise HTTPException(status_code=400, detail="File must be an image.")
    if not local_species_model_status()["ready"]:
        raise HTTPException(status_code=503, detail="Local species models are unavailable.")

    from PIL import UnidentifiedImageError
    from app.services.roboflow_classifier import compare_species_models

    try:
        results = await asyncio.to_thread(compare_species_models, await file.read(), TRIAL_MODEL_PATH)
    except UnidentifiedImageError:
        raise HTTPException(status_code=400, detail="The photo could not be opened.") from None
    except (OSError, RuntimeError, ValueError, KeyError):
        raise HTTPException(status_code=503, detail="Local species models could not run.") from None
    return {"selected_model": "EfficientNet-B0", "results": results}


@router.post("/identify")
async def identify_tree(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    include_trunk_preview: bool = False,
):
    if not (file.content_type or "").startswith("image/"):
        raise HTTPException(status_code=400, detail="File must be an image.")
    contents = await file.read()
    image_data = base64.standard_b64encode(contents).decode("utf-8")
    image_bytes = base64.standard_b64decode(image_data)
    # local_model = local_species_model_status()
    # if local_model.get("ready"):
       # try:
        #    return classify_species_from_image(image_bytes)
       # except Exception:
            # Keep the existing online AI pipeline available if local inference fails.
            # pass

    # Preliminary EfficientNet-B0 inference is disabled until final evaluation.
    # Keep the response field for compatibility with existing clients.
    roboflow_candidate = None

    classify_species, get_local_status = _get_local_species_classifier()
    local_model = get_local_status() if get_local_status else {"ready": False}

    if local_model.get("ready") and classify_species:
        try:
            local_result = classify_species(image_bytes)
            if isinstance(local_result, dict):
                checked_result = restrict_scan_result(local_result)
                if (
                    checked_result.get("not_identified")
                    and local_result.get("source") == "local_efficientnet_b0_trial"
                ):
                    checked_result["source"] = local_result["source"]
                    checked_result["confidence_percent"] = local_result["confidence_percent"]
                    checked_result["below_confidence_threshold"] = (
                        local_result.get("confidence") == "Low"
                    )
                    if checked_result["below_confidence_threshold"]:
                        checked_result["suggested_species"] = {
                            "common_name": local_result.get("common_name"),
                            "scientific_name": local_result.get("scientific_name"),
                            "confidence_percent": local_result["confidence_percent"],
                        }
                local_result = checked_result
                local_result["roboflow_candidate"] = roboflow_candidate
                from app.schemas.photo_observations import normalize_observations
                local_result["photo_observations"] = normalize_observations(local_result.get("photo_observations"))
            return await _with_trunk_preview(local_result, image_bytes, include_trunk_preview)
        except Exception:
          # Keep the existing online AI pipeline available if local inference fails.
            pass

    try:
        result = await _pipeline_with_status(image_bytes, image_data, file.content_type)
        if isinstance(result, dict):
            result["roboflow_candidate"] = roboflow_candidate
            from app.schemas.photo_observations import normalize_observations
            result["photo_observations"] = normalize_observations(result.get("photo_observations"))
        return await _with_trunk_preview(result, image_bytes, include_trunk_preview)
    except Exception as exc:
        result = {
            "not_identified": True,
            "roboflow_candidate": roboflow_candidate,
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
        return await _with_trunk_preview(result, image_bytes, include_trunk_preview)


async def _with_trunk_preview(result, image_bytes, requested):
    if not requested or not isinstance(result, dict):
        return result
    try:
        from app.services.gallery_size_prediction import _detect
        detection, reason = await asyncio.to_thread(_detect, image_bytes)
        if detection and detection.get("target_source") == "yolo":
            result["trunk_preview_png"] = detection.get("preview_png")
        else:
            result["trunk_preview_reason"] = reason or "No trunk detected in this photo."
    except Exception:
        result["trunk_preview_reason"] = "Trunk preview could not be generated."
    return result

class IdentifyFromURLRequest(BaseModel):
    image_url: str


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
):
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
            camera_height_m=payload.camera_height_m,
            pitch_deg=payload.pitch_deg,
            distance_m=payload.distance_m,
            distance_source=payload.distance_source,
            f_px=payload.f_px,
        )
        if result.get("status") in {"retake", "unavailable"}:
            return result
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
    camera_height_m: float = Form(1.4),
    pitch_deg: Optional[float] = Form(None),
    distance_m: Optional[float] = Form(None),
    distance_source: Optional[str] = Form(None),
    f_px: Optional[float] = Form(None),
    _: User = Depends(get_current_user),
):
    image_bytes = b""
    image_base64 = ""
    content_type = file.content_type or "image/jpeg"
    try:
        if not (file.content_type or "").startswith("image/"):
            raise HTTPException(status_code=400, detail="File must be an image.")
        image_bytes = await file.read()
        if method == "yolo_trunk_v1":
            # Strict measured-photo path: disabled/missing model must never
            # invoke legacy YOLO, Gemini or placeholder dimensions.
            from app.services.dbh_yolo import measure_dbh_trunk
            return await asyncio.to_thread(
                measure_dbh_trunk, image_bytes,
                camera_height_m=camera_height_m, pitch_deg=pitch_deg,
                distance_m=distance_m, distance_source=distance_source, f_px=f_px,
            )
        image_base64 = base64.standard_b64encode(image_bytes).decode("utf-8")

        result = await measure_dbh_from_base64(
            image_base64,
            content_type,
            reference_hint,
            method,
            known_distance_m,
            camera_height_m=camera_height_m,
            pitch_deg=pitch_deg,
            distance_m=distance_m,
            distance_source=distance_source,
            f_px=f_px,
        )
        if result.get("status") in {"retake", "unavailable"}:
            return result
        if not result.get("error") and result.get("dbh_cm"):
            return result

        return _safe_dbh_estimate(
            result.get("detail", "Dedicated DBH analysis was not available.") if isinstance(result, dict) else "Dedicated DBH analysis was not available.",
            reference_hint,
            known_distance_m,
        )
    except HTTPException:
        raise
    except Exception as exc:
        if method == "yolo_trunk_v1":
            from app.services.dbh_yolo import failure
            return failure("unavailable", "Trunk measurement failed on the server. Check the backend terminal.")
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

class UnknownSpeciesSubmit(TreeMeasurementInput):
    photo_url: str
    dbh_cm: Optional[float] = None
    height_m: Optional[float] = None
    barangay: Optional[str] = None
    location_description: Optional[str] = None
    possible_name: Optional[str] = None
    submitter_notes: Optional[str] = None
    ai_candidates: Optional[list] = None


class UnknownSpeciesReview(BaseModel):
    reviewed: bool = True
    identified_as: Optional[str] = None
    identified_scientific_name: Optional[str] = Field(default=None, max_length=150)
    review_notes: Optional[str] = None


def _unknown_species_out(entry: UnknownSpecies):
    try:
        candidates = json.loads(entry.ai_candidates or "[]")
    except json.JSONDecodeError:
        candidates = []

    _, carbon = _estimate_tree_carbon(entry.dbh_cm, entry.height_m, require_height=True)
    return {
        "id": entry.id,
        "dbh_cm": entry.dbh_cm,
        "height_m": entry.height_m,
        "carbon_kg": carbon,
        "photo_url": entry.photo_url,
        "location_description": entry.location_description,
        "barangay": entry.barangay,
        "submitter_notes": entry.submitter_notes,
        "possible_name": entry.possible_name,
        "ai_candidates": candidates,
        "reviewed": entry.reviewed,
        "review_notes": entry.review_notes,
        "identified_as": entry.identified_as,
        "identified_scientific_name": entry.identified_scientific_name,
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
        dbh_cm=payload.dbh_cm,
        height_m=payload.height_m,
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


@router.delete("/unknown-species/{entry_id}", status_code=204)
def delete_my_unknown_species(
    entry_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    entry = db.query(UnknownSpecies).filter(UnknownSpecies.id == entry_id).with_for_update().first()
    if entry is None:
        raise HTTPException(status_code=404, detail="Unknown species submission not found")
    if entry.submitted_by_id != current_user.id:
        raise HTTPException(status_code=403, detail="Only the submitter can delete this entry.")
    converted = (
        db.query(TreeSubmission.id)
        .filter(TreeSubmission.source_unknown_species_id == entry.id)
        .first()
    )
    if converted is not None or (entry.reviewed and not entry.identified_as):
        raise HTTPException(status_code=409, detail="Refresh My Submissions to check the current status.")
    db.delete(entry)
    db.commit()


@router.put("/unknown-species/{entry_id}/review")
def review_unknown_species(
    entry_id: int,
    payload: UnknownSpeciesReview,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    entry = db.query(UnknownSpecies).filter(UnknownSpecies.id == entry_id).with_for_update().first()
    if not entry:
        raise HTTPException(status_code=404, detail="Unknown species submission not found")

    if entry.submitted_by_id == current_user.id:
        raise HTTPException(status_code=403, detail="You cannot review your own submission.")

    entry.reviewed = payload.reviewed
    if "identified_scientific_name" in payload.model_fields_set:
        entry.identified_scientific_name = (
            (payload.identified_scientific_name or "").strip() or None
            if payload.reviewed and payload.identified_as
            else None
        )
    elif not payload.reviewed or payload.identified_as != entry.identified_as:
        entry.identified_scientific_name = None
    entry.identified_as = payload.identified_as
    entry.review_notes = payload.review_notes
    db.commit()
    db.refresh(entry)
    return _unknown_species_out(entry)


def _parse_location_description(description: Optional[str]):
    """Recover coordinates from the web client's "lat, lng" free text.

    Best-effort and conservative: anything that does not parse into two
    in-range floats becomes (None, None) - coordinates are never guessed.
    """
    if not description:
        return (None, None)
    parts = [part.strip() for part in description.split(",")]
    if len(parts) != 2:
        return (None, None)
    try:
        lat = float(parts[0])
        lng = float(parts[1])
    except ValueError:
        return (None, None)
    if not (-90.0 <= lat <= 90.0 and -180.0 <= lng <= 180.0):
        return (None, None)
    return (lat, lng)


@router.post("/unknown-species/{entry_id}/convert", status_code=201)
def convert_unknown_species_to_submission(
    entry_id: int,
    response: Response,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_staff),
):
    """Convert an IDENTIFIED unknown-species entry into a pending tree
    submission (Path B integration, safeguard C).

    * Staff only; the original submitter may not convert their own entry.
    * Requires a non-empty identified_as.
    * The unknown-species entry is never modified - the submission references
      it via source_unknown_species_id (unique), and the original submitter
      is preserved as the submission's submitter.
    * Repeated/concurrent conversions are safe: the unique constraint plus a
      replay check return the already-created submission with HTTP 200 and
      Idempotent-Replay: true.
    """
    entry = db.query(UnknownSpecies).filter(UnknownSpecies.id == entry_id).with_for_update().first()
    if entry is None:
        raise HTTPException(
            status_code=404, detail="Unknown species submission not found"
        )

    if entry.submitted_by_id is not None and entry.submitted_by_id == current_user.id:
        raise HTTPException(
            status_code=403,
            detail="You cannot review your own submission.",
        )

    if not (entry.identified_as or "").strip():
        raise HTTPException(
            status_code=422,
            detail=(
                "Identify the species first: a conversion requires a "
                "non-empty identified_as."
            ),
        )

    def replay(existing: TreeSubmission):
        response.status_code = 200
        response.headers["Idempotent-Replay"] = "true"
        return submission_out(existing)

    existing = (
        db.query(TreeSubmission)
        .filter(TreeSubmission.source_unknown_species_id == entry.id)
        .first()
    )
    if existing is not None:
        return replay(existing)

    lat, lng = _parse_location_description(entry.location_description)
    notes_parts = [
        text
        for text in (
            (entry.submitter_notes or "").strip(),
            (
                f"Location note: {entry.location_description}"
                if entry.location_description
                else ""
            ).strip(),
        )
        if text
    ]

    for attempt in range(2):
        try:
            submission = TreeSubmission(
                common_name=(entry.identified_as or "").strip(),
                scientific_name=entry.identified_scientific_name,
                dbh_cm=entry.dbh_cm,
                height_m=entry.height_m,
                photo_url=entry.photo_url,
                barangay=entry.barangay,
                lat=lat,
                lng=lng,
                notes=("\n".join(notes_parts) or None),
                ai_candidates=entry.ai_candidates,
                source="ai_identify",
                source_unknown_species_id=entry.id,
                # Safeguard C: the ORIGINAL submitter stays the submitter;
                # the converting reviewer becomes reviewed_by only after an
                # approve/reject/link action on the submission itself.
                submitted_by_id=entry.submitted_by_id,
                status="pending",
            )
            db.add(submission)
            db.commit()
            db.refresh(submission)
            return submission_out(submission)
        except IntegrityError:
            db.rollback()
            # Lost a concurrent conversion race - return the winner's row.
            existing = (
                db.query(TreeSubmission)
                .filter(TreeSubmission.source_unknown_species_id == entry.id)
                .first()
            )
            if existing is not None:
                return replay(existing)
            if attempt == 0:
                continue
            raise HTTPException(
                status_code=503,
                detail=(
                    "Could not uniquely record this conversion. Please retry."
                ),
            )
