/// Only public botanical/AI fields are carried into the saved profile.
Map<String, dynamic> scanProfilePayload(Map<String, dynamic> result) {
  const textFields = ['scientific_name', 'common_name', 'family', 'description',
    'distinguishing_features', 'look_alikes', 'habitat', 'uses',
    'adaptation_strategies', 'name_story', 'plant_type', 'lifespan', 'flower', 'fruit'];
  return {
    for (final field in textFields)
      if (result[field] is String) field: result[field],
    if (result['confidence_percent'] is num) 'confidence_percent': result['confidence_percent'],
    if (result['estimated_dbh_cm'] is num) 'estimated_dbh_cm': result['estimated_dbh_cm'],
    if (result['estimated_height_m'] is num) 'estimated_height_m': result['estimated_height_m'],
    if (result['age_estimate'] is Map) 'age_estimate': result['age_estimate'],
  };
}
