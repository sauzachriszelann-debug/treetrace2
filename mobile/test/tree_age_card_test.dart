import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treetrace_mobile/widgets/tree_age_card.dart';

void main() {
  test('invalid dimensions never become numeric age inputs', () {
    expect(ageDimension(null), isNull);
    expect(ageDimension('NaN'), isNull);
    expect(ageDimension(-1), isNull);
    expect(ageDimension('45'), 45);
  });

  testWidgets('shows separate age checks and study source', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TreeAgeCard(
      scientificName: 'Gmelina arborea',
      dbhCm: 45,
      heightM: 9,
      lookup: (species, dbh, height, source) async => {
        'status': 'estimated',
        'min_years': 3,
        'max_years': 22,
        'dbh_age_years': 17.6,
        'height_age_years': 3.9,
        'reason': 'Experimental growth scenario.',
        'source': {
          'citation': 'Published study',
          'context': 'Colombia',
          'url': 'https://doi.org/10.1007/s11056-023-10013-x'
        },
      },
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Approximately 3–22 years'), findsOneWidget);
    expect(find.text('From DBH: about 17.6 years'), findsOneWidget);
    expect(find.text('Copy growth study link'), findsOneWidget);
  });

  testWidgets('old photo response cannot replace new species age',
      (tester) async {
    final old = Completer<Map<String, dynamic>>();
    Future<Map<String, dynamic>> lookup(
            String species, double? d, double? h, String s) =>
        species == 'Gmelina arborea'
            ? old.future
            : Future.value(
                {'status': 'unavailable', 'reason': 'No reviewed source.'});
    Widget screen(String species) => MaterialApp(
        home: Scaffold(
            body: TreeAgeCard(scientificName: species, lookup: lookup)));
    await tester.pumpWidget(screen('Gmelina arborea'));
    await tester.pumpWidget(screen('Mangifera indica'));
    await tester.pumpAndSettle();
    old.complete({'status': 'estimated', 'min_years': 5, 'max_years': 10});
    await tester.pumpAndSettle();
    expect(find.text('Age unknown'), findsOneWidget);
    expect(find.textContaining('Approximately'), findsNothing);
  });

  testWidgets('failure gives retry instead of endless loading', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TreeAgeCard(
      scientificName: 'Gmelina arborea',
      lookup: (s, d, h, source) async => throw Exception('offline'),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Retry age estimate'), findsOneWidget);
    expect(find.text('Checking published growth data…'), findsNothing);
  });
}
