import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';

// ── Failure classification ───────────────────────────────────────────────────
/// Outcome kinds attached to queue items after a failed sync attempt.
abstract final class QueueFailureKind {
  static const network = 'network'; // request provably NOT delivered
  static const ambiguous = 'ambiguous'; // non-idempotent, outcome uncertain
  static const auth = 'auth'; // 401
  static const quota = 'quota'; // 402
  static const role = 'role'; // 403
  static const conflict = 'conflict'; // 409 - permanent, never auto-retried
  static const validation = 'validation'; // 400/404/422
  static const server = 'server'; // 5xx
  static const missingPhoto = 'missing_photo';
  static const retriesExhausted = 'retries_exhausted';
  static const unknown = 'unknown';
}

/// Kinds a human must resolve before any sync (automatic or one-tap) may
/// touch the item again. Explicit per-item "Retry" clears the flag.
const Set<String> reviewKinds = {
  QueueFailureKind.ambiguous,
  QueueFailureKind.role,
  QueueFailureKind.conflict,
  QueueFailureKind.validation,
  QueueFailureKind.missingPhoto,
  QueueFailureKind.retriesExhausted,
  QueueFailureKind.unknown,
};

/// Queue types whose server endpoints are idempotent through client_uuid
/// (G2 trees, G4 tree-submissions): an uncertain outcome is always safe to
/// retry automatically because a replay cannot duplicate the record.
const Set<String> idempotentQueueTypes = {
  'CREATE_TREE',
  'CREATE_TREE_SUBMISSION',
};

/// Automatic sync attempts per item before it is held for review (D1-B).
const int maxAutoAttempts = 5;

String photoPurposeFor(String type) {
  switch (type) {
    case 'CREATE_TREE':
      return 'tree_photo';
    case 'CREATE_TREE_SUBMISSION':
      // Citizens may not upload purpose=tree_photo (backend role gate); the
      // existing online path uses the same purpose for citizen photos.
      return 'unknown_species';
    case 'SUBMIT_UNKNOWN':
      return 'unknown_species';
    case 'CREATE_PLANTING_RECOMMENDATION':
      return 'planting_submission';
    default:
      return 'unknown_species';
  }
}

class FailureInfo {
  final String kind;
  final bool requiresReview;
  final bool retryable;
  final bool abortRun;
  final String message;
  const FailureInfo({
    required this.kind,
    required this.requiresReview,
    required this.retryable,
    required this.abortRun,
    required this.message,
  });
}

String? _serverDetail(DioException error) {
  final data = error.response?.data;
  if (data is Map && data['detail'] != null) {
    if (data['detail'] is Map && data['detail']['message'] != null) {
      return data['detail']['message'].toString();
    }
    return data['detail'].toString();
  }
  return null;
}

/// Pure classifier: Dio failure -> disposition (D1/D3 rules).
///
/// * Provably undelivered requests (connection never established) are safe
///   retries for every type.
/// * Delivered-but-unanswered requests are safe retries ONLY for idempotent
///   types; for health logs / unknown species / planting they are AMBIGUOUS:
///   the item is retained, marked for review, and never auto-retried (D3).
/// * 409/403/422 are permanent for practical purposes: review, never auto.
/// * 401 aborts the run (auth banner; queue itself is never touched).
FailureInfo classifyFailure(Object error, {required bool idempotent}) {
  if (error is! DioException) {
    return const FailureInfo(
      kind: QueueFailureKind.unknown,
      requiresReview: true,
      retryable: false,
      abortRun: false,
      message: 'Unexpected error; held for review.',
    );
  }

  final response = error.response;
  if (response == null) {
    final notDelivered = error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.connectionError;
    if (notDelivered) {
      return const FailureInfo(
        kind: QueueFailureKind.network,
        requiresReview: false,
        retryable: true,
        abortRun: true,
        message: 'Could not reach the server - the request was not sent.',
      );
    }
    if (idempotent) {
      return const FailureInfo(
        kind: QueueFailureKind.network,
        requiresReview: false,
        retryable: true,
        abortRun: false,
        message: 'Connection lost before the response arrived. Safe to '
            'retry: this record uses an idempotency key.',
      );
    }
    return const FailureInfo(
      kind: QueueFailureKind.ambiguous,
      requiresReview: true,
      retryable: false,
      abortRun: false,
      message: 'The request may have already reached the server. Kept for '
          'review and NOT retried automatically, because this record type '
          'has no idempotency key and a blind retry could create a '
          'duplicate.',
    );
  }

  final status = response.statusCode ?? 0;
  final detail = _serverDetail(error);
  if (status == 401) {
    return FailureInfo(
      kind: QueueFailureKind.auth,
      requiresReview: false,
      retryable: false,
      abortRun: true,
      message: detail ?? 'Session expired. Sign in again to resume sync.',
    );
  }
  if (status == 402) {
    return FailureInfo(
      kind: QueueFailureKind.quota,
      requiresReview: false,
      retryable: true,
      abortRun: false,
      message: detail ?? 'Daily quota reached for this plan.',
    );
  }
  if (status == 403) {
    return FailureInfo(
      kind: QueueFailureKind.role,
      requiresReview: true,
      retryable: false,
      abortRun: false,
      message: detail ??
          'This account role is not allowed to perform the operation.',
    );
  }
  if (status == 409) {
    return FailureInfo(
      kind: QueueFailureKind.conflict,
      requiresReview: true,
      retryable: false,
      abortRun: false,
      message: detail ??
          'Conflicts with an existing record. Nothing was merged or '
              'overwritten.',
    );
  }
  if (status == 400 || status == 404 || status == 422) {
    return FailureInfo(
      kind: QueueFailureKind.validation,
      requiresReview: true,
      retryable: false,
      abortRun: false,
      message: detail ?? 'The server rejected this record (HTTP $status).',
    );
  }
  if (status >= 500) {
    return FailureInfo(
      kind: QueueFailureKind.server,
      requiresReview: false,
      retryable: true,
      abortRun: false,
      message: detail ?? 'Server error (HTTP $status). Will be retried.',
    );
  }
  return FailureInfo(
    kind: QueueFailureKind.unknown,
    requiresReview: true,
    retryable: false,
    abortRun: false,
    message: detail ?? 'Unexpected response (HTTP $status); held for review.',
  );
}

int backoffMs(int attempts) {
  // 30s, 60s, 120s, ... capped at 30 minutes.
  final exponent = (attempts - 1).clamp(0, 20);
  final ms = 30000 * (1 << exponent);
  return ms > 1800000 ? 1800000 : ms;
}

// ── Item model ───────────────────────────────────────────────────────────────

class OfflineQueueItem {
  /// Stable RFC-4122 v4 identifier, generated once at enqueue (never time-
  /// based, so same-millisecond collisions are impossible).
  final String itemId;
  String type;
  Map<String, dynamic> payload;

  /// Durable on-disk copy of the photo (documents/offline_photos/...).
  String? photoPath;
  bool verified;
  String createdAt;
  int attempts;
  String? lastError;
  String? lastErrorKind;
  bool requiresReview;
  int? nextRetryAtMs;
  int? legacyId;

  OfflineQueueItem({
    required this.itemId,
    required this.type,
    required this.payload,
    this.photoPath,
    this.verified = false,
    required this.createdAt,
    this.attempts = 0,
    this.lastError,
    this.lastErrorKind,
    this.requiresReview = false,
    this.nextRetryAtMs,
    this.legacyId,
  });

  bool get hasPhoto => photoPath != null && photoPath!.trim().isNotEmpty;

  bool get photoMissing => hasPhoto && !File(photoPath!).existsSync();

  bool get photoUploaded =>
      (payload['photo_url']?.toString().trim().isNotEmpty ?? false);

  Map<String, dynamic> toMap() => {
        'item_id': itemId,
        'type': type,
        'payload': payload,
        'photo_path': photoPath,
        'verified': verified,
        'created_at': createdAt,
        'attempts': attempts,
        'last_error': lastError,
        'last_error_kind': lastErrorKind,
        'requires_review': requiresReview,
        'next_retry_at_ms': nextRetryAtMs,
        'legacy_id': legacyId,
      };

  static OfflineQueueItem fromMap(Map<String, dynamic> map) {
    final payload = map['payload'];
    return OfflineQueueItem(
      itemId: (map['item_id'] ?? '').toString().isEmpty
          ? _fallbackId()
          : map['item_id'].toString(),
      type: (map['type'] ?? 'CREATE_TREE').toString(),
      payload: payload is Map ? Map<String, dynamic>.from(payload) : {},
      photoPath: map['photo_path']?.toString(),
      verified: map['verified'] == true,
      createdAt:
          (map['created_at'] ?? DateTime.now().toIso8601String()).toString(),
      attempts: (map['attempts'] is int) ? map['attempts'] as int : 0,
      lastError: map['last_error']?.toString(),
      lastErrorKind: map['last_error_kind']?.toString(),
      requiresReview: map['requires_review'] == true,
      nextRetryAtMs: (map['next_retry_at_ms'] is int)
          ? map['next_retry_at_ms'] as int
          : null,
      legacyId: (map['legacy_id'] is int) ? map['legacy_id'] as int : null,
    );
  }
}

String _fallbackId() => _defaultIdFactory();

String _defaultIdFactory() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

// ── Sync result ──────────────────────────────────────────────────────────────

class SyncResult {
  /// False when nothing ran (offline, already running, or nothing eligible).
  final bool ran;
  final bool alreadyRunning;
  final bool offline;
  final int synced;
  final int heldForReview; // newly flagged or newly skipped-for-review
  final int keptForRetry; // transient failures awaiting backoff
  final int skippedUnverified;
  final int skippedBackoff;
  final String? authError; // set when a 401 aborted the run

  const SyncResult({
    this.ran = false,
    this.alreadyRunning = false,
    this.offline = false,
    this.synced = 0,
    this.heldForReview = 0,
    this.keptForRetry = 0,
    this.skippedUnverified = 0,
    this.skippedBackoff = 0,
    this.authError,
  });

  static const notRun = SyncResult();
  static const alreadyRunningResult = SyncResult(alreadyRunning: true);
  static const offlineResult = SyncResult(offline: true);
}

// ── Service ──────────────────────────────────────────────────────────────────

typedef QueueSender = Future<Map<String, dynamic>> Function(
    String type, Map<String, dynamic> payload);
typedef QueuePhotoUploader = Future<String?> Function(
    String path, String purpose);
typedef OnlineCheck = Future<bool> Function();

class OfflineQueueService {
  OfflineQueueService({
    required Directory directory,
    Future<String?> Function(String key)? legacyRead,
    Future<void> Function(String key)? legacyDelete,
    OnlineCheck? isOnline,
    QueueSender? sender,
    QueuePhotoUploader? uploader,
    String Function()? idFactory,
    DateTime Function()? clock,
  })  : _dir = directory,
        _legacyRead = legacyRead,
        _legacyDelete = legacyDelete,
        _isOnline = isOnline ?? (() async => true),
        _sender = sender,
        _uploader = uploader,
        _idFactory = idFactory ?? _defaultIdFactory,
        _clock = clock ?? DateTime.now;

  static const queueFileName = 'offline_queue.json';
  static const photosDirName = 'offline_photos';
  static const legacyQueueKey = 'treetrace_offline_queue';

  final Directory _dir;
  final Future<String?> Function(String key)? _legacyRead;
  final Future<void> Function(String key)? _legacyDelete;
  final OnlineCheck _isOnline;
  final QueueSender? _sender;
  final QueuePhotoUploader? _uploader;
  final String Function() _idFactory;
  final DateTime Function() _clock;

  final List<OfflineQueueItem> _items = [];
  Future<void>? _loadFuture;
  bool _syncing = false;
  bool _legacyImported = false;
  String? corruptionNotice;
  Future<void> _writeChain = Future<void>.value();

  File get _queueFile =>
      File('${_dir.path}${Platform.pathSeparator}$queueFileName');
  Directory get _photosDir =>
      Directory('${_dir.path}${Platform.pathSeparator}$photosDirName');

  bool get syncInFlight => _syncing;

  // ── Loading: legacy import + corruption quarantine (never silent loss) ───

  Future<void> _ensureLoaded() => _loadFuture ??= _load();

  Future<void> _load() async {
    await _dir.create(recursive: true);

    var needFreshImport = false;
    if (await _queueFile.exists()) {
      try {
        final raw = await _queueFile.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is! Map ||
            decoded['schema'] != 2 ||
            decoded['items'] is! List) {
          throw const FormatException('unexpected queue envelope');
        }
        for (final entry in decoded['items'] as List) {
          if (entry is Map) {
            _items.add(
                OfflineQueueItem.fromMap(Map<String, dynamic>.from(entry)));
          }
        }
        _legacyImported = decoded['legacy_imported'] == true;
      } catch (_) {
        // Corruption: PRESERVE the bytes in a quarantine file, surface a
        // notice, and start from a clean queue. The records are never
        // silently deleted (safeguard 2).
        await _quarantineCorruptFile();
        needFreshImport = true;
      }
    } else {
      needFreshImport = true;
    }

    if (needFreshImport && !_legacyImported && _legacyRead != null) {
      await _importLegacy();
    }
    if (needFreshImport && _items.isNotEmpty) {
      await _persistNow();
    }
  }

  Future<void> _quarantineCorruptFile() async {
    try {
      final stamp = _clock().millisecondsSinceEpoch;
      final target = File(
          '${_dir.path}${Platform.pathSeparator}offline_queue.quarantine-$stamp.json');
      await _queueFile.rename(target.path);
      corruptionNotice =
          'The offline queue file was damaged. Its contents were preserved '
          'at ${target.path.split(Platform.pathSeparator).last} and were NOT '
          'replayed automatically - review them before re-entering records.';
    } catch (_) {
      corruptionNotice =
          'The offline queue file was damaged and could not be preserved. '
          'Re-check your recent offline records before relying on the queue.';
    }
  }

  /// Non-destructive legacy migration: import v1 secure-storage entries once,
  /// confirm the new store contains them, and only then remove the legacy
  /// blob. Re-running never duplicates (marker lives inside the queue file).
  Future<void> _importLegacy() async {
    String? raw;
    try {
      raw = await _legacyRead!(legacyQueueKey);
    } catch (_) {
      raw = null;
    }
    if (raw == null || raw.trim().isEmpty) {
      _legacyImported = true;
      try {
        await _persistNow();
      } catch (_) {}
      return;
    }
    var imported = 0;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final entry in decoded) {
          if (entry is! Map) continue;
          final old = Map<String, dynamic>.from(entry);
          final item = OfflineQueueItem(
            itemId: _idFactory(),
            type: (old['type'] ?? 'CREATE_TREE').toString(),
            payload: old['payload'] is Map
                ? Map<String, dynamic>.from(old['payload'] as Map)
                : {},
            photoPath: old['photo_path']?.toString(),
            verified: old['verified'] == true,
            createdAt: (old['created_at'] ?? DateTime.now().toIso8601String())
                .toString(),
            legacyId: old['id'] is int ? old['id'] as int : null,
          );
          // Upgrade the photo to durable storage while the original still
          // exists; keep the original path as fallback otherwise.
          if (item.hasPhoto) {
            final durable = await _durableCopy(item.photoPath!);
            item.photoPath = durable ?? item.photoPath;
          }
          _items.add(item);
          imported++;
        }
      }
    } catch (_) {
      corruptionNotice = '${corruptionNotice ?? ''}'
          ' The legacy offline queue could not be parsed; it was left '
          'untouched in secure storage for manual recovery.';
      _legacyImported = true; // never loop on an unparseable blob
      try {
        await _persistNow();
      } catch (_) {}
      return;
    }
    _legacyImported = true;
    await _persistNow();
    if (_items.length >= imported && imported >= 0) {
      // Confirmed: everything imported is on disk. Remove the legacy blob.
      try {
        await _legacyDelete?.call(legacyQueueKey);
      } catch (_) {
        // Leftover legacy blob is harmless: the marker prevents re-import.
      }
    }
  }

  // ── Persistence: atomic + serialized (concurrent writes cannot lose items)

  Map<String, dynamic> _envelope() => {
        'schema': 2,
        'legacy_imported': _legacyImported,
        'items': _items.map((e) => e.toMap()).toList(),
      };

  Future<void> _persistNow([String? snapshot]) async {
    final json = snapshot ?? jsonEncode(_envelope());
    final tmp = File('${_dir.path}${Platform.pathSeparator}$queueFileName.tmp');
    await tmp.writeAsString(json, flush: true);
    await tmp.rename(_queueFile.path);
  }

  /// Serializes writes; each call snapshots the CURRENT in-memory state at
  /// call time, so interleaved mutations can never overwrite newer state.
  Future<void> _persist() {
    final snapshot = jsonEncode(_envelope());

    final write = _writeChain.then((_) => _persistNow(snapshot));

    // Keep the internal chain usable after a failed write.
    _writeChain = write.catchError((Object error, StackTrace stackTrace) {
      corruptionNotice ??=
          'Warning: the offline queue could not be written to disk. '
          'Records may not survive an app restart until storage is available.';
    });

    // The caller must still receive the original write failure.
    return write;
  }

  Future<void> _awaitWrites() => _writeChain;

  // ── Photos ────────────────────────────────────────────────────────────────

  Future<String?> _durableCopy(String sourcePath) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) return null;
      await _photosDir.create(recursive: true);
      final extIndex = sourcePath.lastIndexOf('.');
      final ext = extIndex > 0 ? sourcePath.substring(extIndex) : '.jpg';
      final target = File(
          '${_photosDir.path}${Platform.pathSeparator}${_idFactory()}$ext');
      await source.copy(target.path);
      return target.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _prunePhoto(String? path) async {
    if (path == null || path.isEmpty) return;
    // Only ever delete files this service created (durable photo dir).
    if (!path.startsWith(_photosDir.path)) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  // ── Public API (mirrors the legacy ApiService surface) ────────────────────

  Future<List<OfflineQueueItem>> all() async {
    await _ensureLoaded();
    return List.unmodifiable(_items);
  }

  Future<int> count() async => (await all()).length;

  Future<OfflineQueueItem> enqueue(
    String type,
    Map<String, dynamic> payload, {
    String? photoPath,
    bool requiresReview = false,
    String? reviewReason,
  }) async {
    await _ensureLoaded();
    final item = OfflineQueueItem(
      itemId: _idFactory(),
      type: type,
      payload: Map<String, dynamic>.from(payload),
      photoPath: photoPath,
      verified: false,
      createdAt: _clock().toIso8601String(),
      requiresReview: requiresReview,
      lastError: reviewReason,
      lastErrorKind: requiresReview ? QueueFailureKind.ambiguous : null,
    );
    if (photoPath != null && photoPath.trim().isNotEmpty) {
      final durable = await _durableCopy(photoPath);
      item.photoPath = durable ?? photoPath;
    }
    _items.add(item);
    await _persist();
    return item;
  }

  Future<void> setVerified(String itemId, bool verified) async {
    await _ensureLoaded();
    for (final item in _items) {
      if (item.itemId == itemId) item.verified = verified;
    }
    await _persist();
  }

  Future<void> verifyAll() async {
    await _ensureLoaded();
    for (final item in _items) {
      item.verified = true;
    }
    await _persist();
  }

  Future<void> remove(String itemId) async {
    await _ensureLoaded();
    final before = _items.length;
    _items.removeWhere((item) => item.itemId == itemId);
    if (_items.length != before) {
      // Explicit user discard: drop the durable photo with the record.
      await _awaitWrites();
      await _persist();
    }
  }

  /// Explicit per-item retry after review: clears the hold and backoff so a
  /// manual sync may try exactly what the user asked for.
  Future<void> resolveForManualRetry(String itemId) async {
    await _ensureLoaded();
    for (final item in _items) {
      if (item.itemId == itemId) {
        item.requiresReview = false;
        item.attempts = 0;
        item.nextRetryAtMs = null;
        item.lastError = null;
        item.lastErrorKind = null;
      }
    }
    await _persist();
  }

  /// Explicit user consent to sync WITHOUT the (OS-purged) photo (D5: the
  /// record or its photo are never dropped without this kind of decision).
  Future<void> continueWithoutPhoto(String itemId) async {
    await _ensureLoaded();
    for (final item in _items) {
      if (item.itemId == itemId) {
        final path = item.photoPath;
        item.photoPath = null;
        item.requiresReview = false;
        item.attempts = 0;
        item.nextRetryAtMs = null;
        item.lastError = null;
        item.lastErrorKind = null;
        await _prunePhoto(path);
      }
    }
    await _persist();
  }

  // ── Sync engine ───────────────────────────────────────────────────────────

  Future<SyncResult> sync({required bool auto}) async {
    if (_syncing) return SyncResult.alreadyRunningResult;
    await _ensureLoaded();
    if (_sender == null) return SyncResult.notRun;
    if (!await _isOnline()) return SyncResult.offlineResult;

    _syncing = true;
    var synced = 0;
    var heldForReview = 0;
    var keptForRetry = 0;
    var skippedUnverified = 0;
    var skippedBackoff = 0;
    String? authError;

    try {
      final nowMs = _clock().millisecondsSinceEpoch;
      for (final item in List<OfflineQueueItem>.of(_items)) {
        // D1-B / safeguard 9: unverified records are NEVER uploaded, in
        // either mode.
        if (!item.verified) {
          skippedUnverified++;
          continue;
        }
        // Held records are skipped by BOTH modes: only the explicit
        // per-item retry clears them (D1: permanent conflicts are never
        // retried automatically; D3: ambiguity needs a human).
        if (item.requiresReview) {
          heldForReview++;
          continue;
        }
        if (auto) {
          if (item.attempts >= maxAutoAttempts) {
            _hold(
                item,
                QueueFailureKind.retriesExhausted,
                'Automatic retries paused after $maxAutoAttempts attempts. '
                'Review this record and retry manually or remove it.');
            heldForReview++;
            await _persist();
            continue;
          }
          final nextAt = item.nextRetryAtMs;
          if (nextAt != null && nextAt > nowMs) {
            skippedBackoff++;
            continue;
          }
        }

        // ── Photo first (D5): never create the record without the required
        // upload, and never remove the item/photo unless both succeeded. ──
        if (item.hasPhoto && !item.photoUploaded) {
          final missing = item.photoMissing;
          if (missing) {
            _hold(
                item,
                QueueFailureKind.missingPhoto,
                'The photo for this record is missing on this device. '
                'Continue without the photo or remove the record.');
            heldForReview++;
            await _persist();
            continue;
          }
          String? url;
          try {
            final uploader = _uploader;
            if (uploader == null) {
              throw StateError('photo uploader unavailable');
            }
            url = await uploader(item.photoPath!, photoPurposeFor(item.type));
            if (url == null || url.trim().isEmpty) {
              throw Exception('photo upload returned no URL');
            }
          } catch (e) {
            final info = classifyFailure(e, idempotent: true);
            if (info.requiresReview) {
              _hold(item, info.kind, 'Photo upload failed: ${info.message}');
              heldForReview++;
            } else {
              item.attempts++;
              item.lastErrorKind = info.kind;
              item.lastError = 'Photo upload failed: ${info.message}';
              item.nextRetryAtMs =
                  _clock().millisecondsSinceEpoch + backoffMs(item.attempts);
              keptForRetry++;
            }
            await _persist();
            if (info.kind == QueueFailureKind.network && info.abortRun) {
              break;
            }
            continue; // photo failed => the record is NOT created (D5)
          }
          item.payload['photo_url'] = url;
          await _persist(); // crash-safe: a later retry skips re-upload
        } else if (item.hasPhoto && item.photoMissing && item.photoUploaded) {
          // URL already on record; the missing local copy is irrelevant.
          await _prunePhoto(item.photoPath);
          item.photoPath = null;
        }

        try {
          final payload = Map<String, dynamic>.from(item.payload);
          if (item.type == 'CREATE_TREE_SUBMISSION') {
            payload['source'] = payload['source'] ?? 'mobile';
          }
          await _sender!(item.type, payload);
          // Confirmed: photo upload (if any) AND server operation both
          // succeeded - only now is the item (and its photo) removed.
          _items.remove(item);
          synced++;
          await _persist();
          await _prunePhoto(item.photoPath);
        } catch (e) {
          final info = classifyFailure(e,
              idempotent: idempotentQueueTypes.contains(item.type));
          item.attempts++;
          item.lastErrorKind = info.kind;
          item.lastError = info.message;
          if (info.requiresReview) {
            _hold(item, info.kind, info.message);
            heldForReview++;
          } else {
            item.nextRetryAtMs =
                _clock().millisecondsSinceEpoch + backoffMs(item.attempts);
            keptForRetry++;
          }
          await _persist();
          if (info.kind == QueueFailureKind.auth) {
            authError = info.message;
            break;
          }
          if (info.kind == QueueFailureKind.network && info.abortRun) {
            break;
          }
        }
      }
    } finally {
      _syncing = false;
    }

    return SyncResult(
      ran: true,
      synced: synced,
      heldForReview: heldForReview,
      keptForRetry: keptForRetry,
      skippedUnverified: skippedUnverified,
      skippedBackoff: skippedBackoff,
      authError: authError,
    );
  }

  void _hold(OfflineQueueItem item, String kind, String message) {
    item.requiresReview = true;
    item.lastErrorKind = kind;
    item.lastError = message;
  }
}
