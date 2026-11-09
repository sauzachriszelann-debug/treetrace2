import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treetrace_mobile/screens/tree_scan_screen.dart';
import 'package:treetrace_mobile/services/tree_height_measurement.dart';
import 'package:treetrace_mobile/services/tree_scan_result.dart';

void main() {
  test('upright rear camera angles keep the correct sign and quadrant', () {
    for (final degrees in [-60.0, -10.0, 0.0, 25.0, 60.0]) {
      final radians = degrees * math.pi / 180;
      expect(
          phoneElevationDegrees(
              x: 0, y: 9.8 * math.cos(radians), z: 9.8 * math.sin(radians)),
          closeTo(degrees, 1e-8));
    }
    expect(() => phoneElevationDegrees(x: 0, y: -9.8, z: 0),
        throwsFormatException);
    expect(
        () => phoneElevationDegrees(x: 9.8, y: 0, z: 0), throwsFormatException);
  });

  test('missing results stay absent rather than becoming measurements', () {
    const empty = TreeScanResult();
    expect(empty.hasResults, isFalse);
    expect(empty.heightMeters, isNull);
    expect(empty.dbh, isNull);
    final photoOnly = TreeScanResult(photo: File('unknown_tree.jpg'));
    expect(photoOnly.hasResults, isTrue);
    expect(photoOnly.species, isNull);
    expect(photoOnly.heightMeters, isNull);
    expect(const TreeScanResult(heightMeters: 12).hasResults, isTrue);
  });

  testWidgets('combined review cannot accept an empty scan or save a tree',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: TreeScanScreen(autoStart: false)));
    expect(find.text('Review Tree Scan'), findsOneWidget);
    expect(find.text('DBH (cm)'), findsOneWidget);
    expect(find.text('Height (m)'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('use-tree-scan')), 250,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    final button =
        tester.widget<ElevatedButton>(find.byKey(const Key('use-tree-scan')));
    expect(button.onPressed, isNull);
    expect(find.text('Save Tree'), findsNothing);
  });

  testWidgets(
      'AI fills editable fields and corrections preserve original predictions',
      (tester) async {
    TreeScanResult? accepted;
    const initial = TreeScanResult(
      species: {
        'common_name': 'AI tree',
        'scientific_name': 'Original species'
      },
      dbh: {'status': 'ok', 'dbh_cm': 12.0, 'method': 'yolo_trunk_v1_ar_depth'},
      heightMeters: 8,
    );
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        accepted = await Navigator.push<TreeScanResult>(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const TreeScanScreen(
                                    autoStart: false,
                                    initialResult: initial,
                                    advancedAr: true)));
                      },
                      child: const Text('Open review')),
                ))));
    await tester.tap(find.text('Open review'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('scan-common-name')))
            .controller!
            .text,
        'AI tree');
    await tester.ensureVisible(find.byKey(const Key('scan-scientific-name')));
    await tester.enterText(
        find.byKey(const Key('scan-scientific-name')), 'Corrected species');
    await tester.ensureVisible(find.byKey(const Key('scan-dbh')));
    await tester.enterText(find.byKey(const Key('scan-dbh')), '14');
    await tester.ensureVisible(find.byKey(const Key('use-tree-scan')));
    await tester.tap(find.byKey(const Key('use-tree-scan')));
    await tester.pumpAndSettle();
    expect(accepted?.species?['scientific_name'], 'Original species');
    expect(accepted?.reviewedScientificName, 'Corrected species');
    expect(accepted?.dbh?['dbh_cm'], 12);
    expect(accepted?.reviewedDbhCm, 14);
    expect(accepted?.reviewedHeightMeters, 8);
  });
}
