import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'offline_queue.dart';

/// Narrow secure-storage surface. G6 safeguard: authentication cleanup must
/// NEVER wipe unrelated keys (the legacy code called deleteAll() on error,
/// which could destroy the offline queue). Implemented without deleteAll so
/// the prohibition is structural, not just a convention.
abstract class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureStore implements SecureStore {
  const FlutterSecureStore();
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

// OLD: const String kBaseUrl = 'http://10.0.2.2:8000/api';
// For real device on same WiFi: 'http://192.168.x.x:8000/api'
//
// Phase 11B: the base URL is now selected at BUILD time, never at runtime,
// so a value can never be overwritten on a device and the production default
// is preserved exactly. Local USB testing injects the loopback address:
//   flutter run --dart-define=TREETRACE_API_BASE_URL=http://127.0.0.1:8000/api
// which pairs with `adb reverse tcp:8000 tcp:8000`. A build without the
// define behaves exactly as before (the deployed Render backend).
const String kBaseUrl = String.fromEnvironment(
  'TREETRACE_API_BASE_URL',
  defaultValue: 'https://treetrace2.onrender.com/api',
);

@visibleForTesting
Future<bool> checkBackendHealth(Dio client, String baseUrl) async {
  try {
    final response = await client
        .get(
          '$baseUrl/health',
          options: Options(
            sendTimeout: const Duration(seconds: 3),
            receiveTimeout: const Duration(seconds: 3),
          ),
        )
        .timeout(const Duration(seconds: 5));

    return response.statusCode == 200 &&
        response.data is Map &&
        response.data['status'] == 'ok';
  } catch (_) {
    return false;
  }
}

/// True when [error] means the TreeTrace backend could not be reached at all:
/// no HTTP response arrived (DNS failure, refused connection, timeout).
///
/// Anything carrying a response is a real server answer and must never be
/// reported to the user as "the backend is unreachable" — a 404 means the
/// record is genuinely missing, not that the phone is offline. Screens use
/// this to pick an honest message instead of a blanket failure state.
bool isConnectionFailure(Object error) {
  if (error is! DioException) return false;
  if (error.response != null) return false; // the server answered
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
      return true;
    case DioExceptionType.unknown:
      // Dio wraps transport errors (SocketException, HttpException) here.
      return error.error is SocketException || error.error is HttpException;
    default:
      return false;
  }
}

/// True when the server answered 404: the record really is missing.
bool isNotFoundFailure(Object error) =>
    error is DioException && error.response?.statusCode == 404;

/// GET /api/ai/unknown-species is admin-only on the backend
/// (require_admin in app/api/routes/identify.py). There is no staff-scoped
/// equivalent, so non-admin staff must skip the request entirely instead of
/// provoking a 403 they cannot act on.
bool usesAdminUnknownSpeciesReview(String? role) => role == 'admin';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal()
      : _storage = FlutterSecureStore(),
        _testOnline = null;

  /// Test-only instance: injected storage/online check, no plugins, no Dio
  /// (network calls are faked by callers in tests).
  @visibleForTesting
  ApiService.forTest({
    required SecureStore storage,
    Future<bool> Function()? onlineCheck,
  })  : _storage = storage,
        _testOnline = onlineCheck;

  final SecureStore _storage;
  final _connectivity = Connectivity();
  final Future<bool> Function()? _testOnline;
  late final Dio _dio;
  StreamSubscription? _connectivitySub;
  String? _cachedToken;
  OfflineQueueService? _queueService;

  /// Result of the most recent sync run (auto or manual) for UI banners.
  SyncResult? lastSyncResult;

  static const _aiHistoryKey = 'treetrace_ai_history';
  static const _meCacheKey = 'treetrace_me_cache';

  void init() {
    _dio = Dio(BaseOptions(
      baseUrl: kBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = _cachedToken ?? await getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (error, handler) {
        if (error.response?.statusCode == 401) {
          // Scoped: token only. Queue, drafts, and caches are preserved.
          clearToken();
        }
        return handler.next(error);
      },
    ));

    // G6 (D1-B): when connectivity RETURNS, previously verified queue items
    // are synchronized automatically. Unverified items always wait for
    // explicit review; concurrent runs are refused by the service itself.
    bool? wasOffline;
    _connectivitySub ??= _connectivity.onConnectivityChanged.listen((results) {
      final online = !results.contains(ConnectivityResult.none);
      if (online && wasOffline == true) {
        unawaited(_autoSyncVerified());
      }
      wasOffline = !online;
    });
  }

  Future<void> _autoSyncVerified() async {
    try {
      if (await getToken() == null) return; // no session: keep quiet
      final result = await syncOfflineQueue(auto: true);
      debugPrint('G6 auto-sync: ${result.synced} synced, '
          '${result.heldForReview} held, ${result.keptForRetry} retrying');
    } catch (_) {
      // Auto-sync must never crash the app; the queue stays intact.
    }
  }

  Future<bool> isOnline() async {
    if (_testOnline != null) return _testOnline!();

    final result = await _connectivity.checkConnectivity();
    if (result.contains(ConnectivityResult.none)) {
      return false;
    }

    return checkBackendHealth(Dio(), kBaseUrl);
  }

  // ── Offline queue (G6: file-backed service, see offline_queue.dart) ─────

  Future<OfflineQueueService> get offlineQueueService async {
    if (_queueService != null) return _queueService!;
    Directory base;
    try {
      base = await getApplicationDocumentsDirectory();
    } catch (_) {
      // No platform channel (tests): keep the queue usable on disk.
      base = Directory.systemTemp;
    }
    _queueService = OfflineQueueService(
      directory:
          Directory('${base.path}${Platform.pathSeparator}treetrace_offline'),
      legacyRead: _storage.read,
      legacyDelete: _storage.delete,
      isOnline: isOnline,
      sender: _dispatchQueueItem,
      uploader: (path, purpose) =>
          uploadPhotoStrict(File(path), purpose: purpose),
    );
    return _queueService!;
  }

  Future<int> queuedCount() async => (await offlineQueueService).count();

  Future<void> queueOfflineAction(
    String type,
    Map<String, dynamic> payload, {
    String? photoPath,
    bool requiresReview = false,
    String? reviewReason,
  }) async {
    await (await offlineQueueService).enqueue(
      type,
      payload,
      photoPath: photoPath,
      requiresReview: requiresReview,
      reviewReason: reviewReason,
    );
  }

  Future<List<OfflineQueueItem>> offlineQueue() async =>
      (await offlineQueueService).all();

  Future<void> setOfflineActionVerified(String itemId, bool verified) async {
    await (await offlineQueueService).setVerified(itemId, verified);
  }

  Future<void> verifyAllOfflineActions() async {
    await (await offlineQueueService).verifyAll();
  }

  Future<void> deleteOfflineAction(String itemId) async {
    await (await offlineQueueService).remove(itemId);
  }

  Future<SyncResult> syncOfflineQueue({bool auto = false}) async {
    final service = await offlineQueueService;
    final result = await service.sync(auto: auto);
    lastSyncResult = result;
    return result;
  }

  /// Routes a queue item to its endpoint. Trees and tree-submissions are
  /// idempotent through client_uuid (G2/G4); the other types rely on the
  /// queue's ambiguity handling (D3 - see classifyFailure).
  Future<Map<String, dynamic>> _dispatchQueueItem(
      String type, Map<String, dynamic> payload) async {
    switch (type) {
      case 'CREATE_TREE':
        return await createTree(payload);
      case 'CREATE_TREE_SUBMISSION':
        return await createTreeSubmission(payload);
      case 'CREATE_HEALTH_LOG':
        return await createHealthLog(payload);
      case 'SUBMIT_UNKNOWN':
        return await submitUnknownSpecies(payload);
      case 'CREATE_PLANTING_RECOMMENDATION':
        return await createPlantingRecommendation(payload);
      default:
        throw StateError('Unknown offline queue type: $type');
    }
  }

  // ── Idempotent submission key (G2) ─────────────────────────────────────
  /// Generates an RFC 4122 v4 UUID without adding a dependency.
  String generateClientUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static const _pendingDraftKey = 'treetrace_tree_draft';

  /// Pending submission envelope (key + payload snapshot). Survives app
  /// restarts; cleared only on confirmed success or explicit discard.
  Future<Map<String, dynamic>?> readPendingDraft() async {
    final raw = await _storage.read(_pendingDraftKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> writePendingDraft(Map<String, dynamic> draft) async {
    await _storage.write(_pendingDraftKey, jsonEncode(draft));
  }

  Future<void> clearPendingDraft() async {
    await _storage.delete(_pendingDraftKey);
  }

  /// Reads the pending draft while distinguishing three cases:
  ///  - {'draft': Map, 'error': null}         a readable draft;
  ///  - {'draft': null, 'error': null}        nothing stored;
  ///  - {'draft': null, 'error': ...}         stored data exists but could
  ///    not be recovered; 'raw' carries whatever was read, if anything.
  /// Callers must never overwrite stored data when 'error' is set unless
  /// the user explicitly confirmed the overwrite.
  Future<Map<String, dynamic>> readPendingDraftResult() async {
    String? raw;
    try {
      raw = await _storage.read(_pendingDraftKey);
    } catch (_) {
      return {'draft': null, 'error': 'storage', 'raw': null};
    }
    if (raw == null || raw.isEmpty) {
      return {'draft': null, 'error': null, 'raw': null};
    }
    try {
      return {
        'draft': Map<String, dynamic>.from(jsonDecode(raw) as Map),
        'error': null,
        'raw': null,
      };
    } catch (_) {
      // Unparseable but still present: preserve the raw bytes for the UI.
      return {'draft': null, 'error': 'unreadable', 'raw': raw};
    }
  }

  Future<List<Map<String, dynamic>>> aiIdentificationHistory() async {
    final raw = await _storage.read(_aiHistoryKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _recordAiIdentification(Map<String, dynamic> result) async {
    final history = await aiIdentificationHistory();
    history.insert(0, {
      'common_name':
          result['common_name'] ?? result['possible_name'] ?? 'Unknown species',
      'scientific_name': result['scientific_name'],
      'confidence': result['confidence'] ?? 'AI result',
      'status': result['endangered_status'] ?? result['status'] ?? 'Not Listed',
      'protected': result['protected'] == true,
      'not_identified': result['not_identified'] == true,
      'created_at': DateTime.now().toIso8601String(),
    });
    await _storage.write(
      _aiHistoryKey,
      jsonEncode(history.take(30).toList()),
    );
  }

  Future<void> saveToken(String token) async {
    _cachedToken = token;
    await _storage.write('token', token);
  }

  Future<void> clearToken() async {
    _cachedToken = null;
    // G6 safeguard 3: ONLY the token key is touched. Queue, drafts, AI
    // history, and the profile cache always survive auth cleanup.
    try {
      await _storage.delete('token');
    } catch (_) {}
  }

  Future<String?> getToken() async {
    if (_cachedToken != null) return _cachedToken;
    try {
      _cachedToken = await _storage.read('token');
      return _cachedToken;
    } catch (_) {
      // A read failure must never destroy stored records (safeguard 3).
      _cachedToken = null;
      return null;
    }
  }

  // ── Cached profile: lets an offline cold start keep the session usable ──
  Future<void> saveMeCache(Map<String, dynamic> data) async {
    try {
      await _storage.write(_meCacheKey, jsonEncode(data));
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> readMeCache() async {
    try {
      final raw = await _storage.read(_meCacheKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearMeCache() async {
    try {
      await _storage.delete(_meCacheKey);
    } catch (_) {}
  }

  // ── Auth ──────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> login(String email, String password) async {
    final res = await _dio.post('/auth/login', data: {
      'email': email,
      'password': password,
    });
    return res.data;
  }

  Future<Map<String, dynamic>> getMe() async {
    final res = await _dio.get('/auth/me');
    return res.data;
  }

  Future<Map<String, dynamic>> requestUpgrade() async {
    final res = await _dio.post('/users/request-upgrade');
    return res.data;
  }

  Future<List<dynamic>> getUsers() async {
    final res = await _dio.get('/users/');
    return res.data;
  }

  Future<List<dynamic>> getUnknownSpeciesReview() async {
    final res = await _dio.get('/ai/unknown-species');
    return res.data;
  }

  Future<Map<String, dynamic>> reviewUnknownSpecies(
      int id, Map<String, dynamic> data) async {
    final res = await _dio.put('/ai/unknown-species/$id/review', data: data);
    return Map<String, dynamic>.from(res.data);
  }

  // ── Trees ─────────────────────────────────────────────────────────────────
  Future<List<dynamic>> getTrees({int limit = 200}) async {
    final res = await _dio.get('/trees/', queryParameters: {'limit': limit});
    return res.data;
  }

  Future<List<dynamic>> getQrPrintLabels() async {
    final res = await _dio.get('/trees/qr-print');
    return res.data;
  }

  Future<Map<String, dynamic>> getRoutePlan({
    String? barangay,
    String? healthStatus,
    int limit = 15,
  }) async {
    final res = await _dio.get('/trees/route-plan', queryParameters: {
      'limit': limit,
      if (barangay != null && barangay.trim().isNotEmpty)
        'barangay': barangay.trim(),
      if (healthStatus != null && healthStatus.trim().isNotEmpty)
        'health_status': healthStatus.trim(),
    });
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> getRoleAnalytics() async {
    final res = await _dio.get('/users/analytics/role');
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> getEvaluationResults() async {
    final res = await _dio.get('/evaluation/results');
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> importEvaluationCsv(
      {bool replace = true}) async {
    final res = await _dio.post(
      '/evaluation/import-csv',
      queryParameters: {'replace': replace},
    );
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> createEvaluationRow(
      Map<String, dynamic> data) async {
    final res = await _dio.post('/evaluation/rows', data: data);
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> getTree(int id) async {
    final res = await _dio.get('/trees/$id');
    return res.data;
  }

  Future<Map<String, dynamic>> createTree(Map<String, dynamic> data) async {
    final res = await _dio.post('/trees/', data: data);
    return res.data;
  }

  /// G4: citizens create PENDING tree submissions, never official trees.
  /// Idempotent through client_uuid exactly like createTree (G2).
  Future<Map<String, dynamic>> createTreeSubmission(
      Map<String, dynamic> data) async {
    final res = await _dio.post('/tree-submissions/', data: data);
    return res.data;
  }

  /// G4: the caller's own submissions with their review decisions.
  Future<List<dynamic>> getMyTreeSubmissions() async {
    final res = await _dio.get('/tree-submissions/my');
    return res.data;
  }

  /// G3 advisory duplicate-prevention lookup: existing trees near a
  /// proposed GPS point. The short receive timeout keeps the check from
  /// hanging a registration indefinitely; callers must treat a failure as
  /// "unknown", never as "no matches".
  Future<List<Map<String, dynamic>>> getNearbyTrees({
    required double lat,
    required double lng,
    double radiusM = 15,
    int limit = 5,
    String? commonName,
    String? scientificName,
  }) async {
    final res = await _dio.get(
      '/trees/nearby',
      queryParameters: {
        'lat': lat,
        'lng': lng,
        'radius_m': radiusM,
        'limit': limit,
        if (commonName != null && commonName.isNotEmpty)
          'common_name': commonName,
        if (scientificName != null && scientificName.isNotEmpty)
          'scientific_name': scientificName,
      },
      options: Options(receiveTimeout: const Duration(seconds: 8)),
    );
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> updateTree(
      int id, Map<String, dynamic> data) async {
    final res = await _dio.patch('/trees/$id', data: data);
    return res.data;
  }

  Future<void> deleteTree(int id) async {
    await _dio.delete('/trees/$id');
  }

  // ── Health Logs ───────────────────────────────────────────────────────────
  Future<List<dynamic>> getHealthLogs({int limit = 50, int? treeId}) async {
    final res = await _dio.get(
      '/health-logs/',
      queryParameters: {
        'limit': limit,
        if (treeId != null) 'tree_id': treeId,
      },
    );
    return res.data;
  }

  Future<List<dynamic>> getTreeHealthLogs(int treeId) async {
    final res = await _dio.get('/public/tree/$treeId/health-logs');
    return res.data;
  }

  Future<Map<String, dynamic>> createHealthLog(
      Map<String, dynamic> data) async {
    final res = await _dio.post('/health-logs/', data: data);
    return res.data;
  }

  Future<void> deleteHealthLog(int id) async {
    await _dio.delete('/health-logs/$id');
  }

  // ── AI Identify ───────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getAiUsage() async {
    final res = await _dio.get('/ai/usage');
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> identifyTree(File imageFile) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        imageFile.path,
        filename: imageFile.path.split('/').last,
      ),
    });
    // Note: Don't set Content-Type header manually, Dio handles boundary automatically for FormData
    final res = await _dio.post(
      '/ai/identify',
      data: formData,
      options: Options(
        contentType: 'multipart/form-data',
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 120),
      ),
    );
    await _recordAiIdentification(res.data);
    return res.data;
  }

  Future<Map<String, dynamic>> submitUnknownSpecies(
      Map<String, dynamic> data) async {
    final res = await _dio.post('/ai/unknown-species', data: data);
    return res.data;
  }

  Future<List<dynamic>> getMyUnknownSpecies() async {
    final res = await _dio.get('/ai/my-unknown-species');
    return res.data;
  }

  Future<Map<String, dynamic>> measureDbh(
    File imageFile, {
    required String referenceHint,
    required String method,
    double? knownDistanceM,
  }) async {
    final bytes = await imageFile.readAsBytes();
    final res = await _dio.post('/ai/measure-dbh', data: {
      'image_base64': base64Encode(bytes),
      'content_type': 'image/jpeg',
      'reference_hint': referenceHint,
      'method': method,
      'known_distance_m': knownDistanceM,
    });
    return res.data;
  }

  // ── Public ────────────────────────────────────────────────────────────────
  Future<List<dynamic>> getPublicTrees() async {
    final res = await _dio.get('/public/trees/all');
    return res.data;
  }

  Future<Map<String, dynamic>> getPublicTree(String id) async {
    final res = await _dio.get('/public/tree/$id');
    return res.data;
  }

  // ── Upload photo ──────────────────────────────────────────────────────────
  DioMediaType _imageContentType(File file) {
    final extension = file.path.split('.').last.toLowerCase();
    return switch (extension) {
      'jpg' || 'jpeg' => DioMediaType('image', 'jpeg'),
      'png' => DioMediaType('image', 'png'),
      'webp' => DioMediaType('image', 'webp'),
      'gif' => DioMediaType('image', 'gif'),
      _ => DioMediaType('application', 'octet-stream'),
    };
  }

  /// Strict variant used by the offline queue: DioException propagates so
  /// the sync engine can classify it (network vs server vs auth).
  Future<String?> uploadPhotoStrict(File file,
      {required String purpose}) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path,
          filename: file.path.split('/').last,
          contentType: _imageContentType(file)),
      'purpose': purpose,
    });
    final res = await _dio.post(
      '/storage/upload-photo',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
    return res.data['file_url'];
  }

  Future<String?> uploadPhoto(File file, {required String purpose}) async {
    try {
      return await uploadPhotoStrict(file, purpose: purpose);
    } catch (_) {
      return null;
    }
  }

  // ── Community structure ───────────────────────────────────────────────────
  Future<Map<String, dynamic>> getCommunityStructure() async {
    final res = await _dio.get('/ai/community-structure');
    return res.data;
  }

  Future<Map<String, dynamic>> getPlantingSuggestions(
      {String? barangay}) async {
    final res = await _dio.get(
      '/planting/suggestions',
      queryParameters: {
        if (barangay != null && barangay.trim().isNotEmpty)
          'barangay': barangay.trim(),
      },
    );
    return Map<String, dynamic>.from(res.data);
  }

  Future<List<dynamic>> getPlantingRecommendations({String? barangay}) async {
    final res = await _dio.get(
      '/planting/',
      queryParameters: {
        if (barangay != null && barangay.trim().isNotEmpty)
          'barangay': barangay.trim(),
      },
    );
    return res.data;
  }

  Future<Map<String, dynamic>> createPlantingRecommendation(
      Map<String, dynamic> data) async {
    final res = await _dio.post('/planting/', data: data);
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> updatePlantingRecommendation(
      int id, Map<String, dynamic> data) async {
    final res = await _dio.patch('/planting/$id', data: data);
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> getTreeWiki(int treeId) async {
    final res = await _dio.get('/public/tree/$treeId/wiki');
    return res.data;
  }

  Future<Map<String, dynamic>> register(
      String fullName, String email, String password) async {
    final res = await _dio.post('/auth/register', data: {
      'full_name': fullName,
      'email': email,
      'password': password,
    });
    return res.data;
  }
}

final api = ApiService();
