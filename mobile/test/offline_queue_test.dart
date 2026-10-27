import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treetrace_mobile/services/offline_queue.dart';

DioException noResponse(DioExceptionType type) =>
    DioException(requestOptions: RequestOptions(path: '/x'), type: type);

DioException http(int status, {Object? detail}) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: status,
        data: detail == null ? null : {'detail': detail},
      ),
    );

class FakeTransport {
  final calls = <MapEntry<String, Map<String, dynamic>>>[];
  final uploads = <MapEntry<String, String>>[];
  Future<Map<String, dynamic>> Function(String type, Map<String, dynamic>)?
      onSend;
  Future<String?> Function(String path, String purpose)? onUpload;

  Future<Map<String, dynamic>> send(
      String type, Map<String, dynamic> payload) async {
    calls.add(MapEntry(type, payload));
    final handler = onSend;
    if (handler != null) return await handler(type, payload);
    return {'ok': true};
  }

  Future<String?> upload(String path, String purpose) async {
    uploads.add(MapEntry(purpose, path));
    final handler = onUpload;
    if (handler != null) return await handler(path, purpose);
    return 'https://cdn.test/photo.jpg';
  }
}

void main() {
  late Directory temp;
  late FakeTransport transport;
  final fixedNow = DateTime(2026, 10, 21, 12, 0, 0);

  Directory storeDir() =>
      Directory('${temp.path}${Platform.pathSeparator}store');

  OfflineQueueService buildService({
    bool online = true,
    Future<String?> Function(String key)? legacyRead,
    Future<void> Function(String key)? legacyDelete,
  }) {
    return OfflineQueueService(
      directory: storeDir(),
      legacyRead: legacyRead,
      legacyDelete: legacyDelete,
      isOnline: () async => online,
      sender: transport.send,
      uploader: transport.upload,
      clock: () => fixedNow,
    );
  }

  File seedQueueFile(List<Map<String, dynamic>> items) {
    final dir = storeDir()..createSync(recursive: true);
    final file = File(
        '${dir.path}${Platform.pathSeparator}${OfflineQueueService.queueFileName}');
    file.writeAsStringSync(jsonEncode({
      'schema': 2,
      'legacy_imported': true,
      'items': items,
    }));
    return file;
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('g6_queue_test');
    transport = FakeTransport();
  });

  tearDown(() async {
    try {
      await temp.delete(recursive: true);
    } catch (_) {}
  });

  // ── Durability & restart recovery ────────────────────────────────────────
  test('failed disk write is reported and later writes can recover', () async {
    final service = buildService();
    expect(await service.all(), isEmpty);

    final queuePath = '${storeDir().path}${Platform.pathSeparator}'
        '${OfflineQueueService.queueFileName}';

    await Directory(queuePath).create(recursive: true);

    await expectLater(
      service.enqueue('CREATE_TREE', {'client_uuid': 'failed-write'}),
      throwsA(isA<FileSystemException>()),
    );

    await Directory(queuePath).delete();

    await service.enqueue('CREATE_TREE', {'client_uuid': 'recovered-write'});

    final restarted = buildService();
    final items = await restarted.all();

    expect(items, hasLength(2));
    expect(
      items.map((item) => item.payload['client_uuid']),
      containsAll(['failed-write', 'recovered-write']),
    );
  });
  test('enqueue survives an app restart with identity intact', () async {
    final service = buildService();
    final item = await service.enqueue('CREATE_TREE', {
      'common_name': 'Narra',
      'client_uuid': 'uuid-1234',
    });
    expect(item.itemId, isNotEmpty);

    // "Restart": fresh instance over the same directory.
    final restarted = buildService();
    final items = await restarted.all();
    expect(items, hasLength(1));
    expect(items.first.itemId, item.itemId);
    expect(items.first.payload['client_uuid'], 'uuid-1234');
    expect(items.first.verified, isFalse);
    expect(items.first.requiresReview, isFalse);
  });

  test('concurrent enqueues cannot lose records (safeguard 7)', () async {
    final service = buildService();
    await Future.wait([
      service.enqueue('CREATE_HEALTH_LOG', {'tree_id': 1}),
      service.enqueue('CREATE_HEALTH_LOG', {'tree_id': 2}),
    ]);
    expect(await service.all(), hasLength(2));

    final restarted = buildService();
    expect(await restarted.all(), hasLength(2));
  });

  test('sync removal persists across restart', () async {
    final service = buildService();
    final item = await service.enqueue('CREATE_TREE', {'client_uuid': 'u1'});
    await service.setVerified(item.itemId, true);

    final result = await service.sync(auto: false);
    expect(result.synced, 1);

    final restarted = buildService();
    expect(await restarted.all(), isEmpty);
  });

  // ── Legacy queue migration (non-destructive, no duplicates) ─────────────

  test('legacy secure-storage entries import once with fresh UUIDs', () async {
    final photo = File('${temp.path}${Platform.pathSeparator}old_photo.jpg')
      ..writeAsStringSync('jpeg-bytes');
    final legacyJson = jsonEncode([
      {
        'id': 42,
        'type': 'CREATE_TREE',
        'payload': {'common_name': 'Acacia', 'client_uuid': 'legacy-uuid'},
        'photo_path': photo.path,
        'verified': true,
        'created_at': '2026-10-01T00:00:00.000',
      },
    ]);
    final deletedKeys = <String>[];

    OfflineQueueService fresh() => buildService(
          legacyRead: (key) async => legacyJson,
          legacyDelete: (key) async => deletedKeys.add(key),
        );

    final items = await fresh().all();
    expect(items, hasLength(1));
    expect(items.first.legacyId, 42);
    expect(items.first.itemId, isNot('42'));
    expect(
        items.first.itemId,
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(items.first.verified, isTrue);
    // Photo was upgraded to durable storage while the original existed.
    expect(items.first.photoPath, contains('offline_photos'));
    expect(File(items.first.photoPath!).existsSync(), isTrue);
    // Legacy blob removed only AFTER the new store was confirmed on disk.
    expect(deletedKeys, [OfflineQueueService.legacyQueueKey]);

    // A second launch must NOT import again (marker inside the queue file).
    final again = await fresh().all();
    expect(again, hasLength(1));
  });

  test('unparseable legacy queue is preserved, not destroyed', () async {
    final deletedKeys = <String>[];
    final service = buildService(
      legacyRead: (key) async => '### not json ###',
      legacyDelete: (key) async => deletedKeys.add(key),
    );
    final items = await service.all();
    expect(items, isEmpty);
    expect(service.corruptionNotice, contains('legacy'));
    expect(deletedKeys, isEmpty, reason: 'unreadable legacy data is kept');
  });

  // ── Corruption quarantine (never a silent wipe) ─────────────────────────

  test('corrupt queue file is quarantined with a visible notice', () async {
    final dir = storeDir()..createSync(recursive: true);
    final file = File(
        '${dir.path}${Platform.pathSeparator}${OfflineQueueService.queueFileName}');
    file.writeAsStringSync('{"schema":2,"items":[{corrupt');

    final service = buildService();
    expect(await service.all(), isEmpty);
    expect(service.corruptionNotice, isNotNull);
    expect(service.corruptionNotice, contains('NOT replayed automatically'));

    final quarantines = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('quarantine'))
        .toList();
    expect(quarantines, hasLength(1));
    expect(quarantines.first.readAsStringSync(), contains('corrupt'));

    // Queue remains usable afterwards and persists.
    await service.enqueue('CREATE_TREE', {'client_uuid': 'u2'});
    final restarted = buildService();
    expect(await restarted.all(), hasLength(1));
  });

  // ── Verified-only gating (D1-B, safeguard 9) ────────────────────────────

  test('unverified records are never uploaded automatically', () async {
    final service = buildService();
    await service.enqueue('CREATE_TREE', {'client_uuid': 'a'});
    await service.enqueue('CREATE_TREE', {'client_uuid': 'b'});
    final items = await service.all();
    await service.setVerified(items.first.itemId, true);

    final result = await service.sync(auto: true);
    expect(result.ran, isTrue);
    expect(result.synced, 1);
    expect(result.skippedUnverified, 1);
    expect(transport.calls, hasLength(1));
    expect(transport.calls.single.key, 'CREATE_TREE');
    expect(transport.calls.single.value['client_uuid'], 'a',
        reason: 'only the verified record uploads; the unverified twin is '
            'never sent');
  });

  test('offline check blocks the run before anything is attempted', () async {
    final service = buildService(online: false);
    final item = await service.enqueue('CREATE_TREE', {'client_uuid': 'a'});
    await service.setVerified(item.itemId, true);

    final result = await service.sync(auto: true);
    expect(result.offline, isTrue);
    expect(transport.calls, isEmpty);
  });

  // ── Photo handling (D5) ─────────────────────────────────────────────────

  test('photo upload failure keeps the item and never drops the photo',
      () async {
    final service = buildService();
    final photo = File('${temp.path}${Platform.pathSeparator}tree.jpg')
      ..writeAsStringSync('bytes');
    final item = await service.enqueue(
        'CREATE_TREE', {'client_uuid': 'p1', 'photo_url': null},
        photoPath: photo.path);
    await service.setVerified(item.itemId, true);
    transport.onUpload = (path, purpose) async =>
        throw noResponse(DioExceptionType.connectionError);

    final result = await service.sync(auto: true);
    expect(result.ran, isTrue);
    expect(transport.calls, isEmpty,
        reason: 'record not created without photo');
    expect(transport.uploads, hasLength(1));
    final remaining = await service.all();
    expect(remaining, hasLength(1), reason: 'item kept (D5)');
    expect(remaining.first.lastErrorKind, QueueFailureKind.network);
    expect(remaining.first.requiresReview, isFalse);
    expect(File(remaining.first.photoPath!).existsSync(), isTrue,
        reason: 'photo file untouched');
  });

  test('successful upload URL persists; retry does not re-upload', () async {
    final service = buildService();
    final photo = File('${temp.path}${Platform.pathSeparator}tree.jpg')
      ..writeAsStringSync('bytes');
    final item = await service.enqueue(
        'CREATE_TREE', {'client_uuid': 'p2', 'photo_url': null},
        photoPath: photo.path);
    await service.setVerified(item.itemId, true);
    transport.onUpload = (path, purpose) async => 'https://cdn.test/kept.jpg';
    transport.onSend = (type, payload) async => throw http(500, detail: 'boom');

    // First run: photo uploaded, record creation fails.
    var result = await service.sync(auto: false);
    expect(result.synced, 0);
    expect(transport.uploads, hasLength(1));
    var remaining = await service.all();
    expect(remaining, hasLength(1));
    expect(remaining.first.payload['photo_url'], 'https://cdn.test/kept.jpg');
    expect(remaining.first.lastErrorKind, QueueFailureKind.server);

    // Second run: no second upload, record retried.
    transport.onSend = null;
    result = await service.sync(auto: false);
    expect(result.synced, 1);
    expect(transport.uploads, hasLength(1), reason: 'URL reused');
    expect(transport.calls, hasLength(2));
  });

  test('item and photo are removed only after upload AND record succeed',
      () async {
    final service = buildService();
    final photo = File('${temp.path}${Platform.pathSeparator}tree.jpg')
      ..writeAsStringSync('bytes');
    final item = await service.enqueue(
        'CREATE_TREE', {'client_uuid': 'ok', 'photo_url': null},
        photoPath: photo.path);
    await service.setVerified(item.itemId, true);
    final durablePath = (await service.all()).first.photoPath!;

    final result = await service.sync(auto: false);
    expect(result.synced, 1);
    expect(await service.all(), isEmpty);
    expect(File(durablePath).existsSync(), isFalse,
        reason: 'durable photo pruned only after confirmed success');
    expect(File(photo.path).existsSync(), isTrue,
        reason: 'the original capture is never touched by sync');
  });

  test(
      'missing photo file holds the record for review (no silent photoless '
      'creation)', () async {
    final service = buildService();
    final item = await service.enqueue(
        'CREATE_TREE', {'client_uuid': 'gone', 'photo_url': null},
        photoPath: '${temp.path}${Platform.pathSeparator}purged.jpg');
    await service.setVerified(item.itemId, true);

    final result = await service.sync(auto: false);
    expect(transport.calls, isEmpty);
    expect(result.heldForReview, 1);
    final remaining = await service.all();
    expect(remaining.first.requiresReview, isTrue);
    expect(remaining.first.lastErrorKind, QueueFailureKind.missingPhoto);

    // Explicit user consent removes the photo requirement and syncs.
    await service.continueWithoutPhoto(item.itemId);
    final after = await service.all();
    expect(after.first.photoPath, isNull);
    expect(after.first.requiresReview, isFalse);
    final result2 = await service.sync(auto: false);
    expect(result2.synced, 1);
    expect(transport.calls, hasLength(1));
  });

  // ── Retry policy: idempotent vs ambiguous (D3) ──────────────────────────

  test('idempotent types retry automatically after a lost response', () async {
    final service = buildService();
    final item = await service.enqueue('CREATE_TREE', {'client_uuid': 'i1'});
    await service.setVerified(item.itemId, true);
    transport.onSend = (type, payload) async =>
        throw noResponse(DioExceptionType.receiveTimeout);

    var result = await service.sync(auto: true);
    expect(result.keptForRetry, 1);
    var remaining = await service.all();
    expect(remaining.first.requiresReview, isFalse,
        reason: 'client_uuid makes the retry safe');
    expect(remaining.first.lastErrorKind, QueueFailureKind.network);

    // Backoff window: the fixed clock puts the next retry 30s out.
    result = await service.sync(auto: true);
    expect(result.skippedBackoff, 1);
    expect(transport.calls, hasLength(1));

    // Manual sync ignores the window (user intent) but stays idempotent.
    result = await service.sync(auto: false);
    expect(result.ran, isTrue);
    expect(transport.calls, hasLength(2));
  });

  test('citizen submission routing keeps client_uuid and adds source=mobile',
      () async {
    final service = buildService();
    final item = await service.enqueue('CREATE_TREE_SUBMISSION', {
      'client_uuid': 'sub-1',
      'common_name': 'Narra',
      'source': 'mobile',
    });
    await service.setVerified(item.itemId, true);

    final result = await service.sync(auto: false);
    expect(result.synced, 1);
    final call = transport.calls.single;
    expect(call.key, 'CREATE_TREE_SUBMISSION');
    expect(call.value['client_uuid'], 'sub-1');
    expect(call.value['source'], 'mobile');
  });

  test(
      'non-idempotent lost response is held for review and NEVER '
      'auto-retried', () async {
    final service = buildService();
    final item = await service.enqueue('CREATE_HEALTH_LOG', {'tree_id': 7});
    await service.setVerified(item.itemId, true);
    transport.onSend = (type, payload) async =>
        throw noResponse(DioExceptionType.receiveTimeout);

    var result = await service.sync(auto: true);
    expect(result.heldForReview, 1);
    var remaining = await service.all();
    expect(remaining.first.requiresReview, isTrue);
    expect(remaining.first.lastErrorKind, QueueFailureKind.ambiguous);
    expect(remaining.first.lastError, contains('duplicate'));
    expect(transport.calls, hasLength(1));

    // Automatic sync never touches it again (D3)...
    result = await service.sync(auto: true);
    expect(transport.calls, hasLength(1));
    // ...and even the one-tap manual pass skips held records: only the
    // explicit per-item Retry clears the hold.
    result = await service.sync(auto: false);
    expect(transport.calls, hasLength(1));

    await service.resolveForManualRetry(item.itemId);
    result = await service.sync(auto: false);
    expect(transport.calls, hasLength(2));
  });

  test('provably-undelivered request is safe to retry for any type', () async {
    final service = buildService();
    final item =
        await service.enqueue('SUBMIT_UNKNOWN', {'possible_name': 'X'});
    await service.setVerified(item.itemId, true);
    transport.onSend = (type, payload) async =>
        throw noResponse(DioExceptionType.connectionError);

    final result = await service.sync(auto: true);
    expect(result.keptForRetry, 1);
    final remaining = await service.all();
    expect(remaining.first.requiresReview, isFalse,
        reason: 'the request never left the device');
    expect(remaining.first.lastErrorKind, QueueFailureKind.network);
  });

  test('automatic retries are bounded and then pause for review', () async {
    seedQueueFile([
      {
        'item_id': 'seed-cap',
        'type': 'CREATE_PLANTING_RECOMMENDATION',
        'payload': {'species_name': 'Narra'},
        'photo_path': null,
        'verified': true,
        'created_at': fixedNow.toIso8601String(),
        'attempts': maxAutoAttempts,
        'requires_review': false,
        'next_retry_at_ms': 0,
      },
    ]);
    final service = buildService();

    final result = await service.sync(auto: true);
    expect(transport.calls, isEmpty);
    expect(result.heldForReview, 1);
    final items = await service.all();
    expect(items.first.requiresReview, isTrue);
    expect(items.first.lastErrorKind, QueueFailureKind.retriesExhausted);
  });

  test('backoff window defers automatic retries but not manual ones', () async {
    seedQueueFile([
      {
        'item_id': 'seed-backoff',
        'type': 'CREATE_TREE',
        'payload': {'client_uuid': 'b1'},
        'photo_path': null,
        'verified': true,
        'created_at': fixedNow.toIso8601String(),
        'attempts': 2,
        'requires_review': false,
        'next_retry_at_ms':
            fixedNow.add(const Duration(seconds: 30)).millisecondsSinceEpoch,
      },
    ]);
    final service = buildService();

    var result = await service.sync(auto: true);
    expect(result.skippedBackoff, 1);
    expect(transport.calls, isEmpty);

    result = await service.sync(auto: false);
    expect(transport.calls, hasLength(1));
  });

  // ── Conflicts, quota, auth (safeguard 8) ────────────────────────────────

  test('409 conflict is held for review and never auto-retried (D1)', () async {
    final service = buildService();
    final item = await service.enqueue('CREATE_TREE', {'client_uuid': 'c1'});
    await service.setVerified(item.itemId, true);
    transport.onSend = (type, payload) async =>
        throw http(409, detail: 'Key already associated with another tree.');

    var result = await service.sync(auto: true);
    expect(result.heldForReview, 1);
    final remaining = await service.all();
    expect(remaining.first.requiresReview, isTrue);
    expect(remaining.first.lastErrorKind, QueueFailureKind.conflict);
    expect(remaining.first.lastError, contains('another tree'));

    result = await service.sync(auto: true);
    expect(transport.calls, hasLength(1), reason: 'no automatic 409 retry');
    result = await service.sync(auto: false);
    expect(transport.calls, hasLength(1), reason: 'manual pass also holds');
  });

  test('402 quota keeps the record with the server message for the UI',
      () async {
    final service = buildService();
    final item =
        await service.enqueue('CREATE_TREE_SUBMISSION', {'client_uuid': 'q1'});
    await service.setVerified(item.itemId, true);
    transport.onSend = (type, payload) async =>
        throw http(402, detail: "You've used all 10 tree submissions.");

    final result = await service.sync(auto: true);
    expect(result.keptForRetry, 1);
    final remaining = await service.all();
    expect(remaining.first.requiresReview, isFalse,
        reason: 'quota resets daily - retryable');
    expect(remaining.first.lastErrorKind, QueueFailureKind.quota);
    expect(remaining.first.lastError, contains('10 tree submissions'));
  });

  test('401 aborts the run, preserves every record, and reports auth',
      () async {
    final service = buildService();
    final first = await service.enqueue('CREATE_TREE', {'client_uuid': 'a'});
    final second = await service.enqueue('CREATE_TREE', {'client_uuid': 'b'});
    await service.setVerified(first.itemId, true);
    await service.setVerified(second.itemId, true);
    transport.onSend =
        (type, payload) async => throw http(401, detail: 'Token expired');

    final result = await service.sync(auto: true);
    expect(result.authError, isNotNull);
    expect(result.authError, contains('Token expired'));
    expect(transport.calls, hasLength(1), reason: 'run stops at the first 401');

    final remaining = await service.all();
    expect(remaining, hasLength(2), reason: 'records preserved (safeguard 4)');
    expect(remaining.first.attempts, 1);
    expect(remaining.first.requiresReview, isFalse,
        reason: 're-login makes it syncable again');
    expect(remaining.last.attempts, 0, reason: 'untouched after abort');
  });

  test('role denial (403) is surfaced as a review hold, not a loop', () async {
    final service = buildService();
    final item = await service.enqueue('CREATE_TREE', {'client_uuid': 'r1'});
    await service.setVerified(item.itemId, true);
    transport.onSend = (type, payload) async =>
        throw http(403, detail: 'Citizen accounts cannot add official trees.');

    final result = await service.sync(auto: true);
    expect(result.heldForReview, 1);
    expect(transport.calls, hasLength(1));
    final remaining = await service.all();
    expect(remaining.first.lastErrorKind, QueueFailureKind.role);
    expect(remaining.first.lastError, contains('Citizen accounts'));
  });

  test('concurrent sync runs are refused (one at a time)', () async {
    final service = buildService();
    final item = await service.enqueue('CREATE_TREE', {'client_uuid': 'g1'});
    await service.setVerified(item.itemId, true);
    final gate = Completer<void>();
    var entered = 0;
    transport.onSend = (type, payload) async {
      entered++;
      await gate.future;
      return {'ok': true};
    };

    final first = service.sync(auto: false);
    var tries = 0;
    while (entered == 0 && tries < 100) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      tries++;
    }
    expect(entered, 1);

    final second = await service.sync(auto: false);
    expect(second.alreadyRunning, isTrue);

    gate.complete();
    final result = await first;
    expect(result.synced, 1);
    expect(await service.all(), isEmpty);
  });

  // ── Pure classifier rules ───────────────────────────────────────────────

  test('classifyFailure implements the D1/D3 decision table', () {
    // Provably undelivered: retryable for everyone.
    final undelivered = classifyFailure(
        noResponse(DioExceptionType.connectionTimeout),
        idempotent: false);
    expect(undelivered.kind, QueueFailureKind.network);
    expect(undelivered.requiresReview, isFalse);
    expect(undelivered.abortRun, isTrue);

    // Lost response: safe only with an idempotency key.
    final ambiguous = classifyFailure(
        noResponse(DioExceptionType.receiveTimeout),
        idempotent: false);
    expect(ambiguous.kind, QueueFailureKind.ambiguous);
    expect(ambiguous.requiresReview, isTrue);

    final idempotentLost = classifyFailure(
        noResponse(DioExceptionType.receiveTimeout),
        idempotent: true);
    expect(idempotentLost.kind, QueueFailureKind.network);
    expect(idempotentLost.requiresReview, isFalse);

    // Permanent server answers: review, never automatic.
    expect(classifyFailure(http(409), idempotent: true).requiresReview, isTrue);
    expect(classifyFailure(http(422), idempotent: true).requiresReview, isTrue);
    expect(classifyFailure(http(403), idempotent: true).requiresReview, isTrue);

    // 401: abort the run, keep the record.
    final auth = classifyFailure(http(401), idempotent: true);
    expect(auth.kind, QueueFailureKind.auth);
    expect(auth.abortRun, isTrue);
    expect(auth.requiresReview, isFalse);

    // 5xx: retryable with backoff.
    final server = classifyFailure(http(503), idempotent: false);
    expect(server.retryable, isTrue);
    expect(server.requiresReview, isFalse);

    // Unexpected non-Dio errors: conservative hold.
    final unknown = classifyFailure(StateError('boom'), idempotent: true);
    expect(unknown.requiresReview, isTrue);
    expect(unknown.kind, QueueFailureKind.unknown);
  });

  test('backoff grows exponentially and caps at 30 minutes', () {
    expect(backoffMs(1), 30000);
    expect(backoffMs(2), 60000);
    expect(backoffMs(3), 120000);
    expect(backoffMs(20), 1800000);
    expect(backoffMs(50), 1800000);
  });
}
