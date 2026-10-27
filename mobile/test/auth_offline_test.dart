import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treetrace_mobile/services/api_service.dart';
import 'package:treetrace_mobile/services/auth_provider.dart';
import 'package:treetrace_mobile/services/offline_queue.dart';

class FakeSecureStore implements SecureStore {
  final Map<String, String> data = {};
  final List<String> deletes = [];
  bool failReads = false;

  @override
  Future<String?> read(String key) async {
    if (failReads) throw Exception('keystore unavailable');
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    deletes.add(key);
    data.remove(key);
  }
}

DioException dio401() => DioException(
      requestOptions: RequestOptions(path: '/auth/me'),
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: RequestOptions(path: '/auth/me'),
        statusCode: 401,
        data: {'detail': 'Token expired'},
      ),
    );

DioException connectionDown() => DioException(
      requestOptions: RequestOptions(path: '/auth/me'),
      type: DioExceptionType.connectionError,
    );

Map<String, dynamic> meMap({int id = 7, String role = 'field_worker'}) => {
      'id': id,
      'full_name': 'Field Worker',
      'email': 'fw@example.test',
      'role': role,
      'is_active': true,
      'subscription_plan': 'free',
      'upgrade_requested': false,
      'ai_identifications_today': 0,
      'unknown_submissions_today': 0,
    };

void main() {
  late FakeSecureStore store;
  late ApiService api;

  setUp(() {
    store = FakeSecureStore();
    api = ApiService.forTest(storage: store, onlineCheck: () async => false);
  });

  AuthProvider providerWith(AuthProviderDeps deps) =>
      AuthProvider(apiOverride: api, deps: deps);

  // ── Pure decision rule ──────────────────────────────────────────────────

  test('isAuthRejection is true only for an actual 401 response', () {
    expect(isAuthRejection(dio401()), isTrue);
    expect(isAuthRejection(connectionDown()), isFalse,
        reason: 'no response is a network problem, not an auth rejection');
    expect(isAuthRejection(TimeoutException('x')), isFalse);
    expect(isAuthRejection(StateError('boom')), isFalse);
  });

  // ── Token & record preservation (safeguards 3 & 4) ──────────────────────

  test('getToken read failure never deletes stored records', () async {
    store.data['token'] = 'tok';
    store.data[OfflineQueueService.legacyQueueKey] = '[]';
    store.data['treetrace_tree_draft'] = '{"key":"k"}';
    store.failReads = true;

    final token = await api.getToken();
    expect(token, isNull);
    expect(store.deletes, isEmpty, reason: 'no deleteAll, ever (safeguard 3)');
    expect(store.data['token'], 'tok');
    expect(store.data[OfflineQueueService.legacyQueueKey], '[]');
    expect(store.data['treetrace_tree_draft'], '{"key":"k"}');
  });

  test('clearToken removes only the token key', () async {
    store.data['token'] = 'tok';
    store.data[OfflineQueueService.legacyQueueKey] = '[]';
    store.data['treetrace_tree_draft'] = '{"key":"k"}';

    await api.clearToken();
    expect(store.deletes, ['token']);
    expect(store.data.containsKey('token'), isFalse);
    expect(store.data[OfflineQueueService.legacyQueueKey], '[]',
        reason: 'offline queue survives auth cleanup');
    expect(store.data['treetrace_tree_draft'], '{"key":"k"}');
  });

  test('401 at startup clears auth state only; other keys survive',
      () async {
    store.data['token'] = 'expired';
    store.data['treetrace_me_cache'] = jsonEncode(meMap());
    store.data[OfflineQueueService.legacyQueueKey] = '[]';

    final provider = providerWith(AuthProviderDeps(
      fetchMe: () async => throw dio401(),
      minimumSplash: Duration.zero,
    ));
    await provider.init();

    expect(provider.isLoggedIn, isFalse);
    expect(store.data.containsKey('token'), isFalse);
    expect(store.data.containsKey('treetrace_me_cache'), isFalse,
        reason: 'stale profile must not resurrect a dead session');
    expect(store.data[OfflineQueueService.legacyQueueKey], '[]',
        reason: 'records untouched by an expired login');
  });

  // ── Offline cold start (safeguard 4) ────────────────────────────────────

  test('network failure at startup keeps the session and restores the '
      'cached profile', () async {
    store.data['token'] = 'tok';
    store.data['treetrace_me_cache'] = jsonEncode(meMap(id: 42));

    final provider = providerWith(AuthProviderDeps(
      fetchMe: () async => throw connectionDown(),
      minimumSplash: Duration.zero,
    ));
    await provider.init();

    expect(provider.isLoggedIn, isTrue);
    expect(provider.user?.id, 42);
    expect(provider.startedOffline, isTrue);
    expect(store.data['token'], 'tok', reason: 'no logout while offline');
    expect(store.deletes, isEmpty);
  });

  test('slow backend at startup times out into the cached profile, not a '
      'logout', () async {
    store.data['token'] = 'tok';
    store.data['treetrace_me_cache'] = jsonEncode(meMap(id: 9));

    final provider = providerWith(AuthProviderDeps(
      fetchMe: () async => throw TimeoutException('slow'),
      minimumSplash: Duration.zero,
    ));
    await provider.init();

    expect(provider.isLoggedIn, isTrue);
    expect(provider.user?.id, 9);
    expect(store.data['token'], 'tok');
  });

  test('startup without a token stays logged out and deletes nothing',
      () async {
    final provider = providerWith(
        const AuthProviderDeps(minimumSplash: Duration.zero));
    await provider.init();

    expect(provider.isLoggedIn, isFalse);
    expect(store.deletes, isEmpty);
  });

  // ── Login writes token + profile cache ──────────────────────────────────

  test('successful login stores the token and caches the profile', () async {
    final provider = providerWith(AuthProviderDeps(
      login: (email, password) async => {'access_token': 'fresh-token'},
      fetchMe: () async => meMap(id: 5, role: 'admin'),
      minimumSplash: Duration.zero,
    ));

    final ok = await provider.login('fw@example.test', 'pw');
    expect(ok, isTrue);
    expect(store.data['token'], 'fresh-token');
    expect(jsonDecode(store.data['treetrace_me_cache']!)['id'], 5);
    expect(provider.isAdmin, isTrue);
    expect(provider.startedOffline, isFalse);
  });

  test('logout clears token and profile cache but no records', () async {
    store.data['treetrace_tree_draft'] = '{"key":"k"}';
    store.data['treetrace_offline_queue'] = '[]';
    final provider = providerWith(
        const AuthProviderDeps(minimumSplash: Duration.zero));
    await provider.logout();

    expect(store.data.containsKey('treetrace_me_cache'), isFalse);
    expect(store.deletes, isNot(contains('treetrace_offline_queue')));
    expect(store.deletes, isNot(contains('treetrace_tree_draft')));
    expect(store.data['treetrace_tree_draft'], '{"key":"k"}');
    expect(store.data['treetrace_offline_queue'], '[]');
  });
}
