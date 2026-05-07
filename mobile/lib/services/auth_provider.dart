import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  UserModel? _user;
  bool _loading = true;

  UserModel? get user => _user;
  bool get loading => _loading;
  bool get isLoggedIn => _user != null;
  bool get isAdmin => _user?.isAdmin ?? false;

  Future<void> init() async {
    print("DEBUG: AuthProvider.init() started");
    try {
      final token = await api.getToken();
      print("DEBUG: Token found: ${token != null}");
      if (token != null) {
        print("DEBUG: Fetching user info...");
        final data = await api.getMe();
        print("DEBUG: User data received: $data");
        _user = UserModel.fromJson(data);
      }
    } catch (e) {
      print("DEBUG: AuthProvider.init() error: $e");
      await api.clearToken();
    } finally {
      _loading = false;
      print("DEBUG: AuthProvider.init() finished, loading=false");
      notifyListeners();
    }
  }

  Future<bool> login(String email, String password) async {
    try {
      final data = await api.login(email, password);
      await api.saveToken(data['access_token']);
      final me = await api.getMe();
      _user = UserModel.fromJson(me);
      notifyListeners();
      return true;
    } catch (error) {
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
