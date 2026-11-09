"""Offline height contract checks. No field-accuracy claim or provider calls."""
import pytest
from app.services.height_tilt import measure_height


def height(**changes):
    return measure_height(**(dict(pitch_deg=45, distance_m=10,
        camera_height_m=1.4, dbh_status="ok", base_confirmed=True) | changes))


def test_formula_and_half_metre_rounding():
    result = height()
    assert result["height_m"] == 11.5
    assert result["theta_top_deg"] == 45
    assert result["distance_m"] == 10
    assert result["quality"] == "experimental"
    assert result["method"] == "tilt_distance" and result["fallback"] is False


@pytest.mark.parametrize("pitch", [5, 70, 70.1, 85])
def test_boundaries_and_steep_quality(pitch):
    result = height(pitch_deg=pitch)
    assert result["status"] == "ok"
    assert result["quality"] == ("low" if pitch > 70 else "experimental")
    assert result["height_m"] * 2 == round(result["height_m"] * 2)


@pytest.mark.parametrize("changes", [
    {"pitch_deg": None}, {"pitch_deg": float("nan")}, {"pitch_deg": float("inf")},
    {"pitch_deg": 4.9}, {"pitch_deg": 85.1}, {"pitch_deg": True},
    {"distance_m": None}, {"distance_m": True}, {"distance_m": 0}, {"distance_m": -1},
    {"distance_m": float("inf")}, {"distance_m": 1.7e308}, {"camera_height_m": 0},
    {"camera_height_m": None}, {"dbh_status": "retake"},
    {"dbh_status": "unavailable"}, {"base_confirmed": False},
])
def test_retakes_have_no_numbers(changes):
    result = height(**changes)
    assert result["status"] == "retake" and result["reason"]
    assert all(result[key] is None for key in ("height_m", "theta_top_deg", "distance_m"))


def test_endpoint_contract_and_authentication():
    from app.api.routes.identify import router, measure_height as endpoint
    from app.schemas.height import HeightRequest, HeightResponse
    from app.core.security import get_current_user
    route = next(r for r in router.routes if r.path == "/measure-height")
    assert any(dep.call is get_current_user for dep in route.dependant.dependencies)
    # Calling the handler directly avoids database, sockets and provider calls.
    result = endpoint(HeightRequest(pitch_deg=45, distance_m=10,
        dbh_status="ok", base_confirmed=True), _=object())
    assert HeightResponse(**result).height_m == 11.5
    assert endpoint(HeightRequest(), _=object())["height_m"] is None


def test_request_does_not_coerce_boolean_distance():
    from pydantic import ValidationError
    from app.schemas.height import HeightRequest
    with pytest.raises(ValidationError):
        HeightRequest(pitch_deg=45, distance_m=True)
