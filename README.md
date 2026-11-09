# 🌿 TreeTrace — Panabo City Geo-Spatial Tree Inventory

A full-stack system for managing and exploring urban forest inventory.

## Project Structure

```
treetrace-web-flutter/
├── backend/          ← FastAPI (Python 3.11+)
├── frontend/         ← React 18 + Vite + Tailwind (Web)
└── mobile/           ← Flutter (Android + iOS + Web)
```

## Tech Stack

| Layer     | Technology                              |
|-----------|-----------------------------------------|
| Backend   | FastAPI (Python 3.11+)                  |
| Database  | MySQL 8 via SQLAlchemy ORM              |
| Auth      | JWT (python-jose + passlib/bcrypt)      |
| Storage   | Supabase (photos + QR only)             |
| Frontend  | React 18 + Vite + Tailwind CSS          |
| Mobile    | Flutter (consumes same REST API)        |
| AI        | Gemini API + Pl@ntNet + Claude Vision   |
| Email     | Gmail SMTP via smtplib                  |

---

## 🚀 Running the Backend

```bash
cd backend
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Backend runs at: `http://localhost:8000`

---

## 🌐 Running the Web Frontend

```bash
cd frontend
npm install
npm run dev
```

Web runs at: `http://localhost:5173`

---

## 📱 Running the Flutter Mobile App

```bash
cd mobile
flutter pub get
flutter run
```

> For Android emulator: API URL is already set to `http://10.0.2.2:8000/api`
> For real device on same WiFi: change `kBaseUrl` in `lib/services/api_service.dart` to your PC's IP, e.g. `http://192.168.1.x:8000/api`

---

## 👥 User Roles

| Role         | Access                                          |
|--------------|-------------------------------------------------|
| Admin        | Full system — users, trees, reports, QR gen     |
| Field Worker | Add trees, health logs, AI identification       |
| Citizen      | Public portal, map, QR scan, 3 AI scans/day     |

---

## Environment Setup

Copy `backend/.env.example` to `backend/.env` and fill in:

```env
SECRET_KEY=your-secret-key
DATABASE_URL=mysql+pymysql://root:@localhost:3306/treetracecp
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-key
GMAIL_USER=your@gmail.com
GMAIL_APP_PASSWORD=your-app-password
GEMINI_API_KEY=your-gemini-key
PLANTNET_API_KEY=your-plantnet-key
ANTHROPIC_API_KEY=your-anthropic-key
FRONTEND_URL=http://localhost:5173
```

---

## 📲 Features

### Web (React)
- 🗺️ Interactive tree map (OpenStreetMap)
- 🤖 AI species identification (Pl@ntNet + Claude)
- 📊 Community structure & biodiversity analytics
- 📱 QR code generation for each tree
- 🌿 Public tree encyclopedia (PictureThis-style)
- 👥 User management with email invites
- 📋 Health log tracking

### Mobile (Flutter)
- 📱 Native Android & iOS app
- 📷 Camera-based AI tree identification
- 🔍 QR code scanner
- 🗺️ Interactive map with tree markers
- 🌿 Public portal for citizen users
- 🔐 Role-based access (Admin / Field Worker / Citizen)

---

Made with 💚 for Panabo City


## Experimental photo DBH - Phase 1

This is an **experimental estimate**, not a validated measuring instrument.
Validate DBH against a tape measurement at 1.3 m and height against a clinometer.
Phase 1 returns no height. No field accuracy is established by synthetic tests.

### Assumptions and inputs

- Rear-camera DBH shot is level: absolute pitch at most 5 degrees; missing pitch
  returns `retake`. These formulas approximate the accepted shot as level.
- Ground is flat; true trunk-ground contact is visible; camera height is correct
  (default 1.4 m); the trunk is roughly round.
- Send original bytes with EXIF intact: do not resize, strip EXIF or recompress.
  EXIF orientation is applied in memory without rescaling the original geometry.
- Focal length in pixels is supplied as `f_px`, or derived from EXIF 0xA405
  (35 mm equivalent, including the nested Exif IFD):
  `f_px = f35 * hypot(width, height) / 43.267`. No focal-length guess is used.
- Optional `distance_m` must be distance to the trunk **surface for this shot**,
  labelled `distance_source="sensor"` or `"ar"`. Do not pass an unrelated scene
  median or stale camera position as a verified trunk distance.
- Otherwise, use the lowest trunk-mask row to derive camera-height scale. The
  green preview line MUST be confirmed by the operator before acceptance: a
  mask bottom does not prove that the ground contact is visible.

### Contract and algorithm

Authenticated JSON `POST /api/ai/measure-dbh` and multipart
`POST /api/ai/measure-dbh-file` accept optional `camera_height_m`, `pitch_deg`,
`distance_m`, `distance_source`, and `f_px`. Existing legacy fields remain intact.
New request fields are defined in `backend/app/schemas/dbh.py`.

The cached v1 model predicts at 640 px with confidence 0.4. Masks are restored to
original upright dimensions; the largest trunk is selected. The measurement
uses median contiguous-run width over the 17-row band at 1.3 m. Disconnected
pixels are not bridged. Diameter is calculated as:

`dbh_cm = width_px * distance_m / (f_px - width_px / 2) * 100 * CALIB`

`CALIB` defaults to 1.0. Side clipping, a hidden/bottom-clipped base, too few usable
rows, width below 40 px, invalid/missing focal information, invalid scale and
non-finite results cause `retake`. All measurement/scale numbers are null on
failure. Preview PNGs are returned as base64 in memory: mask red, 1.3 m line
yellow, base line green. No photo is logged or written by the service.

Successful photo results use method `yolo_trunk_v1`, `height_m=null`, and
`quality="experimental"`. `needs_base_confirmation=true` marks a provisional
base-scaled estimate; it must not be accepted until the green line is confirmed.
The new mobile confirmation UI belongs to Phase 2 and is not included here.

Photo `ok` or `retake` returns immediately without legacy YOLO or Gemini.
Disabled/unavailable v1 retains the previous legacy path. The old 25 cm / 8 m
service-error fallback remains separately flagged `fallback=true`; it is not a
measurement and must never be accepted by the new measured flow.

### Existing AR service preserved

Before replacement, `git status` reported `dbh_yolo.py` as untracked and `git log`
contained no commit for it. It was introduced during the earlier assistant work,
not sourced from a committed upstream version. Its exact original bytes are in
`backend/app/services/dbh_yolo_ar_backup.py` (SHA-256
`3876cf612604b81aafefd313af88d63523b053b649dea796e9c847c28e6d4c0a`).

The old service segments the trunk, filters metric depth near 1.3 m, fits a
circular cross-section, and returns DBH plus a camera-distance diagnostic, not
height. The AR status/measurement routes and their mobile callers continue to
use the preserved implementation. The mobile unified AR flow separately has a
local height calculation. No AR workflow, mobile capture or web UI is changed
in Phase 1. Accepting a supplied `ar` distance in the new service does not add a
new AR distance reader or establish that the old diagnostic is surface distance.

### Offline validation

Use `backend/tests/dbh_check.py` with `tests/tape.csv`. The CSV is header-only:
real tape/clinometer measurements have not been supplied. Required columns are
`file,tape_dbh_cm,camera_height_m,pitch_deg,distance_m,clinometer_height_m,split`.
Use `calib` or `eval` for split; image paths are relative to the CSV location.
Optional metadata columns are `base_confirmed`, `expected_status`, `case` and
`distance_source`. These record human decisions and rejection evidence, not
invented measurements. A supplied CSV distance without an explicit source is
labelled sensor; do not label it AR unless its origin is actually AR.

For base-derived scale, set `base_confirmed=true` only after independently
checking the green line; false means retake, and blank means pending confirmation.
Retake/unavailable/unconfirmed results are excluded from error calculation but
reported with reasons. Percent error is `abs(prediction-tape)/tape*100`.

Suggested calibration is `mean(tape/uncalibrated_prediction)` from accepted
**calib rows only**. The checker applies that factor to eval predictions, or an
explicit `--calib` override. It never edits the service constant automatically.
Without calib data it uses the configured constant. Rejection counts, eval
coverage and missing required cases are reported alongside accepted errors.

```powershell
python backend/tests/dbh_check.py tests/tape.csv
python backend/tests/dbh_check.py tests/tape.csv --calib 1.0
```

Include near and far shots, tilted phones, hidden bases and clipped trunks.
Use `case` labels `near`, `far`, `tilted`, `hidden_base`, `clipped_trunk` and
`expected_status=retake` on rejection examples. Occluded bases that resemble
valid mask bottoms need human rejection; mask geometry cannot establish that
semantic fact. A suggested calibration or a low error after dropping difficult
samples is not an accuracy demonstration. Report rejection rates as well.

### Production prerequisites - documentation only

The deployed build currently installs only `requirements.txt`. Before enabling:
install `backend/requirements-yolo.txt` (including its PyTorch dependency), supply
`backend/models/tree_trunk_dbh_v1.pt`, retain Pillow, and set
`DBH_TRUNK_ENABLED=true` in the server environment. The default is false.
Check RAM, cold start and request limits on the intended host before enabling.
Each process caches weights; using both preserved AR and photo services may hold
two model instances. Neither model file is overwritten, including
`tree_trunk_segmentation.pt`. No deployment files or credentials were changed.

Future phases require separate approval. Phase 2 adds a separate level-guided
camera option and preserves AR. Phase 3 uses a second, same-position crosshair
capture and sensor pitch (no image analysis or treetop tap), with height rounded
to 0.5 m. Phase 4 provides no web height without a tilt sensor. AR-distance
research remains documentation only.


### Run the four previously excluded async/HTTP tests locally

Run these PowerShell commands from the repository root. Tests use SQLite and
mocked inference; no running backend, real API keys or external requests are
needed. Run on a normal local Python environment where asyncio/TestClient can
create their local event-loop sockets.

```powershell
$env:TESTING = "true"
$env:DATABASE_URL = "sqlite://"
$env:PYTHONPATH = Join-Path (Get-Location) "backend"
python -m pytest -v "backend/tests/test_dbh_ar.py::test_ar_never_calls_old_yolo_or_gemini" "backend/tests/test_dbh_ar.py::test_ar_endpoint_auth_and_retakes" "backend/tests/test_dbh_ar.py::test_legacy_endpoints_pass_through_retakes[measure-dbh-False]" "backend/tests/test_dbh_ar.py::test_legacy_endpoints_pass_through_retakes[measure-dbh-file-True]"
```

These are exactly four cases: one coroutine test, one AR endpoint test, and the
JSON and multipart parameterizations of the legacy endpoint test. This command
also runs exactly those four cases using a name filter:

```powershell
python -m pytest backend/tests/test_dbh_ar.py -v -k "test_ar_never_calls_old_yolo_or_gemini or test_ar_endpoint_auth_and_retakes or test_legacy_endpoints_pass_through_retakes"
```

### Run a real original photo through the local model

After the dependencies and v1 weights are available locally, run from the
repository root (replace the example photo path):

```powershell
$env:DBH_TRUNK_ENABLED = "true"
python backend/tests/run_photo.py "C:\tree-photos\tree.jpg" --camera-height 1.4 --pitch 0
```

With a separately measured trunk-surface distance:

```powershell
python backend/tests/run_photo.py "C:\tree-photos\tree.jpg" --camera-height 1.4 --pitch 0 --distance 2.5
```

Use the actual capture pitch and camera height; do not supply zero pitch merely
to bypass the level check. The default camera height is 1.4 m. Distance is in
metres and is labelled sensor; the script does not read a distance sensor itself.
The photo's original bytes and EXIF are passed unchanged to the service. Missing
focal metadata, invalid geometry or tilt can produce retake with null numbers.
A disabled/missing model produces unavailable; this CLI never invokes legacy AI.

The JSON includes the full service result and `preview_file`. A successful
preview is saved next to the original as `tree.dbh-preview.png`; repeated runs
use numbered names without overwriting the original or earlier previews.
Retake/unavailable produces no preview. A preview write failure is reported in
JSON as `preview_error` and exits with status 1. Base-scaled results still need
human confirmation of the green line before acceptance. Every result remains an
experimental estimate requiring tape DBH/clinometer validation. This CLI has
not by itself established model accuracy.


## Phase 2: separate level-guided photo capture

Add Tree > Add photo > Take Photo now opens one rear-camera capture with a live
level indicator and one capture button. Measurement capture requires a fresh,
stable sensor reading with absolute pitch at most 5 degrees. The one-time camera
height setting defaults to 1.4 m and is adjustable with the settings slider;
there is no per-photo height prompt or typed distance. Capture settings are
persisted separately from authentication and inventory drafts.

The existing AR camera, method channel, depth calculation and height flow are
preserved. Open them through Add photo > Advanced (AR). The native AR activity,
AR service/backup and backend contracts are not modified in Phase 2.

### Focal scale and fixed-lens policy

The installed CameraX plugin (0.6.30) filters its camera selector using the exact
CameraDescription ID populated by availableCameras. The new screen chooses an
exposed rear main-camera candidate by largest active sensor area, explicitly
sets zoom to 1.0, locks portrait capture, and provides no pinch, zoom slider or
lens-switch controls. The Android bridge reads that ID's lens focal length and
sensor physical size, adjusted for the active/pixel array fraction. It reads the
saved JPEG dimensions and EXIF FocalLength without altering the photo.

Pixel focal lengths are lens_mm * saved_pixels / active_sensor_mm for each axis,
matching long and short axes after portrait rotation. More than 5 percent
disagreement between lens focal length and EXIF FocalLength causes retake, never
an assumed focal value. Inconsistent image/sensor aspect ratios, zoom metadata,
missing values and unlocked/ambiguous lens information also cause retake.

An Android logical multi-camera can internally switch physical lenses even when
the app holds its logical ID at 1x. This plugin does not expose a physical-ID lock
or per-shot active physical ID through the current API. The bridge therefore
REFUSES measurement for logical multi-cameras or multiple-focal configurations;
it does not claim that setting 1x alone prevents every hardware lens switch.
Skip measurement remains available. Camera selection, crop interpretation and
physical metadata still need validation on each supported phone.

The requested realme GT Master fixture uses 3468 x 4624 pixels, focal 4.73 mm and
explicit nominal sensor dimensions 6.47 x 4.85 mm. It computes 3381.32 px, within
3 percent of 3380 px. Those sensor dimensions are a TEST FIXTURE, not a production
per-device constant or a calibration verified from the user's handset. Production
always reads its own CameraCharacteristics. No f_px is guessed if reading fails.

### Original photos and result safety

The original camera file bytes and EXIF go unchanged through ApiService; there
is no resize, imageQuality conversion, rotation re-encode or photo logging in
this photo flow. Backend display orientation remains handled by Phase 1.
Camera permission, lifecycle changes, stale sensors and metadata errors prevent
measurement acceptance. A photo can still be used for species identification.

Responses are checked for status/method/quality/fallback BEFORE numeric parsing.
Only successful experimental yolo_trunk_v1 results can be accepted by this path;
retake, unavailable, low-quality approximate and legacy fallback results cannot.
The returned preview is decoded and displayed. A base-scaled result asks:
"Is the green line at the bottom of the tree?" with Yes and Retake.
The single Yes tap is required before using a measured number. Failed preview
decoding cannot bypass that confirmation. Species is filled automatically using
the existing AI identification endpoint; identification is still a suggestion.

Skip measurement on the camera captures a photo even without a valid level
reading and runs species identification without requesting DBH. The result
screen also provides an explicit skip-and-save action. Both dimensions and their
prediction metadata are cleared, rather than retaining stale previous numbers.
The final save passes through the existing Add Tree validation, idempotency,
authorization and offline review rules. A missing required species name or other
invalid form field still prevents saving; nothing is invented to bypass it.
There is no background or automatic inventory sync. The standalone DBH tool can
return without a measurement but cannot save a whole tree on its own.

All measurements remain EXPERIMENTAL estimates requiring comparison against
tape DBH and clinometer height. The default photo flow does not calculate height
in Phase 2. The optional same-position, upward crosshair height capture and its
backend endpoint remain Phase 3, requiring separate approval. It must not reuse
the DBH pitch or display a fabricated height meanwhile.

### iPhone behavior

This checkout has no iOS runner and no new iOS native code was built. The shared
metadata adapter has an EXIF-only fallback for a future iPhone build: it omits
f_px so the backend can use original EXIF FocalLengthIn35mmFilm. If that tag is
missing, measurement returns retake. EXIF FocalLength in mm alone is insufficient
without sensor dimensions. The Android-specific 5 percent cross-check and
physical-lens guarantee are not advertised as implemented on iPhone. Actual
AVFoundation capture and device behavior remain unverified.

### Phase 2 checks

Offline tests cover the focal fixture, invalid focal/lens/crop/zoom metadata,
freshness and level limits, retake/fallback gating, saved height settings,
original-byte upload, explicit skip clearing dimensions and the preserved AR
review. Run from mobile:

```powershell
flutter analyze
flutter test --no-pub test/level_dbh_capture_test.dart test/tree_scan_test.dart test/identify_upload_test.dart test/dbh_ar_test.dart
flutter devices
flutter run -d YOUR_PHONE_ID --flavor production
```

A full rebuild is required for MainActivity and CameraPhotoMetadata changes.
The SDK lock-file restriction in this agent session may prevent Flutter tests
or APK building; report that separately from static analysis or standalone
geometry checks. Field accuracy and live backend/provider operation are not
established by those checks. No deployment settings or dependencies were changed.


### Phase 2 capture regression fixes

The level-camera controller now stays alive through the result-route transition.
For backgrounding, the preview is removed for a frame before its controller is
released, and reopening waits for that release. Back is blocked during a shutter
request. The shutter uses the ready sensor snapshot and continues monitoring for
out-of-range tilt, sensor gaps and lifecycle interruptions; UI stability after
JPEG processing is not used as a second shutter gate. Stale or invalid sensor
evidence still returns retake, never a number.

Add Tree and AI Tree Scanner share safe identification error messages for session,
quota, payload size, unsupported image, missing route, timeout and server errors.
An optional local-history read/write failure no longer discards a successful AI
response. Leaving the AI scanner before a response arrives no longer triggers
setState on its disposed screen. Original photo bytes and the provider pipeline
are unchanged. These client fixes do not establish the cause of a remote provider
failure: check the displayed HTTP status and backend terminal after retrying.
Do not claim live identification or field accuracy from static checks alone.

Regression coverage is in `level_dbh_capture_test.dart`,
`identify_upload_test.dart`, `identification_error_test.dart` and
`ai_identify_badges_test.dart`. Run from mobile:

```powershell
flutter test --no-pub test/level_dbh_capture_test.dart test/identify_upload_test.dart test/identification_error_test.dart test/ai_identify_badges_test.dart
```

In the agent session, standalone Dart checks exercise the shutter guard and
identification error classifications. Full Flutter tests remain blocked by the
SDK cache lock-file permission. Live camera transitions and provider responses
must still be checked on the phone. Advanced AR and height phases are unchanged.


### HTTP 413 photo upload fix (Phase 2)

Species identification uses an in-memory derivative only when the original is
larger than 1,500,000 bytes. It scales that species-only copy until the encoded
PNG fits the budget. The original file is never overwritten, logged or used as
a resized measurement input. Both Add Tree and AI Tree Scanner use this shared
path. Small original species images are sent unchanged. This changes the earlier
Phase 2 species-upload behavior; original bytes remain mandatory for DBH.

The new mobile DBH path sends original bytes/EXIF with capture metadata to
`/api/ai/measure-dbh-file` as multipart instead of base64 JSON, avoiding base64
body expansion. Its strict `method=yolo_trunk_v1` invokes only the new trunk
model: missing/disabled runtime returns unavailable, not old YOLO/Gemini or
placeholder numbers. The red/yellow/green preview is display-only and bounded
to 1024 pixels on its longest side; calculations still use original dimensions.

Multipart does not remove an upstream host's body-size limit. Originals above
that limit require a backend that accepts full-size uploads. The client reports
that HTTP 413 explicitly, and reports the model's unavailable reason. A hot
restart updates Dart but cannot deploy backend Python changes or install YOLO.
No deployment files, API keys, storage uploads or AR workflow were changed.

For local full-original testing, open a PowerShell terminal in `backend`:

```powershell
$env:DBH_TRUNK_ENABLED = "true"
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Keep that terminal running. Use the existing documented local API build override
(`TREETRACE_API_BASE_URL`, pointing at that computer's LAN IP and `/api`) when
launching Flutter on the same Wi-Fi. A build without the override still uses the
hosted backend. Normal authentication still applies. The model file and
`requirements-yolo.txt` dependencies must exist on the backend actually used.

Gallery photos identify species but do not inherit DBH/height guesses from a
species response. Missing capture pitch/distance cannot become measured values.
Height capture remains separately approved Phase 3; no height is fabricated.
Backend validation: `python -m pytest tests/test_dbh_photo.py -q` passed 56 tests,
including strict multipart routing and bounded-preview checks. Flutter image
codec/upload regression tests were added; running them in the agent environment
remains blocked by SDK cache permissions. This is not field-accuracy evidence.


## Phase 3: two captures in the same camera session

The default camera now keeps the same main lens at 1x through both stages.
The first original photo starts existing species identification and strict DBH
processing. A camera-height-based DBH still requires the single green-line Yes
confirmation. Only accepted/confirmed DBH enables the second stage: a center
crosshair aimed at the highest point, with Capture height and Skip height.
There is no treetop tap, manual distance entry, crown model or Gemini height.

The second shutter uses fresh, stable portrait-motion-sensor pitch in 5..85 deg.
It blocks invalid angles and rejects sensor gaps, capture motion beyond 1.5 deg,
and lifecycle interruptions. Its image is not analyzed or uploaded; the temporary
second capture is removed from plugin cache. The original first photo remains the
inventory/species photo. Species processing can finish while the user aims up.
Late identification results from an older trunk photo cannot overwrite a newer
capture. Retaking the trunk clears all pending measurement state.

Authenticated `POST /api/ai/measure-height` accepts only pitch_deg,
camera_height_m, distance_m (from distance_m_used on the accepted DBH response),
dbh_status and base_confirmed. It calculates:

    height_m = distance_m * tan(radians(pitch_deg)) + camera_height_m

The result is rounded to the nearest 0.5 m. Angles above 70 deg are labelled low
quality; other successful results are experimental. Missing/invalid inputs,
rejected DBH or missing confirmation return retake with null height/angle/distance.
The client checks status/method/quality before numeric parsing. Retakes never fill
a height. Skip height preserves species and accepted DBH; Skip measurement clears
both dimensions. Combined review retains height quality metadata in TreeScanResult.

Assumptions remain flat ground, correct saved camera height, a roughly round trunk
with visible ground contact for DBH, and original DBH EXIF kept intact. Both shots
must use the SAME standing position and lens height; only tilt the phone. Ordinary
accelerometers cannot reliably detect a step or verify translation. The camera
therefore instructs the user to stay put and offers 'I moved - restart trunk
capture'. Backgrounding interrupts height eligibility; retry from the trunk or
skip height. No AR translation-tracking claim is made. Existing Advanced AR,
legacy manual height screens, DBH calibration and deployment files are unchanged.

All heights are experimental estimates requiring clinometer validation. DBH still
requires tape validation. The observed 16.6 cm vs approximately 11.8 cm tape-derived
DBH discrepancy is NOT corrected in this phase, and its distance/camera-height
uncertainty also affects height. Two captures do not establish measurement accuracy.

Verification commands:

```powershell
# backend
python -m pytest tests/test_height_tilt.py tests/test_dbh_photo.py -q
# mobile
flutter analyze
flutter test --no-pub test/two_capture_session_test.dart test/level_dbh_capture_test.dart test/tree_scan_test.dart
```

Backend checks passed 80 tests. They cover formula/rounding, angle boundaries,
steep-angle quality, null failures, strict input types and authenticated routing,
plus the existing DBH suite. Mobile regression tests fake the camera and sensors
for second capture, base confirmation, skip, retake and interrupted sessions.
Static analysis and standalone sensor checks are reported separately; full
Flutter test execution remains blocked by the SDK cache lock-file permissions in
the agent environment. Live camera transitions and field accuracy remain unverified.

For phone testing, restart the local backend to load the new endpoint (the existing
uvicorn command without --reload does not reload source changes), then hot restart
Flutter with Shift+R while keeping the existing local API build override. Capture
the trunk, confirm the base, stay in place and capture the treetop or skip height.
Review both results together. This phase adds no iOS native code or web height flow.


## Online Phase 1: Vercel CPU model packaging

APK building and large-photo upload changes are paused. This phase prepares the
model/runtime and configuration diagnostics only. It does not claim a successful
Vercel deployment or remove the 4.5 MB function-body limit.

### Packaged assets and dependencies

The existing, unmodified `backend/models/tree_trunk_dbh_v1.pt` is now explicitly
allowlisted in Git and included in the function configuration. It must be included
in the eventual commit/push; changing .gitignore alone does not upload the file.
The old `tree_trunk_segmentation.pt` is not overwritten. The reviewed new file is
54,846,172 bytes with SHA-256:

    23833b4a12ba8175275a132c3c4dde87c90d2d3bedb127a49ee1dfce49793962

`requirements.txt` now lists the CPU/headless dependencies directly, because Vercel installs
only the default requirements file. The deployment profile pins CPU-only Torch
2.12.0+cpu and torchvision 0.27.0+cpu from the official PyTorch CPU index. It uses
the official `ultralytics-opencv-headless==8.3.243` distribution, which exports the
same `ultralytics` module, with headless OpenCV 4.10.0.84 and NumPy 1.26.4. This
replaces the old 8.3.40 wrapper in the deployment profile; the trained model bytes
and DBH calibration are unchanged. Install into a clean environment: do not mix
standard ultralytics/opencv-python with their headless distributions. CPU PyTorch
wheels exist for the project's Python 3.12 Linux target. Keep `.python-version`
at 3.12 when using this profile; the legacy runtime.txt is not the version source
for this modern configuration.

The current Vercel configuration uses the FastAPI preset and `functions` for
`app/main.py`, replacing deprecated `builds` so packaging/runtime limits can be
configured in one place. Routing remains to the same app/main.py entrypoint.
It sets Fluid compute, a 2,048 MB function memory target and 300-second maximum,
includes the new model and excludes test/scratch/environment files. YOLO and
Matplotlib configuration writes use /tmp; prediction continues to use CPU and
save=False. There are no new photo logs, API keys or photo-network operations.
No global or GPU package installation is performed by this phase's code edits.

### Required dashboard steps before deployment testing

Keep the Vercel project Root Directory as `backend`. For the environment actually
being tested (Preview or Production), set these non-secret project variables:

- `DBH_TRUNK_ENABLED=true` (new model; ENABLE_YOLO_DBH is the legacy model flag).
- `VERCEL_SUPPORT_LARGE_FUNCTIONS=1` for an existing project's larger-function
  opt-in, if enabled for the account. Confirm Fluid compute/Active CPU settings.
- Optionally `VERCEL_ANALYZE_BUILD_OUTPUT=1` to inspect actual function sizes.

Then redeploy without stale dependency caches. The Python normal bundle limit is
500 MB uncompressed; Vercel documents a 5 GB large-functions beta. The CPU Torch
package alone measured about 496 MiB on this Windows installation, so do not assume
the complete Linux deployment fits the normal limit. Dashboard/account eligibility
and the actual built bundle must be checked; this repository cannot prove either.
A configured 2 GB target is not proof of sufficient memory for full-resolution
images, concurrent scans, startup imports and database code.

A Preview deployment marked Ready does not prove that the APK's stable Production
URL serves the same commit. Verify the actual URL/version before building the APK.
No dashboard settings, branch promotion, commit, push or live deployment are
performed automatically in this phase. Existing secret values stay in Vercel;
never paste them into source code, screenshots or chat.

### New model status and offline probe

Authenticated `GET /api/ai/dbh-trunk-status` checks the new model's enabled flag,
file and dependency presence. It reports `configuration_ready`, the model filename,
CPU device and missing prerequisites. It deliberately returns
`inference_verified=false`, `check_type=configuration_only` and
`validated_accuracy=false`: a fast status request does not load weights or prove
successful inference. The existing /dbh-status still describes the legacy model.

Run the probe from backend in an isolated environment with adequate disk space:

```powershell
$env:DBH_TRUNK_ENABLED = "true"
python tests/check_dbh_runtime.py --self-test
```

The probe blocks networking, uses a synthetic 640x640 image without writing it,
checks the model task and exact single trunk class, reports package versions,
model checksum, elapsed cold import/inference time and sampled process peak RSS.
It cannot validate DBH/height accuracy or prove Linux/Vercel compatibility. Exit 2
means configuration/inference failed; exit 3 means the installed profile differs
from the declared deployment profile. JSON is still printed so a successful
local baseline is not confused with successful profile verification.

To measure an already-built function, add `--bundle-dir` pointing at its actual
`.vercel/output/functions/...func` directory. The tool measures real files and
flags bundles over 500 MiB; it does not invent a bundle-size estimate. The 20 ms
RSS sampling is a local lower-bound observation, not a concurrency/load test.

Observed local baseline: Windows Python 3.11.9, Torch 2.12.0+cpu, torchvision
0.27.0+cpu and the previously installed standard Ultralytics 8.3.40 loaded the
packaged segmentation model with exactly {0: trunk}. Synthetic cold probe time
was 56.819 seconds and sampled peak RSS was 614,285,312 bytes (about 586 MiB).
`deployment_profile_matches=false` and `vercel_verified=false` remained false.
The new headless distribution could not be fetched in the agent environment, so
the new clean deployment profile and actual Linux bundle are NOT yet verified.
Do not call online DBH ready or field validated based on this baseline.

Offline regression checks:

```powershell
python -m pytest tests/test_dbh_deployment.py tests/test_dbh_photo.py tests/test_height_tilt.py -q
```

### Sources and the next phase

- Vercel limits: https://vercel.com/docs/functions/limitations
- FastAPI entrypoint/preset: https://vercel.com/docs/frameworks/backend/fastapi
- Python CPU wheels: https://download.pytorch.org/whl/cpu/torch/
- Headless distribution: https://docs.ultralytics.com/quickstart/

The next separately approved phase will handle original photo uploads through
private, authenticated storage transfers without Vercel's 4.5 MB request body.
That transfer must preserve original bytes/EXIF, enforce ownership and size/type
limits, avoid arbitrary user-supplied fetch URLs, and clean up temporary objects.
It is not implemented here. Mobile, web, AR, height logic and APK outputs remain
unchanged. Even after a working model deployment, full-size outdoor photo scans
are not ready until the upload phase and a real deployed inference test pass.

### Vercel requirements parser correction

The first cloud build rejected the nested requirements include. Deployment dependencies are now listed directly in `backend/requirements.txt`, with official CPU wheel URLs for the pinned Python 3.12 / Linux x86_64 runtime. No nested includes or index directives are used there. Other local platforms must install `requirements-yolo.txt` explicitly. A successful cloud build and deployed inference check are still required.

## Original gallery photos and saved capture evidence

Add Tree > Choose from Gallery now opens the same species/DBH review, without
requesting resizing or JPEG quality changes from ImagePicker. Species analysis
may create its existing bounded derivative; DBH receives the selected original.

New level-guided captures save pitch, the camera height at capture time and
validated focal pixels (or the existing EXIF focal path) in local secure storage,
indexed by SHA-256 of the exact original bytes. This is capture evidence, not
photo logging: no image bytes, locations or calculated DBH/height are stored in
that index. The most recent 200 unique originals are retained. Storage failures
never block live measurement. Uninstalling/clearing app data, moving to another
phone, editing/recompressing an image, or OS picker conversion can lose the match.
There is no automatic export to the system gallery and no metadata sync/export;
this flow can restore evidence only when the same original is available locally.
Existing photos captured before this update cannot acquire historical readings.

For matching originals, gallery review automatically requests fresh DBH inference
using the historical readings, never today's camera height, lens or motion sensor.
Camera-height distance still requires one Yes/Retake base confirmation; retakes,
legacy fallbacks and missing evidence cannot fill or accept measured DBH. Unknown
photos still identify species and offer Skip measurement with null DBH/height.
Height observations are not restored from this index; gallery height stays empty.

Assumptions remain: level DBH shot (absolute pitch <= 5 degrees), flat ground,
visible trunk/soil contact, correct camera height, roughly round trunk and intact
original EXIF. Every result is an experimental estimate requiring validation
against tape for DBH and a clinometer for height. This does not establish accuracy
for arbitrary gallery images or bypass Vercel's original-upload size limit.

Validation commands (mobile directory):

```powershell
flutter test test/photo_capture_metadata_store_test.dart test/gallery_tree_scan_test.dart test/two_capture_session_test.dart test/tree_scan_test.dart
flutter analyze
```

## Gallery-only AI-predicted size (unvalidated)

Select Gallery without matching historical capture readings now requests a
separate `POST /api/ai/gallery-size-prediction` prediction. The authenticated
endpoint consumes the existing AI quota, separately from species identification.
It accepts JPEG/PNG/WebP up to 2 MB; mobile sends a bounded, in-memory derivative
using the existing identification-photo helper. The selected original is never
overwritten. This derivative is NOT passed to metric DBH/height calculations.

The existing cached `tree_trunk_dbh_v1.pt` model first segments the largest trunk.
It must be enabled with `DBH_TRUNK_ENABLED=true` and available on the backend.
The red preview shows trunk detection only. Diagnostic width is in uploaded-image
pixels at the mask midpoint, NOT a known 1.3 m row or a measured DBH. Missing or
clipped trunks prevent the visual prediction request. The separately configured
existing Gemini connection sees the photo and target-trunk pixel bounds; it is
instructed to make a best-effort appearance-based prediction without requiring
reference objects, distance, sensor readings or EXIF. Visible trunk/crown features
and explicit uncertainty are required; hidden relevant parts still cause abstention.
No new model weights, credentials or deployment settings are introduced.

Responses contain `predicted_dbh_cm` / `predicted_height_m`, never measured
`dbh_cm` / `height_m`. Null is an expected outcome. Wrong types, non-finite,
nonpositive/out-of-range values, missing evidence/uncertainty and hidden base/top are rejected
rather than replaced or clamped to defaults. Returned values use whole-unit
rounding to avoid suggesting instrumental precision. The model's self-reported
visual evidence is NOT independently verified or a confidence/accuracy guarantee.
Predictions may be substantially wrong even if detection looks correct.

The mobile card reads **AI-predicted size** and **Unvalidated prediction; may be
inaccurate**. Predictions stay out of editable measurement fields, TreeScanResult,
tree create/update payloads, offline measurement queues and carbon calculations.
They are transient display-only results. Skip measurement still saves with null
measurements. A known original uses the existing strict measurement path instead;
a measured retake does not silently become an AI guess. Take Photo, Advanced AR,
base confirmation and the second tilted height capture are unchanged.

Every output is an experimental estimate requiring validation against tape DBH
and clinometer height. Gallery guesses do not assume a level phone, flat ground,
1.4 m camera height or intact EXIF when those facts are unknown. Those assumptions,
a roughly round trunk and visible soil contact still apply to the separate metric
photo measurement path. No photos or inference images are logged or saved by this
new backend service. No real provider calls are made by automated tests.

Validation (backend directory):

```powershell
python -m pytest tests/test_gallery_size_prediction.py tests/test_dbh_photo.py tests/test_height_tilt.py -q
```

Validation (mobile directory):

```powershell
flutter test --no-pub test/photo_capture_metadata_store_test.dart test/gallery_tree_scan_test.dart test/two_capture_session_test.dart test/tree_scan_test.dart
```

This endpoint must be deployed before the updated gallery card can produce
predictions. Passing mocked tests does not prove live inference or field accuracy.
The earlier original-photo HTTP 413 issue for metric captures remains separate.

### Gallery appearance predictions and provider diagnostics

Gallery prediction no longer requires or assumes dimensions of a tire, fence,
roof, door, person or other reference object. YOLO locates the target trunk and
provides diagnostic pixels. Gemini makes a best-effort visual prediction from
visible tree form and learned visual patterns. This is not a metric calibration;
absolute physical scale remains unknown and errors may be substantial. No actual
size, reference object, distance or measurement is manufactured by the backend.
Fixed species/maturity tables and numeric fallbacks are not used. Each returned
number requires photo-specific visual evidence and an uncertainty statement.

Gallery provider calls now request JSON and allow more output tokens. Parsing
combines non-thought text parts rather than assuming the first part is text.
Empty, blocked, truncated and malformed responses, missing credentials,
HTTP access/model/request errors, quota limits, connection failures and timeouts
return controlled error codes and plain-language reasons. No provider URLs,
API-key values, raw error bodies, thought text or images are exposed in diagnostics.
No retry is made for quota or credential errors. Existing species/model settings
and the camera measurement routes are not modified by these gallery-only changes.
The generic provider exception handler cannot establish why an older deployment
failed; the updated deployment must be tested with a real request to learn that.

Provider response fields: https://ai.google.dev/api/generate-content
JSON output: https://ai.google.dev/gemini-api/docs/structured-output

These changes do not validate assumed-reference accuracy. Compare experimental
DBH predictions against tape and height against a clinometer before field use.

### Per-metric gallery rejection reasons and response schema

Gallery AI requests now include a required response schema for both prediction
objects, their evidence/uncertainty/reason fields, and both visibility
flags. The prompt asks for actual observations rather than presenting a template
filled with null predictions and false flags. JSON mode alone did not enforce
that structure. This improves format consistency but cannot guarantee predictions.

The response now includes `dbh_reason_code`, `dbh_reason`, `height_reason_code`
and `height_reason`. The card displays the reasons separately. Reasons distinguish
physical obstacles (insufficient visible tree detail, hidden base/top, obscured DBH, uncertain
perspective, ambiguous target, AI abstention) from rejected output (missing metric,
missing visibility flag, invalid number, missing evidence or missing uncertainty). Unsupported or contradictory numbers stay null. A hidden top does
not suppress otherwise supported DBH; an invalid DBH does not suppress supported
height. Error/abstention reasons use controlled text rather than raw AI reasoning.

This is a response-contract and diagnostic correction, not field validation or
proof of the cause of a previous request. No photos are logged, no extra retry
calls are introduced, no measurements or carbon inputs are filled, and camera/AR
measurement geometry is unchanged. Appearance-based predictions remain
experimental: validate DBH against tape and height against a clinometer.

### Current Select Gallery behavior: no reference objects required

For an original without saved TreeTrace sensor readings, the provider schema now
requires only value, visible-tree evidence, uncertainty and reason_code for each
metric, plus base/top visibility flags. It no longer requests a reference object
or reference dimensions. Response `prediction_basis` is `visual_appearance`, and
`uncertainties` contains the statements shown on the card. Legacy `assumptions`
is retained as an empty list for response compatibility. The mobile card accepts
only the unvalidated appearance basis and cannot copy guesses into measurements.

Missing reference objects must not alone cause abstention. However, unsupported
predictions can remain null: no trunk detection, hidden base or breast-height
trunk, hidden/cropped treetop, ambiguous target, insufficient visual evidence,
malformed values, or missing evidence/uncertainty. DBH and height are evaluated
independently. Whole-unit outputs are model predictions, not verified sizes or
confidence intervals. Tomorrow's field test must compare to tape/clinometer;
passing mocked tests does not demonstrate prediction accuracy or live availability.
Take Photo, saved-original metric geometry, Advanced AR and carbon inputs remain
unchanged. No new credentials, photo logging, model files or deployment changes.

Gallery prediction: YOLO runs first. If it returns no mask, AI can assess one clearly identifiable main tree directly. The response identifies this as `ai_visual`, with no YOLO mask or pixel width. Ambiguous targets return no sizes. Predictions remain separate from measurements and carbon inputs. Disabled or failed trunk inference does not trigger the fallback.

Gallery trunk detection retries once on the lower two-thirds of the photo only when the full-image pass finds no mask. It keeps the model at 640 px and confidence 0.4, restores crop masks to original coordinates, and labels the detected portion. This retry is display-only and does not change Take Photo measurement geometry.

Gallery resilience: partial trunk masks remain visible even when diagnostic width is unavailable; AI evaluates DBH and height independently. Unreadable local capture history falls back to the gallery prediction path. Upload size, request quota, access, timeout and server failures have distinct mobile messages. These changes do not bypass measured-photo validation.


### Reviewed tree health

New trees and submissions default to **Not assessed**. Healthy/Fair/Poor remain explicit staff assessments; existing recorded statuses are not backfilled. Missing mobile values are displayed neutrally. Generic disease/treatment cards have been removed from scan and public profiles; the legacy `common_problems` response remains an empty list. This phase does not introduce a bark or symptom classifier.

Before deploying this feature against an existing PostgreSQL database, run `backend/migrations/0004_add_not_assessed_health.sql` and commit it. SQLAlchemy stores the enum member name `NotAssessed`; clients use `Not assessed`. The migration adds support without updating existing rows. Startup performs a read-only check and refuses an incompatible health schema rather than letting inventory writes fail later. Deploy the backend after the migration, then the clients. The migration has not been applied to the live database by this code change.

Verification: backend `python -m pytest tests/test_health_assessment_defaults.py tests/test_gallery_size_prediction.py tests/test_dbh_photo.py tests/test_height_tilt.py -q`; frontend `npm test -- src/components/trees/HealthAssessment.test.jsx src/pages/__tests__/treeReviews.test.jsx` and `npm run build`; mobile `flutter test --no-pub test/health_assessment_test.dart test/tree_reviews_test.dart test/tree_detail_offline_test.dart`.
