import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/theme.dart';

class ReportsToolsScreen extends StatefulWidget {
  const ReportsToolsScreen({super.key});

  @override
  State<ReportsToolsScreen> createState() => _ReportsToolsScreenState();
}

class _ReportsToolsScreenState extends State<ReportsToolsScreen> {
  final _barangayCtrl = TextEditingController();
  final _healthCtrl = TextEditingController();
  final _limitCtrl = TextEditingController(text: '15');

  List<TreeModel> _trees = [];
  List<TreeModel> _labels = [];
  Map<String, dynamic>? _analytics;
  Map<String, dynamic>? _route;
  bool _loading = true;
  bool _buildingRoute = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _barangayCtrl.dispose();
    _healthCtrl.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final treesRaw = await api.getTrees(limit: 1000);
      final trees = treesRaw.map((e) => TreeModel.fromJson(e)).toList();
      Map<String, dynamic>? analytics = _fallbackAnalytics();
      try {
        final users = await api.getUsers();
        analytics = _buildUserAnalytics(users);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _trees = trees;
        _labels = trees;
        _analytics = analytics;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('Could not load reports data.');
    }
  }

  Map<String, dynamic> _fallbackAnalytics() => {
        'total_users': 0,
        'active_users': 0,
        'ai_identifications_today': 0,
        'by_plan': {'free': 0},
        'business': {
          'pro_users': 0,
          'upgrade_requests': 0,
          'institutional_accounts': 0,
          'estimated_monthly_php': 0,
        },
      };

  Map<String, dynamic> _buildUserAnalytics(List<dynamic> users) {
    final byPlan = <String, int>{};
    final byRole = <String, int>{};
    var active = 0;
    var aiToday = 0;
    var upgrades = 0;
    var pro = 0;
    var institutional = 0;
    for (final raw in users) {
      final user = Map<String, dynamic>.from(raw);
      final plan = '${user['subscription_plan'] ?? 'free'}'.toLowerCase();
      final role = '${user['role'] ?? 'citizen'}'.toLowerCase();
      byPlan[plan] = (byPlan[plan] ?? 0) + 1;
      byRole[role] = (byRole[role] ?? 0) + 1;
      if (user['is_active'] != false) active++;
      aiToday += (user['ai_identifications_today'] as num?)?.toInt() ?? 0;
      if (user['upgrade_requested'] == true) upgrades++;
      if (plan == 'pro') pro++;
      if (plan == 'enterprise' || role == 'admin' || role == 'field_worker') {
        institutional++;
      }
    }
    final monthly = (pro * 99) + (institutional * 399);
    return {
      'total_users': users.length,
      'active_users': active,
      'ai_identifications_today': aiToday,
      'by_plan': byPlan,
      'by_role': byRole,
      'business': {
        'pro_users': pro,
        'upgrade_requests': upgrades,
        'institutional_accounts': institutional,
        'estimated_monthly_php': monthly,
      },
    };
  }

  int get _speciesCount =>
      _trees.map((t) => t.commonName).where((s) => s.trim().isNotEmpty).toSet().length;

  int get _gpsTagged => _trees.where((t) => t.lat != null && t.lng != null).length;

  double get _carbonKg => _trees.fold(0, (sum, t) => sum + (t.carbonKg ?? 0));

  Map<String, int> get _healthSummary {
    final data = <String, int>{};
    for (final tree in _trees) {
      data[tree.healthStatus] = (data[tree.healthStatus] ?? 0) + 1;
    }
    return data;
  }

  Map<String, int> get _barangaySummary {
    final data = <String, int>{};
    for (final tree in _trees) {
      final key = tree.barangay?.trim().isNotEmpty == true ? tree.barangay!.trim() : 'Unspecified';
      data[key] = (data[key] ?? 0) + 1;
    }
    return data;
  }

  String _inventoryCsv() {
    final rows = [
      [
        'ID',
        'Common Name',
        'Scientific Name',
        'Barangay',
        'Health Status',
        'DBH CM',
        'Height M',
        'Carbon KG',
        'Latitude',
        'Longitude',
      ],
      ..._trees.map((t) => [
            t.id,
            t.commonName,
            t.scientificName ?? '',
            t.barangay ?? '',
            t.healthStatus,
            t.dbhCm ?? '',
            t.heightM ?? '',
            t.carbonKg ?? '',
            t.lat ?? '',
            t.lng ?? '',
          ]),
    ];
    return rows.map((row) => row.map(_csvCell).join(',')).join('\n');
  }

  String _reportSummaryText() {
    final health = _healthSummary.entries.map((e) => '${e.key}: ${e.value}').join(', ');
    final barangays = _barangaySummary.entries.map((e) => '${e.key}: ${e.value}').join(', ');
    return '''
TreeTrace Inventory Report
Total Trees: ${_trees.length}
Species Recorded: $_speciesCount
GPS Tagged: $_gpsTagged
Carbon Stored: ${_carbonKg.toStringAsFixed(1)} kg
Health Summary: $health
Barangay Summary: $barangays

Validation Note: DBH and AI-assisted values should be validated through field measurement when used for formal compliance.
'''
        .trim();
  }

  Future<File> _writeReportFile(String fileName, String contents) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    return file.writeAsString(contents, flush: true);
  }

  Future<void> _shareInventoryCsv() async {
    if (_trees.isEmpty) {
      _toast('No tree records yet.');
      return;
    }
    final file = await _writeReportFile('treetrace_inventory.csv', _inventoryCsv());
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      text: 'TreeTrace inventory CSV',
      subject: 'TreeTrace Inventory CSV',
    );
  }

  Future<void> _shareReportSummary() async {
    if (_trees.isEmpty) {
      _toast('No tree records yet.');
      return;
    }
    final file = await _writeReportFile('treetrace_inventory_report.txt', _reportSummaryText());
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/plain')],
      text: 'TreeTrace printable inventory report',
      subject: 'TreeTrace Inventory Report',
    );
  }

  Future<void> _copyQrLabelList() async {
    if (_labels.isEmpty) {
      _toast('No QR labels available yet.');
      return;
    }
    final text = _labels.take(120).map((tree) {
      final name = tree.commonName.isNotEmpty ? tree.commonName : 'Tree';
      final sci = tree.scientificName ?? '';
      final barangay = tree.barangay ?? 'Panabo City';
      final url = '/public/tree/${tree.id}';
      return 'TreeTrace | $name | $sci | ID: ${tree.id} | $barangay | $url';
    }).join('\n');
    final file = await _writeReportFile('treetrace_qr_labels.txt', text);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/plain')],
      text: 'TreeTrace QR label list',
      subject: 'TreeTrace QR Labels',
    );
  }

  Future<void> _buildRoute() async {
    setState(() => _buildingRoute = true);
    try {
      final limit = int.tryParse(_limitCtrl.text.trim()) ?? 15;
      final barangay = _barangayCtrl.text.trim().toLowerCase();
      final health = _healthCtrl.text.trim().toLowerCase();
      final filtered = _trees.where((tree) {
        final hasGps = tree.lat != null && tree.lng != null;
        final barangayOk = barangay.isEmpty || (tree.barangay ?? '').toLowerCase().contains(barangay);
        final healthOk = health.isEmpty || tree.healthStatus.toLowerCase() == health;
        return hasGps && barangayOk && healthOk;
      }).take(limit).toList();
      final stops = <Map<String, dynamic>>[];
      for (var i = 0; i < filtered.length; i++) {
        final tree = filtered[i];
        stops.add({
          'order': i + 1,
          'tree_id': tree.id,
          'common_name': tree.commonName,
          'barangay': tree.barangay,
          'health_status': tree.healthStatus,
          'leg_km': i == 0 ? 0 : 'next',
        });
      }
      final route = {
        'total_stops': stops.length,
        'estimated_distance_km': 'field order',
        'route': stops,
      };
      if (!mounted) return;
      setState(() => _route = route);
    } catch (_) {
      _toast('Could not build route plan.');
    } finally {
      if (mounted) setState(() => _buildingRoute = false);
    }
  }

  String _csvCell(Object? value) {
    final text = '$value'.replaceAll('"', '""');
    return text.contains(',') || text.contains('\n') ? '"$text"' : text;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final business = Map<String, dynamic>.from(_analytics?['business'] ?? {});
    return Scaffold(
      backgroundColor: kBackground,
      body: RefreshIndicator(
        color: kPrimary,
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 154,
              backgroundColor: kSidebarBg,
              title: const Text('Reports & Tools'),
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  color: kSidebarBg,
                  padding: const EdgeInsets.fromLTRB(20, 70, 20, 18),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'Field reporting center',
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Inventory exports, QR labels, business proof, and route planning.',
                        style: TextStyle(color: kSidebarText, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(child: CircularProgressIndicator(color: kPrimary)),
                    )
                  else ...[
                    _MetricGrid(metrics: [
                      _Metric('Total Trees', '${_trees.length}', Icons.forest_rounded, kPrimary),
                      _Metric('Species', '$_speciesCount', Icons.eco_rounded, kHealthy),
                      _Metric('GPS Tagged', '$_gpsTagged', Icons.location_on_rounded, kFair),
                      _Metric('Carbon Stored', '${_carbonKg.toStringAsFixed(1)} kg', Icons.cloud_rounded, kPrimary),
                    ]),
                    const SizedBox(height: 14),
                    _ToolCard(
                      icon: Icons.download_rounded,
                      title: 'Export Reports',
                      subtitle: 'Export files you can open in Sheets, Excel, Drive, or Files.',
                      children: [
                        Row(children: [
                          Expanded(child: _ActionButton(label: 'Open CSV', icon: Icons.table_chart_rounded, onTap: _shareInventoryCsv)),
                          const SizedBox(width: 8),
                          Expanded(child: _ActionButton(label: 'Share Report', icon: Icons.description_rounded, onTap: _shareReportSummary)),
                        ]),
                      ],
                    ),
                    _ToolCard(
                      icon: Icons.qr_code_2_rounded,
                      title: 'QR Printing Layout',
                      subtitle: '${_labels.length} labels ready. Share label text for print layout preparation.',
                      children: [
                        _ActionButton(label: 'Share QR Label List', icon: Icons.print_rounded, onTap: _copyQrLabelList),
                      ],
                    ),
                    _ToolCard(
                      icon: Icons.trending_up_rounded,
                      title: 'Business Model Proof',
                      subtitle: 'Shows the same revenue proof shown on the web reports page.',
                      children: [
                        _MetricGrid(compact: true, metrics: [
                          _Metric('Pro Users', '${business['pro_users'] ?? 0}', Icons.workspace_premium_rounded, kFair),
                          _Metric('Upgrade Requests', '${business['upgrade_requests'] ?? 0}', Icons.upgrade_rounded, kPrimary),
                          _Metric('Institutional', '${business['institutional_accounts'] ?? 0}', Icons.apartment_rounded, kHealthy),
                          _Metric('Monthly PHP', 'PHP ${business['estimated_monthly_php'] ?? 0}', Icons.payments_rounded, kPrimary),
                        ]),
                      ],
                    ),
                    _ToolCard(
                      icon: Icons.people_alt_rounded,
                      title: 'User Analytics',
                      subtitle: 'Admin-only usage and role breakdown.',
                      children: [
                        _MetricGrid(compact: true, metrics: [
                          _Metric('Total Users', '${_analytics?['total_users'] ?? 0}', Icons.groups_rounded, kPrimary),
                          _Metric('Active Users', '${_analytics?['active_users'] ?? 0}', Icons.verified_user_rounded, kHealthy),
                          _Metric('AI Uses Today', '${_analytics?['ai_identifications_today'] ?? 0}', Icons.auto_awesome_rounded, kFair),
                          _Metric('Free Users', '${(_analytics?['by_plan'] ?? {})['free'] ?? 0}', Icons.person_rounded, kMutedFg),
                        ]),
                      ],
                    ),
                    _RoutePlannerCard(
                      barangayCtrl: _barangayCtrl,
                      healthCtrl: _healthCtrl,
                      limitCtrl: _limitCtrl,
                      building: _buildingRoute,
                      route: _route,
                      onBuild: _buildRoute,
                    ),
                    _SummaryCard(title: 'Health Summary', data: _healthSummary),
                    _SummaryCard(title: 'Barangay Summary', data: _barangaySummary),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _Metric(this.label, this.value, this.icon, this.color);
}

class _MetricGrid extends StatelessWidget {
  final List<_Metric> metrics;
  final bool compact;
  const _MetricGrid({required this.metrics, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      crossAxisSpacing: 9,
      mainAxisSpacing: 9,
      childAspectRatio: compact ? 2.05 : 1.95,
      children: metrics.map((m) => _MetricTile(m)).toList(),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final _Metric metric;
  const _MetricTile(this.metric);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: metric.color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(metric.icon, color: metric.color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(metric.value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(metric.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMutedFg, fontSize: 11)),
          ]),
        ),
      ]),
    );
  }
}

class _ToolCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;
  const _ToolCard({required this.icon, required this.title, required this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(18), border: Border.all(color: kBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: kPrimary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: kPrimary, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(color: kMutedFg, fontSize: 12, height: 1.3)),
          ])),
        ]),
        const SizedBox(height: 14),
        ...children,
      ]),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 17),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _RoutePlannerCard extends StatelessWidget {
  final TextEditingController barangayCtrl;
  final TextEditingController healthCtrl;
  final TextEditingController limitCtrl;
  final bool building;
  final Map<String, dynamic>? route;
  final VoidCallback onBuild;
  const _RoutePlannerCard({
    required this.barangayCtrl,
    required this.healthCtrl,
    required this.limitCtrl,
    required this.building,
    required this.route,
    required this.onBuild,
  });

  @override
  Widget build(BuildContext context) {
    final stops = List<Map<String, dynamic>>.from((route?['route'] ?? []).map((e) => Map<String, dynamic>.from(e)));
    return _ToolCard(
      icon: Icons.route_rounded,
      title: 'Field Route Planning',
      subtitle: 'Filter by barangay or health status, then build a visit route.',
      children: [
        TextField(controller: barangayCtrl, decoration: const InputDecoration(labelText: 'Barangay', prefixIcon: Icon(Icons.location_city_rounded))),
        const SizedBox(height: 9),
        TextField(controller: healthCtrl, decoration: const InputDecoration(labelText: 'Health status', hintText: 'Healthy, Fair, Poor', prefixIcon: Icon(Icons.health_and_safety_rounded))),
        const SizedBox(height: 9),
        TextField(controller: limitCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Limit', prefixIcon: Icon(Icons.pin_rounded))),
        const SizedBox(height: 12),
        _ActionButton(label: building ? 'Building...' : 'Build Route', icon: Icons.alt_route_rounded, onTap: building ? () {} : onBuild),
        if (route != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: kBackground, borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${route!['total_stops'] ?? 0} stops | ${route!['estimated_distance_km'] ?? 0} km estimated', style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              ...stops.take(12).map((stop) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('${stop['order']}. ${stop['common_name']} | ${stop['barangay'] ?? 'No barangay'} | ${stop['leg_km']} km', style: const TextStyle(color: kForeground, fontSize: 12)),
                  )),
            ]),
          ),
        ],
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final Map<String, int> data;
  const _SummaryCard({required this.title, required this.data});

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return _ToolCard(
      icon: Icons.summarize_rounded,
      title: title,
      subtitle: 'Breakdown generated from current tree records.',
      children: [
        if (entries.isEmpty)
          const Text('No data available yet.', style: TextStyle(color: kMutedFg))
        else
          ...entries.take(8).map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Expanded(child: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w700))),
                  Text('${entry.value}', style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w900)),
                ]),
              )),
      ],
    );
  }
}
