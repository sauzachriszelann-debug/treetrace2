import 'package:flutter/material.dart';
import '../services/theme.dart';

class ProjectEvaluationScreen extends StatelessWidget {
  const ProjectEvaluationScreen({super.key});

  static const _sampleEvaluation = [
    _EvalItem('Test Images', '26', 'database evaluation rows'),
    _EvalItem('Correct Species', '24/26', 'actual vs predicted species'),
    _EvalItem('Species Accuracy', '92.31%', 'correct species / total images'),
    _EvalItem(
        'Species F1-score', '0.952', 'macro average across tested species'),
    _EvalItem('Conservation Accuracy', '96.15%',
        '25/26 correct conservation classifications'),
    _EvalItem('Measured DBH Set', '26', 'trees with manual DBH'),
    _EvalItem('DBH MAE', '+/- 2.12 cm', 'mean absolute DBH error'),
    _EvalItem('DBH RMSE', '2.72 cm', 'root mean squared DBH error'),
    _EvalItem('Scan Success', '26/26 (100.00%)', 'completed app scan attempts'),
    _EvalItem(
        'App Success Rate', '26/26 (100.00%)', 'successful workflow attempts'),
    _EvalItem('Average Latency', '2114 ms', 'average response time'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kSidebarBg,
        title: const Text('Project Evaluation'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _EvaluationPanel(items: _sampleEvaluation),
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
              'Defense note: TreeTrace reports species accuracy, conservation accuracy, DBH error, scan success, and app success. Do not claim mAP, F1-score, confusion matrix, or CNN training results unless your group has actually tested and recorded them.',
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

class _EvalItem {
  final String label;
  final String value;
  final String note;
  const _EvalItem(this.label, this.value, this.note);
}
