"""Run experimental DBH on one original photo with the real local trunk model.

Requires DBH_TRUNK_ENABLED=true and installed local dependencies. Does not enable
the feature, install dependencies, call an API, or modify the source photograph.
Only the explicitly requested preview is saved. Validate DBH against tape and
height against a clinometer; this Phase 1 tool does not estimate height.
"""
import argparse
import base64
import contextlib
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.services.dbh_yolo import measure_dbh_trunk


def save_preview(photo, encoded):
    """Save beside the source without overwriting a photo or an earlier preview."""
    content = base64.b64decode(encoded, validate=True)
    if not content.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError("The returned preview is not a PNG")
    index = 1
    while True:
        suffix = "" if index == 1 else f"-{index}"
        target = photo.with_name(f"{photo.stem}.dbh-preview{suffix}.png")
        try:
            with target.open("xb") as stream:
                stream.write(content)
            return target
        except FileExistsError:
            index += 1


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("photo", type=Path, help="Original photograph with EXIF intact")
    parser.add_argument("--camera-height", type=float, default=1.4, metavar="METRES")
    parser.add_argument("--pitch", type=float, required=True, metavar="DEGREES")
    parser.add_argument("--distance", type=float, default=None, metavar="METRES",
                        help="Optional independently measured distance to the trunk surface")
    args = parser.parse_args(argv)
    photo = args.photo.resolve()
    try:
        original = photo.read_bytes()
    except OSError as exc:
        parser.error(f"Cannot read photo: {exc}")

    # Keep stdout machine-readable JSON even if a dependency emits startup text.
    with contextlib.redirect_stdout(sys.stderr):
        result = measure_dbh_trunk(
            original, camera_height_m=args.camera_height, pitch_deg=args.pitch,
            distance_m=args.distance,
            distance_source="sensor" if args.distance is not None else None,
        )
    result = dict(result)
    result["preview_file"] = None
    exit_code = 0
    if result.get("preview_png"):
        try:
            result["preview_file"] = str(save_preview(photo, result["preview_png"]))
        except (OSError, ValueError) as exc:
            result["preview_error"] = str(exc)
            exit_code = 1
    print(json.dumps(result, indent=2, allow_nan=False))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
