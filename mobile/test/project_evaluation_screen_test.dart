// G5 focused widget tests for the state-based Project Evaluation screen.
//
// These tests verify the honesty guarantees of the evaluation UI:
//  * "not evaluated" responses render no numbers at all;
//  * legacy fabricated values never reappear;
//  * invalid artifacts and load failures are surfaced instead of hidden;
//  * official runs render with provenance and sample counts.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treetrace_mobile/screens/project_evaluation_screen.dart';

/// Numbers from the old fabricated sample evaluation. None of them may ever
/// appear unless a validated official artifact actually produced them.
const List<String> fabricatedValues = [
  '92.31%',
  '0.952',
  '96.15%',
  '2.12 cm',
  '2.72 cm',
  '2114 ms',
  '26/26',
  '100.00%',
  'High Match',
];

Widget wrap(Widget screen) => MaterialApp(home: screen);

void expectNoFabricatedValues(WidgetTester tester) {
  for (final value in fabricatedValues) {
    expect(
      find.textContaining(value, findRichText: true),
      findsNothing,
      reason: 'fabricated value "$value" must never be rendered',
    );
  }
}

Map<String, dynamic> notEvaluatedResponse() => {
      'state': 'not_evaluated',
      'reason': 'No committed evaluation run exists yet. Official metrics '
          'appear only after a reproducible run over the frozen test manifest.',
      'run': null,
      'field_rows': {
        'count': 0,
        'included_in_official_metrics': false,
        'note': 'Field-captured rows have unverified provenance.',
      },
    };

Map<String, dynamic> invalidArtifactResponse() => {
      'state': 'invalid_artifact',
      'reason': 'Newest artifact failed validation.',
      'run_id': 'run_2026_0002',
      'issues': ['dataset.per_class_support sums to 9, must equal image_count (12)'],
      'run': null,
      'field_rows': {
        'count': 3,
        'included_in_official_metrics': false,
        'note': 'Field-captured rows have unverified provenance.',
      },
    };

Map<String, dynamic> evaluatedResponse() => {
      'state': 'evaluated',
      'reason': null,
      'issues': <String>[],
      'run': {
        'schema_version': 1,
        'run_id': 'run_2026_0001',
        'state': 'evaluated',
        'fixture': false,
        'dataset': {
          'name': 'species-test-v1',
          'manifest_sha256': 'a' * 64,
          'image_count': 120,
        },
        'model': {
          'pipeline': 'yolo+tflite',
          'local_tflite_present': true,
        },
        'environment': {
          'git_commit': 'abc123def456',
          'finished_at': '2026-10-20T00:00:00Z',
          'external_api_calls': false,
        },
        'metrics': {
          'species': {
            'n_total': 120,
            'n_scoreable': 110,
            'accuracy': 0.85,
            'accuracy_ci95': [0.77, 0.91],
            'coverage': 0.9167,
            'macro_f1': 0.8,
            'weighted_f1': 0.84,
            'n_classes': 8,
            'n_low_support': 2,
            'low_support_threshold': 5,
            'n_no_prediction': 10,
            'per_class': [
              {
                'class': 'Narra',
                'support': 20,
                'predicted': 22,
                'precision': 0.9,
                'recall': 0.95,
                'f1': 0.92,
                'low_support': false,
              },
              {
                'class': 'Rare sp.',
                'support': 3,
                'predicted': 2,
                'precision': 0.5,
                'recall': 0.33,
                'f1': 0.4,
                'low_support': true,
              },
            ],
          },
          'conservation': {
            'n_scoreable': 110,
            'accuracy': 0.9,
            'accuracy_ci95': [0.83, 0.94],
          },
          'dbh': {
            'n': 30,
            'mae_cm': 2.5,
            'rmse_cm': 3.1,
            'bias_cm': 0.4,
            'pipeline': 'manual',
          },
          'latency_ms': {'n': 110, 'p50_ms': 1800, 'mean_ms': 2000, 'p95_ms': 3500},
          'confidence_reliability': {
            'note': 'Confidence is a model self-report, not measured accuracy.',
            'buckets': [
              {
                'bucket': '[0.0, 0.5)',
                'n': 12,
                'mean_reported_confidence': 0.4,
                'empirical_accuracy': 0.5,
              },
              {
                'bucket': '[0.9, 1.0]',
                'n': 80,
                'mean_reported_confidence': 0.95,
                'empirical_accuracy': 0.9,
              },
            ],
          },
        },
        'confusion_matrix': {
          'labels': ['Narra', 'Acacia'],
          'counts': [
            [18, 2],
            [1, 19],
          ],
        },
      },
      'field_rows': {
        'count': 5,
        'included_in_official_metrics': false,
        'note': 'Field-captured rows have unverified provenance.',
      },
    };

void main() {
  testWidgets('not_evaluated renders an honest empty state with no numbers',
      (tester) async {
    await tester.pumpWidget(
      wrap(ProjectEvaluationScreen(loadResults: () async => notEvaluatedResponse())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Not yet evaluated'), findsWidgets);
    expect(find.textContaining('No committed evaluation run exists yet'),
        findsOneWidget);
    expect(find.textContaining('Placeholder numbers are never shown'),
        findsOneWidget);
    expectNoFabricatedValues(tester);
  });

  testWidgets(
      'invalid_artifact surfaces validation issues instead of older numbers',
      (tester) async {
    await tester.pumpWidget(wrap(
        ProjectEvaluationScreen(loadResults: () async => invalidArtifactResponse())));
    await tester.pumpAndSettle();

    expect(
        find.textContaining('The newest evaluation artifact failed validation'),
        findsOneWidget);
    expect(
        find.textContaining(
            'dataset.per_class_support sums to 9, must equal image_count (12)'),
        findsOneWidget);
    expect(find.textContaining('falling back to older numbers'), findsOneWidget);
    expectNoFabricatedValues(tester);
  });

  testWidgets('a load failure shows an error state and no numbers',
      (tester) async {
    await tester.pumpWidget(wrap(ProjectEvaluationScreen(
        loadResults: () async => throw Exception('network down'))));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not load evaluation results'), findsOneWidget);
    expect(find.textContaining('network down'), findsOneWidget);
    expect(find.textContaining('No numbers are shown'), findsOneWidget);
    expectNoFabricatedValues(tester);
  });

  testWidgets('loading shows a spinner and nothing else', (tester) async {
    await tester.pumpWidget(wrap(ProjectEvaluationScreen(
        loadResults: () => Completer<Map<String, dynamic>>().future)));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Not yet evaluated'), findsNothing);
    expectNoFabricatedValues(tester);
  });

  testWidgets('an evaluated run renders metrics with provenance and n counts',
      (tester) async {
    await tester.pumpWidget(
      wrap(ProjectEvaluationScreen(loadResults: () async => evaluatedResponse())),
    );
    await tester.pumpAndSettle();

    // Provenance.
    expect(find.textContaining('Run: run_2026_0001'), findsOneWidget);
    expect(find.textContaining('Dataset: species-test-v1'), findsOneWidget);
    expect(find.textContaining('Commit: abc123def456'), findsOneWidget);
    expect(find.textContaining('External API calls: no'), findsOneWidget);

    // Species accuracy with sample count and 95% CI (0.91 - 0.85 = 6.00%).
    expect(find.text('Species accuracy (n=110)'), findsOneWidget);
    expect(find.text('85.00% ± 6.00% (95% CI)'), findsOneWidget);
    expect(find.textContaining('coverage 91.67% of 120 images'), findsOneWidget);

    // DBH error with n.
    expect(find.text('DBH error (n=30)'), findsOneWidget);
    expect(find.text('MAE 2.50 cm'), findsOneWidget);
    expect(find.textContaining('RMSE 3.10 cm'), findsOneWidget);

    // Confidence reliability distinguishes self-report from accuracy.
    expect(find.textContaining('Reported confidence'), findsOneWidget);
    expect(find.textContaining('Empirical accuracy'), findsOneWidget);
    expect(find.textContaining('model self-report'), findsOneWidget);

    // Field rows are explicitly excluded from official metrics.
    expect(find.textContaining('Rows: 5 · included in official metrics: no'),
        findsOneWidget);

    // Confusion matrix labels and the low-support class marker.
    expect(find.textContaining('true \\ pred'), findsOneWidget);
    expect(find.textContaining('Rare sp. (low support)'), findsOneWidget);
  });

  testWidgets('a run not in evaluated state displays no metric tiles',
      (tester) async {
    final response = evaluatedResponse();
    final run = Map<String, dynamic>.from(response['run'] as Map);
    run['state'] = 'unavailable';
    response['run'] = run;

    await tester.pumpWidget(
      wrap(ProjectEvaluationScreen(loadResults: () async => response)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('marked "unavailable"'), findsOneWidget);
    expect(find.text('Species accuracy (n=110)'), findsNothing);
    expect(find.text('85.00% ± 6.00% (95% CI)'), findsNothing);
  });

  testWidgets('an unknown state renders no metrics', (tester) async {
    await tester.pumpWidget(wrap(ProjectEvaluationScreen(
        loadResults: () async => {'state': 'mystery', 'run': null})));
    await tester.pumpAndSettle();

    expect(find.textContaining('Unknown evaluation state "mystery"'), findsOneWidget);
    expectNoFabricatedValues(tester);
  });
}
