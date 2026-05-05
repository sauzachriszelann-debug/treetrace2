import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final data = await api.getTrees(limit: 500);
      setState(() {
        _all = data.map((j) => TreeModel.fromJson(j)).toList();
        _loading = false;
        _filter();
      });
    } catch (_) { setState(() => _loading = false); }
  }

  void _filter() {
    setState(() {
      _filtered = _all.where((t) {
        final q = _search.toLowerCase();
        final ms = q.isEmpty ||
            t.commonName.toLowerCase().contains(q) ||
            (t.scientificName?.toLowerCase().contains(q) ?? false) ||
            (t.barangay?.toLowerCase().contains(q) ?? false);
        final mh = _status == 'all' || t.healthStatus == _status;
        return ms && mh;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tree Inventory'),
            Text('${_all.length} trees recorded',
                style: TextStyle(
                    fontSize: 12,
                    color: kSidebarText.withOpacity(0.65),
                    fontWeight: FontWeight.w400)),
          ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AddTreeScreen()));
              _load();
            },
          ),
        ],
      ),
      body: Column(children: [
        // ── Search + filter bar ───────────────────────────────────────────────
        Container(
          color: kCard,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(children: [
            // Search
            TextField(
              onChanged: (v) { _search = v; _filter(); },
              decoration: InputDecoration(
                hintText: 'Search by name, species, barangay…',
                prefixIcon: const Icon(Icons.search,
                    size: 18, color: kMutedFg),
                filled: true, fillColor: kBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            // Status chips
            Row(children: [
              for (final s in ['all', 'Healthy', 'Fair', 'Poor'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _StatusChip(
                    label: s == 'all' ? 'All' : s,
                    selected: _status == s,
                    color: s == 'Healthy' ? kHealthy
                        : s == 'Fair' ? kFair
                        : s == 'Poor' ? kPoor
                        : kPrimary,
                    onTap: () { _status = s; _filter(); },
                  ),
                ),
            ]),
          ]),
        ),

        // ── Count ─────────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(children: [
            Text('${_filtered.length} trees found',
                style: const TextStyle(fontSize: 12, color: kMutedFg)),
          ]),
        ),

        // ── List ──────────────────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Padding(padding: EdgeInsets.all(16),
                  child: LoadingList())
              : _filtered.isEmpty
                  ? EmptyState(
                      message: 'No trees found',
                      subtitle: _search.isNotEmpty
                          ? 'Try a different search'
                          : 'Add your first tree',
                      icon: Icons.forest_outlined)
                  : RefreshIndicator(
                      onRefresh: _load, color: kPrimary,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) => TreeListItem(
                          tree: _filtered[i],
                          onTap: () async {
                            await Navigator.push(context,
                                MaterialPageRoute(builder: (_) =>
                                    TreeDetailScreen(
                                        treeId: _filtered[i].id)));
                            _load();
                          },
                        ),
                      ),
                    ),
        ),
      ]),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _StatusChip({required this.label, required this.selected,
    required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? color : color.withOpacity(0.25)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w500,
                color: selected ? Colors.white : color)),
      ),
    );
  }
}
