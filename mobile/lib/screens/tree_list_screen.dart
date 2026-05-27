import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/theme.dart';
import '../models/models.dart';
import '../widgets/widgets.dart';
import 'tree_detail_screen.dart';
import 'add_tree_screen.dart';

class TreeListScreen extends StatefulWidget {
  const TreeListScreen({super.key});
  @override
  State<TreeListScreen> createState() => _TreeListScreenState();
}

class _TreeListScreenState extends State<TreeListScreen> {
  List<TreeModel> _all = [];
  List<TreeModel> _filtered = [];
  bool _loading = true;
  String _search = '';
  String _status = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await api.getTrees(limit: 500);
      setState(() {
        _all = data.map((j) => TreeModel.fromJson(j)).toList();
        _loading = false;
      });
      _filter();
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _filter() {
    setState(() {
      _filtered = _all.where((t) {
        final q = _search.toLowerCase();
        final matchesSearch = q.isEmpty ||
            t.commonName.toLowerCase().contains(q) ||
            (t.scientificName?.toLowerCase().contains(q) ?? false) ||
            (t.barangay?.toLowerCase().contains(q) ?? false);
        final matchesHealth = _status == 'all' || t.healthStatus == _status;
        return matchesSearch && matchesHealth;
      }).toList();
    });
  }

  int get _mappedCount => _all.where((t) => t.lat != null && t.lng != null).length;
  int get _attentionCount =>
      _all.where((t) => t.healthStatus == 'Fair' || t.healthStatus == 'Poor').length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: RefreshIndicator(
        onRefresh: _load,
        color: kPrimary,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 170,
              backgroundColor: kSidebarBg,
              title: const Text('Tree Inventory'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AddTreeScreen()),
                    );
                    _load();
                  },
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  padding: const EdgeInsets.fromLTRB(20, 76, 20, 18),
                  color: kSidebarBg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Text(
                        'FIELD RECORDS',
                        style: TextStyle(
                          color: kSidebarPrimary,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_all.length} trees recorded',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _HeaderPill('$_mappedCount mapped'),
                          const SizedBox(width: 8),
                          _HeaderPill('$_attentionCount need attention'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                child: Column(
                  children: [
                    _SearchBox(
                      onChanged: (value) {
                        _search = value;
                        _filter();
                      },
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          for (final s in ['all', 'Healthy', 'Fair', 'Poor'])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _StatusChip(
                                label: s == 'all' ? 'All Trees' : s,
                                selected: _status == s,
                                color: s == 'Healthy'
                                    ? kHealthy
                                    : s == 'Fair'
                                        ? kFair
                                        : s == 'Poor'
                                            ? kPoor
                                            : kPrimary,
                                onTap: () {
                                  _status = s;
                                  _filter();
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          '${_filtered.length} results',
                          style: const TextStyle(
                            color: kMutedFg,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          'Tap a tree for details',
                          style: TextStyle(color: kMutedFg, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: LoadingList(),
                ),
              )
            else if (_filtered.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  message: 'No trees found',
                  subtitle:
                      _search.isNotEmpty ? 'Try a different search.' : 'Add your first tree record.',
                  icon: Icons.forest_outlined,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => TreeListItem(
                      tree: _filtered[i],
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TreeDetailScreen(treeId: _filtered[i].id),
                          ),
                        );
                        _load();
                      },
                    ),
                    childCount: _filtered.length,
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddTreeScreen()),
          );
          _load();
        },
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Tree'),
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  final String label;
  const _HeaderPill(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: kSidebarText,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  final ValueChanged<String> onChanged;
  const _SearchBox({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        onChanged: onChanged,
        decoration: const InputDecoration(
          hintText: 'Search name, species, or barangay...',
          prefixIcon: Icon(Icons.search_rounded, color: kPrimary),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _StatusChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : color.withOpacity(0.09),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? color : color.withOpacity(0.28)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : color,
          ),
        ),
      ),
    );
  }
}
