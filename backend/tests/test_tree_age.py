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
    result = estimate_tree_age(TreeAgeRequest(scientific_name="Mangifera indica", dbh_cm=30, height_m=10))
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
    assert estimate_age(TreeAgeRequest(scientific_name="Gmelina arborea", height_m=20.61), object()).height_age_years == 9
