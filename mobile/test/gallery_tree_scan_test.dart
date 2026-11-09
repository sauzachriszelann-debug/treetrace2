import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treetrace_mobile/screens/tree_scan_screen.dart';
import 'package:treetrace_mobile/services/photo_capture_metadata_store.dart';

// Valid RGB PNG, including verified chunk checksums.
const png =
    'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAFElEQVR4nGM8kWLEAANMDEgANwcARfYBZhhDpbAAAAAASUVORK5CYII=';

// Exact-byte matching and OS-file behavior are covered by the store tests.
// Widget tests isolate the review contract from filesystem scheduling.
class _EvidenceStore extends PhotoCaptureMetadataStore {
  PhotoCaptureMetadata? evidence;
  @override
  Future<PhotoCaptureMetadata?> read(File photo) async => evidence;
}

void main() {
  late File photo;
  late _EvidenceStore store;
  Map<String, dynamic>? prediction;
  setUp(() {
    photo = File('gallery-original.png');
    store = _EvidenceStore();
    prediction = null;
  });

  Future<void> open(
      WidgetTester tester,
      Future<Map<String, dynamic>> Function(File, PhotoCaptureMetadata)
          measure) async {
    // ListView builds children lazily. Keep the review controls in the test
    // viewport; an unbuilt off-screen button is not a processing signal.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 4000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Supply FileImage through the real Flutter cache, with no disk reads.
    final image =
        await tester.runAsync(() => createTestImage(width: 2, height: 2));
    PaintingBinding.instance.imageCache.putIfAbsent(
        FileImage(photo),
        () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: image!))));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
          home: TreeScanScreen(
        galleryPhoto: photo,
        metadataStore: store,
        predictGallerySize: (_) async =>
            prediction ??
            {'status': 'cannot_estimate', 'reason': 'No visible scale.'},
        measurePhoto: measure,
        identifyPhoto: (_) async =>
            {'common_name': 'Mango', 'scientific_name': 'Mangifera indica'},
      )));
      // Always draw at least one frame AFTER post-frame scan startup. Checking
      // the initial frame can otherwise mistake not-yet-started for completed.
      for (var frame = 0; frame < 100; frame++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (find.text('Rescan tree').evaluate().isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty) {
          break;
        }
      }
    });
    expect(find.byType(LinearProgressIndicator), findsNothing,
        reason: 'Gallery processing must finish before testing review');
    expect(find.text('Rescan tree'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('unknown original identifies species without inventing scale',
      (tester) async {
    await open(tester,
        (_, __) async => throw StateError('Must not measure unknown photo'));
    expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('scan-common-name')))
            .controller!
            .text,
        'Mango');
    expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('scan-dbh')))
            .controller!
            .text,
        isEmpty);
    expect(find.textContaining('no saved TreeTrace capture readings'),
        findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('use-tree-scan')));
    expect(
        tester
            .widget<ElevatedButton>(find.byKey(const Key('use-tree-scan')))
            .onPressed,
        isNull);
  });

  for (final valid in [true, false]) {
    testWidgets('gallery prediction stays separate from measurements: $valid',
        (tester) async {
      prediction = {
        'status': valid ? 'predicted' : 'unavailable',
        'method': 'gallery_yolo_vision_prediction',
        'quality': 'unvalidated',
        'validated_accuracy': false,
        'trunk_detected': true,
        'predicted_dbh_cm': valid ? 23 : 'bad',
        'predicted_height_m': valid ? 9 : double.nan,
        'reason': 'Visual prediction only.',
        'assumptions': [
          'Assumed visible tire dimension: 0.6 m; perspective uncertain.'
        ],
      };
      await open(tester, (_, __) async => throw StateError('Must not measure'));
      expect(find.text('AI-predicted size'), findsOneWidget);
      expect(
          find.text(
              'Assumed visible tire dimension: 0.6 m; perspective uncertain.'),
          findsOneWidget);
      expect(find.text('Predicted DBH (cm): ${valid ? '23' : 'Unavailable'}'),
          findsOneWidget);
      expect(find.text('Predicted height (m): ${valid ? '9' : 'Unavailable'}'),
          findsOneWidget);
      expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('scan-dbh')))
              .controller!
              .text,
          isEmpty);
      expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('scan-height')))
              .controller!
              .text,
          isEmpty);
      expect(
          tester
              .widget<ElevatedButton>(find.byKey(const Key('use-tree-scan')))
              .onPressed,
          isNull);
    });
  }

  for (final retake in [false, true]) {
    testWidgets(
        retake
            ? 'retake string numbers are never parsed'
            : 'saved original remeasures with historical readings and confirms base',
        (tester) async {
      store.evidence = const PhotoCaptureMetadata(
          pitchDegrees: -1, cameraHeightMeters: 1.6, focalPixels: 3380);
      var called = false;
      await open(tester, (file, evidence) async {
        called = true;
        expect(file.path, photo.path);
        expect(evidence.cameraHeightMeters, 1.6);
        expect(evidence.pitchDegrees, -1);
        expect(evidence.focalPixels, 3380);
        return retake
            ? {
                'status': 'retake',
                'dbh_cm': 'not a number',
                'reason': 'Move closer',
                'preview_png': png
              }
            : {
                'status': 'ok',
                'method': 'yolo_trunk_v1',
                'quality': 'experimental',
                'dbh_cm': 12.5,
                'distance_m_used': 3.0,
                'needs_base_confirmation': true,
                'preview_png': png
              };
      });
      expect(called, isTrue);
      expect(find.byKey(const Key('gallery-size-prediction')), findsNothing);
      final field =
          tester.widget<TextFormField>(find.byKey(const Key('scan-dbh')));
      expect(field.controller!.text, isEmpty);
      await tester.ensureVisible(find.byKey(const Key('use-tree-scan')));
      expect(
          tester
              .widget<ElevatedButton>(find.byKey(const Key('use-tree-scan')))
              .onPressed,
          isNull);
      if (!retake) {
        await tester.ensureVisible(find.byKey(const Key('confirm-photo-base')));
        expect(
            tester
                .widget<ElevatedButton>(
                    find.byKey(const Key('confirm-photo-base')))
                .onPressed,
            isNotNull,
            reason: 'A valid decoded preview must enable base confirmation');
        await tester.tap(find.byKey(const Key('confirm-photo-base')));
        await tester.pump(const Duration(milliseconds: 300));
        expect(field.controller!.text, '12.5');
        await tester.ensureVisible(find.byKey(const Key('use-tree-scan')));
        expect(
            tester
                .widget<ElevatedButton>(find.byKey(const Key('use-tree-scan')))
                .onPressed,
            isNotNull);
      }
      expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('scan-height')))
              .controller!
              .text,
          isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
