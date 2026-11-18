"""Short botanical summaries paraphrased from the cited primary references.

These describe taxa, never observations, age, health or size of a scanned tree.
Model labels remain unchanged; unresolved labels must be checked by a botanist.
"""
NPARKS = 'https://www.nparks.gov.sg/florafaunaweb/flora/'

# label, common name, family, NParks page, overview, leaves, flowers, fruit
ROWS = [
('Acacia mangium', 'Mangium', 'Fabaceae', '2/6/2695',
 'Mangium is a tropical tree native to northeastern Australia, parts of Indonesia and Papua New Guinea. It is planted in forestry and landscapes.',
 'Mature foliage consists of flattened leaf stalks called phyllodes. Compare phyllode shape and veins with other Acacia species.',
 'Cream to white flower spikes.', 'Dry seed pods.'),
('Cassia fistula', 'Golden shower', 'Fabaceae', '2/7/2787',
 'Golden shower is a tree from India and Sri Lanka, grown for hanging clusters of yellow flowers.',
 'Pinnate leaves with 3–8 pairs of leaflets.', 'Long, drooping clusters of bright yellow flowers.', 'Long cylindrical pods that darken at maturity.'),
('Casuarina equisetifolia', 'Agoho', 'Casuarinaceae', '2/7/2793',
 'Agoho is a coastal flowering tree with a pine-like appearance. Its fine green branchlets carry tiny scale leaves; it is not a true pine.',
 'Jointed, needle-like branchlets with scale leaves in whorls.', 'Small male spikes and female flower heads.', 'Small woody cone-like clusters containing winged fruits.'),
('Ficus benjamina', 'Weeping fig', 'Moraceae', '2/9/2902',
 'Weeping fig is a tropical fig tree found across parts of Asia and the western Pacific. Its drooping branches give it a distinctive weeping form.',
 'Simple pointed leaves carried on drooping twigs.', 'Flowers enclosed inside the fig structure.', 'Small rounded figs, often paired at leaf axils.'),
('Gmelina arborea', 'Gmelina', 'Lamiaceae', '2/9/2939',
 'Gmelina is an Asian tree with broad opposite leaves, yellowish-brown flowers and fleshy fruit.',
 'Broad ovate leaves in opposite pairs; young foliage may be lobed. Two glands occur near the leaf base.',
 'Yellowish-brown flowers with an enlarged yellow lower lobe.', 'Small yellow drupes.'),
('Mangifera indica', 'Mango', 'Anacardiaceae', '3/0/3013',
 'Mango is a tropical fruit tree cultivated for its fleshy, aromatic fruit. Young leaf flushes are often bronze or reddish before turning green.',
 'Simple, elongated leaves with an entire, sometimes gently wavy margin.',
 'Small flowers carried in branched clusters.', 'Fleshy fruit with a large central stone.'),
('Polyalthia longifolia', 'Indian mast tree', 'Annonaceae', '3/0/3079',
 'Indian mast tree, now accepted as Monoon longifolium, is native to southern India and Sri Lanka. Its glossy narrow leaves have conspicuously wavy edges.',
 'Alternate, lance-shaped leaves with strongly wavy margins.', 'Greenish star-like flowers with six narrow petals.', 'Clusters of single-seeded fruits that become purplish black.'),
('Pterocarpus indicus', 'Narra', 'Fabaceae', '3/0/3093',
 'Narra is a tropical Asian tree with yellow flowers and distinctive round, winged pods. Related Pterocarpus species require careful comparison of leaves and fruit.',
 'Pinnate leaves; mature leaflets are usually hairless, with a flat or sunken upper midrib.',
 'Yellow, fragrant pea-like flowers.', 'Rounded pods with a thin wing around the seed-bearing centre.'),
('Samanea saman', 'Rain tree', 'Fabaceae', '3/1/3106',
 'Rain tree is a broad-crowned shade tree. Its finely divided leaves fold in the evening and in overcast conditions.',
 'Bipinnate leaves with asymmetric leaflets.', 'Powder-puff flower heads with pink and white stamens.', 'Dark, thick-edged pods with sticky pulp.'),
('Spathodea campanulata', 'African tulip tree', 'Bignoniaceae', '3/1/3132',
 'African tulip tree is a tropical African flowering tree planted for its large, showy orange-red blooms.',
 'Opposite, pinnately compound leaves.', 'Large orange-red, cup-shaped flowers.', 'Dry capsules containing winged seeds.'),
('Swietenia macrophylla', 'Big-leaf mahogany', 'Meliaceae', '3/1/3150',
 'Big-leaf mahogany is a tropical American timber tree cultivated in many tropical countries. Mature bark becomes ridged and flaky.',
 'Pinnate leaves with asymmetrical leaflets; young foliage can be reddish.',
 'Small, pale flowers in branched clusters.', 'Woody capsules that open to release winged seeds.'),
('Tabebuia rosea', 'Pink poui', 'Bignoniaceae', '3/1/3171',
 'Pink poui is an ornamental tree native to Central and South America, with showy pink or white trumpet-shaped flowers.',
 'Palmately compound leaves with five leaflets.', 'Pink or white trumpet-shaped flowers.', 'Dry capsules containing winged seeds.'),
('Terminalia catappa', 'Talisay', 'Combretaceae', '3/1/3181',
 'Talisay is a tropical coastal tree with layered branches. Its broad leaves may turn red before they fall.',
 'Large reverse-egg-shaped leaves with a pair of glands near the base.',
 'Small pale flowers on slender spikes.', 'Flattened fleshy fruits with a hard inner stone.'),
]

def facts():
    result = {}
    for label, common, family, page, description, leaves, flowers, fruit in ROWS:
        result[label] = dict(scientific_name=label, common_name=common, family=family,
            description=description, distinguishing_features=leaves,
            flower=flowers, fruit=fruit, plant_type='Tree / woody plant', lifespan='Perennial',
            botanical_source=NPARKS + page, taxonomy_status='species',
            look_alikes='A comparison of mature leaves, flowers and fruits is needed; a single photo does not confirm identity.')
    result['Polyalthia longifolia']['accepted_scientific_name'] = 'Monoon longifolium'
    result['Tabebuia rosea'].update(uses='Planted for shade and ornamental flowers.',
        name_story='The species epithet rosea refers to rose-coloured flowers.',
        adaptation_strategies='Species-specific adaptation guidance has not been verified.')
    result['Vitex parviflora'] = dict(scientific_name='Vitex parviflora', common_name='Molave',
        family='Lamiaceae', plant_type='Tree / woody plant', lifespan='Perennial', taxonomy_status='species',
        description='Molave is a tropical tree native to parts of Malesia, including the Philippines, and Palau. It belongs to the mint family, Lamiaceae.',
        distinguishing_features='Compare mature leaves and reproductive structures with related Vitex species. Differences can be subtle.',
        botanical_source='https://powo.science.kew.org/taxon/urn%3Alsid%3Aipni.org%3Anames%3A865916-1/general-information')
    result['Eucalyptus'] = dict(scientific_name='Eucalyptus', common_name='Eucalyptus (genus)',
        family='Myrtaceae', taxonomy_status='genus', plant_type='Tree / woody plant', lifespan='Perennial',
        description='This trained class identifies the genus Eucalyptus, not an exact species. Rainbow eucalyptus (Eucalyptus deglupta) is one example, not a confirmed identification of this tree.',
        distinguishing_features='An expert must compare mature leaves, flower buds, fruits and bark to identify the species.',
        look_alikes='An exact species identification is needed before selecting a close species comparison.',
        botanical_source=NPARKS + '2/8/2886')
    result['Acacia-Semanca'] = dict(scientific_name='Acacia-Semanca', common_name='Acacia-Semanca (unverified label)',
        taxonomy_status='unverified', family=None,
        description='Acacia-Semanca is a dataset label whose scientific identity has not been verified. An expert must confirm the botanical name before family, species photos or comparisons can be assigned.',
        look_alikes='Species comparisons are withheld until the botanical name is verified.')
    return result

# Comparisons are reference material, not second AI predictions or expert diagnoses.
# main label: comparison taxon, common name, primary source, practical distinction
COMPARISONS = {
 'Acacia mangium': ('Acacia auriculiformis','Earleaf acacia','2/6/2693',
    'Both have leaf-like phyllodes. Compare the broad phyllodes of mangium with the more curved phyllodes of earleaf acacia; check mature pods and veins with an expert.'),
 'Cassia fistula': ('Senna siamea','Siamese cassia','3/1/3118',
    'Both have yellow flowers and pinnate leaves. Golden shower has hanging flower clusters and cylindrical pods; Siamese cassia has flattened pods.'),
 'Casuarina equisetifolia': ('Pinus caribaea','Caribbean pine','3/0/3063',
    'Both look needle-leaved. Agoho has jointed green branchlets and tiny scale leaves; Caribbean pine has true needles grouped in bundles.'),
 'Ficus benjamina': ('Ficus microcarpa','Chinese banyan','2/9/2912',
    'Both are figs. Weeping fig has drooping twigs and sharply pointed leaf tips; Chinese banyan usually has blunter leaf tips and non-drooping twigs.'),
 'Gmelina arborea': ('Tectona grandis','Teak','3/1/3178',
    'Both have broad opposite leaves. Compare leaf texture and basal glands, then flowers: Gmelina has yellowish-brown flowers; teak has small pale flowers in large branched clusters.'),
 'Mangifera indica': ('Syzygium cumini','Duhat','3/1/3158',
    'Both can have glossy elongated foliage. Compare fruit and leaf arrangement: mango has large stone fruits; duhat has much smaller fruits that ripen dark purple to black.'),
 'Polyalthia longifolia': ('Saraca indica','Ashoka tree','3/1/3113',
    'Common names can be confusing: Indian mast tree is also called false ashoka. It has simple wavy-edged leaves and greenish flowers. Saraca indica has pinnate compound leaves and dense yellow-orange to red flower clusters. Compare scientific names, leaves and flowers.'),
 'Pterocarpus indicus': ('Pterocarpus macrocarpus','Burma padauk','3/2/3254',
    'These are close look-alikes. Narra usually has hairless mature leaflets and smaller winged pods. Burma padauk has some hairs below the leaflets and a raised upper midrib; inspect mature fruit too.'),
 'Samanea saman': ('Delonix regia','Fire tree','2/8/2838',
    'Both have spreading crowns and divided leaves. Rain tree has pink-white powder-puff flowers and thick pods; fire tree has large red-orange petals and long, flat woody pods.'),
 'Spathodea campanulata': ('Tabebuia rosea','Pink poui','3/1/3171',
    'Both bear showy tubular flowers. African tulip tree has pinnate leaves and orange-red cup-like flowers; pink poui has palmately compound leaves and pink-white trumpet flowers.'),
 'Swietenia macrophylla': ('Swietenia mahagoni','West Indian mahogany','3/1/3151',
    'Both have pinnate leaves and woody capsules with winged seeds. Compare mature leaflets and capsules with an expert; these species can hybridize, so leaf size alone is insufficient.'),
 'Tabebuia rosea': ('Tabebuia heterophylla','Whitewood','3/1/3170',
    'Both can have pink trumpet flowers. Pink poui has five leaflets; whitewood may have one, three or five. Compare mature leaves and flowers together; leaflet count alone cannot confirm identity.'),
 'Terminalia catappa': ('Terminalia mantaly','Madagascar almond','2/7/2762',
    'Both may have tiered crowns. Talisay has large broad leaves that can turn red before falling; Madagascar almond has smaller spatula-shaped leaves with uneven edges.'),
 'Vitex parviflora': ('Vitex quinata','Vitex quinata',
    'https://powo.science.kew.org/taxon/urn%3Alsid%3Aipni.org%3Anames%3A865957-1/general-information',
    'These closely related species can be difficult to separate. An expert should compare mature reproductive structures; foliage or a distant tree photo alone is insufficient.'),
}

def add_comparisons(catalog):
    for label, (taxon, common, page, distinction) in COMPARISONS.items():
        source = page if page.startswith('https:') else NPARKS + page
        catalog[label]['similar_species_records'] = [dict(scientific_name=taxon,
            common_name=common, comparison=distinction, botanical_source=source)]
        catalog[label]['look_alikes'] = f'{common} ({taxon}): {distinction} Botanical comparison, not a second AI prediction.'
        catalog[label]['look_alikes_source'] = source
