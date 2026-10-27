import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treetrace_mobile/screens/offline_sync_screen.dart';
import 'package:treetrace_mobile/services/offline_queue.dart';

DioException http401() => DioException(
      requestOptions: RequestOptions(path: '/trees/'),
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: RequestOptions(path: '/trees/'),
        statusCode: 401,
        data: {'detail': 'Token expired'},
      ),
    );

class FakeTransport {
  final calls = <MapEntry<String, Map<String, dynamic>>>[];
  Future<Map<String, dynamic>> Function(String type, Map<String, dynamic>)?
      onSend;

  Future<Map<String, dynamic>> send(
      String type, Map<String, dynamic> payload) async {
    calls.add(MapEntry(type, payload));
    final handler = onSend;
    if (handler != null) return await handler(type, payload);
    return {'ok': true};
  }

  Future<String?> upload(String path, String purpose) async =>
      'https://cdn.test/photo.jpg';
}

// ── Fake-async / real-I/O bridge ─────────────────────────────────────────────
// testWidgets runs in a fake-async zone: futures from real file I/O only
// resume when the real event loop spins, and fake-zone microtasks only drain
// when the test pumps. Every service mutation therefore runs inside
// tester.runAsync, and every wait pumps fake frames while yielding real time
// so the queue store's disk writes can finish.

Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async {
  final result = await tester.runAsync(body);
  return result as T;
}

Future<void> pumpFor(WidgetTester tester, bool Function() done,
    {int maxIterations = 200}) async {
  for (var i = 0; i < maxIterations; i++) {
    await tester.pump(const Duration(milliseconds: 25));
    if (done()) return;
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)));
  }
  fail('condition was never met within $maxIterations pump iterations');
}

void main() {
  late Directory temp;
  late FakeTransport transport;

  Directory storeDir() =>
      Directory('${temp.path}${Platform.pathSeparator}store');

  OfflineQueueService buildService({bool online = true}) =>
      OfflineQueueService(
        directory: storeDir(),
        isOnline: () async => online,
        sender: transport.send,
        uploader: transport.upload,
      );

  Widget host(OfflineQueueService service, {bool online = true}) =>
      MaterialApp(
        home: OfflineSyncScreen(
            debugService: service, debugIsOnline: () async => online),
      );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('g6_screen_test');
    transport = FakeTransport();
  });

  tearDown(() async {
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets(
      'held record shows its review label and reason and is never sent',
      (tester) async {
    final service = await real(tester, () async {
      final service = buildService();
      final item = await service.enqueue(
        'CREATE_HEALTH_LOG',
        {'tree_id': 3},
        requiresReview: true,
        reviewReason:
            'This save failed after the request may have reached the server. '
            'A blind retry could create a duplicate health log.',
      );
      await service.setVerified(item.itemId, true);
      return service;
    });

    await tester.pumpWidget(host(service));
    await pumpFor(tester,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty);

    expect(find.textContaining('Possible duplicate - review'), findsOneWidget);
    expect(find.textContaining('duplicate health log'), findsOneWidget);
    expect(find.textContaining('held for review'), findsOneWidget);

    // Only held+verified records exist: the batch button stays disabled and
    // nothing can be uploaded automatically.
    final syncButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Sync Verified'));
    expect(syncButton.onPressed, isNull);
    expect(transport.calls, isEmpty);
  });

  testWidgets('Sync Verified uploads only verified records', (tester) async {
    final service = await real(tester, () async {
      final service = buildService();
      final verifiedItem =
          await service.enqueue('CREATE_TREE', {'client_uuid': 'v1'});
      await service.setVerified(verifiedItem.itemId, true);
      await service.enqueue('CREATE_TREE', {'client_uuid': 'u1'});
      return service;
    });

    await tester.pumpWidget(host(service));
    await pumpFor(tester,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Sync Verified'));
    await pumpFor(tester, () => find.text('Synced 1 record.').evaluate().isNotEmpty);

    expect(transport.calls, hasLength(1));
    expect(transport.calls.single.value['client_uuid'], 'v1');
    expect(find.text('No offline records waiting for sync.'), findsNothing,
        reason: 'the unverified record remains queued');
    expect(find.text('Needs your verification'), findsOneWidget);
  });

  testWidgets('401 during sync surfaces a session banner and keeps records',
      (tester) async {
    final service = await real(tester, () async {
      final service = buildService();
      final item = await service.enqueue('CREATE_TREE', {'client_uuid': 'a'});
      await service.setVerified(item.itemId, true);
      return service;
    });
    transport.onSend = (type, payload) async => throw http401();

    await tester.pumpWidget(host(service));
    await pumpFor(tester,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Sync Verified'));
    await pumpFor(
        tester, () => find.textContaining('Session expired').evaluate().isNotEmpty);

    expect(find.textContaining('kept on this device'), findsWidgets);
    final items = await real(tester, () => service.all());
    expect(items, hasLength(1),
        reason: 'records survive an expired session (safeguard 4)');
  });

  testWidgets('offline state shows the reconnect behavior', (tester) async {
    final service = await real(tester, () async {
      final service = buildService(online: false);
      await service.enqueue('CREATE_TREE', {'client_uuid': 'a'});
      return service;
    });

    await tester.pumpWidget(host(service, online: false));
    await pumpFor(tester,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty);

    expect(find.textContaining('Verified records wait here'), findsOneWidget);
  });

  testWidgets('a quarantined queue file is reported, not silently ignored',
      (tester) async {
    final service = await real(tester, () async {
      final dir = storeDir()..createSync(recursive: true);
      File('${dir.path}${Platform.pathSeparator}'
              '${OfflineQueueService.queueFileName}')
          .writeAsStringSync('not-a-queue');
      return buildService();
    });

    await tester.pumpWidget(host(service));
    await pumpFor(tester,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty);

    expect(find.textContaining('was damaged'), findsOneWidget);
    expect(find.textContaining('NOT replayed automatically'), findsOneWidget);
  });

  testWidgets('missing photo is surfaced with an explicit escape hatch',
      (tester) async {
    final service = await real(tester, () async {
      final service = buildService();
      final item = await service.enqueue(
          'CREATE_TREE', {'client_uuid': 'gone', 'photo_url': null},
          photoPath: '${temp.path}${Platform.pathSeparator}purged.jpg');
      await service.setVerified(item.itemId, true);
      return service;
    });

    await tester.pumpWidget(host(service));
    await pumpFor(tester,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty);

    // The attempt classifies the missing photo and holds the record.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sync Verified'));
    await pumpFor(tester,
        () => find.textContaining('Photo missing on device').evaluate().isNotEmpty);
    expect(transport.calls, isEmpty,
        reason: 'record is never created without its photo');

    expect(
        find.textContaining(
            'The photo for this record is missing on this device'),
        findsWidgets);
    expect(find.text('Sync w/o photo'), findsOneWidget);

    final escape = find.text('Sync w/o photo');
    await tester.ensureVisible(escape);
    await tester.pump();
    await tester.tap(escape);
    await pumpFor(
        tester, () => find.text('Sync w/o photo').evaluate().isEmpty);

    final items = await real(tester, () => service.all());
    expect(items.single.photoPath, isNull);
    expect(items.single.requiresReview, isFalse);
  });

  testWidgets('citizen submissions are labelled as pending approval',
      (tester) async {
    final service = await real(tester, () async {
      final service = buildService();
      await service.enqueue('CREATE_TREE_SUBMISSION', {
        'client_uuid': 'sub-1',
        'common_name': 'Narra',
        'source': 'mobile',
      });
      return service;
    });

    await tester.pumpWidget(host(service));
    await pumpFor(tester,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty);

    expect(find.text('Tree submission (pending approval)'), findsOneWidget);
  });
}
