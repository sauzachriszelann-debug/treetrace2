import 'dart:math' as math;

/// Physical sensor axes are matched to saved-image axes by long/short size.
/// Reject cropping/aspect inconsistencies rather than silently rescaling a lens.
Map<String, dynamic> focalPixelsFromMetadata(Map<String, dynamic> data) {
  Map<String, dynamic> fail(String reason) =>
      {'status': 'retake', 'reason': reason, 'f_px': null};
  final keys = [
    'width',
    'height',
    'focal_mm',
    'exif_focal_mm',
    'sensor_width_mm',
    'sensor_height_mm'
  ];
  if (data['lens_locked'] != true) {
    return fail(
        'The main camera lens could not be locked. Retake or skip measurement.');
  }
  if (keys.any((key) =>
      data[key] is! num ||
      !(data[key] as num).isFinite ||
      (data[key] as num) <= 0)) {
    return fail(
        'Camera focal information is missing. Retake or skip measurement.');
  }
  double value(String key) => (data[key] as num).toDouble();
  final focal = value('focal_mm');
  if ((focal - value('exif_focal_mm')).abs() / focal > 0.05) {
    return fail(
        'The photo does not match the selected lens. Retake at 1x zoom.');
  }
  final zoom = data['exif_zoom'];
  if (zoom is num &&
      (!zoom.isFinite || (zoom > 0 && (zoom - 1).abs() > 0.01))) {
    return fail('Retake at 1x zoom.');
  }
  final longPixels = math.max(value('width'), value('height'));
  final shortPixels = math.min(value('width'), value('height'));
  final longMm = math.max(value('sensor_width_mm'), value('sensor_height_mm'));
  final shortMm = math.min(value('sensor_width_mm'), value('sensor_height_mm'));
  final fx = focal * longPixels / longMm;
  final fy = focal * shortPixels / shortMm;
  if ((fx - fy).abs() / math.max(fx, fy) > 0.03) {
    return fail(
        'The photo is cropped or its camera scale is uncertain. Retake at 1x zoom.');
  }
  return {
    'status': 'ok',
    'f_px': (fx + fy) / 2,
    'width': data['width'],
    'height': data['height']
  };
}

bool levelCaptureAllowed(
        {required double? pitch,
        required DateTime? sampledAt,
        required DateTime now,
        required bool stable}) =>
    pitch != null &&
    pitch.isFinite &&
    pitch.abs() <= 5 &&
    stable &&
    sampledAt != null &&
    !sampledAt.isAfter(now) &&
    now.difference(sampledAt) <= const Duration(milliseconds: 600);

bool photoMeasurementAccepted(Map<String, dynamic>? result,
    {required bool baseConfirmed}) {
  if (result == null ||
      result['status'] != 'ok' ||
      result['method'] != 'yolo_trunk_v1' ||
      result['fallback'] == true ||
      result['error'] == true ||
      result['quality'] != 'experimental') {
    return false;
  }
  final dbh = result['dbh_cm'];
  final distance = result['distance_m_used'];
  return dbh is num &&
      dbh.isFinite &&
      dbh > 0 &&
      distance is num &&
      distance.isFinite &&
      distance > 0 &&
      (result['needs_base_confirmation'] != true || baseConfirmed);
}

/// Tracks real sensor evidence across a shutter request. UI settling after the
/// shutter is not a second capture gate; missing/old/tilted evidence still fails.
class CaptureLevelGuard {
  DateTime _lastSample;
  bool _valid;
  final double minPitch, maxPitch;
  final double? maxChange;
  final double _startPitch;
  CaptureLevelGuard(
      {required double pitch,
      required DateTime sampledAt,
      required DateTime now,
      this.minPitch = -5,
      this.maxPitch = 5,
      this.maxChange})
      : _lastSample = sampledAt,
        _startPitch = pitch,
        _valid = captureAngleAllowed(
            pitch: pitch,
            sampledAt: sampledAt,
            now: now,
            stable: true,
            minPitch: minPitch,
            maxPitch: maxPitch);

  void observe(double pitch, DateTime at) {
    if (!pitch.isFinite ||
        pitch < minPitch ||
        pitch > maxPitch ||
        (maxChange != null && (pitch - _startPitch).abs() > maxChange!) ||
        at.isBefore(_lastSample) ||
        at.difference(_lastSample) > const Duration(milliseconds: 600)) {
      _valid = false;
    }
    _lastSample = at;
  }

  void interrupt() => _valid = false;
  bool validAt(DateTime now) =>
      _valid &&
      !now.isBefore(_lastSample) &&
      now.difference(_lastSample) <= const Duration(milliseconds: 600);
}

bool captureAngleAllowed(
        {required double? pitch,
        required DateTime? sampledAt,
        required DateTime now,
        required bool stable,
        double minPitch = 5,
        double maxPitch = 85}) =>
    pitch != null &&
    pitch.isFinite &&
    pitch >= minPitch &&
    pitch <= maxPitch &&
    stable &&
    sampledAt != null &&
    !sampledAt.isAfter(now) &&
    now.difference(sampledAt) <= const Duration(milliseconds: 600);

bool heightMeasurementAccepted(Map<String, dynamic>? result) {
  if (result == null ||
      result['status'] != 'ok' ||
      result['fallback'] == true ||
      result['method'] != 'tilt_distance' ||
      !['experimental', 'low'].contains(result['quality'])) {
    return false;
  }
  final height = result['height_m'],
      pitch = result['theta_top_deg'],
      distance = result['distance_m'];
  return height is num &&
      height.isFinite &&
      height > 0 &&
      pitch is num &&
      pitch.isFinite &&
      pitch >= 5 &&
      pitch <= 85 &&
      distance is num &&
      distance.isFinite &&
      distance > 0;
}
