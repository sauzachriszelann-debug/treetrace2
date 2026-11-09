import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treetrace_mobile/services/api_service.dart';
import 'package:treetrace_mobile/services/identification_photo.dart';

class _Store implements SecureStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _ImageEndpoint implements HttpClientAdapter {
  String? imageType;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    imageType =
        (options.data as FormData).files.single.value.contentType.toString();
    // The real backend rejects an application/octet-stream file with HTTP 400.
    return ResponseBody.fromString(
      '{"common_name":"Test tree","scientific_name":"Test species"}',
      imageType!.startsWith('image/') ? 200 : 400,
      headers: {
        Headers.contentTypeHeader: ['application/json']
      },
    );
  }
}

class _FailingHistoryStore extends _Store {
  final bool failRead;
  _FailingHistoryStore({required this.failRead});
  @override
  Future<String?> read(String key) async {
    if (failRead) throw StateError('test storage unavailable');
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    throw StateError('test storage unavailable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('large species copy stays bounded and original bytes are untouched',
      () async {
    final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jBz0AAAAASUVORK5CYII=');
    final original = Uint8List(2000000)..setRange(0, png.length, png);
    final before = Uint8List.fromList(original);
    final copy = await prepareIdentificationPhoto(original, 'image/png');
    expect(copy.bytes.length, lessThanOrEqualTo(1500000));
    expect(copy.mimeType, 'image/png');
    expect(original, before);
  });

  for (final failRead in [true, false]) {
    test('successful AI survives history read/write failure: $failRead',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('treetrace_ai_history_');
      addTearDown(() => directory.delete(recursive: true));
      final photo =
          await File('${directory.path}/tree.jpg').writeAsBytes([1, 2, 3]);
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/api'))
        ..httpClientAdapter = _ImageEndpoint();
      final result = await ApiService.forTest(
              storage: _FailingHistoryStore(failRead: failRead), dio: dio)
          .identifyTree(photo);
      expect(result['scientific_name'], 'Test species');
    });
  }
  test(
      'DBH sends the original bytes and capture metadata without recompression',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('treetrace_dbh_bytes_');
    addTearDown(() => directory.delete(recursive: true));
    final original = <int>[
      255,
      216,
      255,
      225,
      69,
      120,
      105,
      102,
      0,
      1,
      2,
      3,
      255,
      217
    ];
    final file =
        await File('${directory.path}/capture.jpg').writeAsBytes(original);
    final adapter = _PhotoDbhEndpoint();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/api'))
      ..httpClientAdapter = adapter;
    final client = ApiService.forTest(storage: _Store(), dio: dio);
    final result = await client.measureDbh(file,
        referenceHint: 'Original level photo',
        method: 'yolo_trunk_v1',
        cameraHeightM: 1.4,
        pitchDeg: 2,
        focalPixels: 3380);
    expect(adapter.path, '/ai/measure-dbh-file');
    expect(latin1.decode(adapter.body), contains(latin1.decode(original)));
    expect(adapter.payload!['method'], 'yolo_trunk_v1');
    expect(await file.readAsBytes(), original);
    expect(adapter.payload!['camera_height_m'], '1.4');
    expect(adapter.payload!['pitch_deg'], '2.0');
    expect(adapter.payload!['f_px'], '3380.0');
    expect(result['status'], 'retake');
    expect(result['dbh_cm'], isNull);
  });

  for (final entry in {
    'jpg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp'
  }.entries) {
    test('identify sends ${entry.value} to image-only backend', () async {
      final directory =
          await Directory.systemTemp.createTemp('treetrace_upload_');
      addTearDown(() => directory.delete(recursive: true));
      final photo = await File('${directory.path}/tree.${entry.key}')
          .writeAsBytes([1, 2, 3]);
      final adapter = _ImageEndpoint();
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/api'));
      dio.httpClientAdapter = adapter;
      final client = ApiService.forTest(storage: _Store(), dio: dio);
      final result = await client.identifyTree(photo);
      expect(adapter.imageType, entry.value);
      expect(result['scientific_name'], 'Test species');
    });
  }
}

class _PhotoDbhEndpoint implements HttpClientAdapter {
  Map<String, dynamic>? payload;
  String? path;
  final body = <int>[];
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    path = options.path;
    payload =
        Map<String, dynamic>.fromEntries((options.data as FormData).fields);
    if (stream != null) {
      await for (final chunk in stream) {
        body.addAll(chunk);
      }
    }
    return ResponseBody.fromString(
        '{"status":"retake","dbh_cm":null,"reason":"Hold the phone level"}',
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });
  }
}
