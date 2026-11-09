import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
// Camera's platform boundary is faked; no camera, network or API key is used.
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:treetrace_mobile/screens/level_dbh_camera_screen.dart';
import 'package:treetrace_mobile/services/camera_height_settings.dart';
import 'package:treetrace_mobile/services/camera_photo_metadata.dart';
import 'package:treetrace_mobile/services/photo_measurement_rules.dart';
import 'package:treetrace_mobile/services/photo_capture_metadata_store.dart';

const png =
    'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAFElEQVR4nGM8kWLEAANMDEgANwcARfYBZhhDpbAAAAAASUVORK5CYII=';

class _CaptureStore extends PhotoCaptureMetadataStore {
  int saves = 0;
  @override
  Future<bool> save(File photo, PhotoCaptureMetadata metadata) async {
    saves++;
    expect(metadata.pitchDegrees, closeTo(0, 0.01));
    expect(metadata.cameraHeightMeters, 1.4);
    expect(metadata.focalPixels, closeTo(3380, 100));
    return true;
  }
}

class FakeCamera extends CameraPlatform {
  final List<String> shots;
  int captures = 0, disposals = 0;
  bool disposed = false;
  FakeCamera(this.shots);
  @override
  Future<List<CameraDescription>> availableCameras() async => [
        const CameraDescription(
            name: '0',
            lensDirection: CameraLensDirection.back,
            sensorOrientation: 90)
      ];
  @override
  Future<int> createCameraWithSettings(
      CameraDescription description, MediaSettings? settings) async {
    disposed = false;
    return 7;
  }

  @override
  Future<void> initializeCamera(int cameraId,
      {ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown}) async {}
  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(const CameraInitializedEvent(
          7, 640, 480, ExposureMode.auto, true, FocusMode.auto, true));
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      StreamController<CameraErrorEvent>().stream;
  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      Stream.value(
          const DeviceOrientationChangedEvent(DeviceOrientation.portraitUp));
  @override
  Future<void> setZoomLevel(int cameraId, double zoom) async {}
  @override
  Future<void> lockCaptureOrientation(
      int cameraId, DeviceOrientation orientation) async {}
  @override
  Future<XFile> takePicture(int cameraId) async => XFile(shots[captures++]);
  @override
  Future<void> dispose(int cameraId) async {
    disposed = true;
    disposals++;
  }

  @override
  Widget buildPreview(int cameraId) {
    if (disposed) throw StateError('Preview built after disposal');
    return const ColoredBox(color: Colors.green);
  }
}

void main() {
  test(
      'height rejects malformed, retake and fallback results before numeric use',
      () {
    expect(heightMeasurementAccepted({'status': 'retake', 'height_m': 'bad'}),
        isFalse);
    expect(
        heightMeasurementAccepted({
          'status': 'ok',
          'height_m': 10,
          'method': 'legacy',
          'quality': 'low',
          'theta_top_deg': 45,
          'distance_m': 10
        }),
        isFalse);
    expect(
        captureAngleAllowed(
            pitch: 86,
            sampledAt: DateTime(2026),
            now: DateTime(2026),
            stable: true),
        isFalse);
  });

  for (final mode in ['height', 'skip', 'retake', 'interrupted']) {
    testWidgets('same camera session: $mode', (tester) async {
      final directory =
          Directory.systemTemp.createTempSync('treetrace_two_shots_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final first = File('${directory.path}/trunk.png')
        ..writeAsBytesSync(base64Decode(png));
      final second = File('${directory.path}/top.png')
        ..writeAsBytesSync(base64Decode(png));
      final captureStore = _CaptureStore();
      final originalPlatform = CameraPlatform.instance;
      final camera = FakeCamera([first.path, second.path]);
      CameraPlatform.instance = camera;
      addTearDown(() {
        CameraPlatform.instance = originalPlatform;
      });
      final sensors = StreamController<AccelerometerEvent>();
      addTearDown(sensors.close);
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(CameraPhotoMetadata.channel, (call) async {
        if (call.method == 'cameras') {
          return [
            {'id': '0'}
          ];
        }
        return {
          'status': 'ok',
          'width': 3468,
          'height': 4624,
          'focal_mm': 4.73,
          'exif_focal_mm': 4.73,
          'sensor_width_mm': 6.47,
          'sensor_height_mm': 4.85,
          'lens_locked': true,
          'exif_zoom': 1.0
        };
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(CameraPhotoMetadata.channel, null));
      // Dispose subscriptions before closing the sensor controller, including
      // after an assertion failure, so teardown itself cannot hang.
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      });
      LevelPhotoCapture? returned;
      int heightCalls = 0;
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        returned = await Navigator.push<LevelPhotoCapture>(
                            context,
                            MaterialPageRoute(
                                builder: (_) => LevelDbhCameraScreen(
                                      sensorEvents: sensors.stream,
                                      metadataStore: captureStore,
                                      settings: CameraHeightSettings(
                                          reader: () async => '1.4'),
                                      onMeasureTrunk: (_) async => mode ==
                                              'retake'
                                          ? {
                                              'status': 'retake',
                                              'dbh_cm': 'must not parse',
                                              'reason': 'Move closer'
                                            }
                                          : {
                                              'status': 'ok',
                                              'method': 'yolo_trunk_v1',
                                              'quality': 'experimental',
                                              'dbh_cm': 12,
                                              'distance_m_used': 10,
                                              'needs_base_confirmation': true,
                                              'preview_png': png
                                            },
                                      onMeasureHeight: (pitch, cameraHeight,
                                          distance, confirmed) async {
                                        heightCalls++;
                                        expect(pitch, closeTo(45, 1e-6));
                                        expect(distance, 10);
                                        expect(cameraHeight, 1.4);
                                        expect(confirmed, isTrue);
                                        return {
                                          'status': 'ok',
                                          'method': 'tilt_distance',
                                          'quality': 'experimental',
                                          'height_m': 11.5,
                                          'theta_top_deg': pitch,
                                          'distance_m': distance
                                        };
                                      },
                                    )));
                      },
                      child: const Text('Open capture'))))));
      await tester.tap(find.text('Open capture'));
      await tester.pumpAndSettle();
      Future<void> aim(double degrees) async {
        final a = degrees * math.pi / 180;
        for (var i = 0; i < 6; i++) {
          sensors.add(AccelerometerEvent(
              0, 9.8 * math.cos(a), 9.8 * math.sin(a), DateTime.now()));
          await tester.pump(const Duration(milliseconds: 25));
        }
      }

      await aim(0);
      await tester.tap(find.byKey(const Key('capture-level-dbh')));
      // The real preview codec runs outside fake time; wait for the observable
      // confirmation/retake state, not for an indeterminate progress animation.
      await tester.runAsync(() async {
        for (var i = 0; i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
          if (find
                  .text('Is the green line at the bottom of the tree?')
                  .evaluate()
                  .isNotEmpty ||
              find.text('Move closer').evaluate().isNotEmpty) {
            break;
          }
        }
      });
      expect(camera.captures, 1);
      expect(camera.disposals, 0);
      if (mode == 'retake') {
        expect(find.text('Move closer'), findsOneWidget);
        expect(find.byKey(const Key('capture-tree-height')), findsNothing);
        await tester.tap(find.text('Skip measurement'));
      } else {
        expect(find.text('Is the green line at the bottom of the tree?'),
            findsOneWidget);
        await tester.tap(find.text('Yes'));
        await tester.pump();
        if (mode == 'height') {
          await aim(45);
          await tester.tap(find.byKey(const Key('capture-tree-height')));
        } else {
          if (mode == 'interrupted') {
            tester.binding
                .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
            await tester.pump();
            expect(
                tester
                    .widget<IconButton>(
                        find.byKey(const Key('capture-tree-height')))
                    .onPressed,
                isNull);
          }
          await tester.tap(find.text('Skip height'));
        }
      }
      // Height deletes its temporary second shot asynchronously. Allow real
      // filesystem completion while keeping the shutter's sensor gate tested.
      await tester.runAsync(() async {
        for (var i = 0; i < 100 && returned == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();
      expect(captureStore.saves, 1);
      expect(tester.takeException(), isNull);
      expect(returned?.photo.path, first.path);
      expect(returned?.heightResponse?['height_m'],
          mode == 'height' ? 11.5 : isNull);
      expect(heightCalls, mode == 'height' ? 1 : 0);
      expect(camera.captures, mode == 'height' ? 2 : 1);
      expect(first.existsSync(), isTrue);
      if (mode == 'height') expect(second.existsSync(), isFalse);
      expect(returned?.skipMeasurement, mode == 'retake');
      if (mode != 'retake') expect(returned?.baseConfirmed, isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));
  }
}
