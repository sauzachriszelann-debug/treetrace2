import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';


// OLD: const String kBaseUrl = 'http://10.0.2.2:8000/api';
// For real device on same WiFi: 'http://192.168.x.x:8000/api'
// NEW:
const String kBaseUrl = 'https://treetrace-backend.onrender.com/api';


class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final _storage = const FlutterSecureStorage();
  late final Dio _dio;

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
      String fullName, String email, String password, String role) async {
    final res = await _dio.post('/auth/register', data: {
      'full_name': fullName,
      'email': email,
      'password': password,
      'role': role,
    });
    return res.data;
  }
}

final api = ApiService();
