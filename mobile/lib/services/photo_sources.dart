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
