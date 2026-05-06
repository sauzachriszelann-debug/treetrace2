import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:connectivity_plus/connectivity_plus.dart';


// OLD: const String kBaseUrl = 'http://10.0.2.2:8000/api';
// For real device on same WiFi: 'http://192.168.x.x:8000/api'
// NEW:
const String kBaseUrl = 'https://treetrace-1o7l.onrender.com/api';


class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final _storage = const FlutterSecureStorage();
  final _connectivity = Connectivity();
  late final Dio _dio;
  StreamSubscription? _connectivitySub;

  static const _queueKey = 'treetrace_offline_queue';

  void init() {
    _dio = Dio(BaseOptions(
      baseUrl: kBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: 'token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (error, handler) {
        if (error.response?.statusCode == 401) {
          _storage.delete(key: 'token');
        }
        return handler.next(error);
      },
    ));

    _connectivitySub ??= _connectivity.onConnectivityChanged.listen((result) {
      if (!result.contains(ConnectivityResult.none)) {
        syncOfflineQueue();
      }
    });
    syncOfflineQueue();
  }

  Future<bool> isOnline() async {
    final result = await _connectivity.checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  Future<List<Map<String, dynamic>>> _readQueue() async {
    final raw = await _storage.read(key: _queueKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<int> queuedCount() async => (await _readQueue()).length;

  Future<void> _writeQueue(List<Map<String, dynamic>> queue) =>
      _storage.write(key: _queueKey, value: jsonEncode(queue));

  Future<void> queueOfflineAction(String type, Map<String, dynamic> payload,
      {String? photoPath}) async {
    final queue = await _readQueue();
    queue.add({
      'id': DateTime.now().millisecondsSinceEpoch,
      'type': type,
      'payload': payload,
      'photo_path': photoPath,
      'created_at': DateTime.now().toIso8601String(),
    });
    await _writeQueue(queue);
  }

  Future<int> syncOfflineQueue() async {
    if (!await isOnline()) return 0;
    final queue = await _readQueue();
    if (queue.isEmpty) return 0;

    final remaining = <Map<String, dynamic>>[];
    var synced = 0;
    for (final item in queue) {
      try {
        final payload = Map<String, dynamic>.from(item['payload'] ?? {});
        final photoPath = item['photo_path'] as String?;
        if (item['type'] == 'CREATE_TREE') {
          if (photoPath != null && photoPath.isNotEmpty && File(photoPath).existsSync()) {
            payload['photo_url'] = await uploadPhoto(File(photoPath));
          }
          await createTree(payload);
        } else if (item['type'] == 'SUBMIT_UNKNOWN') {
          if (photoPath != null && photoPath.isNotEmpty && File(photoPath).existsSync()) {
            payload['photo_url'] = await uploadPhoto(File(photoPath)) ?? '';
          }
          await submitUnknownSpecies(payload);
        }
        synced++;
      } catch (_) {
        remaining.add(item);
      }
    }
    await _writeQueue(remaining);
    return synced;
  }

  Future<void> saveToken(String token) =>
      _storage.write(key: 'token', value: token);

  Future<void> clearToken() => _storage.delete(key: 'token');

  Future<String?> getToken() => _storage.read(key: 'token');

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

  // ── Trees ─────────────────────────────────────────────────────────────────
  Future<List<dynamic>> getTrees({int limit = 200}) async {
    final res = await _dio.get('/trees/', queryParameters: {'limit': limit});
    return res.data;
  }

  Future<Map<String, dynamic>> getTree(int id) async {
    final res = await _dio.get('/trees/$id');
    return res.data;
  }

  Future<Map<String, dynamic>> createTree(Map<String, dynamic> data) async {
    final res = await _dio.post('/trees/', data: data);
    return res.data;
  }

  Future<Map<String, dynamic>> updateTree(
      int id, Map<String, dynamic> data) async {
    final res = await _dio.put('/trees/$id', data: data);
    return res.data;
  }

  Future<void> deleteTree(int id) async {
    await _dio.delete('/trees/$id');
  }

  // ── Health Logs ───────────────────────────────────────────────────────────
  Future<List<dynamic>> getHealthLogs({int limit = 50}) async {
    final res =
        await _dio.get('/health-logs/', queryParameters: {'limit': limit});
    return res.data;
  }

  Future<List<dynamic>> getTreeHealthLogs(int treeId) async {
    final res = await _dio.get('/health-logs/tree/$treeId');
    return res.data;
  }

  Future<Map<String, dynamic>> createHealthLog(
      Map<String, dynamic> data) async {
    final res = await _dio.post('/health-logs/', data: data);
    return res.data;
  }

  // ── AI Identify ───────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> identifyTree(File imageFile) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        imageFile.path,
        filename: imageFile.path.split('/').last,
      ),
    });
    // Note: Don't set Content-Type header manually, Dio handles boundary automatically for FormData
    final res = await _dio.post('/ai/identify', data: formData);
    return res.data;
  }

  Future<Map<String, dynamic>> submitUnknownSpecies(
      Map<String, dynamic> data) async {
    final res = await _dio.post('/ai/unknown-species', data: data);
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
  Future<String?> uploadPhoto(File file) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path,
            filename: file.path.split('/').last),
      });
      final res = await _dio.post('/storage/upload-photo', data: formData);
      return res.data['file_url'];
    } catch (_) {
      return null;
    }
  }

  // ── Community structure ───────────────────────────────────────────────────
  Future<Map<String, dynamic>> getCommunityStructure() async {
    final res = await _dio.get('/ai/community-structure');
    return res.data;
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
