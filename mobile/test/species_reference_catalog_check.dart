// Pure Dart contract check: executable without a device or Flutter engine.
import '../lib/services/photo_sources.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

void main() {
  final mango = enrichScanSpeciesFacts({
    'scientific_name': 'Mangifera indica', 'family': 'Unknown',
    'confidence_percent': 86.45, 'estimated_dbh_cm': 15.0,
  });
  check(mango['family'] == 'Anacardiaceae', 'Family was not enriched');
  check(mango['confidence_percent'] == 86.45 && mango['estimated_dbh_cm'] == 15.0,
      'Reference data changed scan evidence');
  check(curatedReferencePhotos(mango).isNotEmpty, 'Mango reference photos missing');
  check(speciesComparisons(mango).first['scientific_name'] == 'Syzygium cumini', 'Wrong comparison');
  final unknown = {'scientific_name': 'Mangifera indica', 'not_identified': true};
  check(curatedReferencePhotos(unknown).isEmpty && speciesComparisons(unknown).isEmpty,
      'Uncertain identification received species photos');
  check(!enrichScanSpeciesFacts(unknown).containsKey('family'), 'Unknown result received confident facts');
  check(curatedReferencePhotos({'scientific_name': 'Acacia-Semanca'}).isEmpty,
      'Unverified label received invented photos');
  check(speciesReferenceFacts(' MONOON   LONGIFOLIUM ')['family'] == 'Annonaceae', 'Synonym did not resolve');
  for (final name in curatedSpeciesPhotos.keys.where((n) => n != 'acacia-semanca')) {
    check(curatedReferencePhotos({'scientific_name':name}).isNotEmpty, 'No references for $name');
  }
  print('Species reference contracts passed.');
}
