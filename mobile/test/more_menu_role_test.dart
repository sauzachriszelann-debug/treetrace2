import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treetrace_mobile/screens/my_submissions_screen.dart';
import 'package:treetrace_mobile/screens/profile_screen.dart';
import 'package:treetrace_mobile/screens/qr_labels_screen.dart';
import 'package:treetrace_mobile/screens/unknown_review_screen.dart';
import 'package:treetrace_mobile/screens/users_screen.dart';

// Phase 11F regression coverage: the More menu must mirror backend
// authorization. GET /api/ai/unknown-species and GET /api/users are both
// require_admin, so field workers and citizens must never be offered the
// "Unknown" and "Users" tiles that open those screens (a field worker
// tapping them previously provoked a 403 they could not resolve).
//
// The label matrix is tested directly, and the grid is pumped per role with
// the sheet callbacks stubbed. No api.init() and no sockets: the pushed
// screens fail their own loads safely against the uninitialized client, and
// the assertions are about visibility and navigation targets only.

/// Records the routes pushed by the menu so tests can assert destinations.
class _RecordingObserver extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

MaterialApp _app(String? role, {required _RecordingObserver observer}) {
  var fieldSyncTaps = 0;
  var historyTaps = 0;
  var expertTaps = 0;
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: MoreActionsGrid(
          role: role,
          onOpenFieldSync: () => fieldSyncTaps++,
          onShowHistory: () => historyTaps++,
          onShowExpertReviews: () => expertTaps++,
        ),
      ),
    ),
    navigatorObservers: [observer],
  );
}

void main() {
  group('moreMenuLabelsForRole', () {
    test('admin keeps the management tiles plus the field tools', () {
      final labels = moreMenuLabelsForRole('admin');
      expect(
        labels,
        ['Unknown', 'Users', 'QR Labels', 'Reports', 'Evaluation', 'Field Sync'],
      );
    });

    test('field worker keeps field tools but never the admin tiles', () {
      final labels = moreMenuLabelsForRole('field_worker');
      expect(labels, isNot(contains('Unknown')));
      expect(labels, isNot(contains('Users')));
      expect(labels, containsAll(['QR Labels', 'Reports', 'Evaluation', 'Field Sync']));
      // Field Sync and Evaluation still exist for staff.
      expect(labels.length, 4);
    });

    test('citizen keeps own-submission tools and no staff tiles', () {
      final labels = moreMenuLabelsForRole('citizen');
      expect(labels, containsAll([
        'Evaluation',
        'My Submissions',
        'Field Sync',
        'History',
        'Expert Reviews',
      ]));
      expect(labels, isNot(contains('Unknown')));
      expect(labels, isNot(contains('Users')));
      expect(labels, isNot(contains('Reports')));
      expect(labels, isNot(contains('QR Labels')));
    });

    test('an unknown or missing role never exposes the admin tiles', () {
      for (final role in ['guest', '', 'Field_Worker', null]) {
        final labels = moreMenuLabelsForRole(role);
        expect(labels, isNot(contains('Unknown')),
            reason: 'role=$role must not see Unknown');
        expect(labels, isNot(contains('Users')),
            reason: 'role=$role must not see Users');
      }
    });

    test('the admin tiles are exactly the require_admin screens', () {
      // Guards the mapping itself: these two labels are the only tiles whose
      // screens call admin-only endpoints, so they must be gated together.
      final adminLabels = moreMenuLabelsForRole('admin');
      final workerLabels = moreMenuLabelsForRole('field_worker');
      final adminOnly = adminLabels.where((l) => !workerLabels.contains(l));
      expect(adminOnly, ['Unknown', 'Users']);
    });
  });

  group('MoreActionsGrid visibility', () {
    testWidgets('field worker sees field tools, not Unknown/Users',
        (tester) async {
      final observer = _RecordingObserver();
      await tester.pumpWidget(_app('field_worker', observer: observer));

      expect(find.text('QR Labels'), findsOneWidget);
      expect(find.text('Reports'), findsOneWidget);
      expect(find.text('Evaluation'), findsOneWidget);
      expect(find.text('Field Sync'), findsOneWidget);
      expect(find.text('Unknown'), findsNothing);
      expect(find.text('Users'), findsNothing);
    });

    testWidgets('admin sees Unknown and Users', (tester) async {
      final observer = _RecordingObserver();
      await tester.pumpWidget(_app('admin', observer: observer));

      expect(find.text('Unknown'), findsOneWidget);
      expect(find.text('Users'), findsOneWidget);
      expect(find.text('QR Labels'), findsOneWidget);
      expect(find.text('Reports'), findsOneWidget);
    });

    testWidgets('citizen sees own-submission tools only', (tester) async {
      final observer = _RecordingObserver();
      await tester.pumpWidget(_app('citizen', observer: observer));

      expect(find.text('My Submissions'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Expert Reviews'), findsOneWidget);
      expect(find.text('Evaluation'), findsOneWidget);
      expect(find.text('Field Sync'), findsOneWidget);
      expect(find.text('Unknown'), findsNothing);
      expect(find.text('Users'), findsNothing);
      expect(find.text('Reports'), findsNothing);
      expect(find.text('QR Labels'), findsNothing);
    });

    testWidgets('a missing role never sees Unknown or Users',
        (tester) async {
      final observer = _RecordingObserver();
      await tester.pumpWidget(_app(null, observer: observer));

      expect(find.text('Unknown'), findsNothing);
      expect(find.text('Users'), findsNothing);
      expect(find.text('QR Labels'), findsOneWidget);
    });
  });

  group('MoreActionsGrid navigation', () {
    testWidgets('admin tapping Users opens the Users screen', (tester) async {
      final observer = _RecordingObserver();
      await tester.pumpWidget(_app('admin', observer: observer));

      await tester.tap(find.text('Users'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(observer.pushed, isNotEmpty);
      expect(find.byType(UsersScreen), findsOneWidget);
    });

    testWidgets('admin tapping Unknown opens the review queue',
        (tester) async {
      final observer = _RecordingObserver();
      await tester.pumpWidget(_app('admin', observer: observer));

      await tester.tap(find.text('Unknown'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(observer.pushed, isNotEmpty);
      expect(find.byType(UnknownReviewScreen), findsOneWidget);
    });

    testWidgets('field worker tapping QR Labels opens the label screen',
        (tester) async {
      final observer = _RecordingObserver();
      await tester.pumpWidget(_app('field_worker', observer: observer));

      await tester.tap(find.text('QR Labels'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(observer.pushed, isNotEmpty);
      expect(find.byType(QrLabelsScreen), findsOneWidget);
    });

    testWidgets('citizen tapping My Submissions opens their submissions',
        (tester) async {
      final observer = _RecordingObserver();
      await tester.pumpWidget(_app('citizen', observer: observer));

      await tester.tap(find.text('My Submissions'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(observer.pushed, isNotEmpty);
      expect(find.byType(MySubmissionsScreen), findsOneWidget);
    });

    testWidgets('field tools fire the injected sheet callbacks',
        (tester) async {
      // Field Sync / History / Expert Reviews open sheets owned by
      // ProfileScreen; here we only prove the wiring reaches the callback.
      final taps = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MoreActionsGrid(
              role: 'citizen',
              onOpenFieldSync: () => taps.add('fieldSync'),
              onShowHistory: () => taps.add('history'),
              onShowExpertReviews: () => taps.add('expert'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Field Sync'));
      await tester.tap(find.text('History'));
      await tester.tap(find.text('Expert Reviews'));
      await tester.pump();

      expect(taps, ['fieldSync', 'history', 'expert']);
    });
  });
}
