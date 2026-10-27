// Phase 12C.2 — map reliability, privacy display, and navigation tests.
//
// Fixture-driven with SYNTHETIC tree data only: fictional ids, names and
// coordinates invented for these tests (never a real device fix).
//
// Network safety: MapScreen and PublicMapPreviewCard are pumped with injected
// loaders/fixtures, and flutter_test's HttpOverrides (_MockHttpOverrides in
// _binding_io.dart) absorbs every dart:io HTTP request — tiles, Google Fonts,
// Wikipedia, Dio to the production URL — returning mock 400s without ever
// opening a socket. No test can contact OSM, ArcGIS, Bing, Supabase, Render,
// or any other external service.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:treetrace_mobile/models/models.dart';
import 'package:treetrace_mobile/screens/map_screen.dart';
import 'package:treetrace_mobile/screens/public_portal_screen.dart';
import 'package:treetrace_mobile/screens/public_tree_profile_screen.dart';
import 'package:treetrace_mobile/screens/tree_detail_screen.dart';
import 'package:treetrace_mobile/services/api_service.dart';
import 'package:treetrace_mobile/services/auth_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Synthetic fixtures — every coordinate below is invented for this file.
// Points sit near the map's hardcoded public center so markers render inside
// the initial viewport (zoom 14).
// ─────────────────────────────────────────────────────────────────────────────

Map<String, dynamic> treeJson({
  required int id,
  String name = 'Synthetic Fir',
  String? sci = 'Picea ficta',
  String health = 'Healthy',
  double? lat = 7.305123456,
  double? lng = 125.68654321,
  String? barangay = 'Fixture Barangay',
  String? city = 'Fixture City',
  String? province = 'Fixture Province',
  String? notes,
}) =>
    {
      'id': id,
      'common_name': name,
      'scientific_name': sci,
      'health_status': health,
      'lat': lat,
      'lng': lng,
      'barangay': barangay,
      'city': city,
      'province': province,
      'notes': notes,
    };

final List<Map<String, dynamic>> threeTrees = [
  treeJson(id: 1, name: 'Synthetic Fir', lat: 7.305123456, lng: 125.68654321),
  treeJson(
      id: 2,
      name: 'Fake Oak',
      health: 'Fair',
      lat: 7.3062,
      lng: 125.6877,
      notes: 'Exact location: 123 Fabricated Lane'),
  treeJson(
      id: 3, name: 'Mock Pine', health: 'Poor', lat: 7.3043, lng: 125.6833),
];

// ─────────────────────────────────────────────────────────────────────────────
// Test seams
// ─────────────────────────────────────────────────────────────────────────────

class _FakeSecureStore implements SecureStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<void> delete(String key) async {}
}

Map<String, dynamic> meMap({String role = 'field_worker'}) => {
      'id': 7,
      'full_name': 'Fixture User',
      'email': 'fixture@example.test',
      'role': role,
      'is_active': true,
      'subscription_plan': 'free',
      'upgrade_requested': false,
      'ai_identifications_today': 0,
      'unknown_submissions_today': 0,
    };

Future<AuthProvider> authWithRole(String role) async {
  final provider = AuthProvider(
    apiOverride: ApiService.forTest(
      storage: _FakeSecureStore(),
      onlineCheck: () async => false,
    ),
    deps: AuthProviderDeps(
      readToken: () async => 'fixture-token',
      fetchMe: () async => meMap(role: role),
      saveCachedMe: (_) async {},
      readCachedMe: () async => null,
      clearToken: () async {},
      clearCachedMe: () async {},
      minimumSplash: Duration.zero,
    ),
  );
  await provider.init();
  return provider;
}

/// Scripted loader: each entry is one response; the last entry repeats.
Future<List<dynamic>> Function() scriptedLoader(
    List<Future<List<dynamic>> Function()> responses) {
  var calls = 0;
  return () {
    final index = calls < responses.length ? calls : responses.length - 1;
    calls++;
    return responses[index]();
  };
}

/// Phase 12C.5: tolerate ONLY image-resource errors from flutter_test's
/// mocked HTTP 400s.
///
/// flutter_map handles each failed tile itself (debugPrint in
/// `_onTileLoadError`), but when the camera refits, in-flight tiles are
/// pruned before their mocked 400 arrives — the orphaned image completers
/// have no listener left, so Flutter re-reports the failure through
/// `FlutterError.onError`, which flutter_test counts as test exceptions.
/// In production the tiles come from a real CDN and this path never fires.
///
/// The filter drops nothing but `library == 'image resource service'`:
/// every other framework error still fails the test as usual, and none of
/// the assertions in this file are relaxed.
void ignoreMockedTileImageErrors() {
  final previous = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.library == 'image resource service') return;
    previous?.call(details);
  };
}

Future<void> pumpMap(
  WidgetTester tester, {
  required Future<List<dynamic>> Function() loader,
  AuthProvider? auth,
}) async {
  ignoreMockedTileImageErrors();
  final provider = auth ?? await authWithRole('field_worker');
  await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
    value: provider,
    child: MaterialApp(home: MapScreen(treeLoader: loader)),
  ));
  await tester.pump(); // initState → _load starts
  await tester.pump(); // loader resolves → setState
}

/// flutter_map 7 renders [Marker] as a data object (its [MarkerLayer]
/// emits a [Positioned] carrying the marker's key), so markers are located
/// by the stable keys the screens attach to them.
Finder keyedMarkers(String prefix) => find.byWidgetPredicate((w) {
      final key = w.key;
      return key is ValueKey &&
          key.value is String &&
          (key.value as String).startsWith(prefix);
    });

Finder mapMarkers() => keyedMarkers('map-marker-');

Future<List<dynamic>> immediate(List<Map<String, dynamic>> trees) async =>
    trees;

Future<List<dynamic>> failing(Object error) async => throw error;

void main() {
  group('MapScreen markers', () {
    testWidgets('only trees with coordinates become markers', (tester) async {
      await pumpMap(
        tester,
        loader: scriptedLoader([
          () => immediate([
                ...threeTrees,
                treeJson(id: 4, name: 'No Fix Tree', lat: null, lng: null),
              ]),
        ]),
      );

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(mapMarkers(), findsNWidgets(3));
      // The coordinate-less fixture must be excluded entirely.
      expect(mapMarkers(),
          findsNWidgets(3), reason: 'null-coordinate tree is filtered out');
    });

    testWidgets('health chips filter markers both ways', (tester) async {
      await pumpMap(tester,
          loader: scriptedLoader([() => immediate(threeTrees)]));
      expect(mapMarkers(), findsNWidgets(3));

      // 'Fair' appears in the filter chip (top controls) and the legend
      // (drawn later) — the first occurrence is the chip.
      await tester.tap(find.text('Fair').first);
      await tester.pump();
      expect(mapMarkers(), findsNWidgets(1));

      await tester.tap(find.text('All Trees'));
      await tester.pump();
      expect(mapMarkers(), findsNWidgets(3));
    });

    testWidgets('search narrows markers and a no-match submit is honest',
        (tester) async {
      await pumpMap(tester,
          loader: scriptedLoader([() => immediate(threeTrees)]));
      expect(mapMarkers(), findsNWidgets(3));

      await tester.enterText(find.byType(TextField), 'oak');
      await tester.pump();
      expect(mapMarkers(), findsNWidgets(1));

      await tester.enterText(find.byType(TextField), 'zzz-no-such-tree');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(find.text('No mapped tree found for that search.'), findsOneWidget);

      // Let the snackbar expire so no timer outlives the test.
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('MapScreen popup (privacy display)', () {
    testWidgets('shows four-decimal coordinates and never the notes line',
        (tester) async {
      await pumpMap(tester,
          loader: scriptedLoader([() => immediate(threeTrees)]));

      await tester.tap(mapMarkers().first);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      // Fixture 1: 4dp rendering of the synthetic values.
      expect(find.text('7.3051, 125.6865'), findsOneWidget);
      // The full-precision string must NOT be displayed.
      expect(find.text('7.305123, 125.686543'), findsNothing);

      // Fixture 2 carries a notes payload: the popup must never surface it
      // (the public endpoint does not return notes at all).
      expect(find.textContaining('Fabricated Lane'), findsNothing);
      expect(find.textContaining('Exact location'), findsNothing);

      expect(find.text('View Full Details'), findsOneWidget);

      Navigator.of(tester.element(find.text('View Full Details'))).pop();
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    });
  });

  group('MapScreen role navigation', () {
    testWidgets('citizen opens the public tree profile', (tester) async {
      await pumpMap(tester,
          loader: scriptedLoader([() => immediate(threeTrees)]),
          auth: await authWithRole('citizen'));

      await tester.tap(mapMarkers().first);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(find.text('View Full Details'));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      expect(find.byType(PublicTreeProfileScreen), findsOneWidget);
      expect(find.byType(TreeDetailScreen), findsNothing);

      Navigator.of(tester.element(find.byType(PublicTreeProfileScreen))).pop();
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    });

    testWidgets('field worker opens the full tree detail', (tester) async {
      await pumpMap(tester,
          loader: scriptedLoader([() => immediate(threeTrees)]),
          auth: await authWithRole('field_worker'));

      await tester.tap(mapMarkers().first);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(find.text('View Full Details'));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      expect(find.byType(TreeDetailScreen), findsOneWidget);
      expect(find.byType(PublicTreeProfileScreen), findsNothing);

      Navigator.of(tester.element(find.byType(TreeDetailScreen))).pop();
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    });
  });

  group('MapScreen loading errors', () {
    testWidgets('a failed load shows an error with a working Retry',
        (tester) async {
      final loader = scriptedLoader([
        () => failing(Exception('fixture outage')),
        () => immediate(threeTrees),
      ]);
      await pumpMap(tester, loader: loader);

      expect(find.byType(FlutterMap), findsNothing);
      expect(find.text('Cannot load the map right now.'), findsOneWidget);
      expect(find.textContaining('could not be fetched'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Retry'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Retry'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Cannot load the map right now.'), findsNothing);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(mapMarkers(), findsNWidgets(3));
    });
  });

  group('MapScreen tiles and attribution', () {
    testWidgets('defaults to OpenStreetMap with a visible OSM credit only',
        (tester) async {
      await pumpMap(tester,
          loader: scriptedLoader([() => immediate(threeTrees)]));

      final tile = tester.widget<TileLayer>(find.byType(TileLayer));
      expect(tile.urlTemplate, contains('tile.openstreetmap.org'));

      // Phase 12C.5 (A): the credit must be a VISIBLE text widget painted in
      // the screen's own stack (flutter_map's attribution layer was removed
      // after failing to paint on-device).
      final credit = find.text('© OpenStreetMap contributors');
      expect(credit, findsOneWidget);
      expect(tester.getSize(credit).width, greaterThan(0),
          reason: 'the credit row must paint with non-zero size');
      expect(find.textContaining('Esri'), findsNothing);
    });

    testWidgets('satellite toggle switches tiles and adds Esri attribution',
        (tester) async {
      await pumpMap(tester,
          loader: scriptedLoader([() => immediate(threeTrees)]));

      await tester.tap(find.byIcon(Icons.satellite_alt_rounded));
      await tester.pump();

      final tile = tester.widget<TileLayer>(find.byType(TileLayer));
      expect(tile.urlTemplate, contains('arcgisonline.com'));

      // Phase 12C.5 (A): both credits appear in the single satellite credit
      // line, and neither may be hidden inside a non-painting widget.
      final osmCredit = find.textContaining('OpenStreetMap');
      final esriCredit = find.textContaining('Esri');
      expect(osmCredit, findsOneWidget);
      expect(esriCredit, findsOneWidget);
      expect(tester.getSize(osmCredit).width, greaterThan(0));
    });
  });

  group('PublicMapPreviewCard', () {
    Widget wrap(Widget child) =>
        MaterialApp(home: Scaffold(body: child));

    testWidgets('shows the honest empty state with no map at all',
        (tester) async {
      await tester.pumpWidget(
          wrap(const PublicMapPreviewCard(trees: [])));

      expect(find.byType(FlutterMap), findsNothing);
      expect(find.text('No GPS data available'), findsOneWidget);
      expect(find.text('0 trees with location'), findsOneWidget);
    });

    testWidgets('caps markers at 20 and counts only GPS-tagged trees',
        (tester) async {
      final many = <Map<String, dynamic>>[
        for (var i = 0; i < 25; i++)
          treeJson(id: i + 1, lat: 7.301 + i * 0.001, lng: 125.681 + i * 0.001),
        for (var i = 0; i < 5; i++) treeJson(id: 100 + i, lat: null, lng: null),
      ];
      await tester.pumpWidget(
          wrap(PublicMapPreviewCard(trees: many.map(TreeModel.fromJson).toList())));
      await tester.pump();

      expect(keyedMarkers('preview-marker-'), findsNWidgets(20));
      expect(find.text('25 trees with location'), findsOneWidget);
      expect(find.byType(FlutterMap), findsOneWidget);
    });

    testWidgets('carries OpenStreetMap attribution', (tester) async {
      await tester.pumpWidget(wrap(
          PublicMapPreviewCard(trees: threeTrees.map(TreeModel.fromJson).toList())));
      await tester.pump();

      expect(find.byType(SimpleAttributionWidget), findsOneWidget);
      expect(find.text('OpenStreetMap contributors'), findsOneWidget);
    });

    testWidgets('the open-map affordance fires its callback', (tester) async {
      var opened = false;
      await tester.pumpWidget(wrap(PublicMapPreviewCard(
        trees: threeTrees.map(TreeModel.fromJson).toList(),
        onOpenMap: () => opened = true,
      )));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
      expect(opened, isTrue);
    });
  });
}
