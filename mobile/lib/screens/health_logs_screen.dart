import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_provider.dart';
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
    final canManage = context.read<AuthProvider>().user?.role != 'citizen';
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
                        '${_logs.length} ${_logs.length == 1 ? 'assessment' : 'assessments'}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
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
                    (_, i) => _HealthLogCard(
                      log: _logs[i],
                      canDelete: canManage,
                      onDelete: () => _deleteLog(_logs[i].id),
                    ),
                    childCount: _logs.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteLog(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Health Log?'),
        content: const Text('This health assessment will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kPoor),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await api.deleteHealthLog(id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Health log deleted.'),
          backgroundColor: kHealthy,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not delete health log: $e'),
          backgroundColor: kPoor,
        ));
      }
    }
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
  final bool canDelete;
  final VoidCallback onDelete;
  const _HealthLogCard({
    required this.log,
    required this.canDelete,
    required this.onDelete,
  });

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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
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
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            log.treeCommonName ?? 'Tree',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            log.assessedDate,
                            style: const TextStyle(
                                fontSize: 11, color: kMutedFg),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    HealthBadge(log.condition, small: true),
                    if (canDelete)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: InkWell(
                          onTap: onDelete,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: kPoor.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.delete_outline_rounded,
                                color: kPoor, size: 18),
                          ),
                        ),
                      ),
                  ],
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
