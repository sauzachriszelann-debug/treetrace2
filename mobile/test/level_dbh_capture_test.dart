import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:treetrace_mobile/screens/tree_scan_screen.dart';
import 'package:treetrace_mobile/services/tree_scan_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treetrace_mobile/services/photo_measurement_rules.dart';
import 'package:treetrace_mobile/services/camera_height_settings.dart';

Map<String, dynamic> realmeFixture() => {
      'width': 3468, 'height': 4624, 'focal_mm': 4.73, 'exif_focal_mm': 4.73,
      // Explicit nominal sensor-size fixture, NOT a hardcoded production calibration.
      // Actual hardware must supply its own CameraCharacteristics values.
      'sensor_width_mm': 6.47, 'sensor_height_mm': 4.85, 'lens_locked': true,
      'exif_zoom': 1.0,
    };

void main() {
  test(
      'height shutter permits upward pitch but rejects movement during capture',
      () {
    final now = DateTime(2026, 11, 9);
    final guard = CaptureLevelGuard(
        pitch: 45,
        sampledAt: now,
        now: now,
        minPitch: 5,
        maxPitch: 85,
        maxChange: 1.5);
    guard.observe(45.5, now.add(const Duration(milliseconds: 100)));
    expect(guard.validAt(now.add(const Duration(milliseconds: 200))), isTrue);
    guard.observe(48, now.add(const Duration(milliseconds: 300)));
    expect(guard.validAt(now.add(const Duration(milliseconds: 300))), isFalse);
  });

  test('shutter accepts ongoing level samples during slow photo processing',
      () {
    final start = DateTime(2026, 11, 9);
    final guard = CaptureLevelGuard(pitch: 2.2, sampledAt: start, now: start);
    guard.observe(3.9, start.add(const Duration(milliseconds: 400)));
    guard.observe(2.9, start.add(const Duration(milliseconds: 800)));
    expect(
        guard.validAt(start.add(const Duration(milliseconds: 1000))), isTrue);
  });
  test('shutter rejects tilt, interruptions and stale sensor evidence', () {
    final start = DateTime(2026, 11, 9);
    CaptureLevelGuard guard() =>
        CaptureLevelGuard(pitch: 0, sampledAt: start, now: start);
    final tilted = guard()
      ..observe(6, start.add(const Duration(milliseconds: 100)));
    tilted.observe(0, start.add(const Duration(milliseconds: 200)));
    expect(
        tilted.validAt(start.add(const Duration(milliseconds: 200))), isFalse);
    expect((guard()..interrupt()).validAt(start), isFalse);
    expect(guard().validAt(start.add(const Duration(seconds: 1))), isFalse);
    expect(
        (guard()..observe(0, start.add(const Duration(seconds: 1))))
            .validAt(start.add(const Duration(seconds: 1))),
        isFalse);
  });
  testWidgets(
      'retake acceptance stays disabled but explicit skip returns no dimensions',
      (tester) async {
    final directory = await Directory.systemTemp.createTemp('treetrace_skip_');
    addTearDown(() => directory.delete(recursive: true));
    final photo = await File('${directory.path}/tree.png').writeAsBytes(
        base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jBz0AAAAASUVORK5CYII='));
    TreeScanResult? saved;
    final initial = TreeScanResult(
        photo: photo,
        species: {'common_name': 'AI tree', 'scientific_name': 'Test species'},
        dbh: {'status': 'retake', 'dbh_cm': 'must not cast'},
        heightMeters: 8);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        saved = await Navigator.push<TreeScanResult>(
                            context,
                            MaterialPageRoute(
                                builder: (_) => TreeScanScreen(
                                    autoStart: false, initialResult: initial)));
                      },
                      child: const Text('Open review')),
                ))));
    await tester.tap(find.text('Open review'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('use-tree-scan')));
    expect(
        tester
            .widget<ElevatedButton>(find.byKey(const Key('use-tree-scan')))
            .onPressed,
        isNull);
    await tester
        .ensureVisible(find.byKey(const Key('skip-result-measurement')));
    await tester.tap(find.byKey(const Key('skip-result-measurement')));
    await tester.pumpAndSettle();
    expect(saved?.measurementSkipped, isTrue);
    expect(saved?.saveRequested, isTrue);
    expect(saved?.dbh, isNull);
    expect(saved?.heightMeters, isNull);
    expect(saved?.reviewedDbhCm, isNull);
    expect(saved?.reviewedHeightMeters, isNull);
    expect(saved?.species?['scientific_name'], 'Test species');
  });

  test('realme GT Master 3468x4624 at 4.73mm gives about 3380px', () {
    final result = focalPixelsFromMetadata(realmeFixture());
    expect(result['status'], 'ok');
    expect(result['f_px'], closeTo(3380, 3380 * 0.03));
    final landscape = realmeFixture()
      ..['width'] = 4624
      ..['height'] = 3468;
    expect(focalPixelsFromMetadata(landscape)['f_px'], result['f_px']);
  });

  test('lens EXIF mismatch over five percent is retake without guessed scale',
      () {
    final result =
        focalPixelsFromMetadata(realmeFixture()..['exif_focal_mm'] = 5.0);
    expect(result['status'], 'retake');
    expect(result['f_px'], isNull);
    expect(result['reason'], contains('selected lens'));
  });

  test('unlocked lens, zoom, missing focal and incompatible crop reject scale',
      () {
    for (final fixture in [
      realmeFixture()..['lens_locked'] = false,
      realmeFixture()..['exif_zoom'] = 2.0,
      realmeFixture()..['exif_focal_mm'] = null,
      realmeFixture()..['height'] = 6000,
    ]) {
      expect(focalPixelsFromMetadata(fixture)['status'], 'retake');
      expect(focalPixelsFromMetadata(fixture)['f_px'], isNull);
    }
  });

  test('capture requires fresh stable pitch at most five degrees', () {
    final now = DateTime.utc(2026);
    bool allowed(double? pitch,
            {bool stable = true, Duration age = Duration.zero}) =>
        levelCaptureAllowed(
            pitch: pitch,
            stable: stable,
            now: now,
            sampledAt: now.subtract(age));
    expect(allowed(5), isTrue);
    expect(allowed(-5), isTrue);
    for (final pitch in [null, 5.01, -5.01, double.nan, double.infinity]) {
      expect(allowed(pitch), isFalse);
    }
    expect(allowed(0, stable: false), isFalse);
    expect(allowed(0, age: const Duration(seconds: 1)), isFalse);
  });

  test(
      'retake, unavailable and legacy fallback cannot be accepted or parsed as measurements',
      () {
    for (final response in [
      {'status': 'retake', 'dbh_cm': 'not a number'},
      {'status': 'unavailable', 'dbh_cm': 25},
      {'status': 'ok', 'dbh_cm': 25, 'fallback': true},
      {
        'status': 'ok',
        'method': 'yolo_trunk_v1',
        'dbh_cm': 20,
        'distance_m_used': 2,
        'quality': 'low'
      },
    ]) {
      expect(photoMeasurementAccepted(response, baseConfirmed: true), isFalse);
    }
    final valid = {
      'status': 'ok',
      'method': 'yolo_trunk_v1',
      'quality': 'experimental',
      'dbh_cm': 20,
      'distance_m_used': 2,
      'needs_base_confirmation': true
    };
    expect(photoMeasurementAccepted(valid, baseConfirmed: false), isFalse);
    expect(photoMeasurementAccepted(valid, baseConfirmed: true), isTrue);
  });

  test('camera height defaults once and persists without per-photo questions',
      () async {
    String? value;
    final settings = CameraHeightSettings(
        reader: () async => value, writer: (text) async => value = text);
    expect(await settings.read(), 1.4);
    await settings.save(1.62);
    expect(await settings.read(), 1.62);
    expect(() => settings.save(double.nan), throwsArgumentError);
  });
}
