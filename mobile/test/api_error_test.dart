import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treetrace_mobile/services/api_service.dart';
import 'dart:typed_data';

// Phase 11D: the app must tell "the backend did not answer" apart from "the
// backend says this does not exist", and must not call an admin-only endpoint
// while signed in as a non-admin.

RequestOptions _req() => RequestOptions(path: '/trees/1');

DioException _noResponse(DioExceptionType type, {Object? error}) =>
    DioException(requestOptions: _req(), type: type, error: error);

DioException _answered(int status) => DioException(
      requestOptions: _req(),
      type: DioExceptionType.badResponse,
      response: Response(requestOptions: _req(), statusCode: status),
    );

class _HealthTestAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"status":"ok"}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

class _UnreachableHealthAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      error: const SocketException('Connection refused'),
    );
  }
}

void main() {
  group('isConnectionFailure', () {
    test('is true only when no HTTP response arrived', () {
      expect(isConnectionFailure(_noResponse(DioExceptionType.connectionError)),
          isTrue);
      expect(
          isConnectionFailure(_noResponse(DioExceptionType.connectionTimeout)),
          isTrue);
      expect(isConnectionFailure(_noResponse(DioExceptionType.sendTimeout)),
          isTrue);
      expect(isConnectionFailure(_noResponse(DioExceptionType.receiveTimeout)),
          isTrue);
      // Dio parks raw transport errors under "unknown".
      expect(
          isConnectionFailure(_noResponse(DioExceptionType.unknown,
              error: const SocketException('network is unreachable'))),
          isTrue);
      expect(
          isConnectionFailure(_noResponse(DioExceptionType.unknown,
              error: const HttpException('connection closed'))),
          isTrue);
    });

    test('is false for a real server answer, including 404', () {
      expect(isConnectionFailure(_answered(404)), isFalse);
      expect(isConnectionFailure(_answered(401)), isFalse);
      expect(isConnectionFailure(_answered(403)), isFalse);
      expect(isConnectionFailure(_answered(500)), isFalse);
    });

    test('is false for cancellations and non-Dio errors', () {
      expect(
          isConnectionFailure(_noResponse(DioExceptionType.cancel)), isFalse);
      expect(
          isConnectionFailure(Exception('LateInitializationError')), isFalse);
      expect(isConnectionFailure('not an error object'), isFalse);
    });
  });

  group('isNotFoundFailure', () {
    test('detects a genuine 404 and nothing else', () {
      expect(isNotFoundFailure(_answered(404)), isTrue);
      expect(isNotFoundFailure(_answered(401)), isFalse);
      expect(isNotFoundFailure(_noResponse(DioExceptionType.connectionError)),
          isFalse);
    });
  });

  group('usesAdminUnknownSpeciesReview', () {
    test('only admins may hit the admin-only review list', () {
      expect(usesAdminUnknownSpeciesReview('admin'), isTrue);
      expect(usesAdminUnknownSpeciesReview('field_worker'), isFalse);
      expect(usesAdminUnknownSpeciesReview('citizen'), isFalse);
      expect(usesAdminUnknownSpeciesReview(null), isFalse);
    });

    test('the role strings match what the backend issues', () {
      // /api/auth/me returns role as a bare string (users.UserOut.role).
      const backendRoles = ['admin', 'field_worker', 'citizen'];
      expect(backendRoles.where(usesAdminUnknownSpeciesReview).toList(),
          ['admin']);
    });
  });
  test('backend health check returns true for a healthy server', () async {
    final dio = Dio();

    dio.httpClientAdapter = _HealthTestAdapter();

    final result = await checkBackendHealth(
      dio,
      'http://localhost:8000/api',
    );

    expect(result, isTrue);
  });
  test('backend health check returns false when server is unreachable',
      () async {
    final dio = Dio();

    dio.httpClientAdapter = _UnreachableHealthAdapter();

    final result = await checkBackendHealth(
      dio,
      'http://localhost:8000/api',
    );

    expect(result, isFalse);
  });
}
