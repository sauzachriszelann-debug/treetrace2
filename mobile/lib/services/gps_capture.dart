// Phase 12A.1 — GPS reliability layer for tree registration.
//
// Everything in this file is either (a) a thin wrapper around Geolocator with
// injectable seams so tests can simulate timeouts, disabled services, denied
// permissions and mocked positions without any real location fix, or (b) a
// pure decision function used by the Add Tree screen when a NEW capture must
// be reconciled with coordinates/barangay already present in the form.
//
// No real location is ever requested or transmitted from tests: every seam
// defaults to the platform implementation only on a real device.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Accuracy grading (display + confirmation policy)
// ─────────────────────────────────────────────────────────────────────────────

/// A fix at or below this many meters is treated as good: no confirmation.
const double kGpsAccuracyGoodM = 15;

/// A fix worse (larger) than this many meters is poor: the user must confirm
/// before the position is placed into the registration form.
const double kGpsAccuracyPoorM = 50;

enum GpsAccuracyGrade { good, moderate, poor }

/// Classifies a reported horizontal accuracy (meters, smaller = better).
///
/// A missing or nonsensical accuracy is graded poor — never silently good —
/// so the confirmation path is shown instead of quietly trusting the fix.
GpsAccuracyGrade classifyGpsAccuracy(double? accuracyMeters) {
  if (accuracyMeters == null || !accuracyMeters.isFinite || accuracyMeters < 0) {
    return GpsAccuracyGrade.poor;
  }
  if (accuracyMeters <= kGpsAccuracyGoodM) return GpsAccuracyGrade.good;
  if (accuracyMeters <= kGpsAccuracyPoorM) return GpsAccuracyGrade.moderate;
  return GpsAccuracyGrade.poor;
}

String gpsAccuracyLabel(double? accuracyMeters) {
  if (accuracyMeters == null || !accuracyMeters.isFinite || accuracyMeters < 0) {
    return 'GPS accuracy: unknown';
  }
  return 'GPS accuracy: ±${accuracyMeters.round()} m';
}

// ─────────────────────────────────────────────────────────────────────────────
// Reverse-geocoding budget (Phase 12B.1A)
// ─────────────────────────────────────────────────────────────────────────────

/// Upper bound for one reverse-geocode lookup.
///
/// By the time this lookup runs, the captured coordinates are already in the
/// form. An address that cannot be resolved within the budget is dropped
/// (the lookup fails as a timeout) instead of holding the GPS loading state
/// — and the capture button — open indefinitely.
const Duration kGeocodeTimeout = Duration(seconds: 5);

// ─────────────────────────────────────────────────────────────────────────────
// Capture outcome
// ─────────────────────────────────────────────────────────────────────────────

enum GpsFailureKind {
  locationServicesDisabled,
  permissionDenied,
  permissionDeniedForever,
  timeout,
  positionUnavailable,
}

/// Honest, user-facing reason a capture produced no position.
String gpsFailureMessage(GpsFailureKind kind) {
  switch (kind) {
    case GpsFailureKind.locationServicesDisabled:
      return 'Location services are turned off.';
    case GpsFailureKind.permissionDenied:
      return 'Location permission was denied.';
    case GpsFailureKind.permissionDeniedForever:
      return 'Location permission is blocked. Enable it in the app settings.';
    case GpsFailureKind.timeout:
      return 'Timed out waiting for a GPS fix. Try again outdoors or with a clear view of the sky.';
    case GpsFailureKind.positionUnavailable:
      return 'No position is available right now.';
  }
}

class GpsCaptureOutcome {
  final Position? position;
  final GpsFailureKind? failure;

  const GpsCaptureOutcome.success(Position this.position) : failure = null;
  const GpsCaptureOutcome.failed(GpsFailureKind this.failure) : position = null;

  bool get success => position != null;
}

typedef GpsBoolCheck = Future<bool> Function();
typedef GpsPermissionCheck = Future<LocationPermission> Function();
typedef GpsPositionFetcher = Future<Position> Function(LocationSettings settings);

/// Wraps the Geolocator platform calls behind injectable seams.
///
/// The default constructor uses the real plugin (device only). Tests inject
/// fakes and never open a socket or a platform channel.
class GpsCaptureService {
  final GpsBoolCheck _servicesEnabled;
  final GpsPermissionCheck _checkPermission;
  final GpsPermissionCheck _requestPermission;
  final GpsPositionFetcher _fetchPosition;

  /// Time budget for a single fix. A cold start indoors can exceed this; the
  /// user gets a clear timeout instead of a spinner that never resolves.
  final Duration timeLimit;

  GpsCaptureService({
    GpsBoolCheck? servicesEnabled,
    GpsPermissionCheck? checkPermission,
    GpsPermissionCheck? requestPermission,
    GpsPositionFetcher? fetchPosition,
    this.timeLimit = const Duration(seconds: 20),
  })  : _servicesEnabled = servicesEnabled ?? Geolocator.isLocationServiceEnabled,
        _checkPermission = checkPermission ?? Geolocator.checkPermission,
        _requestPermission = requestPermission ?? Geolocator.requestPermission,
        _fetchPosition =
            fetchPosition ?? ((s) => Geolocator.getCurrentPosition(locationSettings: s));

  Future<GpsCaptureOutcome> capture() async {
    if (!await _servicesEnabled()) {
      return const GpsCaptureOutcome.failed(GpsFailureKind.locationServicesDisabled);
    }

    var permission = await _checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return const GpsCaptureOutcome.failed(GpsFailureKind.permissionDenied);
    }
    if (permission == LocationPermission.deniedForever) {
      return const GpsCaptureOutcome.failed(GpsFailureKind.permissionDeniedForever);
    }
    // whileInUse / always proceed; unableToDetermine is treated as proceed
    // (it only occurs where the platform cannot pre-decide, e.g. the web).

    try {
      final position = await _fetchPosition(LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: timeLimit,
      ));
      return GpsCaptureOutcome.success(position);
    } on TimeoutException {
      return const GpsCaptureOutcome.failed(GpsFailureKind.timeout);
    } catch (_) {
      return const GpsCaptureOutcome.failed(GpsFailureKind.positionUnavailable);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Coordinate validation — MUST stay consistent with the backend
// (backend/app/schemas/tree.py: finite; lat in [-90, 90]; lng in [-180, 180];
// an empty field means "no coordinate" and is allowed.)
// ─────────────────────────────────────────────────────────────────────────────

const String kCoordinateEmptyError =
    'Latitude must be a number between -90 and 90, or leave it empty.';
const String kLongitudeEmptyError =
    'Longitude must be a number between -180 and 180, or leave it empty.';

/// Parses a coordinate field. Returns the value, or null when the field is
/// empty (missing coordinate — allowed) — in which case [coordinateErrorText]
/// should be consulted to distinguish "empty" from "invalid".
double? tryParseCoordinate(String raw) => double.tryParse(raw.trim());

/// Backend-consistent validation for one coordinate field.
/// Returns an error message, or null when the input is valid (including empty).
String? coordinateErrorText(String raw, {required bool isLatitude}) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final value = double.tryParse(text);
  if (value == null || !value.isFinite) {
    return isLatitude ? kCoordinateEmptyError : kLongitudeEmptyError;
  }
  final limit = isLatitude ? 90.0 : 180.0;
  if (value < -limit || value > limit) {
    return isLatitude ? kCoordinateEmptyError : kLongitudeEmptyError;
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Recapture merge policies (pure)
// ─────────────────────────────────────────────────────────────────────────────

enum CoordinateMergeAction {
  /// The field is empty, already equal, or holds a value the app itself
  /// wrote: the new fix may be applied without asking.
  useNew,

  /// The field holds text the user typed or edited: replacing it requires
  /// explicit confirmation.
  needsConfirmation,
}

/// Decides whether a freshly captured coordinate may replace the field text.
///
/// [lastAutoText] is the exact text the app last wrote into the field for an
/// earlier automatic capture (null when the app never wrote it). When the
/// current text still equals that value, the app owns it and a recapture may
/// refresh it silently — this is the Phase 12A "refresh" fix. Anything else
/// is treated as user-entered data and is preserved unless confirmed.
CoordinateMergeAction coordinateMergeAction({
  required String currentText,
  required String? lastAutoText,
  required String newText,
}) {
  final current = currentText.trim();
  final next = newText.trim();
  if (current.isEmpty) return CoordinateMergeAction.useNew;
  final currentValue = double.tryParse(current);
  final nextValue = double.tryParse(next);
  if (currentValue != null &&
      nextValue != null &&
      currentValue.isFinite &&
      nextValue.isFinite &&
      (currentValue - nextValue).abs() < 5e-7) {
    return CoordinateMergeAction.useNew; // same fix, nothing to confirm
  }
  if (lastAutoText != null && current == lastAutoText.trim()) {
    return CoordinateMergeAction.useNew; // app-owned value: refresh freely
  }
  return CoordinateMergeAction.needsConfirmation;
}

enum BarangayMergeAction {
  /// Apply the new resolution (or clear an app-owned value that no longer
  /// matches the coordinates).
  useNew,

  /// Remove an app-written barangay: the new coordinates are outside every
  /// known barangay, so the old label must not survive.
  clear,

  /// Nothing to change (field empty with no resolution, values agree, or the
  /// user's own text has no contradicting resolution).
  keep,

  /// A user-confirmed barangay conflicts with the new resolution: the user
  /// decides which one stands.
  confirmWithUser,
}

/// Decides how a previously shown barangay reconciles with the resolution
/// for a NEW position.
///
/// The validity check for "still valid for the new coordinates" is the new
/// reverse-geocode resolution itself: if it names a different barangay, the
/// old label is not valid for the new point.
BarangayMergeAction barangayMergeAction({
  required String currentText,
  required String? lastAutoBarangay,
  required String? newResolvedBarangay,
}) {
  final current = currentText.trim();
  final resolved = newResolvedBarangay?.trim();

  if (current.isEmpty) {
    return resolved == null ? BarangayMergeAction.keep : BarangayMergeAction.useNew;
  }
  if (resolved != null && _sameBarangay(current, resolved)) {
    return BarangayMergeAction.keep;
  }
  final appOwned =
      lastAutoBarangay != null && _sameBarangay(current, lastAutoBarangay);
  if (appOwned) {
    // The app wrote this label for the OLD coordinates; it is not confirmed
    // data and must not survive a recapture that resolves differently (or
    // fails to resolve at all).
    return resolved == null
        ? BarangayMergeAction.clear
        : BarangayMergeAction.useNew;
  }
  // User-entered or user-edited label.
  if (resolved == null) return BarangayMergeAction.keep; // cannot contradict
  return BarangayMergeAction.confirmWithUser;
}

bool _sameBarangay(String a, String b) =>
    a.trim().toLowerCase() == b.trim().toLowerCase();

// ─────────────────────────────────────────────────────────────────────────────
// Panabo-area guard (pure)
// ─────────────────────────────────────────────────────────────────────────────

/// Generous bounding box around Panabo City, Davao del Norte. Coordinates
/// outside it must never receive a "Panabo City" / "Davao del Norte" /
/// "Brgy. …" default — an out-of-area or unresolvable position is reported
/// as missing location fields for the user to fill in.
bool isWithinPanaboArea(double lat, double lng) =>
    lat >= 7.10 && lat <= 7.45 && lng >= 125.55 && lng <= 125.80;

// ─────────────────────────────────────────────────────────────────────────────
// Confirmation dialogs (small, widget-testable, no I/O)
// ─────────────────────────────────────────────────────────────────────────────

/// True = use the low-accuracy fix; false = keep the existing form values.
Future<bool> showLowAccuracyConfirmation(
  BuildContext context,
  double? accuracyMeters,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Poor GPS accuracy'),
      content: Text(
        'The last GPS fix is imprecise (${gpsAccuracyLabel(accuracyMeters)}). '
        'A tree recorded far from its true position weakens the inventory.\n\n'
        'Use this fix anyway, try again with a clearer view of the sky, or '
        'cancel to keep the current form values.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Try again'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Use this fix'),
        ),
      ],
    ),
  );
  return result == true;
}

/// True = replace the manually entered coordinates with the new fix.
Future<bool> showCoordinateReplacementConfirmation(
  BuildContext context, {
  required String existing,
  required String replacement,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Replace entered coordinates?'),
      content: Text(
        'This form already contains coordinates you entered or confirmed:\n\n'
        'Current: $existing\n'
        'New GPS fix: $replacement\n\n'
        'Replace them with the new fix?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep current'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Replace'),
        ),
      ],
    ),
  );
  return result == true;
}

/// True = use the newly resolved barangay; false = keep the current one.
Future<bool> showBarangayReplacementConfirmation(
  BuildContext context, {
  required String existing,
  required String replacement,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Barangay mismatch'),
      content: Text(
        'The form is set to "$existing", but the new coordinates resolve to '
        '"$replacement".\n\nUse the newly resolved barangay?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Keep "$existing"'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('Use "$replacement"'),
        ),
      ],
    ),
  );
  return result == true;
}
