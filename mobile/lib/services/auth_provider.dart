import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';

/// True ONLY for a genuine authentication rejection: the server responded
/// 401 to a presented token. Network problems (no response) must never log
/// the user out - G6 safeguard 4: offline records and the session survive
/// connectivity failures and expired-but-unverifiable tokens alike.
bool isAuthRejection(Object error) =>
    error is DioException && error.response?.statusCode == 401;

/// Test seam. Production uses the defaults (real ApiService methods, the
/// 5-second splash floor); tests inject fakes so no network or timer is
/// touched.
class AuthProviderDeps {
  final Future<Map<String, dynamic>> Function()? fetchMe;
  final Future<Map<String, dynamic>> Function(String email, String password)?
      login;
  final Future<String?> Function()? readToken;
  final Future<void> Function()? clearToken;
  final Future<void> Function(Map<String, dynamic>)? saveCachedMe;
  final Future<Map<String, dynamic>?> Function()? readCachedMe;
  final Future<void> Function()? clearCachedMe;
  final Duration minimumSplash;

  const AuthProviderDeps({
    this.fetchMe,
    this.login,
    this.readToken,
    this.clearToken,
    this.saveCachedMe,
    this.readCachedMe,
    this.clearCachedMe,
    this.minimumSplash = const Duration(seconds: 5),
  });
}

class AuthProvider extends ChangeNotifier {
  AuthProvider({ApiService? apiOverride, this.deps = const AuthProviderDeps()})
      : _api = apiOverride ?? api;

  final ApiService _api;
  final AuthProviderDeps deps;

  UserModel? _user;
  bool _loading = true;
  String? _lastError;
  bool _startedOffline = false;

  UserModel? get user => _user;
  bool get loading => _loading;
  bool get isLoggedIn => _user != null;
  bool get isAdmin => _user?.isAdmin ?? false;
  String? get lastError => _lastError;

  /// True when the session could only be restored from the on-device cache
  /// (backend unreachable at startup).
  bool get startedOffline => _startedOffline;

  Future<void> init() async {
    final startedAt = DateTime.now();
    try {
      final token = await (deps.readToken ?? _api.getToken)();
      if (token != null) {
        final fetch = deps.fetchMe ?? (() => _api.getMe());
        try {
          final data = await fetch().timeout(const Duration(seconds: 10));
          _user = UserModel.fromJson(data);
          await (deps.saveCachedMe ?? _api.saveMeCache)(data);
        } on TimeoutException {
          // Slow/unreachable backend: keep the token, restore the cached
          // profile so the app and the offline queue stay usable.
          await _restoreCachedUser();
        } catch (e) {
          if (isAuthRejection(e)) {
            // Genuinely expired/invalid token: clear ONLY auth state.
            await (deps.clearToken ?? _api.clearToken)();
            await (deps.clearCachedMe ?? _api.clearMeCache)();
            _user = null;
          } else {
            // Connectivity failure: never log the user out (safeguard 4).
            await _restoreCachedUser();
          }
        }
      }
    } catch (_) {
      // Storage-level failure: preserve everything, surface logged-out state
      // without destroying records (safeguard 3).
    } finally {
      final elapsed = DateTime.now().difference(startedAt);
      if (elapsed < deps.minimumSplash) {
        await Future.delayed(deps.minimumSplash - elapsed);
      }
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _restoreCachedUser() async {
    final cached = await (deps.readCachedMe ?? _api.readMeCache)();
    if (cached != null) {
      try {
        _user = UserModel.fromJson(cached);
        _startedOffline = true;
      } catch (_) {
        _user = null;
      }
    }
  }

  Future<bool> login(String email, String password) async {
    try {
      _lastError = null;
      final doLogin =
          deps.login ?? ((String e, String p) => _api.login(e, p));
      final data = await doLogin(email, password);
      await _api.saveToken(data['access_token']);
      final fetch = deps.fetchMe ?? (() => _api.getMe());
      final me = await fetch();
      _user = UserModel.fromJson(me);
      await (deps.saveCachedMe ?? _api.saveMeCache)(me);
      _startedOffline = false;
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
    final me = await _api.getMe();
    _user = UserModel.fromJson(me);
    await (deps.saveCachedMe ?? _api.saveMeCache)(me);
    notifyListeners();
  }

  void markUpgradeRequested() {
    final current = _user;
    if (current == null) return;
    _user = current.copyWith(upgradeRequested: true);
    notifyListeners();
  }

  Future<void> logout() async {
    await (deps.clearToken ?? _api.clearToken)();
    await (deps.clearCachedMe ?? _api.clearMeCache)();
    _user = null;
    _startedOffline = false;
    notifyListeners();
  }
}
