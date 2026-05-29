import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';

import 'package:provider/provider.dart';

import '../services/api_service.dart';

import '../services/auth_provider.dart';

import '../services/theme.dart';

import '../models/models.dart';

import '../widgets/widgets.dart';

import 'tree_detail_screen.dart';
import 'scan_qr_screen.dart';
import 'community_structure_screen.dart';
import 'endangered_trees_screen.dart';
import 'unknown_review_screen.dart';
import 'health_logs_screen.dart';
import 'tree_list_screen.dart';
import 'profile_screen.dart';
import 'planting_recommendations_screen.dart';



class DashboardScreen extends StatefulWidget {

  const DashboardScreen({super.key});

  @override

  State<DashboardScreen> createState() => _DashboardScreenState();

}



class _DashboardScreenState extends State<DashboardScreen> {

  List<TreeModel> _trees = [];

  List<HealthLogModel> _logs = [];

  Map<String, dynamic>? _community;
  List<Map<String, dynamic>> _plantingSuggestions = [];
  int _pendingReviews = 0;
  String _search = '';
  final TextEditingController _searchController = TextEditingController();
  bool _reviewNotificationSeen = false;

  bool _loading = true;



  @override

  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }



  Future<void> _load() async {

    try {

      final t = await api.getTrees(limit: 200);

      final l = await api.getHealthLogs(limit: 50);

      final c = await api.getCommunityStructure();
      Map<String, dynamic> planting = {};
      try {
        planting = await api.getPlantingSuggestions();
      } catch (_) {}
      List<dynamic> unknown = [];
      try {
        unknown = await api.getUnknownSpeciesReview();
      } catch (_) {}

      setState(() {

        _trees = t.map((j) => TreeModel.fromJson(j)).toList();

        _logs = l.map((j) => HealthLogModel.fromJson(j)).toList();

        _community = c;
        _plantingSuggestions = (planting['suggestions'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _pendingReviews = unknown.where((e) => e['reviewed'] != true).length;

        _loading = false;

      });

    } catch (_) { setState(() => _loading = false); }

  }



  @override

  Widget build(BuildContext context) {

    final user = context.watch<AuthProvider>().user;

    final healthy = _trees.where((t) => t.healthStatus == 'Healthy').length;

    final fair = _trees.where((t) => t.healthStatus == 'Fair').length;

    final poor = _trees.where((t) => t.healthStatus == 'Poor').length;

    final carbon = _trees.fold<double>(0, (s, t) => s + (t.carbonKg ?? 0));

    final gps = _trees.where((t) => t.lat != null).length;
    final conservationTrees = _trees
        .map(_conservationMapForTree)
        .whereType<Map<String, dynamic>>()
        .toList();
    final query = _search.trim().toLowerCase();
    final recentTrees = query.isEmpty
        ? _trees
        : _trees.where((tree) {
            final text = [
              tree.commonName,
              tree.scientificName ?? '',
              tree.barangay ?? '',
              tree.healthStatus,
            ].join(' ').toLowerCase();
            return text.contains(query);
          }).toList();
    final searching = query.isNotEmpty;



    return Scaffold(

      backgroundColor: kBackground,

      body: RefreshIndicator(

        onRefresh: _load, color: kPrimary,

        child: CustomScrollView(slivers: [

// ── App bar matching sidebar green ─────────────────────────────────

          SliverAppBar(

            pinned: true,

            expandedHeight: 130,

            backgroundColor: kSidebarBg,

            title: const Text(
              'TreeTrace',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),

            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: Row(
                    children: [
                      if (_pendingReviews > 0 && !_reviewNotificationSeen)
                        _ReviewNotificationBadge(
                          count: _pendingReviews,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const UnknownReviewScreen(),
                              ),
                            );
                            if (mounted) {
                              setState(() {
                                _pendingReviews = 0;
                                _reviewNotificationSeen = true;
                              });
                            }
                          },
                        ),
                      const SizedBox(width: 8),
                      const _RoleIconBadge(),
                    ],
                  ),
                ),
              ),
            ],

            flexibleSpace: FlexibleSpaceBar(

              background: Container(

                color: kSidebarBg,

                padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),

                child: Column(

                  crossAxisAlignment: CrossAxisAlignment.start,

                  mainAxisAlignment: MainAxisAlignment.end,

                  children: [

                    Text(
                      'Welcome back, ${user?.fullName.split(' ').first ?? 'User'}',
                      style: TextStyle(
                          color: kSidebarText.withOpacity(0.7),
                          fontSize: 13),
                    ),
                    const SizedBox(height: 4),

                    Text('TreeTrace Geo-Spatial Inventory',
                        style: GoogleFonts.inter(
                            color: Colors.white, fontSize: 18,
                            fontWeight: FontWeight.w700)),

                  ],

                ),

              ),

            ),

          ),



          SliverToBoxAdapter(

            child: Padding(

              padding: const EdgeInsets.all(16),

              child: Column(

                crossAxisAlignment: CrossAxisAlignment.start,

                children: [

                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    crossAxisSpacing: 9,
                    mainAxisSpacing: 9,
                    childAspectRatio: 2.45,
                    children: [
                      _DashboardActionButton(
                          label: 'Scan QR',
                          icon: Icons.qr_code_scanner_rounded,
                          onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ScanQRScreen(
                                    onBack: () => Navigator.pop(context),
                                  ),
                                ),
                              )),
                      _DashboardActionButton(
                          label: 'Community',
                          icon: Icons.diversity_3_rounded,
                          onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const CommunityStructureScreen(),
                                ),
                              )),
                      _DashboardActionButton(
                          label: 'Health',
                          icon: Icons.health_and_safety_outlined,
                          onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const HealthLogsScreen(),
                                ),
                              )),
                      _DashboardActionButton(
                          label: 'Planting',
                          icon: Icons.eco_outlined,
                          onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const PlantingRecommendationsScreen(),
                                ),
                              )),
                    ],
                  ),

                  const SizedBox(height: 10),

                  _DashboardPlantingSuggestions(
                    suggestions: _plantingSuggestions,
                    onOpen: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PlantingRecommendationsScreen(),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _search = value),
                    decoration: InputDecoration(
                      hintText: 'Search trees...',
                      prefixIcon:
                          const Icon(Icons.search_rounded, color: kPrimary),
                      suffixIcon: _search.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  color: kMutedFg),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _search = '');
                              },
                            ),
                    ),
                  ),

                  if (searching) ...[
                    const SizedBox(height: 8),
                    _DashboardSearchResultsPanel(results: recentTrees),
                  ],

                  const SizedBox(height: 10),

// ── Stats grid (2x2) ─────────────────────────────────────

                  GridView.count(

                    crossAxisCount: 2, shrinkWrap: true,

                    physics: const NeverScrollableScrollPhysics(),

                    padding: EdgeInsets.zero,

                    crossAxisSpacing: 9, mainAxisSpacing: 9,

                    childAspectRatio: 1.55,

                    children: [

                      _CompactStatsCard(title: 'Total Trees',

                          value: '${_trees.length}',

                          icon: Icons.park, color: kPrimary),

                      _CompactStatsCard(title: 'Healthy',

                          value: '$healthy',

                          icon: Icons.eco, color: kHealthy),

                      _CompactStatsCard(title: 'Need Attention',

                          value: '${fair + poor}',

                          subtitle: '$fair Fair, $poor Poor',

                          icon: Icons.warning_amber_rounded, color: kFair),

                      _CompactStatsCard(title: 'Carbon Stock',

                          value: '${(carbon / 1000).toStringAsFixed(2)} t',

                          subtitle: 'Total CO2 equivalent',

                          icon: Icons.cloud_outlined,

                          color: Colors.blue.shade600),

                    ],

                  ),

                  const SizedBox(height: 10),

                  _CommunityDashboardCards(
                    data: _community,
                    fallbackConservationTrees: conservationTrees,
                    onStructureTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CommunityStructureScreen(),
                      ),
                    ),
                    onEndangeredTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EndangeredTreesScreen(
                          initialTrees: conservationTrees.isNotEmpty
                              ? conservationTrees
                              : (_community?['endangered_trees']
                                      as List<dynamic>?) ??
                                  const <dynamic>[],
                        ),
                      ),
                    ),
                  ),



// ── Health distribution bar ───────────────────────────────

                  SectionHeader('Health Distribution'),

                  Container(

                    padding: const EdgeInsets.all(16),

                    decoration: BoxDecoration(

                      color: kCard,

                      borderRadius: BorderRadius.circular(14),

                      border: Border.all(color: kBorder),

                    ),

                    child: Column(children: [

                      _HealthBar('Healthy', healthy, _trees.length, kHealthy),

                      const SizedBox(height: 10),

                      _HealthBar('Fair', fair, _trees.length, kFair),

                      const SizedBox(height: 10),

                      _HealthBar('Poor', poor, _trees.length, kPoor),

                      const SizedBox(height: 12),

                      Row(

                        mainAxisAlignment: MainAxisAlignment.spaceBetween,

                        children: [

                          Text('$gps GPS tagged',

                              style: const TextStyle(

                                  fontSize: 12, color: kMutedFg)),

                          Text('${_trees.isEmpty ? 0 : (gps / _trees.length * 100).round()}% mapped',

                              style: const TextStyle(

                                  fontSize: 12, color: kMutedFg)),

                        ],

                      ),

                    ]),

                  ),



// ── Recent entries ────────────────────────────────────────

                  SectionHeader('Recent Entries',

                    action: TextButton(

                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const TreeListScreen(),
                          ),
                        );
                        _load();
                      },

                      child: const Text('View all',

                          style: TextStyle(color: kPrimary, fontSize: 13)),

                    ),

                  ),



                  if (_loading)

                    const LoadingList(count: 3)

                  else if (_trees.isEmpty)

                    const EmptyState(

                        message: 'No trees recorded yet',

                        subtitle: 'Tap + to add your first tree')

                  else

                    ...recentTrees.take(5).map((t) => Padding(

                      padding: const EdgeInsets.only(bottom: 0),

                      child: _RecentTreeRow(

                        tree: t,

                        onTap: () => Navigator.push(context,

                            MaterialPageRoute(

                                builder: (_) =>

                                    TreeDetailScreen(treeId: t.id))),

                      ),

                    )),



// ── Recent health logs ────────────────────────────────────

                  if (_logs.isNotEmpty) ...[

                    SectionHeader('Recent Health Assessments'),

                    ..._logs.take(5).map((log) => Container(

                      margin: const EdgeInsets.only(bottom: 8),

                      padding: const EdgeInsets.symmetric(

                          horizontal: 14, vertical: 10),

                      decoration: BoxDecoration(

                        color: kMuted,

                        borderRadius: BorderRadius.circular(12),

                      ),

                      child: Row(children: [

                        Expanded(child: Column(

                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [

                            Text(log.treeCommonName ?? 'Tree',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,

                                style: const TextStyle(

                                    fontWeight: FontWeight.w600,

                                    fontSize: 13)),

                            Text('${log.assessedDate} · ${log.assessedBy ?? ''}',

                                style: const TextStyle(

                                    fontSize: 11, color: kMutedFg)),

                          ],

                        )),

                        HealthBadge(log.condition, small: true),

                      ]),

                    )),

                  ],

                  SizedBox(height: MediaQuery.of(context).padding.bottom + 104),

                ],

              ),

            ),

          ),

        ]),

      ),

    );

  }

}



class _ReviewNotificationBadge extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _ReviewNotificationBadge({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.notifications_active_rounded,
                color: Colors.orange.shade300, size: 18),
            if (count > 0) ...[
              const SizedBox(width: 3),
              Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoleIconBadge extends StatelessWidget {
  const _RoleIconBadge();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      ),
      customBorder: const CircleBorder(),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.18)),
        ),
        child: const Icon(
          Icons.person_outline_rounded,
          color: kPrimary,
          size: 17,
        ),
      ),
    );
  }
}

class _DashboardPlantingSuggestions extends StatelessWidget {
  final List<Map<String, dynamic>> suggestions;
  final VoidCallback onOpen;
  const _DashboardPlantingSuggestions({
    required this.suggestions,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final items = suggestions.take(5).toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Planting Suggestions',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
              TextButton(
                onPressed: onOpen,
                child: const Text('Open'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kBackground,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kBorder),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.eco_outlined, color: kPrimary),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Open planting planner to add suggested trees.',
                        style: TextStyle(color: kMutedFg, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: 118,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 9),
                itemBuilder: (_, index) => _DashboardPlantCard(
                  item: items[index],
                  onTap: onOpen,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DashboardPlantCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  const _DashboardPlantCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = item['species_name']?.toString() ?? 'Suggested tree';
    final area = item['recommended_area']?.toString() ?? 'Recommended area';
    final photo = _dashboardPlantPhoto(item, name);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 132,
        decoration: BoxDecoration(
          color: kBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.network(
              photo,
              height: 62,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 62,
                color: kPrimary.withOpacity(0.08),
                child: const Icon(Icons.eco_outlined, color: kPrimary),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    area,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kMutedFg, fontSize: 10.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _dashboardPlantPhoto(Map<String, dynamic> item, String name) {
  final images = item['image_urls'];
  if (images is List && images.isNotEmpty) {
    final first = images.first.toString();
    if (first.isNotEmpty) return first;
  }
  return 'https://tse1.mm.bing.net/th?q=${Uri.encodeComponent('$name tree seedling')}';
}

Map<String, dynamic>? _conservationMapForTree(TreeModel tree) {
  final info = _localConservationInfo(
    '${tree.commonName} ${tree.scientificName ?? ''}',
  );
  if (info == null) return null;

  return {
    'tree_id': tree.id,
    'id': tree.id,
    'common_name': tree.commonName,
    'scientific_name': tree.scientificName,
    'barangay': tree.barangay ?? 'Unknown',
    'photo_url': tree.photoUrl,
    'lat': tree.lat,
    'lng': tree.lng,
    'status': info['status'],
    'status_code': info['status_code'],
    'iucn_color': info['iucn_color'],
    'cutting_allowed': false,
  };
}

Map<String, String>? _localConservationInfo(String rawName) {
  final name = rawName.toLowerCase().trim();
  const protectedSpecies = {
    'narra': {
      'status': 'Endangered',
      'status_code': 'EN',
      'iucn_color': '#f57c00',
    },
    'pterocarpus indicus': {
      'status': 'Endangered',
      'status_code': 'EN',
      'iucn_color': '#f57c00',
    },
    'molave': {
      'status': 'Endangered',
      'status_code': 'EN',
      'iucn_color': '#f57c00',
    },
    'yakal': {
      'status': 'Vulnerable',
      'status_code': 'VU',
      'iucn_color': '#fbc02d',
    },
    'yakal tree': {
      'status': 'Vulnerable',
      'status_code': 'VU',
      'iucn_color': '#fbc02d',
    },
    'shorea astylosa': {
      'status': 'Vulnerable',
      'status_code': 'VU',
      'iucn_color': '#fbc02d',
    },
    'kamagong': {
      'status': 'Vulnerable',
      'status_code': 'VU',
      'iucn_color': '#fbc02d',
    },
    'lauan': {
      'status': 'Vulnerable',
      'status_code': 'VU',
      'iucn_color': '#fbc02d',
    },
  };

  for (final entry in protectedSpecies.entries) {
    if (name.contains(entry.key)) return entry.value;
  }
  return null;
}

class _DashboardActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _DashboardActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: kBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.035),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: kPrimary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: kPrimary, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: kForeground,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: kMutedFg, size: 16),
          ],
        ),
      ),
    );
  }
}

class _CompactStatsCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color color;
  const _CompactStatsCard({
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(1),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: kMutedFg,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: kForeground,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: kMutedFg, fontSize: 8),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            Container(
              width: 31,
              height: 31,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 17),
            ),
          ],
        ),
      ),
    );
  }
}



class _DashboardSearchResultsPanel extends StatelessWidget {
  final List<TreeModel> results;

  const _DashboardSearchResultsPanel({required this.results});

  @override
  Widget build(BuildContext context) {
    final visible = results.take(6).toList();
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: visible.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'No matching trees found.',
                style: TextStyle(color: kMutedFg, fontSize: 13),
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < visible.length; i++) ...[
                  _DashboardSearchResultTile(tree: visible[i]),
                  if (i != visible.length - 1)
                    const Divider(height: 1, color: kBorder),
                ],
              ],
            ),
    );
  }
}

class _DashboardSearchResultTile extends StatelessWidget {
  final TreeModel tree;

  const _DashboardSearchResultTile({required this.tree});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TreeDetailScreen(treeId: tree.id)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: kPrimary.withOpacity(0.09),
                borderRadius: BorderRadius.circular(11),
              ),
              child:
                  const Icon(Icons.forest_rounded, color: kPrimary, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tree.commonName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    '${tree.scientificName ?? 'Tree record'} - ${tree.barangay ?? 'No barangay'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kMutedFg, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            HealthBadge(tree.healthStatus, small: true),
          ],
        ),
      ),
    );
  }
}

class _CommunityDashboardCards extends StatelessWidget {
  final Map<String, dynamic>? data;
  final List<Map<String, dynamic>> fallbackConservationTrees;
  final VoidCallback onStructureTap;
  final VoidCallback onEndangeredTap;
  const _CommunityDashboardCards({
    required this.data,
    required this.fallbackConservationTrees,
    required this.onStructureTap,
    required this.onEndangeredTap,
  });

  @override
  Widget build(BuildContext context) {
    final distribution = data?['species_distribution'] as List<dynamic>? ?? [];
    final barangays = data?['barangay_breakdown'] as List<dynamic>? ?? [];
    final endpointConservation =
        data?['endangered_trees'] as List<dynamic>? ?? [];
    final endangered = endpointConservation.isNotEmpty
        ? endpointConservation
        : fallbackConservationTrees;

    if (data == null && fallbackConservationTrees.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (endangered.isNotEmpty) ...[
          _CannotCutWarning(count: endangered.length, onTap: onEndangeredTap),
          const SizedBox(height: 12),
        ],
        _SpeciesDistributionCard(distribution: distribution, onTap: onStructureTap),
        const SizedBox(height: 14),
        _BarangayBarCard(barangays: barangays, onTap: onStructureTap),
        const SizedBox(height: 18),
      ],
    );
  }
}

class _CannotCutWarning extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _CannotCutWarning({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.red.shade100),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.warning_amber_rounded,
                  color: Colors.red.shade700, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count protected/vulnerable tree${count == 1 ? '' : 's'} identified',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.red.shade800,
                        fontWeight: FontWeight.w900,
                        fontSize: 11.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Conservation warning active for protected species',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: Colors.red.shade700, fontSize: 9.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeciesDistributionCard extends StatelessWidget {
  final List<dynamic> distribution;
  final VoidCallback onTap;
  const _SpeciesDistributionCard({
    required this.distribution,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final top = distribution.take(5).toList();
    final total = top.fold<int>(
        0, (sum, item) => sum + ((item['count'] as int?) ?? 0));

    return _DashboardChartCard(
      title: 'Species Distribution',
      subtitle: 'Top species share',
      onTap: onTap,
      child: top.isEmpty
          ? const _ChartEmptyText('No species data yet.')
          : Row(
              children: [
                SizedBox(
                  width: 104,
                  height: 104,
                  child: CustomPaint(
                    painter: _PieChartPainter(
                      values: top
                          .map((e) => ((e['count'] as int?) ?? 0).toDouble())
                          .toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    children: top.map((item) {
                      final index = top.indexOf(item);
                      final count = (item['count'] as int?) ?? 0;
                      final percent =
                          total == 0 ? 0 : ((count / total) * 100).round();
                      return _LegendRow(
                        color: _chartColors[index % _chartColors.length],
                        label: '${item['name'] ?? 'Unknown'}',
                        value: '$percent%',
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
    );
  }
}

class _BarangayBarCard extends StatelessWidget {
  final List<dynamic> barangays;
  final VoidCallback onTap;
  const _BarangayBarCard({
    required this.barangays,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final top = barangays.take(6).toList();
    final maxTrees = top.fold<int>(0, (max, row) {
      final count = (row['total_trees'] as int?) ?? 0;
      return count > max ? count : max;
    });

    return _DashboardChartCard(
      title: 'Trees per Barangay',
      subtitle: 'Mapped inventory count',
      onTap: onTap,
      child: top.isEmpty
          ? const _ChartEmptyText('No barangay data yet.')
          : Column(
              children: top.map((row) {
                final count = (row['total_trees'] as int?) ?? 0;
                final ratio = maxTrees == 0 ? 0.0 : count / maxTrees;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 88,
                        child: Text(
                          '${row['barangay'] ?? 'Unknown'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: ratio,
                            minHeight: 12,
                            color: kPrimary,
                            backgroundColor: kMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 28,
                        child: Text('$count',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontSize: 11,
                                color: kMutedFg,
                                fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _DashboardChartCard extends StatelessWidget {
  final String title, subtitle;
  final Widget child;
  final VoidCallback onTap;
  const _DashboardChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: const TextStyle(color: kMutedFg, fontSize: 11)),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label, value;
  const _LegendRow({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          Text(value,
              style: const TextStyle(
                  fontSize: 11, color: kMutedFg, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _ChartEmptyText extends StatelessWidget {
  final String text;
  const _ChartEmptyText(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
          child:
              Text(text, style: const TextStyle(color: kMutedFg, fontSize: 12))),
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final List<double> values;
  _PieChartPainter({required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (sum, value) => sum + value);
    final rect = Offset.zero & size;
    final paint = Paint()..style = PaintingStyle.fill;
    var start = -1.5708;

    if (total <= 0) {
      paint.color = kMuted;
      canvas.drawCircle(size.center(Offset.zero), size.width / 2, paint);
      return;
    }

    for (var i = 0; i < values.length; i++) {
      final sweep = (values[i] / total) * 6.28318;
      paint.color = _chartColors[i % _chartColors.length];
      canvas.drawArc(rect, start, sweep, true, paint);
      start += sweep;
    }

    paint.color = kCard;
    canvas.drawCircle(size.center(Offset.zero), size.width * 0.28, paint);
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) =>
      oldDelegate.values != values;
}

const _chartColors = [
  kPrimary,
  kHealthy,
  kFair,
  Color(0xFF2563EB),
  Color(0xFF9333EA),
  Color(0xFF0891B2),
];



class _HealthBar extends StatelessWidget {

  final String label;

  final int count;

  final int total;

  final Color color;

  const _HealthBar(this.label, this.count, this.total, this.color);



  @override

  Widget build(BuildContext context) {

    final pct = total == 0 ? 0.0 : count / total;

    return Row(children: [

      SizedBox(width: 56,

          child: Text(label,

              style: const TextStyle(fontSize: 12, color: kMutedFg))),

      Expanded(

        child: ClipRRect(

          borderRadius: BorderRadius.circular(4),

          child: LinearProgressIndicator(

            value: pct, minHeight: 8,

            backgroundColor: color.withOpacity(0.12),

            valueColor: AlwaysStoppedAnimation(color),

          ),

        ),

      ),

      const SizedBox(width: 8),

      Text('$count',

          style: TextStyle(fontSize: 12, color: color,

              fontWeight: FontWeight.w600)),

    ]);

  }

}



class _RecentTreeRow extends StatelessWidget {

  final TreeModel tree;

  final VoidCallback onTap;

  const _RecentTreeRow({required this.tree, required this.onTap});



  @override

  Widget build(BuildContext context) {

    return InkWell(

      onTap: onTap,

      borderRadius: BorderRadius.circular(10),

      child: Padding(

        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),

        child: Row(children: [

          TreePhoto(
            url: tree.photoUrl,
            size: 42,
            radius: BorderRadius.circular(10),
          ),

          const SizedBox(width: 12),

          Expanded(child: Column(

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              Text(tree.commonName,

                  style: const TextStyle(

                      fontWeight: FontWeight.w500, fontSize: 13,

                      color: kForeground)),

              if (tree.barangay != null)

                Row(children: [

                  const Icon(Icons.location_on_outlined,

                      size: 11, color: kMutedFg),

                  const SizedBox(width: 2),

                  Text(tree.barangay!,

                      style: const TextStyle(

                          fontSize: 11, color: kMutedFg)),

                ]),

            ],

          )),

          if (tree.carbonKg != null)

            Text('${tree.carbonKg!.toStringAsFixed(1)} kg C',

                style: const TextStyle(fontSize: 11, color: kMutedFg)),

          const SizedBox(width: 8),

          HealthBadge(tree.healthStatus, small: true),

        ]),

      ),

    );

  }

}
