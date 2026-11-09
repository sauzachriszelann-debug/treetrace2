import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:treetrace_mobile/services/photo_capture_metadata_store.dart';

void main() {
  late Directory directory;
  late File photo;
  late String? saved;
  late PhotoCaptureMetadataStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('capture_evidence_test');
    photo =
        await File('${directory.path}/original.jpg').writeAsBytes([1, 2, 3]);
    saved = null;
    store = PhotoCaptureMetadataStore(
        reader: () async => saved,
        writer: (value) async {
          saved = value;
        });
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  const metadata = PhotoCaptureMetadata(
      pitchDegrees: -2, cameraHeightMeters: 1.6, focalPixels: 3380);

  test('exact renamed copy recovers capture values, changed bytes do not',
      () async {
    expect(await store.read(photo), isNull);
    expect(await store.save(photo, metadata), isTrue);
    final copy = await photo.copy('${directory.path}/renamed.jpg');
    final restored = await store.read(copy);
    expect(restored?.pitchDegrees, -2);
    expect(restored?.cameraHeightMeters, 1.6);
    expect(restored?.focalPixels, 3380);
    await copy.writeAsBytes([1, 2, 4]);
    expect(await store.read(copy), isNull);
    expect(await photo.readAsBytes(), [1, 2, 3]);
    expect(saved, isNot(contains('original.jpg')));
  });

  test('invalid sensor values and corrupt records fail closed', () async {
    for (final pitch in [double.nan, double.infinity, 6.0]) {
      expect(
          await store.save(
              photo,
              PhotoCaptureMetadata(
                  pitchDegrees: pitch, cameraHeightMeters: 1.4)),
          isFalse);
    }
    saved = '{broken';
    expect(await store.read(photo), isNull);
    expect(await store.save(photo, metadata), isTrue);
    expect(await store.read(photo), isNotNull);
    expect(PhotoCaptureMetadata.fromJson({'version': 2}), isNull);
    expect(
        PhotoCaptureMetadata.fromJson(
            {'version': 1, 'pitch': 0, 'camera_height': 1.4, 'f_px': -1}),
        isNull);
  });

  test('EXIF-only focal path keeps missing focal pixels absent', () async {
    await store.save(photo,
        const PhotoCaptureMetadata(pitchDegrees: 0, cameraHeightMeters: 1.4));
    expect((await store.read(photo))?.focalPixels, isNull);
  });

  test('unavailable storage does not throw or manufacture readings', () async {
    final unavailable = PhotoCaptureMetadataStore(
        reader: () async => throw StateError('unavailable'),
        writer: (_) async => throw StateError('unavailable'));
    expect(await unavailable.save(photo, metadata), isFalse);
    expect(await unavailable.read(photo), isNull);
  });
}
