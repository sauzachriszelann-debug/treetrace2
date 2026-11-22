import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treetrace_mobile/services/tree_save_error.dart';

void main() {
  DioException failure(int? status, {dynamic data}) {
    final request = RequestOptions(path: '/trees/');
    return DioException(requestOptions: request, response: status == null ? null : Response(requestOptions: request, statusCode: status, data: data));
  }
  test('server failure is not presented as a connection problem', () {
    expect(treeSaveErrorMessage(failure(500)), contains('HTTP 500'));
    expect(treeSaveErrorMessage(failure(500)), contains('pending submission is kept'));
  });
  test('rejected fields show the API reason', () {
    expect(treeSaveErrorMessage(failure(422, data: {'detail': 'Outside inventory area'})), contains('Outside inventory area'));
  });
  test('missing response preserves uncertainty rather than claiming server save', () {
    expect(treeSaveErrorMessage(failure(null)), contains('on this device'));
    expect(treeSaveErrorMessage(failure(null)), contains('Check the backend'));
  });
}
