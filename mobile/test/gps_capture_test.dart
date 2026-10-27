// Phase 12A.1 — GPS reliability tests.
//
// Every test here is pure or widget-level with MOCKED positions: no real
// location is requested, no platform channel is opened, and no network
// request (Nominatim, tiles, backend) is made.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:treetrace_mobile/services/gps_capture.dart';

Position _position({double lat = 7.3047, double lng = 125.6856, double accuracy = 8}) =>
    // Fully mocked fix (geolocator_platform_interface 4.2.6 requires every
    // field): no real clock, coordinates, or platform channel involved.
    Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.utc(2026, 1, 1),
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
      isMocked: true,
    );

// ─────────────────────────────────────────────────────────────────────────────
// GpsCaptureService (injected seams — no plugins, no sockets)
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('GpsCaptureService.capture', () {
    test('disabled location services fail fast without fetching a position', () async {
      var fetched = false;
      final service = GpsCaptureService(
        servicesEnabled: () async => false,
        checkPermission: () async => LocationPermission.whileInUse,
        fetchPosition: (_) async {
          fetched = true;
          return _position();
        },
      );
      final outcome = await service.capture();
      expect(outcome.success, isFalse);
      expect(outcome.failure, GpsFailureKind.locationServicesDisabled);
      expect(fetched, isFalse);
    });

    test('denied permission is requested once and denied twice reports denial', () async {
      var requested = 0;
      final service = GpsCaptureService(
        servicesEnabled: () async => true,
        checkPermission: () async => LocationPermission.denied,
        requestPermission: () async {
          requested += 1;
          return LocationPermission.denied;
        },
        fetchPosition: (_) async => _position(),
      );
      final outcome = await service.capture();
      expect(outcome.failure, GpsFailureKind.permissionDenied);
      expect(requested, 1);
    });

    test('permission granted through the request returns the mocked fix', () async {
      final service = GpsCaptureService(
        servicesEnabled: () async => true,
        checkPermission: () async => LocationPermission.denied,
        requestPermission: () async => LocationPermission.whileInUse,
        fetchPosition: (_) async => _position(accuracy: 5),
      );
      final outcome = await service.capture();
      expect(outcome.success, isTrue);
      expect(outcome.position!.latitude, 7.3047);
      expect(outcome.position!.accuracy, 5);
    });

    test('deniedForever reports the blocked kind and never prompts again', () async {
      var requested = 0;
      final service = GpsCaptureService(
        servicesEnabled: () async => true,
        checkPermission: () async => LocationPermission.deniedForever,
        requestPermission: () async {
          requested += 1;
          return LocationPermission.denied;
        },
        fetchPosition: (_) async => _position(),
      );
      final outcome = await service.capture();
      expect(outcome.failure, GpsFailureKind.permissionDeniedForever);
      expect(requested, 0);
    });

    test('an already-granted permission does not re-prompt', () async {
      var requested = 0;
      final service = GpsCaptureService(
        servicesEnabled: () async => true,
        checkPermission: () async => LocationPermission.whileInUse,
        requestPermission: () async {
          requested += 1;
          return LocationPermission.denied;
        },
        fetchPosition: (_) async => _position(),
      );
      final outcome = await service.capture();
      expect(outcome.success, isTrue);
      expect(requested, 0);
    });

    test('a timed-out fix is classified as timeout, not an unknown error', () async {
      final service = GpsCaptureService(
        servicesEnabled: () async => true,
        checkPermission: () async => LocationPermission.whileInUse,
        fetchPosition: (_) async => throw TimeoutException('no fix'),
      );
      final outcome = await service.capture();
      expect(outcome.failure, GpsFailureKind.timeout);
    });

    test('any other platform error maps to positionUnavailable', () async {
      final service = GpsCaptureService(
        servicesEnabled: () async => true,
        checkPermission: () async => LocationPermission.whileInUse,
        fetchPosition: (_) async => throw StateError('platform channel missing'),
      );
      final outcome = await service.capture();
      expect(outcome.failure, GpsFailureKind.positionUnavailable);
    });

    test('the request carries high accuracy and the default 20 s time limit', () async {
      LocationSettings? seen;
      final service = GpsCaptureService(
        servicesEnabled: () async => true,
        checkPermission: () async => LocationPermission.whileInUse,
        fetchPosition: (settings) async {
          seen = settings;
          return _position();
        },
      );
      await service.capture();
      expect(seen, isNotNull);
      expect(seen!.accuracy, LocationAccuracy.high);
      expect(seen!.timeLimit, const Duration(seconds: 20));
    });

    test('a custom time limit is forwarded to the platform request', () async {
      LocationSettings? seen;
      final service = GpsCaptureService(
        servicesEnabled: () async => true,
        checkPermission: () async => LocationPermission.whileInUse,
        timeLimit: const Duration(seconds: 5),
        fetchPosition: (settings) async {
          seen = settings;
          return _position();
        },
      );
      await service.capture();
      expect(seen!.timeLimit, const Duration(seconds: 5));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Accuracy grading
  // ───────────────────────────────────────────────────────────────────────────

  group('classifyGpsAccuracy', () {
    test('missing accuracy is poor — never silently trusted', () {
      expect(classifyGpsAccuracy(null), GpsAccuracyGrade.poor);
    });

    test('nonsensical accuracy is poor', () {
      expect(classifyGpsAccuracy(double.nan), GpsAccuracyGrade.poor);
      expect(classifyGpsAccuracy(double.infinity), GpsAccuracyGrade.poor);
      expect(classifyGpsAccuracy(-1), GpsAccuracyGrade.poor);
    });

    test('thresholds: <=15 good, <=50 moderate, worse poor', () {
      expect(classifyGpsAccuracy(10), GpsAccuracyGrade.good);
      expect(classifyGpsAccuracy(15), GpsAccuracyGrade.good);
      expect(classifyGpsAccuracy(15.1), GpsAccuracyGrade.moderate);
      expect(classifyGpsAccuracy(50), GpsAccuracyGrade.moderate);
      expect(classifyGpsAccuracy(50.1), GpsAccuracyGrade.poor);
      expect(classifyGpsAccuracy(120), GpsAccuracyGrade.poor);
    });

    test('label shows meters and handles unknown accuracy', () {
      expect(gpsAccuracyLabel(8.4), 'GPS accuracy: ±8 m');
      expect(gpsAccuracyLabel(null), 'GPS accuracy: unknown');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Coordinate validation — mirrors backend/app/schemas/tree.py
  // ───────────────────────────────────────────────────────────────────────────

  group('coordinate validation (backend-consistent)', () {
    test('empty fields mean no coordinate and are valid', () {
      expect(coordinateErrorText('', isLatitude: true), isNull);
      expect(coordinateErrorText('   ', isLatitude: false), isNull);
      expect(tryParseCoordinate('  '), isNull);
    });

    test('in-range values parse', () {
      expect(coordinateErrorText('7.3047', isLatitude: true), isNull);
      expect(tryParseCoordinate('7.3047'), 7.3047);
      expect(coordinateErrorText('-90', isLatitude: true), isNull);
      expect(coordinateErrorText('90', isLatitude: true), isNull);
      expect(coordinateErrorText('-180', isLatitude: false), isNull);
      expect(coordinateErrorText('180', isLatitude: false), isNull);
    });

    test('out-of-range values are rejected per axis', () {
      expect(coordinateErrorText('90.0000001', isLatitude: true), kCoordinateEmptyError);
      expect(coordinateErrorText('-90.1', isLatitude: true), kCoordinateEmptyError);
      expect(coordinateErrorText('180.1', isLatitude: false), kLongitudeEmptyError);
      expect(coordinateErrorText('-181', isLatitude: false), kLongitudeEmptyError);
    });

    test('non-numeric and non-finite text is rejected', () {
      expect(coordinateErrorText('abc', isLatitude: true), kCoordinateEmptyError);
      expect(coordinateErrorText('NaN', isLatitude: true), kCoordinateEmptyError);
      expect(coordinateErrorText('Infinity', isLatitude: false), kLongitudeEmptyError);
      expect(coordinateErrorText('1e400', isLatitude: false), kLongitudeEmptyError);
    });

    test('error messages stay exactly as the user-facing contract', () {
      expect(kCoordinateEmptyError,
          'Latitude must be a number between -90 and 90, or leave it empty.');
      expect(kLongitudeEmptyError,
          'Longitude must be a number between -180 and 180, or leave it empty.');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Recapture merge policy (the Phase 12A "refresh" fix + manual preservation)
  // ───────────────────────────────────────────────────────────────────────────

  group('coordinateMergeAction', () {
    test('empty field takes the new fix without asking', () {
      expect(
        coordinateMergeAction(
            currentText: '', lastAutoText: null, newText: '7.3047000'),
        CoordinateMergeAction.useNew,
      );
    });

    test('identical fix needs no confirmation', () {
      expect(
        coordinateMergeAction(
            currentText: '7.3047000',
            lastAutoText: null,
            newText: '7.3047000'),
        CoordinateMergeAction.useNew,
      );
    });

    test('an app-owned value refreshes silently on recapture', () {
      expect(
        coordinateMergeAction(
            currentText: '7.3047000',
            lastAutoText: '7.3047000',
            newText: '7.3141500'),
        CoordinateMergeAction.useNew,
      );
    });

    test('a user-typed coordinate is preserved unless confirmed', () {
      expect(
        coordinateMergeAction(
            currentText: '7.2900000',
            lastAutoText: null,
            newText: '7.3141500'),
        CoordinateMergeAction.needsConfirmation,
      );
    });

    test('an edited app value counts as user-entered', () {
      expect(
        coordinateMergeAction(
            currentText: '7.3050000', // edited by hand from the auto value
            lastAutoText: '7.3047000',
            newText: '7.3141500'),
        CoordinateMergeAction.needsConfirmation,
      );
    });

    test('sub-centimeter drift from rounding is treated as identical', () {
      expect(
        coordinateMergeAction(
            currentText: '7.3047000',
            lastAutoText: null,
            newText: '7.30470003'), // < 5e-7 apart
        CoordinateMergeAction.useNew,
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Barangay merge policy (validity = the new resolution)
  // ───────────────────────────────────────────────────────────────────────────

  group('barangayMergeAction', () {
    test('empty field is filled from the resolution', () {
      expect(
        barangayMergeAction(
            currentText: '',
            lastAutoBarangay: null,
            newResolvedBarangay: 'Brgy. Gredu'),
        BarangayMergeAction.useNew,
      );
    });

    test('empty field with no resolution stays untouched', () {
      expect(
        barangayMergeAction(
            currentText: '', lastAutoBarangay: null, newResolvedBarangay: null),
        BarangayMergeAction.keep,
      );
    });

    test('unchanged resolution is a keep', () {
      expect(
        barangayMergeAction(
            currentText: 'Brgy. Gredu',
            lastAutoBarangay: null,
            newResolvedBarangay: 'brgy. gredu'), // case-insensitive
        BarangayMergeAction.keep,
      );
    });

    test('app-written label is refreshed when the new fix resolves elsewhere', () {
      expect(
        barangayMergeAction(
            currentText: 'Brgy. Gredu',
            lastAutoBarangay: 'Brgy. Gredu',
            newResolvedBarangay: 'Brgy. Quezon'),
        BarangayMergeAction.useNew,
      );
    });

    test('app-written label is cleared when nothing resolves for the new fix', () {
      expect(
        barangayMergeAction(
            currentText: 'Brgy. Gredu',
            lastAutoBarangay: 'Brgy. Gredu',
            newResolvedBarangay: null),
        BarangayMergeAction.clear,
      );
    });

    test('a user-confirmed label conflicts with a different resolution', () {
      expect(
        barangayMergeAction(
            currentText: 'Brgy. San Pedro',
            lastAutoBarangay: null,
            newResolvedBarangay: 'Brgy. Gredu'),
        BarangayMergeAction.confirmWithUser,
      );
    });

    test('a user-confirmed label survives when nothing can contradict it', () {
      expect(
        barangayMergeAction(
            currentText: 'Brgy. San Pedro',
            lastAutoBarangay: null,
            newResolvedBarangay: null),
        BarangayMergeAction.keep,
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Panabo-area guard (no phantom "Panabo City" default)
  // ───────────────────────────────────────────────────────────────────────────

  group('isWithinPanaboArea', () {
    test('city proper points are inside', () {
      expect(isWithinPanaboArea(7.3047, 125.6856), isTrue); // Panabo center
      expect(isWithinPanaboArea(7.28, 125.68), isTrue);
      expect(isWithinPanaboArea(7.40, 125.72), isTrue);
    });

    test('nearby cities and far points are outside — no Panabo default', () {
      expect(isWithinPanaboArea(7.07, 125.61), isFalse); // Davao City
      expect(isWithinPanaboArea(7.30, 125.50), isFalse); // offshore west
      expect(isWithinPanaboArea(7.50, 125.68), isFalse); // north of the box
      expect(isWithinPanaboArea(14.5995, 120.9842), isFalse); // Manila
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Confirmation dialogs (widget tests, mocked data)
  // ───────────────────────────────────────────────────────────────────────────

  group('showLowAccuracyConfirmation', () {
    testWidgets('shows the reported accuracy and can accept the fix', (tester) async {
      late Future<bool> result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return TextButton(
            onPressed: () =>
                result = showLowAccuracyConfirmation(context, 87.3),
            child: const Text('go'),
          );
        }),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('Poor GPS accuracy'), findsOneWidget);
      expect(find.textContaining('±87 m'), findsOneWidget);

      await tester.tap(find.text('Use this fix'));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
    });

    testWidgets('cancel keeps the current form values', (tester) async {
      late Future<bool> result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return TextButton(
            onPressed: () => result = showLowAccuracyConfirmation(context, 250),
            child: const Text('go'),
          );
        }),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });
  });

  group('showCoordinateReplacementConfirmation', () {
    testWidgets('shows both fixes; Replace accepts', (tester) async {
      late Future<bool> result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return TextButton(
            onPressed: () => result = showCoordinateReplacementConfirmation(
              context,
              existing: '7.2900000, 125.6700000',
              replacement: '7.3141500, 125.6900000',
            ),
            child: const Text('go'),
          );
        }),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.textContaining('7.2900000, 125.6700000'), findsWidgets);
      expect(find.textContaining('7.3141500, 125.6900000'), findsWidgets);

      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
    });

    testWidgets('Keep current declines', (tester) async {
      late Future<bool> result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return TextButton(
            onPressed: () => result = showCoordinateReplacementConfirmation(
              context,
              existing: '7.2900000, 125.6700000',
              replacement: '7.3141500, 125.6900000',
            ),
            child: const Text('go'),
          );
        }),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep current'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });
  });

  group('showBarangayReplacementConfirmation', () {
    testWidgets('shows both barangays; accepting uses the new one', (tester) async {
      late Future<bool> result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return TextButton(
            onPressed: () => result = showBarangayReplacementConfirmation(
              context,
              existing: 'Brgy. San Pedro',
              replacement: 'Brgy. Gredu',
            ),
            child: const Text('go'),
          );
        }),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('Barangay mismatch'), findsOneWidget);
      expect(find.textContaining('Brgy. San Pedro'), findsWidgets);
      expect(find.textContaining('Brgy. Gredu'), findsWidgets);

      await tester.tap(find.text('Use "Brgy. Gredu"'));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
    });

    testWidgets('keeping the existing barangay declines', (tester) async {
      late Future<bool> result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return TextButton(
            onPressed: () => result = showBarangayReplacementConfirmation(
              context,
              existing: 'Brgy. San Pedro',
              replacement: 'Brgy. Gredu',
            ),
            child: const Text('go'),
          );
        }),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep "Brgy. San Pedro"'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });
  });
}
