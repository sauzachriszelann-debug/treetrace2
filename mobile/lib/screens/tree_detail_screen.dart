import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/theme.dart';
import '../models/models.dart';
import '../widgets/widgets.dart';

class TreeDetailScreen extends StatefulWidget {
  final int treeId;
  const TreeDetailScreen({super.key, required this.treeId});
  @override
  State<TreeDetailScreen> createState() => _TreeDetailScreenState();
}

class _TreeDetailScreenState extends State<TreeDetailScreen> {
  TreeModel? _tree;
  List<HealthLogModel> _logs = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final t = await api.getPublicTree(widget.treeId.toString());
      List<dynamic> l = [];
      try {
        l = await api.getTreeHealthLogs(widget.treeId);
      } catch (_) {}
      setState(() {
        _tree = TreeModel.fromJson(t);
        _logs = l.map((j) => HealthLogModel.fromJson(j)).toList();
        _loading = false;
      });
    } catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(
      appBar: AppBar(),
      body: const Center(child: CircularProgressIndicator(color: kPrimary)),
    );
    if (_tree == null) return Scaffold(
      appBar: AppBar(),
      body: const EmptyState(message: 'Tree not found'),
    );

    final tree = _tree!;
    return Scaffold(
      body: CustomScrollView(slivers: [
        // ── Photo / header ────────────────────────────────────────────────────
        SliverAppBar(
          expandedHeight: tree.photoUrl != null ? 260 : 120,
          pinned: true,
          backgroundColor: kSidebarBg,
          flexibleSpace: FlexibleSpaceBar(
            titlePadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            title: Text(tree.commonName,
                style: const TextStyle(
                    color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.w700)),
            background: tree.photoUrl != null
                ? Stack(fit: StackFit.expand, children: [
                    Image.network(tree.photoUrl!, fit: BoxFit.cover),
                    Container(decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent,
                          Colors.black.withOpacity(0.65)],
                      ),
                    )),
                  ])
                : Container(color: kSidebarBg),
          ),
        ),

        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name + health badge
              Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tree.commonName, style: GoogleFonts.inter(
                        fontSize: 22, fontWeight: FontWeight.w800,
                        color: kForeground)),
                    if (tree.scientificName != null)
                      Text(tree.scientificName!,
                          style: const TextStyle(
                              fontSize: 14, color: kMutedFg,
                              fontStyle: FontStyle.italic)),
                    Text('ID: ${tree.id}',
                        style: const TextStyle(
                            fontSize: 12, color: kMutedFg)),
                  ],
                )),
                HealthBadge(tree.healthStatus),
              ]),
              const SizedBox(height: 16),

              // Details card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kBorder),
                ),
                child: Column(children: [
                  _infoRow(Icons.location_on_outlined, 'Barangay',
                      tree.barangay),
                  _infoRow(Icons.location_city_outlined, 'City',
                      tree.city),
                  _infoRow(Icons.straighten, 'DBH',
                      tree.dbhCm != null
                          ? '${tree.dbhCm!.toStringAsFixed(1)} cm' : null),
                  _infoRow(Icons.height, 'Height',
                      tree.heightM != null
                          ? '${tree.heightM!.toStringAsFixed(1)} m' : null),
                  _infoRow(Icons.eco_outlined, 'Carbon Stock',
                      tree.carbonKg != null
                          ? '${tree.carbonKg!.toStringAsFixed(2)} kg' : null),
                  _infoRow(Icons.gps_fixed, 'GPS',
                      tree.lat != null
                          ? '${tree.lat!.toStringAsFixed(5)}, ${tree.lng!.toStringAsFixed(5)}'
                          : null),
                  if (tree.notes != null && tree.notes!.isNotEmpty) ...[
                    const Divider(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: kBackground,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(tree.notes!,
                          style: const TextStyle(
                              fontSize: 13, color: kForeground,
                              height: 1.5)),
                    ),
                  ],
                ]),
              ),

              // Health logs
              SectionHeader('Health History',
                action: Text('${_logs.length} records',
                    style: const TextStyle(fontSize: 12, color: kMutedFg))),

              if (_logs.isEmpty)
                const EmptyState(message: 'No health logs yet',
                    icon: Icons.history_outlined)
              else
                ..._logs.map((log) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: kCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kBorder),
                  ),
                  child: Row(children: [
                    Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: healthColor(log.condition).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        log.condition == 'Healthy'
                            ? Icons.check_circle_outline
                            : log.condition == 'Fair'
                                ? Icons.warning_amber_outlined
                                : Icons.cancel_outlined,
                        color: healthColor(log.condition), size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          HealthBadge(log.condition, small: true),
                          const Spacer(),
                          Text(log.assessedDate,
                              style: const TextStyle(
                                  fontSize: 11, color: kMutedFg)),
                        ]),
                        if (log.notes != null && log.notes!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(log.notes!,
                              style: const TextStyle(
                                  fontSize: 12, color: kMutedFg)),
                        ],
                        if (log.dbhCm != null)
                          Text('DBH: ${log.dbhCm!.toStringAsFixed(1)} cm'
                              '${log.heightM != null ? '  ·  H: ${log.heightM!.toStringAsFixed(1)} m' : ''}',
                              style: const TextStyle(
                                  fontSize: 11, color: kMutedFg)),
                      ],
                    )),
                  ]),
                )),
              const SizedBox(height: 24),
            ],
          ),
        )),
      ]),
    );
  }

  Widget _infoRow(IconData icon, String label, String? value) {
    if (value == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(icon, size: 15, color: kMutedFg),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(
            fontSize: 13, color: kMutedFg, fontWeight: FontWeight.w500)),
        const Spacer(),
        Text(value, style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600, color: kForeground)),
      ]),
    );
  }
}
