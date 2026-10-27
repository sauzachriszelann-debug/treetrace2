import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/theme.dart';

/// G5: official metrics come ONLY from the backend's validated, versioned
/// evaluation artifacts. This screen contains no local numbers: with no
/// committed run it renders "Not yet evaluated" instead of placeholders.
typedef EvaluationLoader = Future<Map<String, dynamic>> Function();

const _notEvaluatedTitle = 'Not yet evaluated';

String _fmtPercent(num? value) =>
    value == null ? 'Not evaluated' : '${(value * 100).toStringAsFixed(2)}%';

String _fmtNumber(num? value, [int digits = 3]) =>
    value == null ? 'Not evaluated' : value.toStringAsFixed(digits);

String _fmtInt(num? value) => value == null ? '—' : value.round().toString();

String _shortHash(String? value) {
  if (value == null || value.isEmpty) return '—';
  return value.length > 12 ? '${value.substring(0, 12)}…' : value;
}

num? _asNum(Object? value) => value is num ? value : null;

class ProjectEvaluationScreen extends StatefulWidget {
  const ProjectEvaluationScreen({super.key, this.loadResults});

  /// Test seam. Production falls back to the real /evaluation/results API.
  final EvaluationLoader? loadResults;

  @override
  State<ProjectEvaluationScreen> createState() =>
      _ProjectEvaluationScreenState();
}

class _ProjectEvaluationScreenState extends State<ProjectEvaluationScreen> {
  late final Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = (widget.loadResults ?? (() => api.getEvaluationResults()))();
  }

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
        child: Container(
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
                'Official metrics are produced only by the offline evaluation runner over a frozen, '
                'independently labeled test manifest, and are served only from validated artifacts. '
                'Prediction confidence is the model’s self-report, not a measured accuracy.',
                style: TextStyle(color: kSidebarText, fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 12),
              FutureBuilder<Map<String, dynamic>>(
                future: _future,
                builder: (context, snapshot) => _buildBody(snapshot),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── State-based rendering ────────────────────────────────────────────────

  Widget _buildBody(AsyncSnapshot<Map<String, dynamic>> snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: CircularProgressIndicator(color: kSidebarPrimary),
        ),
      );
    }
    if (snapshot.hasError) {
      return _noteBox(
        color: Colors.amber,
        children: [
          _boxTitle('Could not load evaluation results.',
              Icons.warning_amber_rounded, Colors.amber),
          const SizedBox(height: 6),
          Text(
            '${snapshot.error ?? 'The evaluation API is unavailable.'} '
            'No numbers are shown when results cannot be loaded.',
            style: const TextStyle(color: kSidebarText, fontSize: 12, height: 1.35),
          ),
        ],
      );
    }

    final results = snapshot.data;
    if (results == null) {
      return _noteBox(color: Colors.amber, children: [
        _boxTitle('Could not load evaluation results.',
            Icons.warning_amber_rounded, Colors.amber),
        const SizedBox(height: 6),
        const Text(
          'The evaluation API returned no data. No numbers are shown when '
          'results cannot be loaded.',
          style: TextStyle(color: kSidebarText, fontSize: 12, height: 1.35),
        ),
      ]);
    }

    final state = (results['state'] ?? 'unknown').toString();
    final run = results['run'] as Map<String, dynamic>?;
    final fieldRows = results['field_rows'] as Map<String, dynamic>?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStateSection(state, results, run),
        if (fieldRows != null) ...[
          const SizedBox(height: 12),
          _buildFieldRows(fieldRows),
        ],
      ],
    );
  }

  Widget _buildStateSection(
    String state,
    Map<String, dynamic> results,
    Map<String, dynamic>? run,
  ) {
    if (state == 'not_evaluated') {
      return _noteBox(color: kSidebarText, children: [
        const Text(
          _notEvaluatedTitle,
          style: TextStyle(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          (results['reason'] ?? '').toString().isEmpty
              ? 'No committed evaluation run exists yet.'
              : results['reason'].toString(),
          style: const TextStyle(color: kSidebarText, fontSize: 12, height: 1.35),
        ),
        const SizedBox(height: 6),
        const Text(
          'A run is produced by backend/scripts/evaluate_species.py over the '
          'frozen test manifest and appears here only after it is validated '
          'and committed. Placeholder numbers are never shown.',
          style: TextStyle(color: kSidebarText, fontSize: 12, height: 1.35),
        ),
      ]);
    }

    if (state == 'invalid_artifact') {
      final issues =
          (results['issues'] as List?)?.map((e) => e.toString()).toList() ??
              const <String>[];
      return _noteBox(
        color: kPoor,
        children: [
          _boxTitle('The newest evaluation artifact failed validation.',
              Icons.error_outline, kPoor),
          const SizedBox(height: 6),
          Text(
            '${results['reason'] ?? ''} No metrics are shown instead of '
            'falling back to older numbers.',
            style: const TextStyle(color: kSidebarText, fontSize: 12, height: 1.35),
          ),
          for (final issue in issues) ...[
            const SizedBox(height: 4),
            Text('• $issue',
                style: const TextStyle(
                    color: kSidebarText, fontSize: 11.5, height: 1.3)),
          ],
        ],
      );
    }

    if ((state == 'evaluated' || state == 'unavailable') && run != null) {
      return _buildRunSection(run);
    }

    return _noteBox(color: kSidebarText, children: [
      Text(
        'Unknown evaluation state "$state".',
        style: const TextStyle(
            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 6),
      const Text(
        'No metrics are shown for an unrecognized response.',
        style: TextStyle(color: kSidebarText, fontSize: 12, height: 1.35),
      ),
    ]);
  }

  Widget _buildRunSection(Map<String, dynamic> run) {
    final runState = (run['state'] ?? '').toString();
    final metrics = run['metrics'] as Map<String, dynamic>? ?? const {};
    final species = metrics['species'] as Map<String, dynamic>?;
    final conservation = metrics['conservation'] as Map<String, dynamic>?;
    final dbh = metrics['dbh'] as Map<String, dynamic>?;
    final latency = metrics['latency_ms'] as Map<String, dynamic>?;
    final reliability =
        metrics['confidence_reliability'] as Map<String, dynamic>?;
    final confusion = run['confusion_matrix'] as Map<String, dynamic>?;
    final dataset = run['dataset'] as Map<String, dynamic>? ?? const {};
    final model = run['model'] as Map<String, dynamic>? ?? const {};
    final environment = run['environment'] as Map<String, dynamic>? ?? const {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Provenance ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _provenanceLine('Run', '${run['run_id'] ?? '—'}'),
              _provenanceLine('Pipeline', '${model['pipeline'] ?? '—'}'),
              _provenanceLine('Dataset', '${dataset['name'] ?? '—'}'),
              _provenanceLine('Manifest', _shortHash(dataset['manifest_sha256'] as String?)),
              _provenanceLine('Commit', _shortHash(environment['git_commit'] as String?)),
              _provenanceLine('Finished', '${environment['finished_at'] ?? '—'}'),
              _provenanceLine(
                  'External API calls',
                  environment['external_api_calls'] == true ? 'yes' : 'no'),
              _provenanceLine(
                  'Local TFLite model present',
                  model['local_tflite_present'] == true ? 'yes' : 'no'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (runState != 'evaluated')
          _noteBox(color: kSidebarText, children: [
            Text(
              'This run is marked "$runState": no metrics are displayed for it.',
              style: const TextStyle(color: kSidebarText, fontSize: 12.5, height: 1.35),
            ),
          ])
        else ...[
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 9,
            mainAxisSpacing: 9,
            childAspectRatio: 1.35,
            children: [
              _metricTile(
                label:
                    'Species accuracy (n=${_fmtInt(species?['n_scoreable'])})',
                value: _speciesAccuracyValue(species),
                note: 'coverage ${_fmtPercent(_asNum(species?['coverage']))} '
                    'of ${_fmtInt(_asNum(species?['n_total']))} images',
              ),
              _metricTile(
                label: 'F1 (per-class averages)',
                value:
                    'macro ${_fmtNumber(_asNum(species?['macro_f1']))} / weighted '
                    '${_fmtNumber(_asNum(species?['weighted_f1']))}',
                note: '${_fmtInt(_asNum(species?['n_classes']))} classes, '
                    '${_fmtInt(_asNum(species?['n_low_support']))} low-support '
                    '(<${_fmtInt(_asNum(species?['low_support_threshold']) ?? 5)})',
              ),
              _metricTile(
                label:
                    'Conservation accuracy (n=${_fmtInt(_asNum(conservation?['n_scoreable']))})',
                value: _fmtPercent(_asNum(conservation?['accuracy'])),
                note: _conservationCiNote(conservation),
              ),
              _metricTile(
                label: 'DBH error (n=${_fmtInt(_asNum(dbh?['n']))})',
                value: _asNum(dbh?['n']) == null || _asNum(dbh?['n']) == 0
                    ? 'No measured DBH in run'
                    : 'MAE ${_fmtNumber(_asNum(dbh?['mae_cm']), 2)} cm',
                note: _asNum(dbh?['n']) == null || _asNum(dbh?['n']) == 0
                    ? 'MAE/RMSE not defined for n=0'
                    : 'RMSE ${_fmtNumber(_asNum(dbh?['rmse_cm']), 2)} cm · bias '
                        '${_fmtNumber(_asNum(dbh?['bias_cm']), 2)} cm '
                        '(${dbh?['pipeline'] ?? 'pipeline n/a'})',
              ),
              _metricTile(
                label: 'Latency (n=${_fmtInt(_asNum(latency?['n']))})',
                value: _asNum(latency?['n']) == null || _asNum(latency?['n']) == 0
                    ? 'No latency samples'
                    : 'p50 ${_fmtInt(_asNum(latency?['p50_ms']))} ms',
                note: _asNum(latency?['n']) == null || _asNum(latency?['n']) == 0
                    ? '—'
                    : 'mean ${_fmtInt(_asNum(latency?['mean_ms']))} ms · p95 '
                        '${_fmtInt(_asNum(latency?['p95_ms']))} ms',
              ),
              _metricTile(
                label: 'Abstentions',
                value:
                    '${_fmtInt(_asNum(species?['n_no_prediction']))} / ${_fmtInt(_asNum(species?['n_total']))}',
                note: _asNum(species?['n_no_prediction']) == null ||
                        _asNum(species?['n_no_prediction']) == 0
                    ? 'every image received a prediction'
                    : 'excluded from accuracy; shown via coverage',
              ),
            ],
          ),
          const SizedBox(height: 12),
          if ((reliability?['note'] ?? '').toString().isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                reliability!['note'].toString(),
                style: const TextStyle(
                    color: kSidebarText, fontSize: 11.5, height: 1.35),
              ),
            ),
          _sectionTitle('Confidence reliability (reported confidence vs '
              'measured accuracy)'),
          _reliabilityTable(reliability),
          const SizedBox(height: 12),
          _sectionTitle('Per-class metrics'),
          _perClassTable(species),
          const SizedBox(height: 12),
          _sectionTitle('Confusion matrix (rows = true, columns = predicted)'),
          const SizedBox(height: 6),
          _confusionTable(confusion),
        ],
      ],
    );
  }

  String _speciesAccuracyValue(Map<String, dynamic>? species) {
    final accuracy = _asNum(species?['accuracy']);
    if (accuracy == null) return 'No scoreable samples';
    final ci = species?['accuracy_ci95'] as List?;
    if (ci == null || ci.length < 2 || ci[1] is! num) {
      return '${_fmtPercent(accuracy)} (no CI)';
    }
    final half = (ci[1] as num) - accuracy;
    return '${_fmtPercent(accuracy)} ± ${_fmtPercent(half)} (95% CI)';
  }

  String _conservationCiNote(Map<String, dynamic>? conservation) {
    final ci = conservation?['accuracy_ci95'] as List?;
    if (ci == null || ci.length < 2 || ci[0] is! num || ci[1] is! num) {
      return 'no labeled conservation pairs';
    }
    return '95% CI ${_fmtPercent(ci[0] as num)}–${_fmtPercent(ci[1] as num)}';
  }

  Widget _buildFieldRows(Map<String, dynamic> fieldRows) {
    final note = (fieldRows['note'] ?? '').toString().isEmpty
        ? 'Field-captured rows have unverified provenance and never contribute '
            'to official metrics.'
        : fieldRows['note'].toString();
    final included = fieldRows['included_in_official_metrics'] == true;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.table_rows_outlined, color: kSidebarText, size: 15),
            SizedBox(width: 6),
            Text(
              'Field-Captured Rows (unverified)',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800),
            ),
          ]),
          const SizedBox(height: 6),
          Text(note,
              style: const TextStyle(
                  color: kSidebarText, fontSize: 11.5, height: 1.35)),
          const SizedBox(height: 4),
          Text(
            'Rows: ${_fmtInt(_asNum(fieldRows['count']))} · included in '
            'official metrics: ${included ? 'yes' : 'no'}',
            style: const TextStyle(
                color: kSidebarText, fontSize: 11.5, height: 1.35),
          ),
        ],
      ),
    );
  }

  // ── Shared pieces ────────────────────────────────────────────────────────

  Widget _noteBox({required Color color, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color == kPoor
            ? kPoor.withValues(alpha: 0.12)
            : color == Colors.amber
                ? Colors.amber.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: color == kSidebarText
                ? Colors.white.withValues(alpha: 0.12)
                : color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _boxTitle(String text, IconData icon, Color color) {
    return Row(children: [
      Icon(icon, color: color, size: 16),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          style: TextStyle(
              color: color, fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
    ]);
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
            color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _provenanceLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Text(
        '$label: $value',
        style: const TextStyle(
            color: kSidebarText, fontSize: 11, height: 1.3),
      ),
    );
  }

  Widget _metricTile(
      {required String label, required String value, required String note}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: kSidebarPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                height: 1.2),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                height: 1.2),
          ),
          const SizedBox(height: 4),
          Text(
            note,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: kSidebarText, fontSize: 10.5, height: 1.25),
          ),
        ],
      ),
    );
  }

  static const _tableHeaders = [
    'Reported confidence',
    'Images (n)',
    'Mean score',
    'Empirical accuracy',
  ];

  Widget _tableRow(List<String> cells, {bool header = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < cells.length; i++)
            Expanded(
              flex: i == 0 ? 3 : 2,
              child: Text(
                cells[i],
                style: TextStyle(
                  color: header ? Colors.white70 : kSidebarText,
                  fontSize: 11,
                  fontWeight: header ? FontWeight.w700 : FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _reliabilityTable(Map<String, dynamic>? reliability) {
    final buckets = (reliability?['buckets'] as List?) ?? const [];
    if (buckets.isEmpty) {
      return const Text(
        'No confidence-reliability buckets in this run.',
        style: TextStyle(color: kSidebarText, fontSize: 11.5, height: 1.35),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(children: [
            _tableRow(_tableHeaders, header: true),
            const Divider(color: Colors.white12, height: 8),
            for (final raw in buckets)
              if (raw is Map)
                _tableRow([
                  '${raw['bucket']}',
                  '${raw['n'] ?? 0}',
                  raw['mean_reported_confidence'] == null
                      ? 'not reported'
                      : _fmtNumber(_asNum(raw['mean_reported_confidence'])),
                  raw['empirical_accuracy'] == null
                      ? 'no scoreable samples'
                      : _fmtPercent(_asNum(raw['empirical_accuracy'])),
                ]),
          ]),
        ),
      ],
    );
  }

  Widget _perClassTable(Map<String, dynamic>? species) {
    final entries = (species?['per_class'] as List?) ?? const [];
    if (entries.isEmpty) {
      return const Text(
        'No per-class metrics in this run.',
        style: TextStyle(color: kSidebarText, fontSize: 11.5, height: 1.35),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tableRow(const [
          'Class',
          'Support',
          'Precision',
          'Recall',
          'F1',
        ], header: true),
        const Divider(color: Colors.white12, height: 8),
        for (final raw in entries)
          if (raw is Map)
            _tableRow([
              '${raw['class']}${raw['low_support'] == true ? ' (low support)' : ''}',
              '${raw['support'] ?? 0}',
              _fmtNumber(_asNum(raw['precision'])),
              _fmtNumber(_asNum(raw['recall'])),
              _fmtNumber(_asNum(raw['f1'])),
            ]),
      ],
    );
  }

  Widget _confusionTable(Map<String, dynamic>? confusion) {
    final labels =
        (confusion?['labels'] as List?)?.map((e) => e.toString()).toList() ??
            const <String>[];
    final counts = (confusion?['counts'] as List?) ?? const [];
    if (labels.isEmpty) {
      return const Text(
        'No scoreable samples - no confusion matrix exists for this run.',
        style: TextStyle(color: kSidebarText, fontSize: 11.5, height: 1.35),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _confusionCell('true \\ pred', header: true),
            for (final label in labels) _confusionCell(label, header: true),
          ]),
          const Divider(color: Colors.white12, height: 6),
          for (var row = 0; row < labels.length; row++)
            Row(children: [
              _confusionCell(labels[row], header: true),
              for (var col = 0;
                  col <
                      ((counts[row] is List) ? (counts[row] as List).length : 0);
                  col++)
                _confusionCell(
                  '${(counts[row] as List)[col]}',
                  color: row == col
                      ? ((counts[row] as List)[col] is num &&
                              (counts[row] as List)[col] > 0
                          ? kHealthy
                          : kSidebarText)
                      : ((counts[row] as List)[col] is num &&
                              (counts[row] as List)[col] > 0
                          ? kPoor
                          : kSidebarText),
                ),
            ]),
        ],
      ),
    );
  }

  Widget _confusionCell(String text, {bool header = false, Color? color}) {
    return Container(
      constraints: const BoxConstraints(minWidth: 34),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Text(
        text,
        style: TextStyle(
          color: header ? Colors.white70 : (color ?? kSidebarText),
          fontSize: 10.5,
          fontWeight: header ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
    );
  }
}
