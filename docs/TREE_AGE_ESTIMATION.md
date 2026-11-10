# Experimental growth-based age

The scanner and gallery review show display-only age scenarios from species,
DBH and/or total height. POST `/api/ai/estimate-age` requires authentication and
uses published data first, then an unverified AI species-growth-rate fallback.
Published calculations do not consume an AI identification. The fallback uses
the existing configured Gemini provider and consumes one request under the
existing authenticated AI plan limit. It never writes database records.
No Aiven migration is needed. Inventory dates and carbon calculations are unchanged.

## Reviewed source catalog (60 species plus explicit synonyms)

Schneider, Ashton, Montagnini & Milan, *New Forests* 45, 83–96 (2014;
online 2013), Table 4: https://doi.org/10.1007/s11056-013-9393-5
Author-uploaded full text:
https://www.researchgate.net/publication/258164722_Growth_performance_of_sixty_tree_species_in_smallholder_reforestation_trials_on_Leyte_Philippines

The published rates cover 60 species sampled in Leyte, with annual mean DBH
increments in cm/year and total-height increments in m/year. DBH was measured
at **1.4 m**, differing from TreeTrace's 1.3 m convention. Measurements in 2011
were divided by plantation age (sites established 1995–2000). The study is not
a validated individual-tree age predictor. Some species have only 1–4 sampled
individuals; sample counts are retained and the UI warns for N < 20.

Source Table 2 and Table 4 disagree on total-height means for Vitex parviflora,
Terminalia microcarpa and Toona philippinensis. These three height values are
deliberately omitted; their DBH means remain usable. Table 4 Podocarpus uses
the spelling 'rhumbii'; Table 2 identifies the same sample as P. rumphii.
The Appendix/Table 4 DBH mean 0.32 is used (Table 2 rounds/reports 0.31).
Do not treat these transcription differences as measured uncertainty ranges.

Catalog: `backend/app/services/published_growth_rates.py`. Exact botanical
aliases handle historical Shorea names; never match every member of a genus.
Unlisted synonyms can use the explicitly unverified AI fallback.

The existing Gmelina profile below remains preferred to preserve its previous
calculation and rate bounds; the Leyte Gmelina row is retained for provenance.

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

The mobile card headlines one rounded scenario age: DBH-based age first, with
height-based age only when DBH age is unavailable. Height is a cross-check,
not an equally weighted input to an average. This is an explicit display
choice, not evidence that DBH predicts age more accurately for every species.
Conflicting checks keep a prominent "highly uncertain" warning. Independent
dimensional ages remain available under Calculation details. The server's
scenario envelope is not the primary age headline when a central age exists.

For each supplied dimension, scenario age = size / (published size / 9).
The display range envelopes the independent DBH and height scenarios using the
published family extrema, rounded outward to whole years. The central values
are shown separately, never averaged. Non-overlapping dimensional intervals
produce a disagreement warning. This is a linear-growth assumption extrapolated
from a single-age trial, **not a validated inverse growth model, prediction
interval, or confidence interval**. Even the range may exclude the actual age.
Pruning, mature growth, management, climate, and species errors can invalidate it.
AI-derived sizes retain `dimensions_source=ai_prediction` and an extra warning.
For the Leyte profiles, only means are published. Their rate triples contain the
same mean three times, not fabricated low/high bounds. The displayed span is
the envelope of the independent dimensional scenarios rounded outward. A
two-fold difference between central dimensional ages triggers a display warning
only; this is a heuristic, not a statistical agreement test.

## AI fallback for other species

For species without a reviewed profile, the server asks AI for species-specific
diameter and total-height growth-rate ranges, using the supplied DBH/height as
context. It explicitly distinguishes diameter from radius/circumference, and
total height from merchantable height. For palms, AI must omit DBH growth when
diameter is not an applicable age indicator. The server computes ages itself
from those ranges, using their arithmetic midpoint for the central rate. This
midpoint is an assumption, not a measured mean.

The UI says **AI growth estimate — source unverified**, shows the rate ranges
and assumptions, and never displays model-invented source URLs or citations.
`estimation_basis=ai_growth_guess`, `source=null`, `validated=false`. Malformed,
nonpositive, reversed, nonfinite, species-mismatched or implausibly extreme
rates cannot create ages. No sizes, no applicable rates, ambiguous/non-tree
species or provider failure can still yield age unavailable. There is no
scientifically supportable guarantee of a numerical age for every possible tree.
There are no hardcoded universal rates or placeholder ages.

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
Add reviewed profiles in `backend/app/services/published_growth_rates.py` or
`tree_age.py` with regression tests.

## Checks

Backend: `python -m pytest tests/test_tree_age.py -q`

Mobile: `flutter test --no-pub test/tree_age_card_test.dart test/gallery_tree_scan_test.dart test/two_capture_session_test.dart test/ai_identify_badges_test.dart`

After deploying backend and rebuilding mobile, check Yemane, unsupported species,
different-photo selection, retry offline, source link, and independent size values.
