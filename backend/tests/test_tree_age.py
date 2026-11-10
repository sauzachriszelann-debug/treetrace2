import inspect
import math

import pytest
from fastapi.params import Depends
from pydantic import ValidationError

from app.schemas.tree_age import TreeAgeRequest
from app.services.tree_age import estimate_tree_age


def estimate(**kwargs):
    return estimate_tree_age(TreeAgeRequest(scientific_name="Gmelina arborea", **kwargs))


def test_published_trial_means_reproduce_reference_age():
    result = estimate(dbh_cm=22.95, height_m=20.61)
    assert result.dbh_age_years == result.height_age_years == 9
    assert not result.dimensions_disagree
    assert result.min_years == 8 and result.max_years == 11
    assert result.source.reference_age_years == 9
    assert result.source.url.endswith("10.1007/s11056-023-10013-x")
    assert not result.validated


def test_conflicting_ai_sizes_remain_separate_not_averaged():
    result = estimate(dbh_cm=45, height_m=9)
    assert result.dimensions_disagree
    assert result.dbh_age_years == 17.6
    assert result.height_age_years == 3.9
    assert (result.min_years, result.max_years) == (3, 22)
    assert "unvalidated AI" in result.reason
    assert "not a confidence interval" in result.reason


def test_dbh_only_and_measured_provenance():
    result = estimate(dbh_cm=22.95, dimensions_source="measurement")
    assert result.height_age_years is None
    assert "unvalidated AI" not in result.reason
    assert not result.validated


def test_missing_sizes_and_unknown_species_never_get_defaults():
    assert estimate().status == "unavailable"
    result = estimate_tree_age(TreeAgeRequest(scientific_name="Annona muricata", dbh_cm=30, height_m=10))
    assert result.status == "unavailable" and result.min_years is None
    assert result.source is None


def test_species_matching_is_exact_except_case_and_whitespace():
    assert estimate_tree_age(TreeAgeRequest(scientific_name="  GMELINA   ARBOREA ", height_m=20.61)).status == "estimated"
    assert estimate_tree_age(TreeAgeRequest(scientific_name="Gmelina sp.", height_m=20)).status == "unavailable"


@pytest.mark.parametrize("value", [0, -1, math.nan, math.inf, 501])
def test_invalid_sizes_rejected(value):
    with pytest.raises(ValidationError):
        TreeAgeRequest(scientific_name="Gmelina arborea", dbh_cm=value)


def test_route_is_authenticated_and_calculation_is_read_only():
    from app.api.routes.identify import estimate_age
    from app.core.security import get_current_user
    dependency = inspect.signature(estimate_age).parameters["_"].default
    assert isinstance(dependency, Depends)
    assert dependency.dependency is get_current_user
    coroutine = estimate_age(TreeAgeRequest(scientific_name="Gmelina arborea", height_m=20.61), object(), None)
    with pytest.raises(StopIteration) as completed:
        coroutine.send(None)
    assert completed.value.value.height_age_years == 9


def test_published_catalog_and_actual_species_rate_units():
    from app.services.published_growth_rates import PUBLISHED_RATES
    assert len(PUBLISHED_RATES) == 60
    mango = estimate_tree_age(TreeAgeRequest(scientific_name="Mangifera indica", dbh_cm=19, height_m=13.4))
    assert mango.dbh_age_years == mango.height_age_years == 20
    assert mango.source.sample_size == 16
    assert mango.source.dbh_measurement_height_m == 1.4
    assert mango.estimation_basis == "published_growth"
    assert mango.source.url.endswith("s11056-013-9393-5")
    assert "Small study sample" in mango.reason


def test_synonyms_and_conflicting_source_heights():
    result = estimate_tree_age(TreeAgeRequest(scientific_name="Pentacme contorta", dbh_cm=8.7))
    assert result.dbh_age_years == 10
    molave = estimate_tree_age(TreeAgeRequest(scientific_name="Vitex parviflora", dbh_cm=9.1, height_m=7.2))
    assert molave.height_age_years is None
    assert "Tables 2 and 4 disagree" in molave.source.context


def ai_rates(**changes):
    return dict(applicable=True, scientific_name="Annona muricata",
                dbh_cm_per_year=[0.4, 1.2], height_m_per_year=[0.3, 1.0],
                assumptions="Tropical urban tree; pruning and maturity can slow growth.", **changes)


def test_ai_rates_are_used_without_fabricated_citations():
    from app.services.tree_age import parse_ai_growth
    raw = ai_rates()
    raw.update(url="https://fake.example/study", min_years=999)
    result = parse_ai_growth(raw, TreeAgeRequest(scientific_name="Annona muricata", dbh_cm=12, height_m=6))
    assert result.estimation_basis == "ai_growth_guess"
    assert result.source is None and not result.validated
    assert result.dbh_age_years == 15
    assert result.max_years == 30
    assert result.growth_rates.dbh_cm_per_year == [0.4, 0.8, 1.2]


@pytest.mark.parametrize("bad", [[1, 0.2], [0, 1], [True, 2], [math.nan, 1], [0.1, 999], [1], "fast"])
def test_bad_ai_rates_cannot_create_age(bad):
    from app.services.tree_age import parse_ai_growth
    raw = ai_rates()
    raw["dbh_cm_per_year"] = bad
    assert parse_ai_growth(raw, TreeAgeRequest(scientific_name="Annona muricata", dbh_cm=12)).status == "unavailable"


def test_ai_species_mismatch_and_palms():
    from app.services.tree_age import parse_ai_growth
    raw = ai_rates()
    raw['scientific_name'] = "Cocos nucifera"
    assert parse_ai_growth(raw, TreeAgeRequest(scientific_name="Annona muricata", dbh_cm=12)).status == "unavailable"
    raw['dbh_cm_per_year'] = None
    result = parse_ai_growth(raw, TreeAgeRequest(scientific_name="Cocos nucifera", dbh_cm=40, height_m=10))
    assert result.dbh_age_years is None and result.height_age_years is not None


def test_route_only_uses_ai_and_quota_for_missing_source(monkeypatch):
    from app.api.routes import identify
    from app.services import tree_age
    calls = []
    async def fake_ai(payload):
        calls.append("provider")
        raw = ai_rates()
        raw['scientific_name'] = payload.scientific_name
        return tree_age.parse_ai_growth(raw, payload)
    monkeypatch.setattr(tree_age, 'estimate_ai_tree_age', fake_ai)
    monkeypatch.setattr(identify, 'enforce_ai_limit', lambda user, db: calls.append("quota"))
    coroutine = identify.estimate_age(TreeAgeRequest(scientific_name="Annona muricata", dbh_cm=12), object(), None)
    with pytest.raises(StopIteration) as completed:
        coroutine.send(None)
    assert completed.value.value.status == "estimated"
    assert calls == ["quota", "provider"]
    calls.clear()
    coroutine = identify.estimate_age(TreeAgeRequest(scientific_name="Mangifera indica", dbh_cm=12), object(), None)
    with pytest.raises(StopIteration):
        coroutine.send(None)
    assert calls == []
    # A published DBH mean must not block the AI fallback when only height
    # was supplied and its published height value was omitted as conflicting.
    coroutine = identify.estimate_age(TreeAgeRequest(scientific_name="Vitex parviflora", height_m=7), object(), None)
    with pytest.raises(StopIteration) as completed:
        coroutine.send(None)
    assert completed.value.value.estimation_basis == "ai_growth_guess"
    assert calls == ["quota", "provider"]


def test_provider_failure_returns_no_age_and_no_provider_details(monkeypatch):
    from app.api.routes import identify
    from app.services import tree_age
    async def fail(payload):
        raise RuntimeError('private provider details')
    monkeypatch.setattr(tree_age, 'estimate_ai_tree_age', fail)
    monkeypatch.setattr(identify, 'enforce_ai_limit', lambda user, db: None)
    coroutine = identify.estimate_age(TreeAgeRequest(scientific_name="Annona muricata", dbh_cm=12), object(), None)
    with pytest.raises(StopIteration) as completed:
        coroutine.send(None)
    result = completed.value.value
    assert result.status == "unavailable" and result.min_years is None
    assert 'private' not in result.reason


def test_provider_access_errors_are_not_retried_on_other_models(monkeypatch):
    from app.services import ai_identify
    calls = []
    class Client:
        def __init__(self, **kwargs):
            pass
        async def __aenter__(self):
            return self
        async def __aexit__(self, *args):
            pass
        async def post(self, url, json):
            calls.append(json)
            return type('Response', (), {'status_code': 403})()
    monkeypatch.setattr(ai_identify.httpx, 'AsyncClient', Client)
    monkeypatch.setattr(ai_identify, 'GEMINI_API_KEY', 'test-placeholder')
    monkeypatch.setattr(ai_identify, '_gemini_candidate_models', lambda: ['primary', 'secondary'])
    coroutine = ai_identify.species_growth_prediction('test species growth')
    with pytest.raises(ai_identify.GalleryVisionError):
        coroutine.send(None)
    assert len(calls) == 1
    assert calls[0]['contents'][0]['parts'] == [{'text': 'test species growth'}]
