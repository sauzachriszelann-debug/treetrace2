from fastapi import APIRouter, Depends, UploadFile, File, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional
import base64
import json

from app.db.database import get_db
from app.models.user import User
from app.models.unknown_species import UnknownSpecies
from app.core.security import get_current_user
from app.services.ai_identify import identify_tree_from_base64, identify_tree_from_url, _pipeline_with_status
from app.services.species_db import get_all_protected, lookup_species, PHILIPPINE_ENDANGERED_SPECIES

router = APIRouter()

@router.post("/identify")
async def identify_tree(
    file: UploadFile = File(...),
    _: User = Depends(get_current_user),
):
    allowed = {"image/jpeg", "image/png", "image/webp", "image/gif"}
    if file.content_type not in allowed:
        raise HTTPException(status_code=400, detail="File must be an image (JPEG, PNG, WebP)")
    contents = await file.read()
    image_data = base64.standard_b64encode(contents).decode("utf-8")
    image_bytes = base64.standard_b64decode(image_data)
    result = await _pipeline_with_status(image_bytes, image_data, file.content_type)
    return result

class IdentifyFromURLRequest(BaseModel):
    image_url: str

@router.post("/identify-url")
async def identify_from_url(
    payload: IdentifyFromURLRequest,
    _: User = Depends(get_current_user),
):
    result = await identify_tree_from_url(payload.image_url)
    return result

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
            if info["status_code"] in ("CR", "EN"):
                barangay_map[b]["endangered"] += 1
                endangered_list.append({
                    "tree_id": tree.id,
                    "common_name": tree.common_name,
                    "scientific_name": tree.scientific_name,
                    "barangay": b,
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

@router.post("/unknown-species")
def submit_unknown_species(
    payload: UnknownSpeciesSubmit,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
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
    _: User = Depends(get_current_user),
):
    return db.query(UnknownSpecies).order_by(UnknownSpecies.created_at.desc()).all()
