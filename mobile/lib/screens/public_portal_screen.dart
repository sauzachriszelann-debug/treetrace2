import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:treetrace_mobile/screens/public_tree_profile_screen.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_provider.dart';
import '../services/theme.dart';
import '../models/models.dart';
import '../widgets/widgets.dart';

class PublicPortalScreen extends StatefulWidget {
  const PublicPortalScreen({super.key});
  @override
  State<PublicPortalScreen> createState() => _PublicPortalScreenState();
}

class _PublicPortalScreenState extends State<PublicPortalScreen> {
  List<TreeModel> _trees = [];
  Map<String, dynamic>? _stats;
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final treeData = await api.getPublicTrees();
      final statsData = await api.getCommunityStructure();
      setState(() {
        _trees = treeData.map((j) => TreeModel.fromJson(j)).toList();
        _stats = statsData;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  List<TreeModel> get _filtered => _search.isEmpty
      ? _trees
      : _trees.where((t) =>
          t.commonName.toLowerCase().contains(_search.toLowerCase()) ||
          (t.scientificName?.toLowerCase().contains(_search.toLowerCase()) ?? false) ||
          (t.barangay?.toLowerCase().contains(_search.toLowerCase()) ?? false)).toList();

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final totalTrees = _stats?['total_trees'] ?? _trees.length;
    final totalSpecies = _stats?['total_species'] ?? 0;
    final endangeredCount = _stats?['total_endangered'] ?? 0;

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
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Primary Dashboard Stats ────────────────────────────────
                    Row(
                      children: [
                        _StatCard('Total Trees', '$totalTrees', Icons.analytics_outlined, kPrimary),
                        const SizedBox(width: 12),
                        _StatCard('Species', '$totalSpecies', Icons.eco_outlined, Colors.teal),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (endangeredCount > 0) _buildEndangeredAlert(endangeredCount),

                    const SizedBox(height: 32),
                    _buildSearchBar(),
                    const SizedBox(height: 32),

                    // ── Biodiversity Dashboard ────────────────────────────────
                    if (_search.isEmpty) ...[
                      _buildBiodiversityInsights(),
                      const SizedBox(height: 32),
                    ],

                    // ── Featured Collections ──────────────────────────────────
                    if (_search.isEmpty && _trees.isNotEmpty) ...[
                      _buildSectionHeader('Priority Conservation', 'Map View'),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 200,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemCount: _trees.take(5).length,
                          itemBuilder: (_, i) => _FeaturedTreeCard(
                            tree: _trees[i],
                            onTap: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => PublicTreeProfileScreen(treeId: _trees[i].id))),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],

                    // ── Species Inventory ─────────────────────────────────────
                    _buildSectionHeader(_search.isEmpty ? 'Urban Forest Inventory' : 'Search Results', '${_filtered.length} entries'),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            if (_loading)
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(20), child: LoadingList()))
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => TreeListItem(
                      tree: _filtered[i],
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => PublicTreeProfileScreen(treeId: _filtered[i].id))),
                    ),
                    childCount: _filtered.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBiodiversityInsights() {
    if (_stats == null) return const SizedBox.shrink();
    
    final breakdown = _stats!['barangay_breakdown'] as List<dynamic>? ?? [];
    final distribution = _stats!['species_distribution'] as List<dynamic>? ?? [];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Ecosystem Insights', 'Full Report'),
        const SizedBox(height: 16),
        
        // Horizontal scroll for Barangay Diversity (Shannon Index)
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
        
        // Species Distribution Progress Bars
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: kBorder),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Top Species Distribution', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
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
                          Text(s['name'], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          Text('$count trees', style: const TextStyle(fontSize: 11, color: kMutedFg, fontWeight: FontWeight.w600)),
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
      expandedHeight: 180,
      pinned: true,
      backgroundColor: kSidebarBg,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF1a3323), Color(0xFF243d2c)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text('BIODIVERSITY PORTAL',
                      style: TextStyle(color: kSidebarPrimary, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                  const SizedBox(height: 4),
                  Text('Hello, ${user?.fullName.split(' ').first ?? 'Explorer'}! 🌿',
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                  Text('Panabo City Digital Tree Inventory',
                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEndangeredAlert(int count) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text('$count Endangered trees identified in the latest survey.',
                style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: TextField(
        onChanged: (v) => setState(() => _search = v),
        decoration: InputDecoration(
          hintText: 'Search by species name, location, or tag...',
          prefixIcon: const Icon(Icons.search_rounded, color: kPrimary),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String action) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: kForeground)),
        Text(action, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kPrimary)),
      ],
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kBorder),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 12),
            Text(value, style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800, color: kForeground)),
            Text(label, style: const TextStyle(fontSize: 10, color: kMutedFg, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}

class _BarangayDiversityCard extends StatelessWidget {
  final String name, shannon, count;
  const _BarangayDiversityCard({required this.name, required this.shannon, required this.count});

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
          Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: kForeground), maxLines: 1, overflow: TextOverflow.ellipsis),
          const Spacer(),
          const Text('Shannon H\'', style: TextStyle(color: kMutedFg, fontSize: 10, fontWeight: FontWeight.w800)),
          Text(shannon, style: const TextStyle(color: kPrimary, fontSize: 18, fontWeight: FontWeight.w900)),
          Text('$count trees', style: const TextStyle(color: kMutedFg, fontSize: 10, fontWeight: FontWeight.w600)),
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
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              tree.photoUrl != null
                  ? CachedNetworkImage(imageUrl: tree.photoUrl!, fit: BoxFit.cover)
                  : Container(color: kPrimary.withOpacity(0.1), child: const Icon(Icons.park, color: kPrimary, size: 40)),
              Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(0.8)]))),
              Positioned(
                bottom: 16, left: 16, right: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tree.commonName, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(tree.barangay ?? 'Panabo', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10)),
                  ],
                ),
              ),
              Positioned(top: 12, right: 12, child: HealthBadge(tree.healthStatus, small: true)),
            ],
          ),
        ),
      ),
    );
  }
}
