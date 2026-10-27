import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treetrace_mobile/screens/tree_detail_screen.dart';
import 'package:treetrace_mobile/services/api_service.dart';

// Phase 11D regression coverage for the tree-detail empty state: a field
// worker tapping a tree while the backend is unreachable must NOT be told the
// tree does not exist.
//
// These are pure tests on purpose. The screen talks to the process-wide
// `api` singleton, whose base URL is the build-time constant; under
// `flutter test` that constant is the deployed default, so pumping the screen
// would attempt a real request. The classification (network vs 404) and the
// resulting message are therefore tested directly, with no socket opened.

DioException _noResponse(DioExceptionType type, {Object? error}) =>
    DioException(requestOptions: RequestOptions(path: '/trees/3'), type: type, error: error);

DioException _answered(int status) => DioException(
      requestOptions: RequestOptions(path: '/trees/3'),
      type: DioExceptionType.badResponse,
      response: Response(
          requestOptions: RequestOptions(path: '/trees/3'), statusCode: status),
    );

void main() {
  group('treeDetailEmptyMessage', () {
    test('reports an unreachable server honestly', () {
      expect(treeDetailEmptyMessage(unreachable: true),
          contains('Cannot reach the TreeTrace server'));
      expect(treeDetailEmptyMessage(unreachable: true),
          isNot(contains('not found')));
    });

    test('reports a genuine miss as not found', () {
      expect(treeDetailEmptyMessage(unreachable: false), 'Tree not found');
    });
  });

  group('the message the screen will render for each failure', () {
    test('a dropped connection maps to the connection message', () {
      final message = treeDetailEmptyMessage(
          unreachable:
              isConnectionFailure(_noResponse(DioExceptionType.connectionError)));
      expect(message, contains('Cannot reach the TreeTrace server'));
    });

    test('a dropped connection wrapped by Dio as "unknown" maps the same way', () {
      final message = treeDetailEmptyMessage(
          unreachable: isConnectionFailure(_noResponse(DioExceptionType.unknown,
              error: const SocketException('network is unreachable'))));
      expect(message, contains('Cannot reach the TreeTrace server'));
    });

    test('a real 404 still maps to "Tree not found"', () {
      final message = treeDetailEmptyMessage(
          unreachable: isConnectionFailure(_answered(404)));
      expect(message, 'Tree not found');
    });

    test('a rejected token (401) is not mistaken for an offline device', () {
      // An expired session must never be reported as a connectivity problem.
      final message = treeDetailEmptyMessage(
          unreachable: isConnectionFailure(_answered(401)));
      expect(message, 'Tree not found');
      expect(isConnectionFailure(_answered(401)), isFalse);
    });
  });
}
