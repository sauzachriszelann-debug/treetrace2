import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:treetrace_mobile/screens/height_measure_screen.dart';
import 'package:treetrace_mobile/services/tree_height_measurement.dart';

void main() {
  group('tree height clinometer calculation', () {
    test('uses signed top and base angles in the height calculation', () {
      final actual = calculateTreeHeightMeters(
        horizontalDistanceMeters: 10,
        topAngleDegrees: 45,
        baseAngleDegrees: -10,
      );
      final expected = 10 * (math.tan(math.pi / 4) - math.tan(-math.pi / 18));
      expect(actual, closeTo(expected, 1e-10));
      expect(actual, closeTo(11.7633, 0.001));
    });

    test('rejects non-positive and non-finite distance', () {
      for (final distance in [0.0, -2.0, double.nan, double.infinity]) {
        expect(
          () => calculateTreeHeightMeters(
            horizontalDistanceMeters: distance,
            topAngleDegrees: 30,
            baseAngleDegrees: 0,
          ),
          throwsFormatException,
        );
      }
    });

    test('rejects non-finite, near-vertical and inverted angles', () {
      expect(
        () => calculateTreeHeightMeters(
          horizontalDistanceMeters: 5,
          topAngleDegrees: double.nan,
          baseAngleDegrees: 0,
        ),
        throwsFormatException,
      );
      expect(
        () => calculateTreeHeightMeters(
          horizontalDistanceMeters: 5,
          topAngleDegrees: 89,
          baseAngleDegrees: 0,
        ),
        throwsFormatException,
      );
      expect(
        () => calculateTreeHeightMeters(
          horizontalDistanceMeters: 5,
          topAngleDegrees: 5,
          baseAngleDegrees: 10,
        ),
        throwsFormatException,
      );
    });
  });

  testWidgets('sensor angle can be captured and manual angle remains editable',
      (tester) async {
    const radians = 25 * math.pi / 180;
    await tester.pumpWidget(MaterialApp(
      home: HeightMeasureScreen(
        sensorEvents: Stream.value(AccelerometerEvent(
          0,
          -9.8 * math.cos(radians),
          -9.8 * math.sin(radians),
          DateTime.utc(2026, 1, 1),
        )),
      ),
    ));
    await tester.pump();

    final captureTop = find.byKey(const Key('capture-top-angle'));
    await tester.ensureVisible(captureTop);
    await tester.tap(captureTop);
    await tester.pump();
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('top-angle')))
            .controller!
            .text,
        '25.0');

    await tester.enterText(find.byKey(const Key('top-angle')), '30');
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('top-angle')))
            .controller!
            .text,
        '30');
  });

  testWidgets('sensor errors leave manual angle entry available',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: HeightMeasureScreen(
        sensorEvents: Stream<AccelerometerEvent>.empty(),
      ),
    ));
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('top-angle')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('base-angle')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('base-angle')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('sensor-status')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Enter top and base angles manually'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('capture-top-angle')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('capture-top-angle')), findsOneWidget);
    expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('capture-top-angle')))
            .onPressed,
        isNull);
  });

  testWidgets('worker can correct an estimate before accepting it',
      (tester) async {
    HeightMeasurementResult? accepted;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    accepted = await Navigator.push<HeightMeasurementResult>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const HeightMeasureScreen(
                          sensorEvents: Stream<AccelerometerEvent>.empty(),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open height tool'),
                ),
              )),
    ));
    await tester.tap(find.text('Open height tool'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('horizontal-distance')), '10');
    await tester.ensureVisible(find.byKey(const Key('top-angle')));
    await tester.enterText(find.byKey(const Key('top-angle')), '45');
    await tester.ensureVisible(find.byKey(const Key('base-angle')));
    await tester.enterText(find.byKey(const Key('base-angle')), '-10');
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('horizontal-distance')))
            .controller!
            .text,
        '10');
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('top-angle')))
            .controller!
            .text,
        '45');
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('base-angle')))
            .controller!
            .text,
        '-10');
    await tester.ensureVisible(find.text('Calculate Estimated Height'));
    await tester.tap(find.text('Calculate Estimated Height'));
    await tester.pump();

    expect(find.byKey(const Key('height-error')), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const Key('height-estimate-result')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Estimated tree height'), findsOneWidget);
    expect(find.text('11.76 m'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('corrected-height')));
    await tester.enterText(find.byKey(const Key('corrected-height')), '12.5');
    await tester.ensureVisible(find.byKey(const Key('accept-height')));
    await tester.tap(find.byKey(const Key('accept-height')));
    await tester.pumpAndSettle();

    expect(accepted?.heightMeters, 12.5);
  });
}
