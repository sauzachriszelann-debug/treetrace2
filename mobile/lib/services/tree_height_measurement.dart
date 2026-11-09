import 'dart:math' as math;

/// Validates and calculates tree height from signed clinometer angles.
///
/// Distance is the horizontal distance to the tree base. Angles are in
/// degrees relative to horizontal: an upward sight to the top is positive,
/// while a downward sight to a lower base is negative.
double calculateTreeHeightMeters({
  required double horizontalDistanceMeters,
  required double topAngleDegrees,
  required double baseAngleDegrees,
}) {
  if (!horizontalDistanceMeters.isFinite || horizontalDistanceMeters <= 0) {
    throw const FormatException(
        'Enter a finite horizontal distance greater than zero.');
  }
  if (!topAngleDegrees.isFinite || !baseAngleDegrees.isFinite) {
    throw const FormatException('Enter finite top and base angles.');
  }
  if (topAngleDegrees.abs() >= 89 || baseAngleDegrees.abs() >= 89) {
    throw const FormatException(
        'Angles must be between -89° and 89°. Reposition and measure again.');
  }

  final topRadians = topAngleDegrees * math.pi / 180;
  final baseRadians = baseAngleDegrees * math.pi / 180;
  final height =
      horizontalDistanceMeters * (math.tan(topRadians) - math.tan(baseRadians));
  if (!height.isFinite || height <= 0) {
    throw const FormatException(
      'The top angle must be above the base angle. Check the readings and try again.',
    );
  }
  return height;
}

/// Converts a portrait-held phone's gravity vector to a signed camera
/// elevation angle. This is intended for a stationary phone aimed with its
/// rear camera at the target; large roll makes the reading unreliable.
double phoneElevationDegrees({
  required double x,
  required double y,
  required double z,
}) {
  if (![x, y, z].every((value) => value.isFinite)) {
    throw const FormatException('Phone sensor reading is unavailable.');
  }
  final magnitude = math.sqrt(x * x + y * y + z * z);
  if (magnitude < 7 || magnitude > 12) {
    throw const FormatException(
        'Hold the phone still while capturing an angle.');
  }
  if (x.abs() / magnitude > math.sin(15 * math.pi / 180)) {
    throw const FormatException(
        'Hold the phone upright in portrait orientation.');
  }
  // Android/iOS device coordinates: +Y points toward the top of the
  // portrait display, +Z out of its front. Rear-camera upward elevation
  // therefore has positive Z when the upright phone tilts toward the sky.
  if (y <= 0) {
    throw const FormatException(
        'Hold the phone upright, with its top edge up.');
  }
  return math.atan2(z, y) * 180 / math.pi;
}
