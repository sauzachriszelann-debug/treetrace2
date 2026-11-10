# Experimental growth-based age

The scanner and gallery review show display-only age scenarios from species,
DBH and/or total height. POST `/api/ai/estimate-age` requires authentication and
does not call AI, consume an AI identification, or write database records.
No Aiven migration is needed. Inventory dates and carbon calculations are unchanged.

## Reviewed source catalog (initial coverage: one species)

**Gmelina arborea (Yemane):** López-Aguirre, Barrios-Trilleras & Melo-Cruz,
*New Forests* 55, 961–978 (2024; online 2023).
https://doi.org/10.1007/s11056-023-10013-x

Methods specify DBH at 1.3 m and total height measured at nine years. Results,
Table 2, report family means: DBH 19.10–25.43 cm (mean 22.95); total height
19.31–22.39 m (mean 20.61). These are seed-grown plantation trees in tropical
dry forest, Colombia, not Philippine urban trees.

Derived mean annual size increments (not reported instantaneous annual rates):
DBH 22.95/9 = 2.55 cm/year; total height 20.61/9 = 2.29 m/year.
Family extrema imply DBH 2.1222–2.8256 cm/year and height
2.1456–2.4878 m/year. Code keeps original sizes and divides without pre-rounding.

## Calculation and limits

For each supplied dimension, scenario age = size / (published size / 9).
The display range envelopes the independent DBH and height scenarios using the
published family extrema, rounded outward to whole years. The central values
are shown separately, never averaged. Non-overlapping dimensional intervals
produce a disagreement warning. This is a linear-growth assumption extrapolated
from a single-age trial, **not a validated inverse growth model, prediction
interval, or confidence interval**. Even the range may exclude the actual age.
Pruning, mature growth, management, climate, and species errors can invalidate it.
AI-derived sizes retain `dimensions_source=ai_prediction` and an extra warning.
No universal growth factor or invented fallback is used for unsupported species.

## Expanding coverage

Start with Philippine studies from DENR–ERDB, DOST–PCAARRD, university forestry
research, and CIFOR–ICRAF. A relevant Philippine multi-species study is Santos
Martin, Lusiana & van Noordwijk (2010), *Tree Growth Prediction in Relation to
Simple Set of Site Quality Indicators for Six Native Tree Species in the
Philippines*, https://doi.org/10.1155/2010/507392 (not yet encoded).

For every added species, verify scientific name, numeric table/equation, units,
DBH measurement height, total versus merchantable height, age range, site,
seed-grown versus coppice, and applicability. Prefer fitted age-size models
with validation over this initial linear scenario. Do not use harvest age,
merchantable height, collar diameter or radius growth as interchangeable rates.
Add reviewed profiles in `backend/app/services/tree_age.py` with regression tests.

## Checks

Backend: `python -m pytest tests/test_tree_age.py -q`

Mobile: `flutter test --no-pub test/tree_age_card_test.dart test/gallery_tree_scan_test.dart test/two_capture_session_test.dart test/ai_identify_badges_test.dart`

After deploying backend and rebuilding mobile, check Yemane, unsupported species,
different-photo selection, retry offline, source link, and independent size values.
