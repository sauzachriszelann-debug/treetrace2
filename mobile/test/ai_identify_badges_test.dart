// Phase 13.6 — AI Identify widget tests: usage badges, result rendering and
// error states.
//
// Fixture-driven with SYNTHETIC data only (invented species, invented usage
// counters, a token file path that is never opened). The screen's Phase 13.6
// test seams (usageLoader / identifyFn / initialPhoto) inject every response,
// and flutter_test's HttpOverrides (_MockHttpOverrides in _binding_io.dart)
// absorbs any stray dart:io HTTP — no test can contact PlantNet, Gemini,
// Render, Aiven, Supabase, or any other external service.

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:treetrace_mobile/screens/ai_identify_screen.dart';
import 'package:treetrace_mobile/services/api_service.dart';
import 'package:treetrace_mobile/services/auth_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Synthetic fixtures
// ─────────────────────────────────────────────────────────────────────────────

/// Token path handed to the screen's test-only `debugIdentify`. The identify
/// seam receives the File but never reads it, and `debugIdentify` runs with
/// `markLoading: false` so the screen keeps its own photo slot null — no
/// bytes are ever loaded and no file is opened.
File syntheticPhoto() => File('synthetic_phase13_fixture.jpg');

/// Mirrors GET /api/ai/usage for a free-plan user: `used_today` /
/// `daily_limit` / `remaining` per bucket.
Map<String, dynamic> usageFixture({int used = 3, int limit = 10}) => {
      'ai': {
        'used_today': used,
        'daily_limit': limit,
        'remaining': limit - used,
        'unlimited': false,
      },
      'unknown': {
        'used_today': 1,
        'daily_limit': 5,
        'remaining': 4,
        'unlimited': false,
      },
    };

/// Staff payload shape: no counters, `unlimited: true`.
Map<String, dynamic> unlimitedUsageFixture() => {
      'ai': {'unlimited': true, 'remaining': null, 'daily_limit': null},
      'unknown': {'unlimited': true, 'remaining': null, 'daily_limit': null},
    };

Map<String, dynamic> identifyFixture() => {
      'common_name': 'Synthetic Narra',
      'scientific_name': 'Pterocarpus fictus',
      'family': 'Fabaceae',
      'confidence': 'High',
      'endangered_status': 'Vulnerable',
      'protected': false,
      'source': 'plantnet',
      'plantnet_score': 0.91,
    };

DioException dailyLimit402() => DioException(
      requestOptions: RequestOptions(path: '/api/ai/identify'),
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: RequestOptions(path: '/api/ai/identify'),
        statusCode: 402,
        data: {
          'detail': 'Free AI limit reached. Upgrade to Pro for unlimited scans.',
        },
      ),
    );

// ─────────────────────────────────────────────────────────────────────────────
// Test seams
// ─────────────────────────────────────────────────────────────────────────────

class _FakeSecureStore implements SecureStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<void> delete(String key) async {}
}

Future<void> pumpScreen(
  WidgetTester tester, {
  required Future<Map<String, dynamic>> Function() usageLoader,
  Future<Map<String, dynamic>> Function(File file)? identifyFn,
}) async {
  final api = ApiService.forTest(
    storage: _FakeSecureStore(),
    onlineCheck: () async => false,
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>(
      create: (_) => AuthProvider(apiOverride: api),
      child: MaterialApp(
        home: AIIdentifyScreen(
          usageLoader: usageLoader,
          identifyFn: identifyFn,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Runs a scan through the screen's `@visibleForTesting` entry point, which
/// is defined on the (private) State class — hence the dynamic invocation.
Future<void> runScan(WidgetTester tester) async {
  final state = tester.state<State<AIIdentifyScreen>>(
    find.byType(AIIdentifyScreen),
  );
  await (state as dynamic).debugIdentify(syntheticPhoto());
  await tester.pumpAndSettle();
}

// ─────────────────────────────────────────────────────────────────────────────
// Usage badges
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('usage badges render live counters once the fetch succeeds',
      (tester) async {
    await pumpScreen(tester, usageLoader: () async => usageFixture());

    expect(find.text('Loading'), findsNothing);
    expect(find.text('7 / 10 left'), findsOneWidget);
    expect(find.text('4 / 5 left'), findsOneWidget);
  });

  testWidgets('badges show Loading only while the fetch is in flight',
      (tester) async {
    final completer = Completer<Map<String, dynamic>>();
    await pumpScreen(tester, usageLoader: () => completer.future);

    expect(find.text('Loading'), findsNWidgets(2));

    completer.complete(usageFixture());
    await tester.pumpAndSettle();

    expect(find.text('Loading'), findsNothing);
    expect(find.text('7 / 10 left'), findsOneWidget);
  });

  testWidgets('a failed usage fetch shows a retry state, never an endless spinner',
      (tester) async {
    var calls = 0;
    await pumpScreen(tester, usageLoader: () async {
      calls++;
      if (calls == 1) throw Exception('adb tunnel momentarily down');
      return usageFixture();
    });

    // Phase 13.4 regression guard: the old code swallowed this failure and
    // left both badges on "Loading" forever.
    expect(find.text('Loading'), findsNothing);
    expect(find.text('Unavailable — tap to retry'), findsNWidgets(2));

    await tester.tap(find.text('Unavailable — tap to retry').first);
    await tester.pumpAndSettle();

    expect(calls, 2, reason: 'tapping the failed badge must retry the fetch');
    expect(find.text('Unavailable — tap to retry'), findsNothing);
    expect(find.text('7 / 10 left'), findsOneWidget);
  });

  testWidgets('a staff payload renders as Unlimited, not as a stuck value',
      (tester) async {
    await pumpScreen(tester, usageLoader: () async => unlimitedUsageFixture());

    expect(find.text('Unlimited'), findsNWidgets(2));
    expect(find.text('Loading'), findsNothing);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Identify results and error states
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('a successful identify renders the synthetic species result card',
      (tester) async {
    await pumpScreen(
      tester,
      usageLoader: () async => usageFixture(),
      identifyFn: (_) async => identifyFixture(),
    );
    await runScan(tester);

    // The name also repeats in the plant profile section, so allow >= 1.
    expect(find.text('Synthetic Narra'), findsAtLeastNWidgets(1));
    expect(find.text('Pterocarpus fictus'), findsAtLeastNWidgets(1));
    // No role is injected, so the screen is not in the citizen flow.
    expect(find.text('Add to Inventory'), findsOneWidget);
    // The scan consumed one AI credit: 3 of 10 used -> 6 of 10 left.
    expect(find.text('6 / 10 left'), findsOneWidget);
    expect(find.text('Could Not Identify'), findsNothing);
  });

  testWidgets('a backend failure renders Could Not Identify with a submit path',
      (tester) async {
    await pumpScreen(
      tester,
      usageLoader: () async => usageFixture(),
      identifyFn: (_) async => throw Exception('backend unreachable'),
    );
    await runScan(tester);

    expect(find.text('Could Not Identify'), findsOneWidget);
    expect(
      find.textContaining('AI identification could not connect'),
      findsOneWidget,
    );
    expect(find.text('Submit Unknown Species'), findsOneWidget);
    // A failed scan must not silently consume a credit.
    expect(find.text('7 / 10 left'), findsOneWidget);
  });

  testWidgets('a 402 response renders the Daily Limit Reached state',
      (tester) async {
    await pumpScreen(
      tester,
      usageLoader: () async => usageFixture(),
      identifyFn: (_) async => throw dailyLimit402(),
    );
    await runScan(tester);

    expect(find.text('Daily Limit Reached'), findsOneWidget);
    expect(find.text('Could Not Identify'), findsNothing);
    expect(
      find.text('Free AI limit reached. Upgrade to Pro for unlimited scans.'),
      findsOneWidget,
    );
    expect(find.text('View Pro Plans'), findsOneWidget);
  });
}