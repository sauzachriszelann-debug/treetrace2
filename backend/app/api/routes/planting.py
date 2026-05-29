from collections import Counter, defaultdict
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.core.security import get_current_user
from app.db.database import get_db
from app.models.planting_recommendation import PlantingRecommendation
from app.models.tree import Tree
from app.models.user import User
from app.schemas.planting import (
    PlantingRecommendationCreate,
    PlantingRecommendationOut,
    PlantingRecommendationUpdate,
)

router = APIRouter()

NATIVE_PRIORITY = [
    ("Narra", "Pterocarpus indicus", "Native shade and biodiversity tree; protected status encourages careful planting."),
    ("Molave", "Vitex parviflora", "Hardy native tree suitable for restoration and long-term canopy diversity."),
    ("Dao", "Dracontomelon dao", "Native canopy tree that supports birds, shade, and urban biodiversity."),
    ("Banaba", "Lagerstroemia speciosa", "Flowering native tree useful for streets, parks, and pollinator support."),
    ("Ipil", "Intsia bijuga", "Native hardwood species that improves long-term species diversity."),
    ("Bitaog", "Calophyllum inophyllum", "Coastal and lowland native tree useful for resilient planting."),
]


@router.get("/", response_model=list[PlantingRecommendationOut])
def list_recommendations(
    barangay: str | None = None,
    limit: int = Query(100, ge=1, le=300),
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    query = db.query(PlantingRecommendation)
    if barangay:
        query = query.filter(PlantingRecommendation.barangay.ilike(f"%{barangay}%"))
    return query.order_by(PlantingRecommendation.created_at.desc()).limit(limit).all()


@router.get("/suggestions")
def planting_suggestions(
    barangay: str | None = None,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    trees = db.query(Tree).all()
    filtered = [
        tree for tree in trees
        if not barangay or ((tree.barangay or "").lower().find(barangay.lower()) >= 0)
    ]
    species_counts = Counter((tree.common_name or "").strip() for tree in filtered if tree.common_name)
    barangay_counts: dict[str, set[str]] = defaultdict(set)
    for tree in trees:
        if tree.barangay and tree.common_name:
            barangay_counts[tree.barangay].add(tree.common_name)

    suggestions = []
    for common, scientific, base_reason in NATIVE_PRIORITY:
        existing = species_counts.get(common, 0)
        if existing <= 1:
            suggestions.append({
                "species_name": common,
                "scientific_name": scientific,
                "priority": "High" if existing == 0 else "Medium",
                "reason": (
                    f"{common} is underrepresented"
                    f"{' in ' + barangay if barangay else ' in the current inventory'}. "
                    f"{base_reason}"
                ),
            })

    if not suggestions:
        suggestions.append({
            "species_name": "Native mixed-species planting",
            "scientific_name": None,
            "priority": "Medium",
            "reason": "This area already has recorded diversity. Add mixed native seedlings to keep the canopy resilient.",
        })

    return {
        "barangay": barangay,
        "total_trees_checked": len(filtered),
        "species_count": len(species_counts),
        "barangays_with_records": len(barangay_counts),
        "suggestions": suggestions[:6],
    }


@router.post("/", response_model=PlantingRecommendationOut, status_code=201)
def create_recommendation(
    payload: PlantingRecommendationCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    recommendation = PlantingRecommendation(
        **payload.model_dump(),
        submitted_by_id=current_user.id,
    )
    db.add(recommendation)
    db.commit()
    db.refresh(recommendation)
    return recommendation


@router.patch("/{recommendation_id}", response_model=PlantingRecommendationOut)
def update_recommendation(
    recommendation_id: int,
    payload: PlantingRecommendationUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    recommendation = db.query(PlantingRecommendation).filter(
        PlantingRecommendation.id == recommendation_id
    ).first()
    if not recommendation:
        raise HTTPException(status_code=404, detail="Planting recommendation not found")
    if current_user.role == "citizen" and recommendation.submitted_by_id != current_user.id:
        raise HTTPException(status_code=403, detail="You can only update your own planting recommendation.")

    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(recommendation, field, value)
    db.commit()
    db.refresh(recommendation)
    return recommendation
