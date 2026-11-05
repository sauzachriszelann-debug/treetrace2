from collections import Counter, defaultdict
from datetime import date
from functools import lru_cache
from fastapi import APIRouter, Depends, HTTPException, Query
import httpx
from sqlalchemy.orm import Session

from app.core.security import get_current_user, require_admin
from app.db.database import get_db
from app.models.planting_recommendation import PlantingRecommendation
from app.models.species_photo import SpeciesPhoto
from app.models.tree import Tree
from app.models.user import User
from app.services.species_db import lookup_species
from app.schemas.planting import (
    PlantingRecommendationCreate,
    PlantingRecommendationOut,
    PlantingRecommendationUpdate,
    SpeciesPhotoUpsert,
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


def _species_key(scientific_name: str | None) -> str:
    return " ".join((scientific_name or "").strip().lower().split())


def _conservation_status(common_name: str, scientific_name: str | None = None) -> str:
    info = lookup_species(common_name) or lookup_species(scientific_name or "") or {}
    return info.get("status", "Not Listed")


@router.get("/species-photos")
def list_species_photos(
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    return [
        {
            "species_name": item.species_name,
            "scientific_name": item.scientific_name,
            "photo_url": item.photo_url,
            "updated_at": item.updated_at,
        }
        for item in db.query(SpeciesPhoto).order_by(SpeciesPhoto.species_name).all()
    ]


@router.put("/species-photos")
def upsert_species_photo(
    payload: SpeciesPhotoUpsert,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    species_name = payload.species_name.strip()
    scientific_name = payload.scientific_name.strip()
    photo_url = payload.photo_url.strip()
    key = _species_key(scientific_name)
    if not species_name or not key or not photo_url:
        raise HTTPException(status_code=422, detail="Species name, scientific name, and photo are required.")
    photo = db.query(SpeciesPhoto).filter(SpeciesPhoto.species_key == key).first()
    if photo is None:
        photo = SpeciesPhoto(species_key=key, verified_by_id=current_user.id)
        db.add(photo)
    photo.species_name = species_name
    photo.scientific_name = scientific_name
    photo.photo_url = photo_url
    photo.verified_by_id = current_user.id
    db.commit()
    db.refresh(photo)
    return {
        "species_name": photo.species_name,
        "scientific_name": photo.scientific_name,
        "photo_url": photo.photo_url,
        "updated_at": photo.updated_at,
    }


@lru_cache(maxsize=64)
def _weather_summary(latitude: float, longitude: float) -> dict | None:
    """Fetch a five-year weather baseline for a barangay inventory centroid."""
    today = date.today()
    end_year = today.year - 1
    start_year = end_year - 4
    try:
        response = httpx.get(
            "https://archive-api.open-meteo.com/v1/archive",
            params={
                "latitude": latitude,
                "longitude": longitude,
                "start_date": f"{start_year}-01-01",
                "end_date": f"{end_year}-12-31",
                "daily": "temperature_2m_mean,precipitation_sum",
                "timezone": "Asia/Manila",
            },
            timeout=8.0,
        )
        response.raise_for_status()
        daily = response.json().get("daily", {})
        temperatures = [v for v in daily.get("temperature_2m_mean", []) if v is not None]
        rainfall = [v for v in daily.get("precipitation_sum", []) if v is not None]
        if not temperatures or not rainfall:
            return None
        return {
            "period": f"{start_year}-{end_year}",
            "mean_temperature_c": round(sum(temperatures) / len(temperatures), 1),
            "mean_annual_rainfall_mm": round(sum(rainfall) / (end_year - start_year + 1), 1),
            "latitude": round(latitude, 5),
            "longitude": round(longitude, 5),
            "source": "Open-Meteo historical weather reanalysis",
            "estimated": True,
        }
    except (httpx.HTTPError, ValueError, TypeError):
        return None


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
    verified_photos = {
        item.species_key: item.photo_url
        for item in db.query(SpeciesPhoto).all()
    }
    geolocated = [tree for tree in filtered if tree.lat is not None and tree.lng is not None]
    weather = None
    if geolocated:
        latitude = sum(float(tree.lat) for tree in geolocated) / len(geolocated)
        longitude = sum(float(tree.lng) for tree in geolocated) / len(geolocated)
        weather = _weather_summary(round(latitude, 4), round(longitude, 4))
    barangay_counts: dict[str, set[str]] = defaultdict(set)
    barangay_tree_totals: Counter[str] = Counter()
    barangay_species_totals: dict[str, Counter[str]] = defaultdict(Counter)
    for tree in trees:
        area = (tree.barangay or "").strip()
        common_name = (tree.common_name or "").strip()
        if area:
            barangay_tree_totals[area] += 1
            if common_name:
                barangay_counts[area].add(common_name)
                barangay_species_totals[area][common_name] += 1

    barangay_needs = []
    for area, total in barangay_tree_totals.items():
        priority_species_gaps = [
            {
                "species_name": common,
                "scientific_name": scientific,
                "conservation_status": _conservation_status(common, scientific),
                "recorded_count": barangay_species_totals[area].get(common, 0),
                "photo_missing": _species_key(scientific) not in verified_photos,
            }
            for common, scientific, *_ in NATIVE_PRIORITY
            if barangay_species_totals[area].get(common, 0) <= 1
        ]
        unrecorded_species = [
            item for item in priority_species_gaps if item["recorded_count"] == 0
        ]
        barangay_needs.append({
            "barangay": area,
            "recorded_tree_count": total,
            "recorded_species_count": len(barangay_counts[area]),
            "underrepresented_native_priority_species": priority_species_gaps,
            "unrecorded_native_priority_species": unrecorded_species,
            "inventory_gap_count": len(priority_species_gaps),
            "missing_verified_photo_count": sum(item["photo_missing"] for item in priority_species_gaps),
            "photo_needed_species": [
                item["species_name"] for item in priority_species_gaps if item["photo_missing"]
            ],
            "basis": "TreeTrace inventory only; unrecorded species may still be present.",
        })
    barangay_needs.sort(key=lambda item: (
        -item["inventory_gap_count"],
        item["recorded_species_count"],
        item["recorded_tree_count"],
        item["barangay"].casefold(),
    ))

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
        verified_photo = verified_photos.get(_species_key(record.scientific_name))
        images = [verified_photo or record.photo_url] if verified_photo or record.photo_url else []
        suggestions.append({
            "species_name": record.species_name,
            "scientific_name": record.scientific_name,
            "conservation_status": _conservation_status(record.species_name, record.scientific_name),
            "priority": "Approved",
            "recommended_area": record.barangay or barangay or "Recommended planting area",
            "area_reason": "Approved by admin/field review for this planting area.",
            "image_urls": images,
            "photo_verified": verified_photo is not None,
            "photo_missing": verified_photo is None,
            "reason": record.reason or "Approved planting recommendation from the TreeTrace review queue.",
            "source": "approved",
        })

    for common, scientific, base_reason, recommended_area, area_reason in NATIVE_PRIORITY:
        existing = species_counts.get(common, 0)
        if filtered and existing <= 1:
            verified_photo = verified_photos.get(_species_key(scientific))
            suggestions.append({
                "species_name": common,
                "scientific_name": scientific,
                "conservation_status": _conservation_status(common, scientific),
                "priority": "High" if existing == 0 else "Medium",
                "recommended_area": barangay or recommended_area,
                "area_reason": (
                    f"{barangay} has only {existing} recorded {common} tree"
                    f"{'' if existing == 1 else 's'}, so planting here can improve species balance."
                    if barangay else area_reason
                ),
                "image_urls": [verified_photo] if verified_photo else [],
                "photo_verified": verified_photo is not None,
                "photo_missing": verified_photo is None,
                "reason": (
                    f"{common} is underrepresented"
                    f"{' in ' + barangay if barangay else ' in the current inventory'}. "
                    f"{base_reason}"
                ),
                "source": "system",
            })

    if not suggestions and (not barangay or filtered):
        suggestions.append({
            "species_name": "Native mixed-species planting",
            "scientific_name": None,
            "priority": "Medium",
            "recommended_area": barangay or "Barangays with low species balance",
            "area_reason": "Use mixed native seedlings where the inventory already has dominant species but needs resilience.",
            "image_urls": [],
            "photo_verified": False,
            "photo_missing": True,
            "reason": "This area already has recorded diversity. Add mixed native seedlings to keep the canopy resilient.",
            "source": "system",
        })

    return {
        "barangay": barangay,
        "total_trees_checked": len(filtered),
        "species_count": len(species_counts),
        "barangays_with_records": len(barangay_counts),
        "weather_context": weather,
        "recommendation_basis": "inventory_balance",
        "barangay_has_inventory": bool(filtered),
        "barangay_needs": barangay_needs,
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
