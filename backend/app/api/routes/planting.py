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


def _role_name(user: User) -> str:
    role = user.role
    return getattr(role, "value", role)


def _can_manage(user: User) -> bool:
    return _role_name(user) in {"admin", "field_worker"}

NATIVE_PRIORITY = [
    (
        "Narra",
        "Pterocarpus indicus",
        "Native shade and biodiversity tree; protected status encourages careful planting.",
        "Open parks, school grounds, civic areas, and wide roadside strips",
        "Narra adds long-term canopy, improves habitat value, and should be planted where it has room to mature without later removal.",
    ),
    (
        "Molave",
        "Vitex parviflora",
        "Hardy native tree suitable for restoration and long-term canopy diversity.",
        "Dry open barangay lots, road edges, and restoration zones",
        "Molave tolerates heat and dry periods, so it helps strengthen areas with lower survival rates for softer seedlings.",
    ),
    (
        "Dao",
        "Dracontomelon dao",
        "Native canopy tree that supports birds, shade, and urban biodiversity.",
        "Riparian edges, large open lots, and low-lying green corridors",
        "Dao is useful where shade, food value for wildlife, and flood-tolerant canopy cover are needed.",
    ),
    (
        "Banaba",
        "Lagerstroemia speciosa",
        "Flowering native tree useful for streets, parks, and pollinator support.",
        "Roadside verges, school frontage, parks, and community gardens",
        "Banaba gives shade and seasonal flowers, making it good for visible community planting areas.",
    ),
    (
        "Ipil",
        "Intsia bijuga",
        "Native hardwood species that improves long-term species diversity.",
        "Protected open lots, watershed buffers, and restoration sites",
        "Ipil is valuable for resilient native diversity and should be placed in protected areas where it can grow long term.",
    ),
    (
        "Bitaog",
        "Calophyllum inophyllum",
        "Coastal and lowland native tree useful for resilient planting.",
        "Lowland barangays, exposed roadsides, and drainage-adjacent areas",
        "Bitaog handles wind and lowland stress better than many ornamental trees, so it helps stabilize exposed planting zones.",
    ),
]


def _image_urls(common: str, scientific: str | None = None) -> list[str]:
    terms = [common, scientific or common, f"{common} seedling", f"{common} leaves"]
    return [
        f"https://tse1.mm.bing.net/th?q={term.replace(' ', '%20')}%20tree"
        for term in terms[:4]
    ]


@router.get("/", response_model=list[PlantingRecommendationOut])
def list_recommendations(
    barangay: str | None = None,
    limit: int = Query(100, ge=1, le=300),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(PlantingRecommendation)
    if not _can_manage(current_user):
        query = query.filter(PlantingRecommendation.submitted_by_id == current_user.id)
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
    approved_records = db.query(PlantingRecommendation).filter(
        PlantingRecommendation.status.in_(["approved", "recommended"])
    )
    if barangay:
        approved_records = approved_records.filter(
            PlantingRecommendation.barangay.ilike(f"%{barangay}%")
        )
    for record in approved_records.order_by(
        PlantingRecommendation.created_at.desc()
    ).limit(8).all():
        images = [record.photo_url] if record.photo_url else _image_urls(
            record.species_name,
            record.scientific_name,
        )
        suggestions.append({
            "species_name": record.species_name,
            "scientific_name": record.scientific_name,
            "priority": "Approved",
            "recommended_area": record.barangay or barangay or "Recommended planting area",
            "area_reason": "Approved by admin/field review for this planting area.",
            "image_urls": images,
            "reason": record.reason or "Approved planting recommendation from the TreeTrace review queue.",
            "source": "approved",
        })

    for common, scientific, base_reason, recommended_area, area_reason in NATIVE_PRIORITY:
        existing = species_counts.get(common, 0)
        if existing <= 1:
            suggestions.append({
                "species_name": common,
                "scientific_name": scientific,
                "priority": "High" if existing == 0 else "Medium",
                "recommended_area": barangay or recommended_area,
                "area_reason": (
                    f"{barangay} has only {existing} recorded {common} tree"
                    f"{'' if existing == 1 else 's'}, so planting here can improve species balance."
                    if barangay else area_reason
                ),
                "image_urls": _image_urls(common, scientific),
                "reason": (
                    f"{common} is underrepresented"
                    f"{' in ' + barangay if barangay else ' in the current inventory'}. "
                    f"{base_reason}"
                ),
                "source": "system",
            })

    if not suggestions:
        suggestions.append({
            "species_name": "Native mixed-species planting",
            "scientific_name": None,
            "priority": "Medium",
            "recommended_area": barangay or "Barangays with low species balance",
            "area_reason": "Use mixed native seedlings where the inventory already has dominant species but needs resilience.",
            "image_urls": _image_urls("native Philippine tree seedling"),
            "reason": "This area already has recorded diversity. Add mixed native seedlings to keep the canopy resilient.",
            "source": "system",
        })

    return {
        "barangay": barangay,
        "total_trees_checked": len(filtered),
        "species_count": len(species_counts),
        "barangays_with_records": len(barangay_counts),
        "suggestions": suggestions[:8],
    }


@router.post("/", response_model=PlantingRecommendationOut, status_code=201)
def create_recommendation(
    payload: PlantingRecommendationCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    data = payload.model_dump()
    if _can_manage(current_user):
        data["status"] = data.get("status") or "recommended"
    else:
        data["status"] = "pending"
        data["planted"] = False
    recommendation = PlantingRecommendation(
        **data,
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
    if not _can_manage(current_user):
        if recommendation.submitted_by_id != current_user.id:
            raise HTTPException(status_code=403, detail="You can only update your own planting recommendation.")
        if recommendation.status != "pending":
            raise HTTPException(status_code=403, detail="Reviewed planting suggestions can no longer be edited.")

    update_data = payload.model_dump(exclude_unset=True)
    if not _can_manage(current_user):
        update_data.pop("status", None)
        update_data.pop("planted", None)

    for field, value in update_data.items():
        setattr(recommendation, field, value)
    db.commit()
    db.refresh(recommendation)
    return recommendation
