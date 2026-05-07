import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';

import 'package:provider/provider.dart';

import '../services/api_service.dart';

import '../services/auth_provider.dart';

import '../services/theme.dart';

import '../models/models.dart';

import '../widgets/widgets.dart';

import 'tree_detail_screen.dart';



class DashboardScreen extends StatefulWidget {

  const DashboardScreen({super.key});

  @override

  State<DashboardScreen> createState() => _DashboardScreenState();

}



class _DashboardScreenState extends State<DashboardScreen> {

  List<TreeModel> _trees = [];

  List<HealthLogModel> _logs = [];

  bool _loading = true;



  @override

  void initState() { super.initState(); _load(); }



  Future<void> _load() async {

    try {

      final t = await api.getTrees(limit: 200);

      final l = await api.getHealthLogs(limit: 50);

      setState(() {

        _trees = t.map((j) => TreeModel.fromJson(j)).toList();

        _logs = l.map((j) => HealthLogModel.fromJson(j)).toList();

        _loading = false;

      });

    } catch (_) { setState(() => _loading = false); }

  }



  @override

  Widget build(BuildContext context) {

    final user = context.watch<AuthProvider>().user;

    final healthy = _trees.where((t) => t.healthStatus == 'Healthy').length;

    final fair = _trees.where((t) => t.healthStatus == 'Fair').length;

    final poor = _trees.where((t) => t.healthStatus == 'Poor').length;

    final carbon = _trees.fold<double>(0, (s, t) => s + (t.carbonKg ?? 0));

    final gps = _trees.where((t) => t.lat != null).length;



    return Scaffold(

      backgroundColor: kBackground,

      body: RefreshIndicator(

        onRefresh: _load, color: kPrimary,

        child: CustomScrollView(slivers: [

// ── App bar matching sidebar green ─────────────────────────────────

          SliverAppBar(

            pinned: true,

            expandedHeight: 130,

            backgroundColor: kSidebarBg,

            flexibleSpace: FlexibleSpaceBar(

              background: Container(

                color: kSidebarBg,

                padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),

                child: Column(

                  crossAxisAlignment: CrossAxisAlignment.start,

                  mainAxisAlignment: MainAxisAlignment.end,

                  children: [

                    Text(

                      'Welcome back, ${user?.fullName.split(' ').first ?? 'User'}',

                      style: TextStyle(

                          color: kSidebarText.withOpacity(0.7),

                          fontSize: 13),

                    ),

                    const SizedBox(height: 2),

                    Text('TreeTrace Geo-Spatial Inventory',

                        style: GoogleFonts.inter(

                            color: Colors.white, fontSize: 18,

                            fontWeight: FontWeight.w700)),

                  ],

                ),

              ),

            ),

          ),



          SliverToBoxAdapter(

            child: Padding(

              padding: const EdgeInsets.all(16),

              child: Column(

                crossAxisAlignment: CrossAxisAlignment.start,

                children: [

// ── Stats grid (2x2) ─────────────────────────────────────

                  GridView.count(

                    crossAxisCount: 2, shrinkWrap: true,

                    physics: const NeverScrollableScrollPhysics(),

                    crossAxisSpacing: 10, mainAxisSpacing: 10,

                    childAspectRatio: 1.55,

                    children: [

                      StatsCard(title: 'Total Trees',

                          value: '${_trees.length}',

                          icon: Icons.park, color: kPrimary),

                      StatsCard(title: 'Healthy',

                          value: '$healthy',

                          icon: Icons.eco, color: kHealthy),

                      StatsCard(title: 'Need Attention',

                          value: '${fair + poor}',

                          subtitle: '$fair Fair, $poor Poor',

                          icon: Icons.warning_amber_rounded, color: kFair),

                      StatsCard(title: 'Carbon Stock',

                          value: '${(carbon / 1000).toStringAsFixed(2)} t',

                          subtitle: 'Total CO₂ equivalent',

                          icon: Icons.cloud_outlined,

                          color: Colors.blue.shade600),

                    ],

                  ),



// ── Health distribution bar ───────────────────────────────

                  SectionHeader('Health Distribution'),

                  Container(

                    padding: const EdgeInsets.all(16),

                    decoration: BoxDecoration(

                      color: kCard,

                      borderRadius: BorderRadius.circular(14),

                      border: Border.all(color: kBorder),

                    ),

                    child: Column(children: [

                      _HealthBar('Healthy', healthy, _trees.length, kHealthy),

                      const SizedBox(height: 10),

                      _HealthBar('Fair', fair, _trees.length, kFair),

                      const SizedBox(height: 10),

                      _HealthBar('Poor', poor, _trees.length, kPoor),

                      const SizedBox(height: 12),

                      Row(

                        mainAxisAlignment: MainAxisAlignment.spaceBetween,

                        children: [

                          Text('$gps GPS tagged',

                              style: const TextStyle(

                                  fontSize: 12, color: kMutedFg)),

                          Text('${_trees.isEmpty ? 0 : (gps / _trees.length * 100).round()}% mapped',

                              style: const TextStyle(

                                  fontSize: 12, color: kMutedFg)),

                        ],

                      ),

                    ]),

                  ),



// ── Recent entries ────────────────────────────────────────

                  SectionHeader('Recent Entries',

                    action: TextButton(

                      onPressed: () {},

                      child: const Text('View all',

                          style: TextStyle(color: kPrimary, fontSize: 13)),

                    ),

                  ),



                  if (_loading)

                    const LoadingList(count: 3)

                  else if (_trees.isEmpty)

                    const EmptyState(

                        message: 'No trees recorded yet',

                        subtitle: 'Tap + to add your first tree')

                  else

                    ..._trees.take(5).map((t) => Padding(

                      padding: const EdgeInsets.only(bottom: 0),

                      child: _RecentTreeRow(

                        tree: t,

                        onTap: () => Navigator.push(context,

                            MaterialPageRoute(

                                builder: (_) =>

                                    TreeDetailScreen(treeId: t.id))),

                      ),

                    )),



// ── Recent health logs ────────────────────────────────────

                  if (_logs.isNotEmpty) ...[

                    SectionHeader('Recent Health Assessments'),

                    ..._logs.take(5).map((log) => Container(

                      margin: const EdgeInsets.only(bottom: 8),

                      padding: const EdgeInsets.symmetric(

                          horizontal: 14, vertical: 12),

                      decoration: BoxDecoration(

                        color: kMuted,

                        borderRadius: BorderRadius.circular(12),

                      ),

                      child: Row(children: [

                        Expanded(child: Column(

                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [

                            Text(log.treeCommonName ?? 'Tree',

                                style: const TextStyle(

                                    fontWeight: FontWeight.w600,

                                    fontSize: 13)),

                            Text('${log.assessedDate} · ${log.assessedBy ?? ''}',

                                style: const TextStyle(

                                    fontSize: 11, color: kMutedFg)),

                          ],

                        )),

                        HealthBadge(log.condition, small: true),

                      ]),

                    )),

                  ],

                  const SizedBox(height: 24),

                ],

              ),

            ),

          ),

        ]),

      ),

    );

  }

}



class _HealthBar extends StatelessWidget {

  final String label;

  final int count;

  final int total;

  final Color color;

  const _HealthBar(this.label, this.count, this.total, this.color);



  @override

  Widget build(BuildContext context) {

    final pct = total == 0 ? 0.0 : count / total;

    return Row(children: [

      SizedBox(width: 56,

          child: Text(label,

              style: const TextStyle(fontSize: 12, color: kMutedFg))),

      Expanded(

        child: ClipRRect(

          borderRadius: BorderRadius.circular(4),

          child: LinearProgressIndicator(

            value: pct, minHeight: 8,

            backgroundColor: color.withOpacity(0.12),

            valueColor: AlwaysStoppedAnimation(color),

          ),

        ),

      ),

      const SizedBox(width: 8),

      Text('$count',

          style: TextStyle(fontSize: 12, color: color,

              fontWeight: FontWeight.w600)),

    ]);

  }

}



class _RecentTreeRow extends StatelessWidget {

  final TreeModel tree;

  final VoidCallback onTap;

  const _RecentTreeRow({required this.tree, required this.onTap});



  @override

  Widget build(BuildContext context) {

    return InkWell(

      onTap: onTap,

      borderRadius: BorderRadius.circular(10),

      child: Padding(

        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),

        child: Row(children: [

          Container(

            width: 36, height: 36,

            decoration: BoxDecoration(

              color: kPrimary.withOpacity(0.08),

              borderRadius: BorderRadius.circular(8),

            ),

            child: const Icon(Icons.park_outlined,

                color: kPrimary, size: 18),

          ),

          const SizedBox(width: 12),

          Expanded(child: Column(

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              Text(tree.commonName,

                  style: const TextStyle(

                      fontWeight: FontWeight.w500, fontSize: 13,

                      color: kForeground)),

              if (tree.barangay != null)

                Row(children: [

                  const Icon(Icons.location_on_outlined,

                      size: 11, color: kMutedFg),

                  const SizedBox(width: 2),

                  Text(tree.barangay!,

                      style: const TextStyle(

                          fontSize: 11, color: kMutedFg)),

                ]),

            ],

          )),

          if (tree.carbonKg != null)

            Text('${tree.carbonKg!.toStringAsFixed(1)} kg C',

                style: const TextStyle(fontSize: 11, color: kMutedFg)),

          const SizedBox(width: 8),

          HealthBadge(tree.healthStatus, small: true),

        ]),

      ),

    );

  }

}
