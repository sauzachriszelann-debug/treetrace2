import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  UserModel? _user;
  bool _loading = true;
  String? _lastError;

  UserModel? get user => _user;
  bool get loading => _loading;
  bool get isLoggedIn => _user != null;
  bool get isAdmin => _user?.isAdmin ?? false;
  String? get lastError => _lastError;

  Future<void> init() async {
    final startedAt = DateTime.now();
    print("DEBUG: AuthProvider.init() started");
    try {
      final token = await api.getToken();
      print("DEBUG: Token found: ${token != null}");
      if (token != null) {
        print("DEBUG: Fetching user info...");
        final data = await api.getMe().timeout(const Duration(seconds: 10));
        print("DEBUG: User data received: $data");
        _user = UserModel.fromJson(data);
      }
    } on TimeoutException {
      print("DEBUG: AuthProvider.init() timed out after 10 seconds");
    } catch (e) {
      print("DEBUG: AuthProvider.init() error: $e");
      await api.clearToken();
    } finally {
      final elapsed = DateTime.now().difference(startedAt);
      const minimumSplashTime = Duration(seconds: 5);
      if (elapsed < minimumSplashTime) {
        await Future.delayed(minimumSplashTime - elapsed);
      }
      _loading = false;
      print("DEBUG: AuthProvider.init() finished, loading=false");
      notifyListeners();
    }
  }

  Future<bool> login(String email, String password) async {
    try {
      _lastError = null;
      final data = await api.login(email, password);
      await api.saveToken(data['access_token']);
      final me = await api.getMe();
      _user = UserModel.fromJson(me);
      notifyListeners();
      return true;
    } catch (error) {
      if (error is DioException) {
        final detail = error.response?.data is Map
            ? error.response?.data['detail']?.toString()
            : null;
        _lastError = detail ??
            (error.response?.statusCode != null
                ? 'Login failed with status ${error.response?.statusCode}.'
                : 'Cannot reach the backend. Check internet or wake Render.');
      } else {
        _lastError = 'Login failed. Please try again.';
      }
      debugPrint('DEBUG: login failed: $error');
      return false;
    }
  }

  Future<void> refreshUser() async {
    final me = await api.getMe();
    _user = UserModel.fromJson(me);
    notifyListeners();
  }

  void markUpgradeRequested() {
    final current = _user;
    if (current == null) return;
    _user = current.copyWith(upgradeRequested: true);
    notifyListeners();
  }

  Future<void> logout() async {
    await api.clearToken();
    _user = null;
    notifyListeners();
  }
}
