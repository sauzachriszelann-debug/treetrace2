import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treetrace_mobile/screens/automatic_dbh_screen.dart';
import 'package:treetrace_mobile/services/dbh_ar_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'retake, unavailable, placeholders and invalid values cannot be accepted',
      () {
    for (final response in <Map<String, dynamic>>[
      {'status': 'retake', 'dbh_cm': null},
      {'status': 'unavailable', 'dbh_cm': 25},
      {'status': 'ok', 'dbh_cm': 25, 'fallback': true},
      {'status': 'ok', 'dbh_cm': double.nan},
      {'status': 'ok', 'dbh_cm': double.infinity},
      {'status': 'ok', 'dbh_cm': -1},
      {'status': 'ok', 'dbh_cm': 500},
    ]) {
      expect(acceptedAutomaticDbh(response), isNull);
    }
    expect(acceptedAutomaticDbh({'status': 'ok', 'dbh_cm': 32.5}), 32.5);
  });

  testWidgets(
      'advanced AR still reports unsupported devices and disables acceptance',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        DbhArService.channel,
        (call) async => {
              'supported': false,
              'reason': 'Depth is unsupported on this phone.'
            });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(DbhArService.channel, null));
    await tester
        .pumpWidget(MaterialApp(home: AutomaticDbhScreen(onUse: (_) {})));
    await tester.pumpAndSettle();
    expect(find.text('Depth is unsupported on this phone.'), findsOneWidget);
    expect(find.text('Manual Circumference'), findsNothing);
    expect(find.text('With Reference Object'), findsNothing);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Use This Measurement'))
            .onPressed,
        isNull);
  });
}
