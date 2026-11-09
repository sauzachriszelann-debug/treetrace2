import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treetrace_mobile/screens/tree_reviews_screen.dart';
import 'package:treetrace_mobile/screens/unknown_review_screen.dart';
import 'package:treetrace_mobile/services/api_service.dart';

class _Store implements SecureStore {
  @override
  Future<void> delete(String key) async {}
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
}

class _Adapter implements HttpClientAdapter {
  _Adapter({
    this.unknownStatus = 'pending',
    this.submissionStatus = 'pending',
    this.failPath,
  });
  final String unknownStatus;
  final String submissionStatus;
  final String? failPath;
  final requests = <RequestOptions>[];
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    await requestStream?.drain<void>();
    if (failPath == options.path) {
      return ResponseBody.fromString(
          jsonEncode({'detail': 'Review forbidden'}), 403,
          headers: {
            Headers.contentTypeHeader: ['application/json']
          });
    }
    final payload = options.path.endsWith('/ai/unknown-species')
        ? [
            {
              'id': 7,
              'photo_url': 'https://img.example/tree.jpg',
              'possible_name': 'Unidentified tree',
              'ai_candidates': [
                {'common_name': 'Narra', 'confidence': .82}
              ],
              'reviewed': unknownStatus != 'pending',
              'identified_as': unknownStatus == 'identified' ? 'Narra' : null,
              'review_status': unknownStatus,
              'created_at': '2026-10-01T12:00:00Z'
            }
          ]
        : options.path.endsWith('/trees/')
            ? [
                {
                  'id': 9,
                  'common_name': 'Existing Narra',
                  'barangay': 'San Isidro'
                }
              ]
            : options.path.endsWith('/tree-submissions/')
                ? [
                    {
                      'id': 3,
                      'status': submissionStatus,
                      'common_name': 'Mango',
                      'lat': 7.3,
                      'lng': 125.6,
                      'dbh_cm': 20
                    }
                  ]
                : {'status': 'ok'};
    return ResponseBody.fromString(jsonEncode(payload), 200, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
  }
}

ApiService _service(_Adapter adapter) => ApiService.forTest(
      storage: _Store(),
      dio: Dio(BaseOptions(baseUrl: 'https://api.example.test/api'))
        ..httpClientAdapter = adapter,
    );

void main() {
  test('review service uses existing API routes and payloads', () async {
    final adapter = _Adapter();
    final service = _service(adapter);
    await service.getTreeSubmissions(status: 'pending');
    await service.approveTreeSubmission(3, overrides: {'dbh_cm': 22});
    await service.rejectTreeSubmission(3, reason: 'Duplicate');
    await service.linkTreeSubmission(3, treeId: 9);
    await service.reopenTreeSubmission(3);
    await service.reviewUnknownSpecies(7, {
      'reviewed': true,
      'identified_as': 'Narra',
      'review_notes': 'Verified',
    });
    await service.convertUnknownSpeciesToTreeSubmission(7);

    expect(adapter.requests.map((request) => request.method),
        ['GET', 'POST', 'POST', 'POST', 'POST', 'PUT', 'POST']);
    expect(adapter.requests[0].path, '/tree-submissions/');
    expect(adapter.requests[0].queryParameters['status'], 'pending');
    expect(adapter.requests[1].path, '/tree-submissions/3/approve');
    expect(adapter.requests[1].data, {'dbh_cm': 22});
    expect(adapter.requests[2].data, {'reason': 'Duplicate'});
    expect(adapter.requests[3].data, {'tree_id': 9});
    expect(adapter.requests[5].path, '/ai/unknown-species/7/review');
    expect(adapter.requests[6].path, '/ai/unknown-species/7/convert');
  });

  testWidgets('admin review screen exposes both tabs and loads review queues',
      (tester) async {
    final adapter = _Adapter();
    await tester.pumpWidget(MaterialApp(
      home: TreeReviewsScreen(role: 'admin', apiOverride: _service(adapter)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Tree Submissions'), findsOneWidget);
    expect(find.text('Unknown Species'), findsOneWidget);
    expect(find.text('Mango'), findsOneWidget);
    await tester.tap(find.text('Unknown Species'));
    await tester.pumpAndSettle();
    expect(find.text('Unidentified tree'), findsOneWidget);
    expect(find.text('Possible AI matches'), findsNothing); // in detail sheet
    expect(adapter.requests.any((r) => r.path.endsWith('/ai/unknown-species')),
        isTrue);
  });

  testWidgets('field worker never requests admin-only unknown-species API',
      (tester) async {
    final adapter = _Adapter();
    await tester.pumpWidget(MaterialApp(
      home: TreeReviewsScreen(
          role: 'field_worker', apiOverride: _service(adapter)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unknown Species'));
    await tester.pumpAndSettle();
    expect(find.textContaining('administrators only'), findsOneWidget);
    expect(adapter.requests.any((r) => r.path.endsWith('/ai/unknown-species')),
        isFalse);
  });

  testWidgets('unknown review details show candidate and existing workflows',
      (tester) async {
    final adapter = _Adapter();
    await tester.pumpWidget(MaterialApp(
      home: UnknownReviewScreen(apiOverride: _service(adapter)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unidentified tree'));
    await tester.pumpAndSettle();
    expect(find.text('Possible AI matches'), findsOneWidget);
    expect(find.textContaining('Narra'), findsOneWidget);
    expect(find.text('Approve identification'), findsOneWidget);
    expect(find.text('Close unresolved'), findsOneWidget);
  });

  testWidgets('approve requires confirmation and posts approval',
      (tester) async {
    final adapter = _Adapter();
    await tester.pumpWidget(MaterialApp(
      home: TreeReviewsScreen(role: 'admin', apiOverride: _service(adapter)),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Approve').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve').last);
    await tester.pumpAndSettle();
    expect(find.text('Approve submission?'), findsOneWidget);
    await tester.tap(find.text('Approve').last);
    await tester.pumpAndSettle();
    expect(adapter.requests.any((r) => r.path == '/tree-submissions/3/approve'),
        isTrue);
  });

  testWidgets('review API permission errors are shown to the reviewer',
      (tester) async {
    final adapter = _Adapter(failPath: '/tree-submissions/3/approve');
    await tester.pumpWidget(MaterialApp(
      home: TreeReviewsScreen(role: 'admin', apiOverride: _service(adapter)),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Approve').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve').last);
    await tester.pumpAndSettle();
    expect(find.text('Review forbidden'), findsOneWidget);
  });

  testWidgets('reject requires a reason before posting', (tester) async {
    final adapter = _Adapter();
    await tester.pumpWidget(MaterialApp(
      home: TreeReviewsScreen(
          role: 'field_worker', apiOverride: _service(adapter)),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Reject').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reject').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Confirm reject'))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField).last, 'Duplicate record');
    await tester.pump();
    expect(
      tester
          .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Confirm reject'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Confirm reject'));
    await tester.pumpAndSettle();
    final request = adapter.requests
        .firstWhere((r) => r.path == '/tree-submissions/3/reject');
    expect(request.data, {'reason': 'Duplicate record'});
  });

  testWidgets('linking requires choosing and confirming an existing tree',
      (tester) async {
    final adapter = _Adapter();
    await tester.pumpWidget(MaterialApp(
      home: TreeReviewsScreen(role: 'admin', apiOverride: _service(adapter)),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Link existing tree').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link existing tree').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Existing Narra · #9'));
    await tester.pumpAndSettle();
    expect(find.text('Link to existing tree?'), findsOneWidget);
    await tester.tap(find.text('Confirm link'));
    await tester.pumpAndSettle();
    final request = adapter.requests
        .firstWhere((r) => r.path == '/tree-submissions/3/link');
    expect(request.data, {'tree_id': 9});
  });

  testWidgets('reopen is offered for a rejected submission', (tester) async {
    final adapter = _Adapter(submissionStatus: 'rejected');
    await tester.pumpWidget(MaterialApp(
      home: TreeReviewsScreen(
          role: 'field_worker', apiOverride: _service(adapter)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rejected').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Reopen').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reopen').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reopen').last);
    await tester.pumpAndSettle();
    expect(adapter.requests.any((r) => r.path == '/tree-submissions/3/reopen'),
        isTrue);
  });

  testWidgets('identified unknown species can be converted through API',
      (tester) async {
    final adapter = _Adapter(unknownStatus: 'identified');
    await tester.pumpWidget(MaterialApp(
      home: UnknownReviewScreen(apiOverride: _service(adapter)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Narra'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send to Tree Submissions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
        adapter.requests.any((r) => r.path == '/ai/unknown-species/7/convert'),
        isTrue);
  });
}
