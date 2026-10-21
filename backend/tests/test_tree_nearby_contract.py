"""Contract tests for the G3 nearby-matching endpoint (GET /api/trees/nearby).

The endpoint is advisory and strictly read-only: these tests pin down
distance filtering, nearest-first ordering (including with more than 50
in-box candidates), GPS validation, role-based authorization, species-match
labelling, and the absence of any write behavior.
"""

import math

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.models.tree import HealthStatus, Tree
from app.models.user import UserRole

# Same sphere as app.api.routes.trees._distance_km (R = 6371.0 km).
METERS_PER_DEGREE = 6371000.0 * math.pi / 180.0

BASE_LAT = 7.4333371
BASE_LNG = 125.8089195


def north_of(meters: float, lat: float = BASE_LAT, lng: float = BASE_LNG):
    """A point exactly `meters` north of (lat, lng) along the meridian."""
    return lat + meters / METERS_PER_DEGREE, lng


def east_of(meters: float, lat: float = BASE_LAT, lng: float = BASE_LNG):
    """A point `meters` east of (lat, lng) along the parallel."""
    cos_lat = math.cos(math.radians(lat))
    return lat, lng + meters / (METERS_PER_DEGREE * cos_lat)


def ref_distance_m(a_lat: float, a_lng: float, b_lat: float, b_lng: float):
    """Independent haversine (same R = 6371 km, asin form instead of the
    route's atan2 form) used to state expected orderings without trusting
    the implementation under test."""
    phi1, phi2 = math.radians(a_lat), math.radians(b_lat)
    d_phi = phi2 - phi1
    d_lam = math.radians(b_lng - a_lng)
    h = (
        math.sin(d_phi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(d_lam / 2) ** 2
    )
    return 2 * 6371000.0 * math.asin(math.sqrt(h))


def insert_tree(
    db_session: Session,
    common_name: str = "Narra",
    scientific_name: str | None = "Pterocarpus indicus",
    lat: float | None = None,
    lng: float | None = None,
    barangay: str = "New Visayas",
) -> Tree:
    tree = Tree(
        common_name=common_name,
        scientific_name=scientific_name,
        health_status=HealthStatus.Healthy,
        barangay=barangay,
        lat=lat,
        lng=lng,
    )
    db_session.add(tree)
    db_session.commit()
    db_session.refresh(tree)
    return tree


def nearby(client: TestClient, **params):
    defaults = {"lat": BASE_LAT, "lng": BASE_LNG}
    defaults.update(params)
    return client.get("/api/trees/nearby", params=defaults)


# ── Authorization ──────────────────────────────────────────────────────────


def test_nearby_requires_authentication(client: TestClient, db_session):
    insert_tree(db_session, lat=BASE_LAT, lng=BASE_LNG)

    response = nearby(client)

    assert response.status_code == 401


def test_nearby_forbidden_for_citizens(client: TestClient, citizen_user, db_session):
    response = nearby(client)

    assert response.status_code == 403


@pytest.mark.parametrize("role", [UserRole.admin, UserRole.field_worker])
def test_nearby_allows_staff_roles(
    client: TestClient, auth_as, db_session, role
):
    auth_as(role)
    insert_tree(db_session, lat=BASE_LAT, lng=BASE_LNG)

    response = nearby(client)

    assert response.status_code == 200


# ── Distance filtering and ordering ────────────────────────────────────────


def test_nearby_returns_only_trees_within_radius_sorted_by_distance(
    client: TestClient, admin_user, db_session
):
    near = insert_tree(db_session, common_name="Near", **_coords(10))
    mid = insert_tree(db_session, common_name="Mid", **_coords(50))
    insert_tree(db_session, common_name="Far", **_coords(500))

    response = nearby(client, radius_m=100)

    assert response.status_code == 200
    data = response.json()
    assert [item["common_name"] for item in data] == ["Near", "Mid"]
    assert data[0]["tree_id"] == near.id
    assert data[1]["tree_id"] == mid.id
    assert data[0]["distance_m"] == pytest.approx(10.0, abs=0.5)
    assert data[1]["distance_m"] == pytest.approx(50.0, abs=0.5)


def test_nearby_default_radius_is_fifteen_meters(
    client: TestClient, admin_user, db_session
):
    insert_tree(db_session, common_name="Inside", **_coords(10))
    insert_tree(db_session, common_name="Outside", **_coords(30))

    response = nearby(client)

    assert response.status_code == 200
    assert [item["common_name"] for item in response.json()] == ["Inside"]


def test_nearby_excludes_trees_without_coordinates(
    client: TestClient, admin_user, db_session
):
    insert_tree(db_session, common_name="NoGps", lat=None, lng=None)
    insert_tree(db_session, common_name="HalfGps", lat=BASE_LAT, lng=None)

    response = nearby(client)

    assert response.status_code == 200
    assert response.json() == []


def test_nearby_distance_math_matches_haversine(
    client: TestClient, admin_user, db_session
):
    insert_tree(db_session, common_name="Measured", **_coords(55.597))

    response = nearby(client, radius_m=100)

    data = response.json()
    assert len(data) == 1
    # 0.0005 degrees of latitude on the R=6371 km sphere.
    assert data[0]["distance_m"] == pytest.approx(55.6, abs=0.2)


def test_nearby_orders_correctly_with_more_than_fifty_candidates(
    client: TestClient, admin_user, db_session
):
    """Regression: nearest-neighbor selection must not be corrupted by any
    arbitrary pre-sort row cap. 61 candidates fall inside the box; the five
    truly nearest must come back, closest first."""
    spacing = 1.5  # meters between consecutive planted trees
    for i in range(61):
        insert_tree(
            db_session,
            common_name=f"Grid{i:02d}",
            scientific_name=None,
            **_coords(0.5 + i * spacing),
        )

    response = nearby(client, radius_m=100, limit=5)

    assert response.status_code == 200
    data = response.json()
    assert [item["common_name"] for item in data] == [
        "Grid00", "Grid01", "Grid02", "Grid03", "Grid04",
    ]
    distances = [item["distance_m"] for item in data]
    assert distances == sorted(distances)
    assert distances[0] == pytest.approx(0.5, abs=0.2)


def test_nearby_limit_is_respected(client: TestClient, admin_user, db_session):
    for i in range(7):
        insert_tree(db_session, common_name=f"Many{i}", **_coords(2 + i))

    response = nearby(client, radius_m=100, limit=5)

    assert response.status_code == 200
    assert len(response.json()) == 5


# ── Exact nearest-N selection guarantees (G3 correction) ───────────────────
#
# The endpoint must return the true nearest candidates by exact haversine
# distance. These tests pin that guarantee against the two approximation
# hazards the implementation must not have: ordering by a rounded distance,
# and pre-LIMIT selection on a planar proxy.


def test_nearby_orders_by_exact_distance_when_rounded_distances_tie(
    client: TestClient, admin_user, db_session
):
    """Candidates 1 mm apart all round to the same displayed distance; the
    truly nearest ones must still win the limit cut, regardless of insertion
    order (they are inserted farthest-first, so ids run opposite to
    distance)."""
    for i in reversed(range(6)):  # farthest first: ids run opposite to distance
        insert_tree(db_session, common_name=f"MM{i}", **_coords(50.0 + i * 0.001))

    response = nearby(client, radius_m=100, limit=3)

    assert response.status_code == 200
    data = response.json()
    assert [item["common_name"] for item in data] == ["MM0", "MM1", "MM2"]
    assert {item["distance_m"] for item in data} == {50.0}  # rounded display ties


def test_nearby_breaks_exact_ties_by_tree_id_deterministically(
    client: TestClient, admin_user, db_session
):
    """Trees at identical coordinates are equally near; the tie must break
    by tree id so repeated calls return the same set."""
    ids = [
        insert_tree(db_session, common_name=f"Tie{i}", **_coords(30.0)).id
        for i in range(4)
    ]

    first = nearby(client, radius_m=100, limit=2).json()
    second = nearby(client, radius_m=100, limit=2).json()

    assert [item["tree_id"] for item in first] == sorted(ids)[:2]
    assert first == second


def test_nearby_nearest_n_with_sixty_candidates_of_mixed_bearings(
    client: TestClient, admin_user, db_session
):
    """64 candidates on four distance rings x sixteen bearings. The limit
    cut must select exactly the nearest ring, whatever the bearing, and the
    returned distances must never decrease — planar-proxy or rounded-order
    selection would leak farther-ring candidates in."""
    planted = []
    for ring, meters in enumerate((20.0, 40.0, 60.0, 80.0)):
        for spoke in range(16):
            bearing = spoke * 22.5
            lat_i = BASE_LAT + meters * math.cos(
                math.radians(bearing)
            ) / METERS_PER_DEGREE
            lng_i = BASE_LNG + meters * math.sin(math.radians(bearing)) / (
                METERS_PER_DEGREE * math.cos(math.radians(BASE_LAT))
            )
            tree = insert_tree(
                db_session, common_name=f"R{ring}S{spoke:02d}", lat=lat_i, lng=lng_i
            )
            planted.append((ring, tree))

    response = nearby(client, radius_m=100, limit=10)

    assert response.status_code == 200
    data = response.json()
    assert len(data) == 10
    ring_of = {tree.id: ring for ring, tree in planted}
    assert all(ring_of[item["tree_id"]] == 0 for item in data)  # only ring 1
    distances = [item["distance_m"] for item in data]
    assert distances == sorted(distances)
    # Every returned candidate is genuinely nearer (independent haversine)
    # than every candidate left out of the limit cut.
    returned = {item["tree_id"] for item in data}
    ref = {
        tree.id: ref_distance_m(BASE_LAT, BASE_LNG, tree.lat, tree.lng)
        for _, tree in planted
    }
    assert max(ref[tid] for tid in returned) <= min(
        ref[tree.id] for _, tree in planted if tree.id not in returned
    ) + 1e-6


def test_nearby_haversine_order_beats_planar_proxy_order(
    client: TestClient, admin_user, db_session
):
    """Sharp regression for the ordering guarantee. At high latitude a due
    -east candidate planted one full meter-fraction farther in planar
    (equirectangular) terms is nevertheless NEARER by true great-circle
    distance: a great circle bulges poleward, shortening east-west arcs by
    about d*(Δλ*sinφ)²/24 (~3.4 µm at 100 m / 89°N). A planar-proxy
    selection returns the north tree first; exact haversine must return the
    east tree first."""
    q_lat, q_lng = 89.0, 60.0  # high latitude amplifies the GC-vs-parallel gap
    south = insert_tree(
        db_session, common_name="South", lat=q_lat - 99.9 / METERS_PER_DEGREE,
        lng=q_lng,
    )
    north = insert_tree(
        db_session,
        common_name="North",
        lat=q_lat + (100.0 - 2e-6) / METERS_PER_DEGREE,
        lng=q_lng,
    )
    east_lat, east_lng = east_of(100.0, lat=q_lat, lng=q_lng)
    east = insert_tree(db_session, common_name="East", lat=east_lat, lng=east_lng)

    response = nearby(client, lat=q_lat, lng=q_lng, radius_m=100, limit=2)

    assert response.status_code == 200
    # The inversion this test relies on, stated with independent math: the
    # east tree is truly nearer although its planar proxy is farther.
    d_north = ref_distance_m(q_lat, q_lng, north.lat, north.lng)
    d_east = ref_distance_m(q_lat, q_lng, east.lat, east.lng)
    planar_north = (north.lat - q_lat) * METERS_PER_DEGREE
    planar_east = (east_lng - q_lng) * METERS_PER_DEGREE * math.cos(
        math.radians(q_lat)
    )
    assert d_east < d_north < 100.0
    assert planar_east > planar_north
    assert [item["tree_id"] for item in response.json()] == [south.id, east.id]


def test_nearby_includes_just_inside_and_excludes_just_outside_radius(
    client: TestClient, admin_user, db_session
):
    """Radius boundary is exact: 1 mm inside counts at both the default and
    the maximum radius, 1 mm outside does not, including on the diagonal
    where the bounding box is widest."""
    insert_tree(db_session, common_name="In15", **_coords(14.999))
    insert_tree(db_session, common_name="Out15", **_coords(15.001))

    default_data = nearby(client).json()  # default radius = 15 m
    assert [item["common_name"] for item in default_data] == ["In15"]

    in_diag_lat, in_diag_lng = (
        BASE_LAT + 99.999 * math.cos(math.radians(45)) / METERS_PER_DEGREE,
        BASE_LNG + 99.999 * math.sin(math.radians(45))
        / (METERS_PER_DEGREE * math.cos(math.radians(BASE_LAT))),
    )
    insert_tree(db_session, common_name="InDiag", lat=in_diag_lat, lng=in_diag_lng)
    insert_tree(db_session, common_name="In100", **_coords(99.999))
    east_lat, east_lng = east_of(100.001)
    insert_tree(db_session, common_name="Out100East", lat=east_lat, lng=east_lng)

    max_data = nearby(client, radius_m=100, limit=10).json()
    # In15 and Out15 (15 m pair) both fall inside the 100 m radius, plus the
    # two 100 m pair members that are inside; only Out100East is excluded.
    assert sorted(item["common_name"] for item in max_data) == [
        "In100",
        "In15",
        "InDiag",
        "Out15",
    ]


# ── GPS and parameter validation ───────────────────────────────────────────


@pytest.mark.parametrize(
    "params",
    [
        {"lat": 91},
        {"lat": -91},
        {"lng": 181},
        {"lng": -181},
        {"lat": float("nan")},
        {"radius_m": 0},
        {"radius_m": -5},
        {"radius_m": 101},
        {"limit": 0},
        {"limit": 11},
    ],
)
def test_nearby_rejects_invalid_parameters(
    client: TestClient, admin_user, params
):
    response = nearby(client, **params)

    assert response.status_code == 422


def test_nearby_requires_coordinates(client: TestClient, admin_user):
    response = client.get("/api/trees/nearby")

    assert response.status_code == 422


# ── Species matching labels ────────────────────────────────────────────────


def test_nearby_species_match_exact_is_normalized(
    client: TestClient, admin_user, db_session
):
    insert_tree(db_session, common_name="Narra", **_coords(5))

    response = nearby(client, common_name="  narra  ")

    assert response.json()[0]["species_match"] == "exact"


def test_nearby_species_match_scientific_name_counts_as_exact(
    client: TestClient, admin_user, db_session
):
    insert_tree(
        db_session,
        common_name="Narra",
        scientific_name="Pterocarpus indicus",
        **_coords(5),
    )

    response = nearby(
        client,
        common_name="Molave",
        scientific_name="pterocarpus INDICUS",
    )

    assert response.json()[0]["species_match"] == "exact"


def test_nearby_species_match_different(
    client: TestClient, admin_user, db_session
):
    insert_tree(db_session, common_name="Narra", **_coords(5))

    response = nearby(client, common_name="Molave")

    assert response.json()[0]["species_match"] == "different"


def test_nearby_species_unknown_when_no_species_submitted(
    client: TestClient, admin_user, db_session
):
    insert_tree(db_session, common_name="Narra", **_coords(5))

    response = nearby(client)

    assert response.json()[0]["species_match"] == "unknown"


# ── Read-only behavior and response shape ──────────────────────────────────


def test_nearby_is_read_only(client: TestClient, admin_user, db_session):
    insert_tree(db_session, **_coords(5))
    insert_tree(db_session, common_name="Other", **_coords(8))
    before = db_session.query(Tree).count()

    nearby(client, radius_m=100)
    nearby(client, common_name="Narra", radius_m=100)

    assert db_session.query(Tree).count() == before


def test_nearby_response_shape(client: TestClient, admin_user, db_session):
    insert_tree(db_session, **_coords(5))

    data = nearby(client, radius_m=100).json()[0]

    assert set(data) == {
        "tree_id",
        "common_name",
        "scientific_name",
        "distance_m",
        "species_match",
        "health_status",
        "barangay",
        "created_at",
    }
    # Advisory data only: no raw coordinates beyond distance (approved D6).
    assert "lat" not in data and "lng" not in data and "photo_url" not in data


def _coords(meters_north: float):
    lat, lng = north_of(meters_north)
    return {"lat": lat, "lng": lng}
