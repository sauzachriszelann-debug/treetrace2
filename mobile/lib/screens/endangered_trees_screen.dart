import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/theme.dart';
import '../widgets/widgets.dart';
import 'public_tree_profile_screen.dart';
import 'tree_detail_screen.dart';

class EndangeredTreesScreen extends StatefulWidget {
  final bool publicMode;
  final List<dynamic>? initialTrees;

  const EndangeredTreesScreen({
    super.key,
    this.publicMode = false,
    this.initialTrees,
  });

  @override
  State<EndangeredTreesScreen> createState() => _EndangeredTreesScreenState();
}

class _EndangeredTreesScreenState extends State<EndangeredTreesScreen> {
  List<dynamic> _trees = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _trees = widget.initialTrees ?? [];
    if (_trees.isEmpty) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await api.getCommunityStructure();
      setState(() {
        _trees = data['endangered_trees'] as List<dynamic>? ?? [];
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  int? _treeId(dynamic tree) {
    if (tree is! Map) return null;
    final raw = tree['tree_id'] ?? tree['id'];
    if (raw is int) return raw;
    return int.tryParse('$raw');
  }

  void _openTree(dynamic tree) {
    final id = _treeId(tree);
    if (id == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => widget.publicMode
            ? PublicTreeProfileScreen(treeId: id)
            : TreeDetailScreen(treeId: id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: const Text('Conservation Alerts'),
        backgroundColor: kSidebarBg,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: kPrimary,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _trees.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(20),
                    children: const [
                      SizedBox(height: 120),
                      Icon(Icons.verified_outlined,
                          color: kHealthy, size: 42),
                      SizedBox(height: 12),
                      Center(
                        child: Text(
                          'No protected or vulnerable trees found.',
                          style: TextStyle(
                              color: kMutedFg,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: _trees.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _EndangeredTreeTile(
                      tree: _trees[i],
                      onTap: () => _openTree(_trees[i]),
                    ),
                  ),
      ),
    );
  }
}

class _EndangeredTreeTile extends StatelessWidget {
  final dynamic tree;
  final VoidCallback onTap;

  const _EndangeredTreeTile({required this.tree, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final map = tree is Map ? tree as Map : const {};
    final name = '${map['common_name'] ?? 'Unknown Tree'}';
    final scientific = '${map['scientific_name'] ?? ''}';
    final barangay = '${map['barangay'] ?? 'Unknown barangay'}';
    final rawPhotoUrl = map['photo_url'];
    final photoUrl = rawPhotoUrl is String ? rawPhotoUrl.trim() : '';
    final status = '${map['status_code'] ?? map['status'] ?? 'Protected'}';

    return Material(
      color: kCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.red.shade100),
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  TreePhoto(
                    url: photoUrl.isEmpty ? null : photoUrl,
                    size: 54,
                    radius: BorderRadius.circular(14),
                  ),
                  Positioned(
                    right: -3,
                    bottom: -3,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.red.shade100),
                      ),
                      child: Icon(Icons.warning_amber_rounded,
                          color: Colors.red.shade700, size: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: kForeground,
                          fontWeight: FontWeight.w900,
                          fontSize: 14),
                    ),
                    if (scientific.isNotEmpty)
                      Text(
                        scientific,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: kMutedFg, fontSize: 11),
                      ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            color: kMutedFg, size: 13),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            barangay,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: kMutedFg, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.red.shade100),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 11,
                      fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
