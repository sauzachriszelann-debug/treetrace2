import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:treetrace_mobile/screens/public_tree_profile_screen.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_provider.dart';
import '../services/theme.dart';
import '../models/models.dart';
import '../widgets/widgets.dart';
import 'map_screen.dart';
import 'community_structure_screen.dart';
import 'endangered_trees_screen.dart';
import 'planting_recommendations_screen.dart';
import 'profile_screen.dart';

class PublicPortalScreen extends StatefulWidget {
  final VoidCallback? onOpenMap;

  const PublicPortalScreen({
    super.key,
    this.onOpenMap,
  });

  @override
  State<PublicPortalScreen> createState() => _PublicPortalScreenState();
}

class _PublicPortalScreenState extends State<PublicPortalScreen> {
  List<TreeModel> _trees = [];
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _plantingSuggestions = [];
  List<dynamic> _reviewedUnknown = [];
  bool _loading = true;
  String _search = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final treeData = await api.getPublicTrees();
      final statsData = await api.getCommunityStructure();
      final plantingData = await api.getPlantingSuggestions();
      List<dynamic> reviewedUnknown = [];
      try {
        final mine = await api.getMyUnknownSpecies();
        reviewedUnknown =
            mine.where((item) => item['reviewed'] == true).toList();
      } catch (_) {}
      setState(() {
        _trees = treeData.map((j) => TreeModel.fromJson(j)).toList();
        _stats = statsData;
        _plantingSuggestions = (plantingData['suggestions'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _reviewedUnknown = reviewedUnknown;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  List<TreeModel> get _filtered => _search.isEmpty
      ? _trees
      : _trees
          .where((t) =>
              t.commonName.toLowerCase().contains(_search.toLowerCase()) ||
              (t.scientificName
                      ?.toLowerCase()
                      .contains(_search.toLowerCase()) ??
                  false) ||
              (t.barangay?.toLowerCase().contains(_search.toLowerCase()) ??
                  false))
          .toList();

  void _showReviewedUnknownSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Reviewed Submissions',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              ..._reviewedUnknown.take(5).map((item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: kMuted,
                      child: Icon(Icons.check_circle_outline, color: kPrimary),
                    ),
                    title: Text(
                      '${item['identified_as'] ?? item['possible_name'] ?? 'Unknown species'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: const Text('Expert review completed'),
                    onTap: () => Navigator.pop(context),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final totalTrees = _stats?['total_trees'] ?? _trees.length;
    final totalSpecies = _stats?['total_species'] ?? 0;
    final endangeredCount = _stats?['total_endangered'] ?? 0;
    final searching = _search.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: kBackground,
      body: RefreshIndicator(
        onRefresh: _load,
        color: kPrimary,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            _buildSliverHeader(user),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSearchBar(),
                    if (searching) ...[
                      const SizedBox(height: 8),
                      _buildSearchResultsPanel(),
                    ],
                    const SizedBox(height: 12),
                    _buildPlantingPreview(),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _StatCard('Total Trees', '$totalTrees',
                            Icons.analytics_outlined, kPrimary),
                        const SizedBox(width: 10),
                        _StatCard('Species', '$totalSpecies',
                            Icons.eco_outlined, Colors.teal),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (endangeredCount > 0)
                      _buildEndangeredAlert(endangeredCount),
                    const SizedBox(height: 24),
                    _buildSectionHeader('Public Tree Map', 'Open Map',
                        onTap: _openMap),
                    const SizedBox(height: 16),
                    _buildMapCard(height: 220),
                    const SizedBox(height: 32),
                    if (_search.isEmpty) ...[
                      _buildBiodiversityInsights(),
                      const SizedBox(height: 32),
                    ],
                    if (_search.isEmpty && _trees.isNotEmpty) ...[
                      _buildSectionHeader('Priority Conservation', 'Map View',
                          onTap: _openMap),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 200,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemCount: _trees.take(5).length,
                          itemBuilder: (_, i) => _FeaturedTreeCard(
                            tree: _trees[i],
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    PublicTreeProfileScreen(treeId: _trees[i].id),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                    if (!searching) ...[
                      _buildSectionHeader(
                        'Urban Forest Inventory',
                        '${_filtered.length} entries',
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: LoadingList(),
                ),
              )
            else if (!searching)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => TreeListItem(
                      tree: _filtered[i],
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              PublicTreeProfileScreen(treeId: _filtered[i].id),
                        ),
                      ),
                    ),
                    childCount: _filtered.length,
                  ),
                ),
              )
            else
              const SliverToBoxAdapter(
                child: SizedBox(height: 100),
              ),
          ],
        ),
      ),
    );
  }

  void _openMap() {
    if (widget.onOpenMap != null) {
      widget.onOpenMap!();
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => const MapScreen()));
  }

  void _openFullReport() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CommunityStructureScreen()),
    );
  }

  void _openPlanting() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlantingRecommendationsScreen()),
    );
  }

  Widget _buildPlantingPreview() {
    final suggestions = _plantingSuggestions.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Suggested Plants', 'Open', onTap: _openPlanting),
        const SizedBox(height: 12),
        if (suggestions.isEmpty)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openPlanting,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kSidebarBg,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.eco_outlined,
                        color: kSidebarPrimary, size: 28),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Add user suggested plants for your area',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: kSidebarPrimary),
                  ],
                ),
              ),
            ),
          )
        else
          SizedBox(
            height: 178,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: suggestions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, index) => _PlantingSuggestionCard(
                item: suggestions[index],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBiodiversityInsights() {
    if (_stats == null) return const SizedBox.shrink();

    final breakdown = _stats!['barangay_breakdown'] as List<dynamic>? ?? [];
    final distribution = _stats!['species_distribution'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Ecosystem Insights', 'Full Report',
            onTap: _openFullReport),
        const SizedBox(height: 16),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: breakdown.take(5).length,
            itemBuilder: (context, index) {
              final b = breakdown[index];
              return _BarangayDiversityCard(
                name: b['barangay'],
                shannon: b['shannon_index'].toString(),
                count: b['total_trees'].toString(),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: kBorder),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Top Species Distribution',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 20),
              ...distribution.take(3).map((s) {
                final total = _trees.length;
                final count = s['count'] as int;
                final ratio = total > 0 ? count / total : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(s['name'],
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700)),
                          Text('$count trees',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: kMutedFg,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: ratio,
                          backgroundColor: kBackground,
                          color: kPrimary,
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSliverHeader(dynamic user) {
    return SliverAppBar(
      expandedHeight: 145,
      pinned: true,
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
                _CitizenNotificationButton(
                  reviewedCount: _reviewedUnknown.length,
                  plantingCount: _plantingSuggestions.length,
                  onReviewed: _showReviewedUnknownSheet,
                  onPlanting: _openPlanting,
                ),
                const SizedBox(width: 8),
                _ProfileHeaderButton(user: user),
              ],
            ),
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1a3323), Color(0xFF243d2c)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'BIODIVERSITY PORTAL',
                          style: TextStyle(
                            color: kSidebarPrimary,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Hello, ${user?.fullName.split(' ').first ?? 'Explorer'}!',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Panabo City Digital Tree Inventory',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.6), fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEndangeredAlert(int count) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const EndangeredTreesScreen(publicMode: true),
          ),
        ),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orange.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.orange, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$count protected/vulnerable trees identified in the latest survey.',
                  style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.orange, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _search = v),
        decoration: InputDecoration(
          hintText: 'Search by species name, location, or tag...',
          prefixIcon: const Icon(Icons.search_rounded, color: kPrimary),
          suffixIcon: _search.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, color: kMutedFg),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _search = '');
                  },
                ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _buildSearchResultsPanel() {
    final results = _filtered.take(6).toList();
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: results.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'No matching trees found.',
                style: TextStyle(color: kMutedFg, fontSize: 13),
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < results.length; i++) ...[
                  _SearchResultTile(
                    tree: results[i],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            PublicTreeProfileScreen(treeId: results[i].id),
                      ),
                    ),
                  ),
                  if (i != results.length - 1)
                    const Divider(height: 1, color: kBorder),
                ],
              ],
            ),
    );
  }

  Widget _buildMapCard({double height = 280}) {
    final mappedTrees =
        _trees.where((t) => t.lat != null && t.lng != null).toList();

    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 6),
          )
        ],
        border: Border.all(color: kBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            if (mappedTrees.isNotEmpty)
              FlutterMap(
                options: MapOptions(
                  initialCenter: LatLng(
                    mappedTrees.first.lat ?? 7.3047,
                    mappedTrees.first.lng ?? 125.6856,
                  ),
                  initialZoom: 13,
                  minZoom: 2,
                  maxZoom: 22,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.treetrace.mobile',
                    maxNativeZoom: 19,
                  ),
                  MarkerLayer(
                    markers: mappedTrees.take(20).map((tree) {
                      final color = healthColor(tree.healthStatus);
                      return Marker(
                        point: LatLng(tree.lat!, tree.lng!),
                        width: 32,
                        height: 32,
                        child: Container(
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                  color: color.withOpacity(0.4), blurRadius: 6)
                            ],
                          ),
                          child: const Icon(Icons.park,
                              color: Colors.white, size: 14),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              )
            else
              Container(
                color: kBackground,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.location_off_rounded,
                          size: 40, color: kMutedFg.withOpacity(0.5)),
                      const SizedBox(height: 8),
                      Text(
                        'No GPS data available',
                        style: TextStyle(
                            color: kMutedFg.withOpacity(0.6), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: true,
                child: Container(
                  height: 76,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.68),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Interactive Tree Map',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${mappedTrees.length} trees with location',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: _openMap,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.arrow_forward_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String action, {VoidCallback? onTap}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
              fontSize: 16, fontWeight: FontWeight.w800, color: kForeground),
        ),
        GestureDetector(
          onTap: onTap,
          child: Text(
            action,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: kPrimary),
          ),
        ),
      ],
    );
  }
}

class _ProfileHeaderButton extends StatelessWidget {
  final dynamic user;
  const _ProfileHeaderButton({required this.user});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      ),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: kSidebarPrimary, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.14),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Text(
            user?.fullName?.isNotEmpty == true
                ? user.fullName[0].toUpperCase()
                : '?',
            style: const TextStyle(
              color: kPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlantingSuggestionCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _PlantingSuggestionCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final name = item['species_name']?.toString() ?? 'Suggested plant';
    final area = item['recommended_area']?.toString() ?? 'Recommended area';
    final reason = item['area_reason']?.toString() ??
        item['reason']?.toString() ??
        'Recommended for local canopy balance.';
    final photo = _firstSuggestionPhoto(item, name);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showExplorePlantDetail(
          context,
          imageUrl: photo,
          title: name,
          subtitle: area,
          description: reason,
        ),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 210,
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CachedNetworkImage(
                imageUrl: photo,
                height: 82,
                width: double.infinity,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  height: 82,
                  color: kPrimary.withOpacity(0.08),
                  child: const Icon(Icons.eco_outlined, color: kPrimary),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      area,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: kPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: kMutedFg,
                        fontSize: 10.5,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _firstSuggestionPhoto(Map<String, dynamic> item, String name) {
  final images = item['image_urls'];
  if (images is List && images.isNotEmpty) {
    final first = images.first.toString();
    if (first.isNotEmpty) return first;
  }
  return 'https://tse1.mm.bing.net/th?q=${Uri.encodeComponent('$name tree seedling')}';
}

void _showExplorePlantDetail(
  BuildContext context, {
  required String imageUrl,
  required String title,
  required String subtitle,
  required String description,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.42,
      maxChildSize: 0.92,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: kBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Text(
              subtitle,
              style: const TextStyle(
                color: kPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                height: 260,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  height: 260,
                  color: kPrimary.withOpacity(0.08),
                  child: const Icon(
                    Icons.eco_outlined,
                    color: kPrimary,
                    size: 48,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              description,
              style: const TextStyle(
                color: kForeground,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CitizenNotificationButton extends StatelessWidget {
  final int reviewedCount;
  final int plantingCount;
  final VoidCallback onReviewed;
  final VoidCallback onPlanting;
  const _CitizenNotificationButton({
    required this.reviewedCount,
    required this.plantingCount,
    required this.onReviewed,
    required this.onPlanting,
  });

  @override
  Widget build(BuildContext context) {
    final total = reviewedCount + plantingCount;
    return InkWell(
      onTap: () {
        if (reviewedCount > 0 && plantingCount == 0) {
          onReviewed();
        } else if (plantingCount > 0 && reviewedCount == 0) {
          onPlanting();
        } else if (total > 0) {
          _showCitizenNotificationMenu(context);
        }
      },
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        width: 34,
        height: 34,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Icon(
                total > 0
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
                color: total > 0 ? kSidebarPrimary : Colors.white,
                size: 21,
              ),
            ),
            if (total > 0)
              Positioned(
                top: 1,
                right: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: kPoor,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: kSidebarBg, width: 1.2),
                  ),
                  child: Text(
                    '$total',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showCitizenNotificationMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Notifications',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: 10),
              if (reviewedCount > 0)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: kMuted,
                    child: Icon(Icons.science_outlined, color: kPrimary),
                  ),
                  title: Text('$reviewedCount expert review update'),
                  subtitle: const Text('View reviewed unknown submissions'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(context);
                    onReviewed();
                  },
                ),
              if (plantingCount > 0)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: kMuted,
                    child: Icon(Icons.eco_outlined, color: kPrimary),
                  ),
                  title: Text('$plantingCount suggested plants available'),
                  subtitle: const Text('Open planting recommendations'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(context);
                    onPlanting();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final TreeModel tree;
  final VoidCallback onTap;

  const _SearchResultTile({
    required this.tree,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
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
              child: const Icon(Icons.park_rounded, color: kPrimary, size: 20),
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

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorder),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(height: 8),
            Text(value,
                style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: kForeground)),
            Text(label,
                style: const TextStyle(
                    fontSize: 9,
                    color: kMutedFg,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2)),
          ],
        ),
      ),
    );
  }
}

class _BarangayDiversityCard extends StatelessWidget {
  final String name, shannon, count;
  const _BarangayDiversityCard(
      {required this.name, required this.shannon, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name,
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: kForeground),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const Spacer(),
          const Text('Shannon H\'',
              style: TextStyle(
                  color: kMutedFg, fontSize: 10, fontWeight: FontWeight.w800)),
          Text(shannon,
              style: const TextStyle(
                  color: kPrimary, fontSize: 18, fontWeight: FontWeight.w900)),
          Text('$count trees',
              style: const TextStyle(
                  color: kMutedFg, fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _FeaturedTreeCard extends StatelessWidget {
  final TreeModel tree;
  final VoidCallback onTap;
  const _FeaturedTreeCard({required this.tree, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 4))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              tree.photoUrl != null
                  ? CachedNetworkImage(imageUrl: tree.photoUrl!, fit: BoxFit.cover)
                  : Container(
                      color: kPrimary.withOpacity(0.1),
                      child:
                          const Icon(Icons.park, color: kPrimary, size: 40)),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                  ),
                ),
              ),
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tree.commonName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(tree.barangay ?? 'Panabo',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.7), fontSize: 10)),
                  ],
                ),
              ),
              Positioned(
                  top: 12,
                  right: 12,
                  child: HealthBadge(tree.healthStatus, small: true)),
            ],
          ),
        ),
      ),
    );
  }
}
