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
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final data = await api.getHealthLogs(limit: 100);
      setState(() {
        _logs = data.map((j) => HealthLogModel.fromJson(j)).toList();
        _loading = false;
      });
    } catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Health Logs'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _logs.isEmpty
              ? const EmptyState(message: 'No health logs yet',
                  icon: Icons.history_outlined)
              : RefreshIndicator(onRefresh: _load, color: kPrimary,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _logs.length,
                    itemBuilder: (_, i) {
                      final log = _logs[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: kCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kBorder)),
                        child: Row(children: [
                          Container(width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: healthColor(log.condition).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10)),
                            child: Icon(
                              log.condition == 'Healthy' ? Icons.check_circle_outline
                                  : log.condition == 'Fair' ? Icons.warning_amber_outlined
                                  : Icons.cancel_outlined,
                              color: healthColor(log.condition), size: 18)),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Text(log.treeCommonName ?? 'Tree',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              const Spacer(),
                              HealthBadge(log.condition, small: true),
                            ]),
                            const SizedBox(height: 2),
                            Text(log.assessedDate,
                                style: const TextStyle(fontSize: 11, color: kMutedFg)),
                            if (log.notes != null && log.notes!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(log.notes!, style: const TextStyle(fontSize: 12, color: kMutedFg)),
                            ],
                          ])),
                        ]),
                      );
                    },
                  )),
    );
  }
}
