// Phase 12B.1A — Add Tree screen GPS wiring tests (mocked, widget-level).
//
// These tests pump the real AddTreeScreen with injected seams: a scripted
// GpsCaptureService (no platform channels, no real fix) and a fake reverse
// geocoder (no geocoding plugin, no Nominatim). The online lookup is skipped
// entirely, so no test can open a socket.
//
// They cover the screen-level wiring the Phase 12B.1 inspection found
// untested: automatic capture on open, fill-only-if-empty protection,
// confirmation before replacing user-entered coordinates, the withheld
// poor-fix policy, and (new in 12B.1A) loading-state recovery when the
// geocoder hangs or fails.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:treetrace_mobile/screens/add_tree_screen.dart';
import 'package:treetrace_mobile/services/gps_capture.dart';

// Fully mocked fix (geolocator_platform_interface requires every field):
// no real clock, coordinates or platform channel involved.
Position _position({double lat = 8.1403, double lng = 123.833, double accuracy = 8}) =>
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

/// A capture service whose permission is initially denied and granted by the
/// request — the first-ever-open path — recording every call.
typedef _Fix = Future<Position> Function();

class _ScriptedGps {
  _ScriptedGps({required this.fixes});
  /// One entry per expected fetch; each produces the position (or future).
  final List<_Fix> fixes;
  int fetchCount = 0;
  int permissionRequests = 0;

  Future<Position> _nextFix(LocationSettings _) {
    final index = fetchCount++;
    return fixes[index]();
  }

  GpsCaptureService build() => GpsCaptureService(
        servicesEnabled: () async => true,
        checkPermission: () async => LocationPermission.denied,
        requestPermission: () async {
          permissionRequests++;
          return LocationPermission.whileInUse;
        },
        fetchPosition: _nextFix,
      );
}

// The inner TextField carries the InputDecoration the screen configured;
// TextFormField itself does not expose it.
Finder _field(String hint) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == hint);

String _value(WidgetTester tester, String hint) =>
    tester.widget<TextField>(_field(hint)).controller!.text;

Finder _captureButton() =>
    find.widgetWithText(OutlinedButton, 'Capture GPS & Address');

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _ScriptedGps gps,
  PlacemarkLookup? geocode,
  bool drainSnackbars = true,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: AddTreeScreen(
      gpsService: gps.build(),
      // Default geocoder: resolves nothing and contacts nothing.
      placemarkLookup: geocode ?? ((_, __) async => <Placemark>[]),
      skipOnlineLocationLookup: true,
    ),
  ));
  await tester.pump(); // post-frame callback fires the automatic capture
  await tester.pump(); // microtasks: permission + fix resolution
  if (drainSnackbars) {
    // Expire the draft-check snackbar the screen raises when secure storage
    // is unavailable (always the case under flutter_test) so it can neither
    // block taps nor leave a pending timer.
    await tester.pump(const Duration(seconds: 6));
  }
}

void main() {
  testWidgets('screen open runs exactly one automatic capture and one '
      'permission request — never repeated', (tester) async {
    final gps = _ScriptedGps(fixes: [() async => _position()]);
    await _pumpScreen(tester, gps: gps);
    await tester.pump(const Duration(seconds: 1));

    expect(gps.fetchCount, 1);
    expect(gps.permissionRequests, 1);
    // The screen is usable again (button restored, not stuck loading).
    expect(_captureButton(), findsOneWidget);
    expect(find.text('Getting Location...'), findsNothing);
  });

  testWidgets('automatic capture fills empty coordinates and records the '
      'app-owned text for later recaptures', (tester) async {
    final gps = _ScriptedGps(fixes: [() async => _position()]);
    await _pumpScreen(tester, gps: gps);

    // Out-of-area mocked fix: coordinates fill, nothing else is invented.
    expect(_value(tester, 'Latitude'), '8.1403000');
    expect(_value(tester, 'Longitude'), '123.8330000');
    expect(_value(tester, 'Auto-filled from GPS, or type Purok / landmark'), '');
    expect(_captureButton(), findsOneWidget);
  });

  testWidgets('coordinates the user already typed are never touched by '
      'automatic capture', (tester) async {
    final pending = Completer<Position>();
    final gps = _ScriptedGps(fixes: [() => pending.future]);
    await _pumpScreen(tester, gps: gps, drainSnackbars: false);

    // The user types a latitude while the fix is still in flight.
    await tester.enterText(_field('Latitude'), '7.2222222');
    await tester.pump();

    pending.complete(_position());
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));

    // The typed value survives; the empty longitude is filled (per-field
    // fill-only-if-empty).
    expect(_value(tester, 'Latitude'), '7.2222222');
    expect(_value(tester, 'Longitude'), '123.8330000');
  });

  testWidgets('a poor automatic fix is withheld with an honest message',
      (tester) async {
    final gps =
        _ScriptedGps(fixes: [() async => _position(accuracy: 120)]);
    await _pumpScreen(tester, gps: gps, drainSnackbars: false);

    expect(_value(tester, 'Latitude'), '');
    expect(_value(tester, 'Longitude'), '');
    expect(find.textContaining('the fix was not applied'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6)); // expire snackbars
  });

  testWidgets('manual recapture keeps user-entered coordinates unless the '
      'user confirms — "Keep current"', (tester) async {
    final gps = _ScriptedGps(fixes: [
      () async => _position(),
      () async => _position(lat: 7.3, lng: 125.6),
    ]);
    await _pumpScreen(tester, gps: gps, drainSnackbars: false);

    // The user replaces the app-written latitude with their own value.
    await tester.enterText(_field('Latitude'), '7.1111111');
    await tester.ensureVisible(_captureButton());
    await tester.pump();
    await tester.tap(_captureButton());
    await tester.pump();
    await tester.pump();

    // The app-owned longitude may refresh silently; the typed latitude may
    // not — one confirmation covers both, so declining protects everything.
    expect(find.text('Replace entered coordinates?'), findsOneWidget);
    await tester.tap(find.text('Keep current'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));

    expect(_value(tester, 'Latitude'), '7.1111111');
    expect(_value(tester, 'Longitude'), '123.8330000');
  });

  testWidgets('manual recapture applies the new fix when the user confirms — '
      '"Replace"', (tester) async {
    final gps = _ScriptedGps(fixes: [
      () async => _position(),
      () async => _position(lat: 7.3, lng: 125.6),
    ]);
    await _pumpScreen(tester, gps: gps, drainSnackbars: false);

    await tester.enterText(_field('Latitude'), '7.1111111');
    await tester.ensureVisible(_captureButton());
    await tester.pump();
    await tester.tap(_captureButton());
    await tester.pump();
    await tester.pump();

    expect(find.text('Replace entered coordinates?'), findsOneWidget);
    await tester.tap(find.text('Replace'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));

    expect(_value(tester, 'Latitude'), '7.3000000');
    expect(_value(tester, 'Longitude'), '125.6000000');
  });

  testWidgets('a geocoder that never answers cannot keep the loading state '
      'stuck', (tester) async {
    final gps = _ScriptedGps(fixes: [() async => _position()]);
    // A lookup that never completes — the Phase 12B.1A hang scenario.
    final hang = Completer<List<Placemark>>();
    await _pumpScreen(
      tester,
      gps: gps,
      geocode: (_, __) => hang.future,
      drainSnackbars: false,
    );
    await tester.pump();

    // Fix applied, lookup in flight: the button shows the loading label.
    expect(_value(tester, 'Latitude'), '8.1403000');
    expect(find.text('Getting Location...'), findsOneWidget);

    // Past the geocode budget the screen gives up on the address — and the
    // loading state clears while the captured coordinates stay put.
    await tester.pump(kGeocodeTimeout + const Duration(milliseconds: 200));
    expect(_captureButton(), findsOneWidget);
    expect(find.text('Getting Location...'), findsNothing);
    expect(_value(tester, 'Latitude'), '8.1403000');
    expect(_value(tester, 'Longitude'), '123.8330000');

    await tester.pump(const Duration(seconds: 6)); // expire snackbars
  });

  testWidgets('a geocoder that fails still keeps the captured coordinates',
      (tester) async {
    final gps = _ScriptedGps(fixes: [() async => _position()]);
    await _pumpScreen(
      tester,
      gps: gps,
      geocode: (_, __) async => throw Exception('geocoder down'),
      drainSnackbars: false,
    );
    await tester.pump(const Duration(seconds: 6));

    // Failure means fewer auto-filled fields, never a lost fix or a crash.
    expect(_value(tester, 'Latitude'), '8.1403000');
    expect(_value(tester, 'Longitude'), '123.8330000');
    expect(_value(tester, 'Auto-filled from GPS, or type Purok / landmark'), '');
    expect(_captureButton(), findsOneWidget);
  });
}
