import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:treetrace_mobile/services/gps_capture.dart';
import 'package:treetrace_mobile/widgets/unknown_submission_sheet.dart';

Position position() => Position(
    latitude: 7.31,
    longitude: 125.67,
    timestamp: DateTime.utc(2026),
    accuracy: 8,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
    isMocked: true);

void main() {
  Future<void> open(
      WidgetTester tester, Future<GpsCaptureOutcome> Function() capture,
      {String status = 'resolved',
      ValueChanged<Map<String, dynamic>?>? onResult}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final photo = File('review-test.png');
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
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        final result =
                            await showModalBottomSheet<Map<String, dynamic>>(
                                context: context,
                                isScrollControlled: true,
                                builder: (_) => UnknownSubmissionSheet(
                                    photo: photo,
                                    result: const {
                                      'suggested_species': {
                                        'common_name': 'Mango'
                                      },
                                      'measurement_prediction': {
                                        'status': 'predicted',
                                        'method':
                                            'gallery_yolo_vision_prediction',
                                        'quality': 'unvalidated',
                                        'prediction_basis': 'visual_appearance',
                                        'validated_accuracy': false,
                                        'trunk_detected': true,
                                        'predicted_dbh_cm': 15,
                                        'predicted_height_m': 4,
                                        'dbh_reason': 'Same reason',
                                        'height_reason': 'Same reason',
                                      }
                                    },
                                    captureLocation: capture,
                                    lookupLocation:
                                        (lat, lng, accuracy) async => {
                                              'status': status,
                                              if (status == 'resolved')
                                                'barangay': 'New Visayas'
                                            }));
                        onResult?.call(result);
                      },
                      child: const Text('Open')),
                ))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('automatically geotags once and submits the captured coordinates',
      (tester) async {
    var calls = 0;
    Map<String, dynamic>? evidence;
    await open(tester, () async {
      calls++;
      return GpsCaptureOutcome.success(position());
    }, onResult: (result) => evidence = result);
    expect(calls, 1);
    expect(find.text('Capture GPS'), findsNothing);
    expect(find.text('Submit for Expert Review'), findsOneWidget);
    await tester.tap(find.text('Submit for Expert Review'));
    await tester.pumpAndSettle();
    expect(evidence!['location_description'], '7.31, 125.67');
    expect(evidence!['barangay'], 'New Visayas');
  });

  testWidgets('permission failure blocks submission and allows retry',
      (tester) async {
    var calls = 0;
    await open(tester, () async {
      calls++;
      return calls == 1
          ? const GpsCaptureOutcome.failed(GpsFailureKind.permissionDenied)
          : GpsCaptureOutcome.success(position());
    });
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.ensureVisible(find.text('Retry location'));
    await tester.tap(find.text('Retry location'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
  });

  testWidgets('lookup unavailable keeps GPS and shows an amber reminder',
      (tester) async {
    await open(tester, () async => GpsCaptureOutcome.success(position()),
        status: 'unavailable');
    await tester.ensureVisible(
        find.text('GPS captured. Barangay could not be verified.'));
    final message = tester.widget<Text>(
        find.text('GPS captured. Barangay could not be verified.'));
    expect(message.style!.color, const Color(0xFF946200));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
  });
}
