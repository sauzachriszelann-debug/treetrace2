"""Display-only growth scenarios; never planting dates or inventory measurements.

The source below is a single-age trial, NOT a fitted age prediction model.
Size / (published size / trial age) assumes linear growth from planting.
Ranges are envelopes of scenarios from family means, not confidence intervals.
Keep study measurements verbatim here; derive the rates rather than rounding them.
"""
import math

from app.schemas.tree_age import GrowthSource, TreeAgeRequest, TreeAgeResponse


GROWTH_SOURCES = {
    "gmelina arborea": GrowthSource(
        title="Balancing wood production and water use efficiency in the selection of open-pollinated families of Gmelina arborea",
        url="https://doi.org/10.1007/s11056-023-10013-x",
        citation="López-Aguirre, Barrios-Trilleras & Melo-Cruz (2024), New Forests 55, 961–978, Table 2; published online 2023.",
        context="Nine-year-old, seed-grown plantation trial in tropical dry forest, Colombia. Family mean ranges; not calibrated for Philippine urban trees. DBH measured at 1.3 m; height is total height.",
        reference_age_years=9,
        dbh_cm=[19.1, 22.95, 25.43],
        height_m=[19.31, 20.61, 22.39],
    ),
}


def estimate_tree_age(payload: TreeAgeRequest) -> TreeAgeResponse:
    name = " ".join(payload.scientific_name.split())
    source = GROWTH_SOURCES.get(name.casefold())
    common = dict(scientific_name=name, dimensions_source=payload.dimensions_source)
    if source is None:
        return TreeAgeResponse(status="unavailable", reason="Age unknown: no reviewed growth source for this species.", **common)
    if payload.dbh_cm is None and payload.height_m is None:
        return TreeAgeResponse(status="unavailable", source=source, reason="Age unknown: DBH or height is needed.", **common)

    intervals = []
    means = {}
    for key, size, reference in (
        ("dbh_age_years", payload.dbh_cm, source.dbh_cm),
        ("height_age_years", payload.height_m, source.height_m),
    ):
        if size is not None:
            low, mean, high = reference
            intervals.append((size * source.reference_age_years / high,
                              size * source.reference_age_years / low))
            means[key] = round(size * source.reference_age_years / mean, 1)

    disagree = len(intervals) == 2 and max(x[0] for x in intervals) > min(x[1] for x in intervals)
    reason = "Experimental linear growth scenario, not a measured age. The range is not a confidence interval. Growth changes with age, site and management; this extrapolates a single-age Colombian trial."
    if payload.dimensions_source == "ai_prediction":
        reason += " Uses unvalidated AI size predictions, so age uncertainty is greater."
    if disagree:
        reason += " DBH and height imply different ages; check sizes and pruning history."
    return TreeAgeResponse(
        status="estimated", min_years=max(0, math.floor(min(x[0] for x in intervals))),
        max_years=math.ceil(max(x[1] for x in intervals)),
        dimensions_disagree=disagree, source=source, reason=reason, **common, **means,
    )
