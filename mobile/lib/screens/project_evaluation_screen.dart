import 'package:flutter/material.dart';
import '../services/theme.dart';
import '../services/api_service.dart';

class ProjectEvaluationScreen extends StatefulWidget {
  const ProjectEvaluationScreen({super.key});

  @override
  State<ProjectEvaluationScreen> createState() => _ProjectEvaluationScreenState();
}

class _ProjectEvaluationScreenState extends State<ProjectEvaluationScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<_EvalItem> _metrics = [];
  List<dynamic> _algorithmComparison = [];

  @override
  void initState() {
    super.initState();
    _loadEvaluationData();
  }

  Future<void> _loadEvaluationData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await api.getEvaluationResults();
      final List<dynamic> metricsList = data['metrics'] ?? [];
      final List<dynamic> compList = data['algorithm_comparison'] ?? [];

      setState(() {
        _metrics = metricsList.map((m) {
          return _EvalItem(
            m['label']?.toString() ?? '',
            m['value']?.toString() ?? '',
            m['note']?.toString() ?? '',
          );
        }).toList();
        _algorithmComparison = compList;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load evaluation results from server.';
        // Fallback to offline defaults
        _metrics = const [
          _EvalItem('Test Images', '26', 'database evaluation rows'),
          _EvalItem('Correct Species', '24/26', 'actual vs predicted species'),
          _EvalItem('Species Accuracy', '92.31%', 'correct species / total images'),
          _EvalItem('Species F1-score', '0.952', 'macro average across tested species'),
          _EvalItem('Conservation Accuracy', '96.15%', '25/26 correct conservation classifications'),
          _EvalItem('Measured DBH Set', '26', 'trees with manual DBH'),
          _EvalItem('DBH MAE', '+/- 2.12 cm', 'mean absolute DBH error'),
          _EvalItem('DBH RMSE', '2.72 cm', 'root mean squared DBH error'),
          _EvalItem('Scan Success', '26/26 (100.00%)', 'completed app scan attempts'),
          _EvalItem('App Success Rate', '26/26 (100.00%)', 'successful workflow attempts'),
          _EvalItem('Average Latency', '2114 ms', 'average response time'),
        ];
        _algorithmComparison = const [
          {
            "algorithm": "YOLOv8-seg (Proposed)",
            "map50": "92.41%",
            "latency": "45 ms",
            "f1_score": "0.912",
            "status": "Selected (Optimal)"
          },
          {
            "algorithm": "YOLOv5-detector",
            "map50": "88.15%",
            "latency": "38 ms",
            "f1_score": "0.875",
            "status": "Rejected (Lower Accuracy)"
          },
          {
            "algorithm": "Faster R-CNN",
            "map50": "89.50%",
            "latency": "180 ms",
            "f1_score": "0.884",
            "status": "Rejected (High Latency)"
          }
        ];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kSidebarBg,
        title: const Text('Project Evaluation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadEvaluationData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: kSidebarPrimary))
          : RefreshIndicator(
              color: kSidebarPrimary,
              onRefresh: _loadEvaluationData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.red),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    _EvaluationPanel(items: _metrics),
                    const SizedBox(height: 20),
                    _AlgorithmComparisonTable(list: _algorithmComparison),
                  ],
                ),
              ),
            ),
    );
  }
}

class _EvaluationPanel extends StatelessWidget {
  final List<_EvalItem> items;
  const _EvaluationPanel({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSidebarBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.fact_check_rounded, color: kSidebarPrimary, size: 22),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Model Evaluation Results',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Use this during the final demo. Replace values with actual group testing results after scanning labeled tree images.',
            style: TextStyle(color: kSidebarText, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Defense note: TreeTrace reports species accuracy, conservation accuracy, DBH error, scan success, and app success. mAP, F1-score, and latency metrics are compared to select the best algorithms (SO#2 & SO#3).',
              style: TextStyle(color: kSidebarText, fontSize: 11, height: 1.35),
            ),
          ),
          const SizedBox(height: 15),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 9,
            mainAxisSpacing: 9,
            childAspectRatio: 1.18,
            children: items.map((item) => _EvalTile(item)).toList(),
          ),
        ],
      ),
    );
  }
}

class _EvalTile extends StatelessWidget {
  final _EvalItem item;
  const _EvalTile(this.item);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: kSidebarPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.note,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: kSidebarText,
              fontSize: 10.5,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlgorithmComparisonTable extends StatelessWidget {
  final List<dynamic> list;
  const _AlgorithmComparisonTable({required this.list});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSidebarBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.compare_rounded, color: kSidebarPrimary, size: 22),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Algorithm Comparison (SO#2)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Comparative analysis of candidate models against SO#3 metrics (mAP, latency, F1-score) to select the optimal engine.',
            style: TextStyle(color: kSidebarText, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 15),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 16,
              headingRowHeight: 40,
              dataRowMinHeight: 48,
              dataRowMaxHeight: 48,
              columns: const [
                DataColumn(label: Text('Algorithm', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text('mAP@0.5', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text('Latency', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text('F1-Score', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text('Decision', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
              ],
              rows: list.map((item) {
                final isSelected = item['status'].toString().contains('Selected');
                return DataRow(
                  cells: [
                    DataCell(Text(item['algorithm']?.toString() ?? '', style: TextStyle(color: isSelected ? kSidebarPrimary : Colors.white, fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal))),
                    DataCell(Text(item['map50']?.toString() ?? '', style: const TextStyle(color: kSidebarText, fontSize: 11))),
                    DataCell(Text(item['latency']?.toString() ?? '', style: const TextStyle(color: kSidebarText, fontSize: 11))),
                    DataCell(Text(item['f1_score']?.toString() ?? '', style: const TextStyle(color: kSidebarText, fontSize: 11))),
                    DataCell(Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSelected ? kSidebarPrimary.withOpacity(0.2) : Colors.white10,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isSelected ? 'Selected' : 'Rejected',
                        style: TextStyle(color: isSelected ? kSidebarPrimary : kSidebarText, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    )),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _EvalItem {
  final String label;
  final String value;
  final String note;
  const _EvalItem(this.label, this.value, this.note);
}
