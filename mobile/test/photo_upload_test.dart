import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treetrace_mobile/services/api_service.dart';

class _MemoryStore implements SecureStore {
  @override
  Future<void> delete(String key) async {}

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}
}

class _UploadAdapter implements HttpClientAdapter {
  _UploadAdapter({this.responseBody, this.error});

  final String? responseBody;
  final Object? error;
  RequestOptions? request;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    await requestStream?.drain<void>();
    if (error != null) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: error,
      );
    }
    return ResponseBody.fromString(
      responseBody!,
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

void main() {
  late Directory temp;
  late File photo;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('photo_upload_test');
    photo = File('${temp.path}${Platform.pathSeparator}tree.jpg');
    await photo.writeAsBytes([0xff, 0xd8, 0xff, 0xd9]);
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  ApiService serviceFor(_UploadAdapter adapter) => ApiService.forTest(
        storage: _MemoryStore(),
        dio: Dio(BaseOptions(baseUrl: 'https://api.example.test/api'))
          ..httpClientAdapter = adapter,
      );

  test('required photo upload returns the stored URL', () async {
    final adapter = _UploadAdapter(
      responseBody: '{"file_url":"https://cdn.example.test/tree.jpg"}',
    );

    final url = await serviceFor(adapter).uploadPhotoRequired(
      photo,
      purpose: 'tree_photo',
    );

    expect(url, 'https://cdn.example.test/tree.jpg');
    expect(adapter.request?.path, '/storage/upload-photo');
    expect(adapter.request?.method, 'POST');
  });

  test('required photo upload failure is surfaced to the caller', () async {
    final adapter = _UploadAdapter(error: const SocketException('offline'));

    await expectLater(
      serviceFor(adapter).uploadPhotoRequired(
        photo,
        purpose: 'unknown_species',
      ),
      throwsA(isA<PhotoUploadException>()),
    );
  });

  test('optional photo upload may return null without blocking the record',
      () async {
    final adapter = _UploadAdapter(error: const SocketException('offline'));

    final url = await serviceFor(adapter).uploadPhoto(
      photo,
      purpose: 'planting_submission',
    );

    expect(url, isNull);
    expect(adapter.request?.path, '/storage/upload-photo');
  });

  test('required upload rejects an empty URL response', () async {
    final adapter = _UploadAdapter(responseBody: '{"file_url":" "}');

    await expectLater(
      serviceFor(adapter).uploadPhotoRequired(
        photo,
        purpose: 'tree_photo',
      ),
      throwsA(isA<PhotoUploadException>()),
    );
  });
}
