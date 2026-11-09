import 'dart:math' as math;

/// Crown ray above a tracked tree-base anchor, all observed in the same frame.
/// This assumes an upright tree with its crown point vertically above its base.
/// AR scale and operator targeting remain subject to field validation.
double? heightFromArObservation(Map<String, dynamic> observation) {
  if (observation['source'] != 'arcore_base_anchor' ||
      observation['tracking'] != 'tracking' ||
      observation['stable'] != true) {
    return null;
  }
  final distance = observation['horizontal_distance_m'];
  final elevation = observation['elevation_degrees'];
  final cameraHeight = observation['camera_height_m'];
  final alignment = observation['alignment_degrees'];
  if ([distance, elevation, cameraHeight, alignment]
      .any((value) => value is! num || !value.isFinite)) {
    return null;
  }
  if (distance < 2 ||
      distance > 30 ||
      elevation <= 0 ||
      elevation >= 80 ||
      cameraHeight < 0.3 ||
      cameraHeight > 3 ||
      alignment.abs() > 5) {
    return null;
  }
  final height = cameraHeight + distance * math.tan(elevation * math.pi / 180);
  return height.isFinite && height > cameraHeight && height <= 100
      ? height.toDouble()
      : null;
}
