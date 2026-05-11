import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/theme.dart';

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
                        'Endangered',
                        '${data['total_endangered'] ?? 0}',
                        Icons.warning_amber_rounded,
                        kPoor,
                      ),
                      _SummaryCard('Barangays', '${barangays.length}',
                          Icons.location_on_outlined, Colors.blue.shade600),
                    ],
                  ),
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
                    _SectionTitle('Endangered Trees - Do Not Cut'),
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
    return Container(
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
                  color: Colors.red.shade700, fontWeight: FontWeight.w900)),
        ],
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
