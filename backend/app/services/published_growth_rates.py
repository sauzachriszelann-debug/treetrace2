"""Factual MAI values transcribed from Schneider et al., Table 4 (2014).

DBH at 1.4 m and total height, 2011 measurements / plantation age (11–16 years),
Leyte mixed smallholder rainforestation. NOT instantaneous annual increments.
Only means published: no invented standard errors or uncertainty bands.
Three height means conflict with Table 2 and are omitted pending clarification.
"""
from app.schemas.tree_age import GrowthRates, GrowthSource


# scientific name | sample N | diameter cm/year | total height m/year
_ROWS = """
Agathis philippinensis|77|1.05|0.79
Anisoptera thurifera|21|0.72|0.79
Artocarpus blancoi|20|0.72|0.68
Artocarpus heterophyllus|46|0.84|0.71
Artocarpus odoratissimus|20|1.18|0.99
Azadirachta indica|1|0.85|0.66
Afzelia rhomboidea|4|0.55|0.75
Bridelia minutiflora|1|0.95|0.94
Calophyllum blancoi|49|0.52|0.64
Casuarina equisetifolia|51|0.86|0.75
Chrysophyllum cainito|2|0.42|0.61
Citrus microcarpa|2|0.57|0.70
Dillenia philippinensis|1|0.18|0.30
Diospyros philippinensis|15|0.25|0.31
Diospyros pilosanthera|6|0.46|0.64
Diplodiscus paniculatus|15|0.46|0.55
Dipterocarpus grandiflorus|21|0.69|0.71
Dracontomelon dao|206|0.98|0.89
Dracontomelon edule|4|0.68|0.87
Durio zibethinus|13|0.57|0.68
Garcinia mangostana|21|0.27|0.33
Garuga floribunda|2|0.26|0.41
Gliricidia sepium|2|0.90|1.06
Gmelina arborea|32|1.38|1.10
Heritiera sylvatica|1|0.15|0.43
Hopea foxworthyi|5|0.97|1.05
Hopea malibato|60|0.53|0.72
Hopea plagata|156|0.57|0.75
Intsia bijuga|20|0.31|0.45
Knema mindanensis|5|0.43|0.40
Lansium domesticum|48|0.34|0.45
Leucaena leucocephala|2|1.03|0.60
Mangifera indica|16|0.95|0.67
Melia dubia|21|1.89|1.31
Myrica javanica|9|0.90|0.75
Nephelium lappaceum|27|0.69|0.56
Parashorea malaanonan|145|0.62|0.89
Persea americana|4|0.68|0.63
Petersianthus quadrialatus|12|0.43|0.45
Podocarpus rumphii|26|0.32|0.37
Polyscias nodosa|3|0.86|0.68
Pterocarpus indicus|192|0.89|0.80
Samanea saman|41|1.19|0.80
Sandoricum koetjape|12|1.33|0.85
Securinega flexuosa|17|1.08|0.67
Shorea almon|3|0.74|0.86
Shorea contorta|286|0.87|0.97
Shorea guiso|52|1.19|1.07
Shorea polysperma|18|0.79|0.94
Shorea squamata|19|1.71|1.53
Strombosia philippinensis|8|0.21|0.30
Swietenia macrophylla|413|1.25|1.00
Cleistocalyx operculatus|1|1.25|1.14
Tectona grandis|73|1.51|1.22
Terminalia microcarpa|259|1.42|
Theobroma cacao|11|0.44|0.49
Toona philippinensis|29|0.97|
Tristania decorticata|3|0.62|0.78
Vitex parviflora|154|0.91|
Viticipremna philippinensis|5|0.91|0.61
"""

PUBLISHED_RATES = {}
for row in _ROWS.strip().splitlines():
    species, count, diameter, height = row.split("|")
    PUBLISHED_RATES[species.casefold()] = (
        GrowthRates(dbh_cm_per_year=[float(diameter)] * 3,
                    height_m_per_year=[float(height)] * 3 if height else None),
        GrowthSource(
            title="Growth performance of sixty tree species in smallholder reforestation trials on Leyte, Philippines",
            url="https://doi.org/10.1007/s11056-013-9393-5",
            citation="Schneider, Ashton, Montagnini & Milan (2014), New Forests 45, 83–96, Table 4 (online 2013).",
            context="Leyte, Philippines; mixed rainforestation sites aged 11–16 years. DBH measured at 1.4 m, total height. Published species means, not a calibrated age model or uncertainty range."
                + (" Height omitted: Tables 2 and 4 disagree." if not height else ""),
            sample_size=int(count), dbh_measurement_height_m=1.4,
        ),
    )

# Explicit botanical synonyms / spelling variants, never genus-wide matching.
ALIASES = {
    "artocarpus heterophylla": "artocarpus heterophyllus",
    "azfelia rhomboidea": "afzelia rhomboidea",
    "podocarpus rhumbii": "podocarpus rumphii",
    "citrus × microcarpa": "citrus microcarpa",
    "citrus x microcarpa": "citrus microcarpa",
    "pentacme contorta": "shorea contorta",
    "rubroshorea almon": "shorea almon",
    "rubroshorea polysperma": "shorea polysperma",
    "rubroshorea squamata": "shorea squamata",
}
