import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treetrace_mobile/services/identification_error.dart';

void main() {
  DioException failure(int status) {
    final options = RequestOptions(path: '/ai/identify');
    return DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response(
            requestOptions: options,
            statusCode: status,
            data: {'detail': 'private-provider-error-test-marker'}));
  }

  test('HTTP errors distinguish payload, authentication, backend and quota',
      () {
    expect(identificationError(failure(413)), contains('too large'));
    expect(identificationError(failure(401)), contains('Sign in again'));
    expect(identificationError(failure(402)), contains('limit reached'));
    expect(identificationError(failure(404)), contains('configured backend'));
    expect(identificationError(failure(503)), contains('HTTP 503'));
    expect(
        identificationError(failure(503)), isNot(contains('private-provider')));
  });
  test('timeouts and invalid responses do not invent an identity', () {
    expect(
        identificationError(DioException(
            requestOptions: RequestOptions(path: '/ai/identify'),
            type: DioExceptionType.receiveTimeout)),
        contains('timed out'));
    expect(identificationError(const FormatException()),
        contains('invalid identification response'));
  });
}
