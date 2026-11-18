import 'species_reference_catalog.dart';

String _referenceKey(Object? name) => name is String
    ? name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ')
    : '';

Map<String, dynamic> speciesReferenceFacts(Object? name) {
  var key = _referenceKey(name);
  key = {'monoon longifolium': 'polyalthia longifolia', 'albizia saman': 'samanea saman'}[key] ?? key;
  for (final entry in speciesReferenceCatalog.entries) {
    if (_referenceKey(entry.key) == key) return Map<String, dynamic>.from(entry.value as Map);
  }
  return {};
}

Map<String, dynamic> enrichScanSpeciesFacts(Map<String, dynamic> result) {
  if (result['not_identified'] == true) return result;
  final facts = speciesReferenceFacts(result['scientific_name']);
  facts.remove('scientific_name');
  return {...result, ...facts};
}

List<Map<String, dynamic>> speciesComparisons(Map<String, dynamic> result) {
  if (result['not_identified'] == true) return [];
  final facts = speciesReferenceFacts(result['scientific_name']);
  final records = facts['similar_species_records'] ?? result['similar_species_records'];
  return records is List ? records.whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList() : [];
}

bool _isPhotoUrl(Object? value) {
  if (value is! String) return false;
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      ['https', 'http'].contains(uri.scheme) &&
      uri.host.isNotEmpty;
}

/// Actual record images must come from the record, never a species-name search.
List<String> recordedTreePhotos(String? photoUrl) =>
    _isPhotoUrl(photoUrl) ? [photoUrl!.trim()] : [];

List<String> speciesReferencePhotos(Map<String, dynamic> result) {
  String normalize(Object? name) => name is String
      ? name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ')
      : '';
  final identified = normalize(result['scientific_name']);
  if (identified.isEmpty ||
      normalize(result['reference_scientific_name']) != identified ||
      result['reference_source'] != 'plantnet') {
    return [];
  }
  final images = result['match_images'];
  if (images is! List) return [];
  return images
      .where(_isPhotoUrl)
      .cast<String>()
      .map((url) => url.trim())
      .toSet()
      .take(8)
      .toList();
}

/// Curated, taxon-matched reference images, separate from a user's tree photo.
final curatedSpeciesPhotos = <String, List<Map<String, String>>>{
  for (final entry in speciesReferenceCatalog.entries)
    _referenceKey(entry.key): [
      for (final photo in (entry.value['reference_photos'] as List? ?? []))
        Map<String, String>.from(photo as Map),
    ],
};

List<Map<String, String>> curatedReferencePhotos(Map<String, dynamic> result) {
  final name = result['scientific_name'];
  if (name is! String || result['not_identified'] == true) return [];
  final photos = speciesReferenceFacts(name)['reference_photos'];
  return photos is List ? photos.whereType<Map>().map((p) => Map<String, String>.from(p)).toList() : [];
}
