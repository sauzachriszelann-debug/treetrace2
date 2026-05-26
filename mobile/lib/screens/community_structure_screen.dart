import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/theme.dart';
import 'tree_detail_screen.dart';

class CommunityStructureScreen extends StatefulWidget {
  const CommunityStructureScreen({super.key});

  @override
  State<CommunityStructureScreen> createState() =>
      _CommunityStructureScreenState();
}

class _CommunityStructureScreenState extends State<CommunityStructureScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await api.getCommunityStructure();
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data ?? {};
    final distribution = data['species_distribution'] as List<dynamic>? ?? [];
    final barangays = data['barangay_breakdown'] as List<dynamic>? ?? [];
    final endangered = data['endangered_trees'] as List<dynamic>? ?? [];

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: const Text('Community Structure'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: kPrimary,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: kPrimary))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Biodiversity analysis and species distribution across Panabo City',
                    style: TextStyle(color: kMutedFg, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.55,
                    children: [
                      _SummaryCard('Total Trees',
                          '${data['total_trees'] ?? 0}', Icons.park, kPrimary),
                      _SummaryCard('Species',
                          '${data['total_species'] ?? 0}', Icons.eco, kHealthy),
                      _SummaryCard(
                        'Conservation',
                        '${data['total_endangered'] ?? 0}',
                        Icons.warning_amber_rounded,
                        kPoor,
                      ),
                      _SummaryCard('Barangays', '${barangays.length}',
                          Icons.location_on_outlined, Colors.blue.shade600),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _CommunityPieCard(distribution: distribution),
                  const SizedBox(height: 14),
                  _CommunityBarCard(barangays: barangays),
                  const SizedBox(height: 22),
                  _SectionTitle('Top Species Distribution'),
                  const SizedBox(height: 10),
                  _Panel(
                    child: distribution.isEmpty
                        ? const _EmptyLine('No species data yet.')
                        : Column(
                            children: distribution.take(8).map((item) {
                              final count = item['count'] as int? ?? 0;
                              final total = data['total_trees'] as int? ?? 0;
                              final ratio = total == 0 ? 0.0 : count / total;
                              return _ProgressRow(
                                label: '${item['name'] ?? 'Unknown'}',
                                value: '$count trees',
                                ratio: ratio,
                              );
                            }).toList(),
                          ),
                  ),
                  const SizedBox(height: 22),
                  _SectionTitle('Barangay Biodiversity'),
                  const SizedBox(height: 10),
                  ...barangays.map((row) => _BarangayCard(row)),
                  if (endangered.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    _SectionTitle('Protected / Vulnerable Trees'),
                    const SizedBox(height: 10),
                    ...endangered.map((tree) => _EndangeredCard(tree)),
                  ],
                  const SizedBox(height: 28),
                ],
              ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title, value;
  final IconData icon;
  final Color color;
  const _SummaryCard(this.title, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w900)),
                Text(title,
                    style: const TextStyle(color: kMutedFg, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: child,
    );
  }
}

class _CommunityPieCard extends StatelessWidget {
  final List<dynamic> distribution;
  const _CommunityPieCard({required this.distribution});

  @override
  Widget build(BuildContext context) {
    final top = distribution.take(5).toList();
    final total = top.fold<int>(
        0, (sum, item) => sum + ((item['count'] as int?) ?? 0));
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Species Distribution',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          const SizedBox(height: 14),
          if (top.isEmpty)
            const _EmptyLine('No species data yet.')
          else
            Row(
              children: [
                SizedBox(
                  width: 110,
                  height: 110,
                  child: CustomPaint(
                    painter: _CommunityPiePainter(
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
                      return _CommunityLegend(
                        color: _communityChartColors[
                            index % _communityChartColors.length],
                        label: '${item['name'] ?? 'Unknown'}',
                        value: '$percent%',
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CommunityBarCard extends StatelessWidget {
  final List<dynamic> barangays;
  const _CommunityBarCard({required this.barangays});

  @override
  Widget build(BuildContext context) {
    final top = barangays.take(6).toList();
    final maxTrees = top.fold<int>(0, (max, row) {
      final count = (row['total_trees'] as int?) ?? 0;
      return count > max ? count : max;
    });
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Trees per Barangay',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          const SizedBox(height: 14),
          if (top.isEmpty)
            const _EmptyLine('No barangay data yet.')
          else
            ...top.map((row) {
              final count = (row['total_trees'] as int?) ?? 0;
              final ratio = maxTrees == 0 ? 0.0 : count / maxTrees;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text('${row['barangay'] ?? 'Unknown'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700)),
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
                    Text('$count',
                        style: const TextStyle(
                            color: kMutedFg,
                            fontSize: 11,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _CommunityLegend extends StatelessWidget {
  final Color color;
  final String label, value;
  const _CommunityLegend({
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

class _CommunityPiePainter extends CustomPainter {
  final List<double> values;
  _CommunityPiePainter({required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (sum, value) => sum + value);
    final rect = Offset.zero & size;
    final paint = Paint()..style = PaintingStyle.fill;
    var start = -1.5708;
    if (total <= 0) return;
    for (var i = 0; i < values.length; i++) {
      final sweep = (values[i] / total) * 6.28318;
      paint.color = _communityChartColors[i % _communityChartColors.length];
      canvas.drawArc(rect, start, sweep, true, paint);
      start += sweep;
    }
    paint.color = kCard;
    canvas.drawCircle(size.center(Offset.zero), size.width * 0.28, paint);
  }

  @override
  bool shouldRepaint(covariant _CommunityPiePainter oldDelegate) =>
      oldDelegate.values != values;
}

const _communityChartColors = [
  kPrimary,
  kHealthy,
  kFair,
  Color(0xFF2563EB),
  Color(0xFF9333EA),
  Color(0xFF0891B2),
];

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900));
  }
}

class _ProgressRow extends StatelessWidget {
  final String label, value;
  final double ratio;
  const _ProgressRow({
    required this.label,
    required this.value,
    required this.ratio,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800)),
              ),
              Text(value,
                  style: const TextStyle(color: kMutedFg, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio.clamp(0, 1),
              color: kPrimary,
              backgroundColor: kMuted,
              minHeight: 7,
            ),
          ),
        ],
      ),
    );
  }
}

class _BarangayCard extends StatelessWidget {
  final dynamic row;
  const _BarangayCard(this.row);

  @override
  Widget build(BuildContext context) {
    final topSpecies = row['top_species'] as List<dynamic>? ?? [];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${row['barangay'] ?? 'Unknown Barangay'}',
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MiniMetric('${row['total_trees'] ?? 0}', 'trees'),
              _MiniMetric('${row['species_count'] ?? 0}', 'species'),
              _MiniMetric('${row['endangered_count'] ?? 0}', 'endangered'),
              _MiniMetric('${row['shannon_index'] ?? 0}', 'shannon'),
            ],
          ),
          if (topSpecies.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Top: ${topSpecies.map((s) => s['name']).join(', ')}',
              style: const TextStyle(color: kMutedFg, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final String value, label;
  const _MiniMetric(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: kMuted,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$value $label',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _EndangeredCard extends StatelessWidget {
  final dynamic tree;
  const _EndangeredCard(this.tree);

  @override
  Widget build(BuildContext context) {
    final rawId = tree is Map ? tree['tree_id'] ?? tree['id'] : null;
    final treeId = rawId is int ? rawId : int.tryParse('$rawId');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: treeId == null
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TreeDetailScreen(treeId: treeId),
                  ),
                ),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.shade100),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${tree['common_name'] ?? 'Unknown Tree'}',
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text('${tree['scientific_name'] ?? ''}',
                        style: const TextStyle(color: kMutedFg, fontSize: 11)),
                  ],
                ),
              ),
              Text('${tree['status'] ?? ''}',
                  style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w900)),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.red.shade700, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  final String text;
  const _EmptyLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
          child:
              Text(text, style: const TextStyle(color: kMutedFg, fontSize: 12))),
    );
  }
}
