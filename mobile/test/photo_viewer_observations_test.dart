import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treetrace_mobile/widgets/expandable_photo.dart';
import 'package:treetrace_mobile/widgets/photo_observations_card.dart';
import 'package:treetrace_mobile/services/photo_sources.dart';

void main() {
  test('recorded tree photos never fabricate species search URLs', () {
    expect(recordedTreePhotos(null), isEmpty);
    expect(recordedTreePhotos('https://example.test/record.jpg'),
        ['https://example.test/record.jpg']);
  });

  test('reference photos require matching species and a known source', () {
    final result = <String, dynamic>{
      'scientific_name': 'Alpha beta',
      'reference_scientific_name': 'Alpha beta',
      'reference_source': 'plantnet',
      'match_images': [
        'https://example.test/reference.jpg',
        'https://example.test/reference.jpg',
        'not a url'
      ],
    };
    expect(
        speciesReferencePhotos(result), ['https://example.test/reference.jpg']);
    result['reference_scientific_name'] = 'Gamma delta';
    expect(speciesReferencePhotos(result), isEmpty);
  });
  testWidgets('photo opens uncropped with zoom and closes to the same screen',
      (tester) async {
    final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAFElEQVR4nGM8kWLEAANMDEgANwcARfYBZhhDpbAAAAAASUVORK5CYII=');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ExpandablePhoto(
                image: MemoryImage(bytes),
                label: 'Your scan',
                thumbnail: const SizedBox(
                    width: 200, height: 200, child: Text('Tap photo'))))));
    await tester.tap(find.text('Tap photo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
    expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .maxScale,
        6);
    await tester.tap(find.byTooltip('Close photo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Tap photo'), findsOneWidget);
  });

  testWidgets('unassessed photo never displays a healthy conclusion',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PhotoObservationsCard())));
    expect(find.text('Bark appearance: Unclear'), findsOneWidget);
    expect(find.text('Not assessed from this photo.'), findsOneWidget);
    expect(find.text('Healthy'), findsNothing);
  });

  testWidgets('bark and surface signs remain descriptive', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: PhotoObservationsCard(observations: {
      'status': 'observed',
      'bark_appearance': 'Ridged',
      'needs_closeup': false,
      'visible_signs': [
        {'code': 'leaf_holes', 'evidence': 'Two holes visible.'}
      ],
    }))));
    expect(find.text('Bark appearance: Ridged'), findsOneWidget);
    expect(find.text('Holes visible in leaves: Two holes visible.'),
        findsOneWidget);
    expect(find.textContaining('borer'), findsNothing);
  });
}
