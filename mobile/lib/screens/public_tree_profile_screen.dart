import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../services/theme.dart';
import '../models/models.dart';
import '../widgets/widgets.dart';

class PublicTreeProfileScreen extends StatefulWidget {
  final int treeId;
  const PublicTreeProfileScreen({super.key, required this.treeId});
  @override
  State<PublicTreeProfileScreen> createState() => _PublicTreeProfileScreenState();
}

class _PublicTreeProfileScreenState extends State<PublicTreeProfileScreen>
    with SingleTickerProviderStateMixin {
  TreeModel? _tree;
  Map<String, dynamic>? _wiki;
  List<HealthLogModel> _logs = [];
  bool _loading = true;
  bool _wikiLoading = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final t = await api.getPublicTree(widget.treeId.toString());
      List<dynamic> l = [];
      try { l = await api.getTreeHealthLogs(widget.treeId); } catch (_) {}
      setState(() {
        _tree = TreeModel.fromJson(t);
        _logs = l.map((j) => HealthLogModel.fromJson(j)).toList();
        _loading = false;
      });
      _loadWiki();
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadWiki() async {
    if (_tree == null) return;
    setState(() => _wikiLoading = true);
    try {
      final wiki = await api.getTreeWiki(widget.treeId);
      setState(() { _wiki = wiki; _wikiLoading = false; });
    } catch (_) {
      setState(() => _wikiLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(
      backgroundColor: kSidebarBg,
      body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(color: Colors.white),
        const SizedBox(height: 12),
        Text('Accessing Encyclopedia...', style: GoogleFonts.inter(color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.w600)),
      ])),
    );

    if (_tree == null) return Scaffold(
      appBar: AppBar(title: const Text('Tree Profile')),
      body: const EmptyState(message: 'Tree not found', icon: Icons.error_outline),
    );

    final tree = _tree!;

    return Scaffold(
      backgroundColor: kBackground,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          _buildSliverHeader(tree),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildOverviewTab(tree),
            _buildCareTab(),
            _buildExploreTab(tree),
            _buildInfoTab(tree),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverHeader(TreeModel tree) {
    return SliverAppBar(
      expandedHeight: 320,
      pinned: true,
      backgroundColor: kSidebarBg,
      foregroundColor: Colors.white,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Hero Photo
            tree.photoUrl != null
                ? CachedNetworkImage(imageUrl: tree.photoUrl!, fit: BoxFit.cover)
                : Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [Color(0xFF1a3323), Color(0xFF2d6b3a)]),
                    ),
                    child: const Icon(Icons.park, color: Colors.white24, size: 80),
                  ),
            
            // Modern Gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.2), Colors.black.withOpacity(0.9)],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),

            // Info Content
            Positioned(
              bottom: 80, left: 24, right: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HealthBadge(tree.healthStatus),
                  const SizedBox(height: 12),
                  Text(tree.commonName, style: GoogleFonts.inter(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
                  if (tree.scientificName != null)
                    Text(tree.scientificName!, style: GoogleFonts.inter(color: Colors.white.withOpacity(0.7), fontSize: 16, fontStyle: FontStyle.italic)),
                ],
              ),
            ),
          ],
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          decoration: const BoxDecoration(
            color: kBackground,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: TabBar(
            controller: _tabController,
            indicatorColor: kPrimary,
            indicatorSize: TabBarIndicatorSize.label,
            labelColor: kPrimary,
            unselectedLabelColor: kMutedFg,
            dividerColor: Colors.transparent,
            labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Care'),
              Tab(text: 'Explore'),
              Tab(text: 'Record'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewTab(TreeModel tree) {
    if (_wikiLoading) return _buildLoading();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildStatsStrip(tree),
        const SizedBox(height: 24),
        if (tree.isProtected || const ['CR', 'EN', 'VU'].contains(tree.statusCode)) ...[
          _PublicConservationWarning(tree: tree),
          const SizedBox(height: 16),
        ],
        _buildTreePhotoGallery(tree),
        const SizedBox(height: 16),
        _buildStoryCard(
          'AI Summary',
          _wiki?['tagline']?.toString() ??
              '${tree.commonName} is part of the TreeTrace public inventory.',
        ),
        const SizedBox(height: 16),
        if (_wiki?['basic_info'] != null)
          _buildWikiSection('🌿 General Description', _wiki!['basic_info']),
        const SizedBox(height: 16),
        if (_wiki?['characteristics'] != null)
          _buildWikiSection('⭐ Characteristics', _wiki!['characteristics']),
        const SizedBox(height: 16),
        _buildCommonProblems(),
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildStatsStrip(TreeModel tree) {
    final carbon = tree.carbonKg ?? _estimateCarbonKg(tree.dbhCm, tree.heightM);
    return Row(
      children: [
        _StatPill(Icons.eco_rounded, '${carbon.toStringAsFixed(1)} kg', 'CO2 Stock'),
        const SizedBox(width: 12),
        _StatPill(Icons.straighten_rounded, '${tree.dbhCm?.toStringAsFixed(0) ?? "0"} cm', 'DBH'),
        const SizedBox(width: 12),
        _StatPill(Icons.height_rounded, '${tree.heightM?.toStringAsFixed(1) ?? "0"} m', 'Height'),
      ],
    );
  }

  Widget _buildWikiSection(String title, Map<String, dynamic> data) {
    final entries = data.entries
        .where((e) => e.value != null && e.value.toString().trim().isNotEmpty)
        .toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(24), border: Border.all(color: kBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 16),
          ...entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 100, child: Text(e.key.replaceAll('_', ' ').toUpperCase(), style: GoogleFonts.inter(color: kMutedFg, fontSize: 10, fontWeight: FontWeight.w800))),
                Expanded(child: Text(e.value.toString(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
              ],
            ),
          )).toList(),
        ],
      ),
    );
  }

  Widget _buildCareTab() {
    if (_wikiLoading) return _buildLoading();
    final care = _wiki?['care_profile'] as Map<String, dynamic>?;
    if (care == null) return _buildEmpty();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Optimal Growth Requirements', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.5,
          children: [
            _CareCard(Icons.wb_sunny_rounded, 'Sunlight', care['sunlight'] ?? 'Partial', Colors.amber),
            _CareCard(Icons.water_drop_rounded, 'Watering', care['watering'] ?? 'Moderate', Colors.blue),
            _CareCard(Icons.layers_rounded, 'Soil Type', care['soil'] ?? 'Loamy', Colors.brown),
            _CareCard(Icons.thermostat_rounded, 'Climate', care['temperature'] ?? 'Tropical', Colors.orange),
          ],
        ),
        const SizedBox(height: 24),
        _buildWikiSection('📖 Maintenance Guide', {
          'Difficulty': care['difficulty'],
          'Fertilizer': care['fertilizer'],
          'Note': care['difficulty_note'],
        }),
        const SizedBox(height: 16),
        _buildHowTos(),
        const SizedBox(height: 16),
        _buildPopularQuestions(),
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildExploreTab(TreeModel tree) {
    if (_wikiLoading) return _buildLoading();
    final uses = _wiki?['uses'] is Map
        ? Map<String, dynamic>.from(_wiki!['uses'])
        : <String, dynamic>{};
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildStoryCard(
          'Name Story',
          _wiki?['name_story']?.toString() ??
              'The name ${tree.commonName} reflects the way people identify this tree in the field.',
        ),
        const SizedBox(height: 16),
        _buildStoryCard(
          'Adaptation Strategies',
          _wiki?['adaptation_strategies']?.toString() ??
              '${tree.commonName} adapts to tropical field conditions through steady root growth and seasonal leaf response.',
        ),
        const SizedBox(height: 16),
        _buildStoryCard(
          'Legends & Symbolism',
          _wiki?['history_and_legends']?.toString() ??
              '${tree.commonName} represents the value of local biodiversity and community tree care.',
        ),
        const SizedBox(height: 16),
        if (uses.isNotEmpty) _buildWikiSection('Ecological Uses', uses),
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildInfoTab(TreeModel tree) {
    final location = _displayLocation(tree);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildWikiSection('🌳 Inventory Record', {
          'Record ID': '#${tree.id}',
          'Health Status': tree.healthStatus,
          'Location': location,
          'Coordinates': '${tree.lat?.toStringAsFixed(5)}, ${tree.lng?.toStringAsFixed(5)}',
          'Last Survey': tree.createdAt == null ? 'Not available' : _formatDate(tree.createdAt!),
        }),
        const SizedBox(height: 16),
        if (tree.notes != null)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: kPrimary.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: kPrimary.withOpacity(0.1))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('FIELD NOTES', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, color: kPrimary, letterSpacing: 1.5)),
                const SizedBox(height: 8),
                Text(tree.notes!, style: const TextStyle(fontSize: 14, height: 1.5)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildHistoryTab(TreeModel tree) {
    final history = _wiki?['history_and_legends'] as String?;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Legends & Symbolism', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(24), border: Border.all(color: kBorder)),
          child: Text(history ?? 'No historical data available for this species.', style: const TextStyle(fontSize: 15, height: 1.8, color: kForeground)),
        ),
        const SizedBox(height: 24),
        if (_logs.isNotEmpty)
          _buildWikiSection('🩺 Health Inspection Log', {
            'Total Inspections': _logs.length.toString(),
            'Recent Condition': _logs.first.condition,
            'Latest Date': _logs.first.assessedDate,
          }),
      ],
    );
  }

  Widget _buildTreePhotoGallery(TreeModel tree) {
    final photos = _similarPhotos(tree);
    if (photos.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Photos of Same Tree', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 12),
        SizedBox(
          height: 170,
          child: PageView.builder(
            controller: PageController(viewportFraction: 0.9),
            itemCount: photos.length,
            itemBuilder: (_, index) => Container(
              margin: const EdgeInsets.only(right: 10),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: kBorder),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: photos[index],
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const Icon(Icons.park_outlined, color: kMutedFg),
                  ),
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(index == 0 ? 'Inventory photo' : 'Similar photo $index',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<String> _similarPhotos(TreeModel tree) {
    final photos = <String>[];
    void add(String? url) {
      final value = url?.trim();
      if (value != null && value.startsWith('http') && !photos.contains(value)) {
        photos.add(value);
      }
    }

    add(tree.photoUrl);
    final wikiPhotos = _wiki?['match_images'];
    if (wikiPhotos is List) {
      for (final item in wikiPhotos) {
        add(item?.toString());
      }
    }
    final name = (tree.scientificName?.trim().isNotEmpty == true
            ? tree.scientificName
            : tree.commonName)
        ?.trim();
    if (name != null && name.isNotEmpty) {
      final encoded = Uri.encodeComponent(name);
      add('https://commons.wikimedia.org/wiki/Special:FilePath/$encoded.jpg');
      add('https://source.unsplash.com/900x600/?$encoded,tree');
    }
    return photos.take(5).toList();
  }

  double _estimateCarbonKg(double? dbhCm, double? heightM) {
    if (dbhCm == null || dbhCm <= 0) return 0;
    final height = heightM != null && heightM > 0 ? heightM : 10.0;
    const woodDensity = 0.6;
    final biomass =
        0.0673 * math.pow(woodDensity * dbhCm * dbhCm * height, 0.976);
    return (biomass * 0.47).toDouble();
  }

  Widget _buildStoryCard(String title, String text) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 10),
          Text(text, style: const TextStyle(fontSize: 14, height: 1.55, color: kForeground)),
        ],
      ),
    );
  }

  Widget _buildCommonProblems() {
    final raw = _wiki?['common_problems'];
    final problems = raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    if (problems.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Common Problems', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 12),
        SizedBox(
          height: 230,
          child: PageView.builder(
            controller: PageController(viewportFraction: 0.9),
            itemCount: problems.length,
            itemBuilder: (_, index) {
              final item = problems[index];
              return _ProblemCard(
                title: item['name']?.toString() ?? 'Common problem',
                description: item['description']?.toString() ?? '',
                severity: item['severity']?.toString() ?? 'Watch',
                imageUrl: item['image_url']?.toString() ?? '',
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHowTos() {
    final raw = _wiki?['how_tos'];
    final items = raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('How Tos', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 12),
        ...items.map((item) {
          final steps = item['steps'] is List ? item['steps'] as List : const [];
          return _GuideCard(
            title: item['title']?.toString() ?? 'Guide',
            body: steps.map((e) => e.toString()).join('\n'),
          );
        }),
      ],
    );
  }

  Widget _buildPopularQuestions() {
    final raw = _wiki?['popular_questions'];
    final items = raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Popular Questions', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 12),
        ...items.map((item) => _GuideCard(
              title: item['q']?.toString() ?? 'Question',
              body: item['a']?.toString() ?? '',
            )),
      ],
    );
  }

  String _displayLocation(TreeModel tree) {
    final parts = [
      if ((tree.barangay ?? '').trim().isNotEmpty) tree.barangay!.trim(),
      if ((tree.city ?? '').trim().isNotEmpty) tree.city!.trim(),
      if ((tree.province ?? '').trim().isNotEmpty) tree.province!.trim(),
    ];
    if (parts.isNotEmpty) return parts.join(', ');
    return _exactLocationFromNotes(tree.notes) ?? 'Location not tagged';
  }

  String? _exactLocationFromNotes(String? notes) {
    if (notes == null) return null;
    for (final line in notes.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.toLowerCase().startsWith('exact location:')) {
        final value = trimmed.substring('exact location:'.length).trim();
        if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
      }
    }
    return null;
  }

  String _formatDate(DateTime date) => '${date.month}/${date.day}/${date.year}';

  Widget _buildLoading() => const Center(child: CircularProgressIndicator(color: kPrimary));
  Widget _buildEmpty() => const EmptyState(message: 'Data unavailable', icon: Icons.info_outline);
}

class _ProblemCard extends StatelessWidget {
  final String title;
  final String description;
  final String severity;
  final String imageUrl;

  const _ProblemCard({
    required this.title,
    required this.description,
    required this.severity,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final color = severity.toLowerCase() == 'high'
        ? kPoor
        : severity.toLowerCase() == 'medium'
            ? kFair
            : kHealthy;
    return Container(
      margin: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: imageUrl.startsWith('http')
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const Icon(Icons.bug_report_outlined, color: kMutedFg),
                  )
                : const Center(child: Icon(Icons.bug_report_outlined, color: kMutedFg)),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(999)),
                      child: Text(severity, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMutedFg, fontSize: 11.5, height: 1.25)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  final String title;
  final String body;

  const _GuideCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(color: kMutedFg, fontSize: 13, height: 1.45)),
        ],
      ),
    );
  }
}

class _PublicConservationWarning extends StatelessWidget {
  final TreeModel tree;

  const _PublicConservationWarning({required this.tree});

  @override
  Widget build(BuildContext context) {
    final code = tree.statusCode;
    final critical = code == 'CR';
    final endangered = code == 'EN';
    final color = critical
        ? kPoor
        : endangered
            ? Colors.orange.shade800
            : Colors.amber.shade800;
    final bg = critical
        ? Colors.red.shade50
        : endangered
            ? Colors.orange.shade50
            : Colors.amber.shade50;
    final title = critical
        ? 'Do not cut: critically endangered'
        : endangered
            ? 'Protected species: cutting prohibited'
            : 'Vulnerable species: handle with care';
    final cuttingRule = tree.cuttingAllowed
        ? 'allowed only with proper permit review'
        : 'strictly prohibited without DENR clearance';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            critical || endangered
                ? Icons.shield_outlined
                : Icons.warning_amber_rounded,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.inter(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 14)),
                const SizedBox(height: 5),
                Text(
                  '${tree.commonName} is listed as ${tree.endangeredStatus}. '
                  'Cutting or transporting this tree is $cuttingRule.',
                  style: const TextStyle(
                      color: kForeground, fontSize: 12.5, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String value, label;
  const _StatPill(this.icon, this.value, this.label);
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: kBorder)),
        child: Column(
          children: [
            Icon(icon, size: 16, color: kPrimary),
            const SizedBox(height: 4),
            Text(value, style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14)),
            Text(label, style: const TextStyle(color: kMutedFg, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _CareCard extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _CareCard(this.icon, this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.1))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
