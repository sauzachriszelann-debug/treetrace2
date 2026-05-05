from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from app.db.database import get_db
from app.models.tree import Tree
from app.models.health_log import HealthLog
from app.schemas.tree import TreeOut
from app.schemas.health_log import HealthLogOut

router = APIRouter()


@router.get("/tree/{tree_id}", response_model=TreeOut)
def public_get_tree(tree_id: str, db: Session = Depends(get_db)):
    """
    Public endpoint — no auth required.
    Used by QR code scans to show the tree profile page.
    Accepts both integer IDs and UUID strings.
    """
    # Try integer ID first
    try:
        tid = int(tree_id)
        tree = db.query(Tree).filter(Tree.id == tid).first()
    except ValueError:
        # UUID-style string ID
        tree = db.query(Tree).filter(Tree.id == tree_id).first()

    if not tree:
        raise HTTPException(status_code=404, detail="Tree not found")
    return tree


@router.get("/tree/{tree_id}/health-logs", response_model=List[HealthLogOut])
def public_get_tree_health_logs(tree_id: str, db: Session = Depends(get_db)):
    """
    Public health log history for a tree. No auth required.
    """
    try:
        tid = int(tree_id)
        filter_expr = HealthLog.tree_id == tid
    except ValueError:
        filter_expr = HealthLog.tree_id == tree_id

    logs = (
        db.query(HealthLog)
        .filter(filter_expr)
        .order_by(HealthLog.created_at.desc())
        .all()
    )
    result = []
    for log in logs:
        result.append({
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
        })
    return result


@router.get("/trees", response_model=List[TreeOut])
def public_list_trees(db: Session = Depends(get_db)):
    """
    Public tree listing — GPS-tagged trees only (for map view).
    """
    return (
        db.query(Tree)
        .filter(Tree.lat.isnot(None), Tree.lng.isnot(None))
        .order_by(Tree.created_at.desc())
        .limit(500)
        .all()
    )


@router.get("/trees/all", response_model=List[TreeOut])
def public_list_all_trees(db: Session = Depends(get_db)):
    """
    Public listing of ALL trees (including those without GPS).
    Used for list view and aggregate stats in the Public Portal.
    """
    return (
        db.query(Tree)
        .order_by(Tree.created_at.desc())
        .limit(500)
        .all()
    )


from anthropic import Anthropic
from app.core.config import settings
import json, re


# @router.get("/tree/{tree_id}/wiki")
# def public_tree_wiki(tree_id: str, db: Session = Depends(get_db)):
#     try:
#         tid = int(tree_id)
#         tree = db.query(Tree).filter(Tree.id == tid).first()
#     except ValueError:
#         tree = db.query(Tree).filter(Tree.id == tree_id).first()
#     if not tree:
#         raise HTTPException(status_code=404, detail="Tree not found")

#     import httpx, json, re
#     from app.core.config import settings

#     name = tree.common_name or "Unknown Tree"
#     sci  = tree.scientific_name or ""

#     prompt = f"""You are a Philippine botanist. Generate a wiki profile for: "{name}" ({sci}).
# Respond ONLY with valid JSON, no markdown fences:
# {{
#   "tagline": "One evocative sentence",
#   "basic_info": {{"native_to":"","invasive_status":"","plant_type":"","lifespan":"","mature_height":"","mature_spread":"","leaf_type":"","flowering_season":""}},
#   "characteristics": {{"nativity":"3","flower":"3","fruit":"3","leaf_color":""}},
#   "care_profile": {{"difficulty":"Easy","difficulty_note":"","watering":"","sunlight":"","temperature":"","hardiness_zones":"","soil":"","fertilizer":""}},
#   "how_tos": [{{"title":"How to water","steps":["step1","step2","step3"]}},{{"title":"How to prune","steps":["step1","step2","step3"]}},{{"title":"How to propagate","steps":["step1","step2","step3"]}}],
#   "popular_questions": [{{"q":"question?","a":"answer"}},{{"q":"question?","a":"answer"}},{{"q":"question?","a":"answer"}}],
#   "common_problems": [{{"name":"Problem","description":"description","severity":"Low"}},{{"name":"Problem 2","description":"description","severity":"Medium"}}],
#   "uses": {{"timber":"","medicinal":"","food":"","ecological":""}},
#   "adaptation_strategies": "2-3 sentences",
#   "history_and_legends": "2-3 sentences",
#   "name_story": "2-3 sentences",
#   "symbolism": "2-3 sentences"
# }}"""

#     url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:generateContent?key={settings.GEMINI_API_KEY}"
#     payload = {
#         "contents": [{"parts": [{"text": prompt}]}],
#         "generationConfig": {"temperature": 0.7, "maxOutputTokens": 1500}
#     }

#     with httpx.Client(timeout=30) as http:
#         resp = http.post(url, json=payload)
#         if resp.status_code == 429:
#             raise HTTPException(status_code=503, detail="AI service busy, try again in a moment")
#         resp.raise_for_status()

#     raw = resp.json()["candidates"][0]["content"]["parts"][0]["text"].strip()
#     raw = re.sub(r"^```(?:json)?\s*", "", raw, flags=re.MULTILINE)
#     raw = re.sub(r"\s*```\s*$", "", raw, flags=re.MULTILINE)
#     return json.loads(raw.strip())



import asyncio as _asyncio

@router.get("/tree/{tree_id}/wiki")
def public_tree_wiki(tree_id: str, db: Session = Depends(get_db)):
    try:
        tid = int(tree_id)
        tree = db.query(Tree).filter(Tree.id == tid).first()
    except ValueError:
        tree = db.query(Tree).filter(Tree.id == tree_id).first()
    if not tree:
        raise HTTPException(status_code=404, detail="Tree not found")

    from app.services.ai_identify import get_species_wiki
    name = tree.common_name or "Unknown Tree"
    sci  = tree.scientific_name or ""

    try:
        loop = _asyncio.new_event_loop()
        wiki = loop.run_until_complete(get_species_wiki(name, sci))
        loop.close()
        return wiki
    except Exception as e:
        # Fallback wiki if APIs fail
        from app.services.ai_identify import _build_wiki
        return _build_wiki(name, sci, None, None, None)