import 'dart:io';
import 'package:dio/dio.dart';
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
  bool fail = false;
  @override
  Future<PhotoCaptureMetadata?> read(File photo) async {
    if (fail) throw const FileSystemException('Capture index unavailable');
    return evidence;
  }
}

void main() {
  late File photo;
  late _EvidenceStore store;
  Map<String, dynamic>? prediction;
  Object? predictionError;
  setUp(() {
    photo = File('gallery-original.png');
    store = _EvidenceStore();
    prediction = null;
    predictionError = null;
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
        predictGallerySize: (_) async {
          if (predictionError != null) throw predictionError!;
          return prediction ??
              {'status': 'cannot_estimate', 'reason': 'No visible scale.'};
        },
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

  for (final mode in [
    'yolo',
    'unavailable',
    'ai_visual',
    'ambiguous',
    'history_error'
  ]) {
    final valid =
        mode == 'yolo' || mode == 'ai_visual' || mode == 'history_error';
    testWidgets('gallery prediction stays separate from measurements: $mode',
        (tester) async {
      prediction = {
        'status': mode == 'unavailable' ? 'unavailable' : 'predicted',
        'method': 'gallery_yolo_vision_prediction',
        'quality': 'unvalidated',
        'prediction_basis': 'visual_appearance',
        'validated_accuracy': false,
        'trunk_detected':
            mode == 'yolo' || mode == 'unavailable' || mode == 'history_error',
        'target_source': mode == 'yolo' ? 'yolo' : 'ai_visual',
        'target_identified': mode == 'ai_visual',
        'detection_note': 'AI assessed the photo without a YOLO mask.',
        'predicted_dbh_cm': 23,
        'predicted_height_m': 9,
        'reason': 'Visual prediction only.',
        'dbh_reason': valid
            ? 'Appearance-based visual prediction.'
            : 'Insufficient tree detail.',
        'height_reason':
            valid ? 'Appearance-based visual prediction.' : 'Treetop hidden.',
        'uncertainties': [
          'Physical scale is unknown; prediction may be inaccurate.'
        ],
      };
      store.fail = mode == 'history_error';
      await open(tester, (_, __) async => throw StateError('Must not measure'));
      expect(find.text('AI-predicted size'), findsOneWidget);
      expect(find.text('AI assessed the photo without a YOLO mask.'),
          findsOneWidget);
      expect(
          find.text(
              'DBH: ${valid ? 'Appearance-based visual prediction.' : 'Insufficient tree detail.'}'),
          findsOneWidget);
      expect(
          find.text(
              'Height: ${valid ? 'Appearance-based visual prediction.' : 'Treetop hidden.'}'),
          findsOneWidget);
      expect(
          find.text('Physical scale is unknown; prediction may be inaccurate.'),
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

  for (final status in [413, 429, 503]) {
    testWidgets('gallery explains request failure $status', (tester) async {
      final request = RequestOptions(path: '/ai/gallery-size-prediction');
      predictionError = DioException(
          requestOptions: request,
          response: Response(requestOptions: request, statusCode: status),
          type: DioExceptionType.badResponse);
      await open(tester, (_, __) async => throw StateError('Must not measure'));
      expect(
          find.text(status == 413
              ? 'The gallery upload exceeded the server size limit.'
              : status == 429
                  ? 'The AI request limit has been reached. Try again later.'
                  : 'The gallery prediction server could not complete the request. Try again.'),
          findsOneWidget);
      expect(find.text('Predicted DBH (cm): Unavailable'), findsOneWidget);
      expect(find.text('Predicted height (m): Unavailable'), findsOneWidget);
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
