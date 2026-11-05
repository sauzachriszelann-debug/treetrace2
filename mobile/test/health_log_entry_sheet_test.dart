import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treetrace_mobile/models/models.dart';
import 'package:treetrace_mobile/screens/tree_detail_screen.dart';

void main() {
  final tree = TreeModel(
    id: 42,
    commonName: 'Mango',
    healthStatus: 'Healthy',
    dbhCm: 20,
    heightM: 10,
  );

  Future<Future<bool?>?> openSheet(
    WidgetTester tester, {
    required Future<bool> Function(Map<String, dynamic>) onSave,
  }) async {
    Future<bool?>? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              result = showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                builder: (_) => HealthLogEntrySheet(
                  tree: tree,
                  onSave: onSave,
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('successful save closes the sheet once without lifecycle errors',
      (tester) async {
    final completer = Completer<bool>();
    Map<String, dynamic>? submitted;
    final result = await openSheet(
      tester,
      onSave: (payload) {
        submitted = payload;
        return completer.future;
      },
    );

    await tester.tap(find.text('Save Health Log'));
    await tester.pump();
    expect(find.text('Saving…'), findsOneWidget);
    expect(tester.takeException(), isNull);

    completer.complete(false);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(await result, isFalse);
    expect(submitted?['tree_id'], 42);
    expect(submitted?['condition'], 'Healthy');
    expect(submitted?['dbh_cm'], 20.0);
    expect(submitted?['height_m'], 10.0);
    expect(tester.takeException(), isNull);
    expect(find.text('Add Health Log'), findsNothing);
  });

  testWidgets('failed save keeps entered values and permits retry',
      (tester) async {
    var attempts = 0;
    final result = await openSheet(
      tester,
      onSave: (_) async {
        attempts++;
        if (attempts == 1) throw Exception('server rejected request');
        return true;
      },
    );

    await tester.enterText(find.byType(TextField).last, 'field note');
    await tester.tap(find.text('Save Health Log'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.textContaining('Your entries are still here'), findsOneWidget);
    expect(find.text('Add Health Log'), findsOneWidget);
    expect(find.text('field note'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Save Health Log'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(await result, isTrue);
    expect(tester.takeException(), isNull);
  });
}
