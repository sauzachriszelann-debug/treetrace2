import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treetrace_mobile/widgets/nearby_tree_warnings.dart';

void main() {
  testWidgets('sample warning has no registration action or record navigation', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
      TextButton(onPressed: () => showNearbyTreeWarnings(context, [{
        'common_name': 'Mango (sample)', 'distance_m': 3,
        'species_match': 'exact', 'duplicate_warning': 'red',
        'duplicate_reason': 'Matching DBH and height',
      }], preview: true), child: const Text('Preview'))))));
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.text('Sample data only. Nothing will be saved.'), findsOneWidget);
    expect(find.text('Matching DBH and height'), findsOneWidget);
    expect(find.text('Register as a new tree'), findsNothing);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'View tree record')).onPressed, isNull);
    await tester.tap(find.text('Close preview'));
    await tester.pumpAndSettle();
    expect(find.text('Duplicate warning preview'), findsNothing);
  });
}
