import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/theme.dart';
import '../models/models.dart';
import '../widgets/widgets.dart';

class HealthLogsScreen extends StatefulWidget {
  const HealthLogsScreen({super.key});
  @override
  State<HealthLogsScreen> createState() => _HealthLogsScreenState();
}

class _HealthLogsScreenState extends State<HealthLogsScreen> {
  List<HealthLogModel> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await api.getHealthLogs(limit: 100);
      setState(() {
        _logs = data.map((j) => HealthLogModel.fromJson(j)).toList();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  int get _healthy => _logs.where((l) => l.condition == 'Healthy').length;
  int get _fair => _logs.where((l) => l.condition == 'Fair').length;
  int get _poor => _logs.where((l) => l.condition == 'Poor').length;

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
              expandedHeight: 162,
              backgroundColor: kSidebarBg,
              title: const Text('Health Logs'),
              actions: [
                IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  color: kSidebarBg,
                  padding: const EdgeInsets.fromLTRB(20, 74, 20, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Text(
                        'TREE MONITORING',
                        style: TextStyle(
                          color: kSidebarPrimary,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_logs.length} assessments',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _HeaderStat('$_healthy healthy', kHealthy),
                          const SizedBox(width: 8),
                          _HeaderStat('$_fair fair', kFair),
                          const SizedBox(width: 8),
                          _HeaderStat('$_poor poor', kPoor),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(color: kPrimary)),
              )
            else if (_logs.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  message: 'No health logs yet',
                  subtitle: 'Health assessments will appear here after field checks.',
                  icon: Icons.history_outlined,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _HealthLogCard(log: _logs[i]),
                    childCount: _logs.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  final String label;
  final Color color;
  const _HeaderStat(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _HealthLogCard extends StatelessWidget {
  final HealthLogModel log;
  const _HealthLogCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final color = healthColor(log.condition);
    final icon = log.condition == 'Healthy'
        ? Icons.check_circle_outline_rounded
        : log.condition == 'Fair'
            ? Icons.warning_amber_rounded
            : Icons.error_outline_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        log.treeCommonName ?? 'Tree',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    HealthBadge(log.condition, small: true),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  log.assessedDate,
                  style: const TextStyle(fontSize: 11, color: kMutedFg),
                ),
                if ((log.dbhCm != null) || (log.heightM != null)) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (log.dbhCm != null) _MiniPill('DBH ${log.dbhCm} cm'),
                      if (log.heightM != null) _MiniPill('Height ${log.heightM} m'),
                    ],
                  ),
                ],
                if (log.notes != null && log.notes!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    log.notes!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: kMutedFg,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  final String label;
  const _MiniPill(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: kMuted,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
      ),
    );
  }
}
