import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treetrace_mobile/screens/landing_screen.dart';
import 'package:treetrace_mobile/services/theme.dart';

void main() {
  testWidgets('TreeTrace landing screen renders primary actions',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const LandingScreen(),
      ),
    );

    expect(find.text('TreeTrace'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.text('Log In'), findsWidgets);
  });
}
