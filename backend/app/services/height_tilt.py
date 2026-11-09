"""Experimental center-crosshair height; no image analysis or AI calls.

Assumptions: flat ground, correct saved camera height, accepted DBH distance,
same standing position and lens height for both captures, and crosshair aimed
at the true highest point. Ordinary motion sensors cannot verify translation.
Validate against a clinometer; inherited DBH distance errors affect height.
"""
import math

NOTE = "Experimental estimate; validate height against a clinometer and DBH against tape."


def measure_height(pitch_deg=None, camera_height_m=1.4, distance_m=None,
                   dbh_status="retake", base_confirmed=False):
    def retake(reason):
        return dict(status="retake", height_m=None, theta_top_deg=None,
                    distance_m=None, quality="low", reason=reason,
                    method="tilt_distance", fallback=False, accuracy_note=NOTE)

    if dbh_status != "ok" or base_confirmed is not True:
        return retake("Capture and confirm a valid DBH measurement first.")
    def valid(value):
        return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)
    if not valid(pitch_deg):
        return retake("Phone angle missing. Aim at the top and retake.")
    if not 5 <= pitch_deg <= 85:
        return retake("Aim upward at the treetop between 5 and 85 degrees.")
    if not valid(distance_m) or distance_m <= 0:
        return retake("Distance missing. Restart with a trunk capture.")
    if not valid(camera_height_m) or camera_height_m <= 0:
        return retake("Camera height is invalid. Check the saved setting.")
    height = distance_m * math.tan(math.radians(pitch_deg)) + camera_height_m
    if not math.isfinite(height) or height <= 0:
        return retake("Height could not be calculated. Retake.")
    if not math.isfinite(height * 2):
        return retake("Height could not be calculated. Retake.")
    height = math.floor(height * 2 + 0.5) / 2
    if height <= 0:
        return retake("Height could not be calculated. Retake.")
    return dict(status="ok", height_m=height, theta_top_deg=float(pitch_deg),
                distance_m=float(distance_m), quality="low" if pitch_deg > 70 else "experimental",
                reason="Steep angle; estimate is especially sensitive to angle and distance error." if pitch_deg > 70 else "",
                method="tilt_distance", fallback=False, accuracy_note=NOTE)
