import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../services/camera_height_settings.dart';
import '../services/photo_capture_metadata_store.dart';
import '../services/camera_photo_metadata.dart';
import '../services/photo_measurement_rules.dart';
import '../services/tree_height_measurement.dart';
import '../services/identification_error.dart';

class LevelPhotoCapture {
  final File photo;
  final double? pitchDegrees;
  final double cameraHeightMeters;
  final double? focalPixels;
  final String? retakeReason;
  final bool skipMeasurement;
  final Map<String, dynamic>? dbhResponse, heightResponse;
  final bool baseConfirmed;
  const LevelPhotoCapture(
      {required this.photo,
      required this.cameraHeightMeters,
      this.pitchDegrees,
      this.focalPixels,
      this.retakeReason,
      this.skipMeasurement = false,
      this.dbhResponse,
      this.heightResponse,
      this.baseConfirmed = false});
}

class LevelDbhCameraScreen extends StatefulWidget {
  final Future<Map<String, dynamic>> Function(LevelPhotoCapture)?
      onMeasureTrunk;
  final Future<Map<String, dynamic>> Function(
          double pitch, double cameraHeight, double distance, bool confirmed)?
      onMeasureHeight;
  final Stream<AccelerometerEvent>? sensorEvents;
  final CameraHeightSettings settings;
  final PhotoCaptureMetadataStore metadataStore;
  const LevelDbhCameraScreen(
      {super.key,
      this.onMeasureTrunk,
      this.onMeasureHeight,
      this.sensorEvents,
      this.metadataStore = const PhotoCaptureMetadataStore(),
      this.settings = const CameraHeightSettings()});
  @override
  State<LevelDbhCameraScreen> createState() => _LevelDbhCameraScreenState();
}

enum _CaptureStage { trunk, confirmBase, height, retake }

class _LevelDbhCameraScreenState extends State<LevelDbhCameraScreen>
    with WidgetsBindingObserver {
  _CaptureStage _stage = _CaptureStage.trunk;
  LevelPhotoCapture? _first;
  Map<String, dynamic>? _dbhResponse, _heightResponse;
  Uint8List? _basePreview;
  bool _baseConfirmed = false, _sessionInterrupted = false;
  final _metadata = CameraPhotoMetadata();
  CameraHeightSettings get _settings => widget.settings;
  CameraController? _camera;
  StreamSubscription<AccelerometerEvent>? _sensor;
  Timer? _freshnessTimer;
  final _samples = <double>[];
  double? _pitch;
  DateTime? _sampledAt;
  bool _stable = false, _busy = false, _heightReady = false;
  bool _paused = false;
  double _cameraHeight = CameraHeightSettings.defaultMeters;
  String? _error;
  int _generation = 0;
  CaptureLevelGuard? _captureLevel;
  bool _returning = false;
  Future<void> _cameraDisposal = Future<void>.value();

  bool get _level =>
      !_paused &&
      _heightReady &&
      levelCaptureAllowed(
          pitch: _pitch,
          sampledAt: _sampledAt,
          now: DateTime.now(),
          stable: _stable);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
    _freshnessTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted &&
          !_returning &&
          _pitch != null &&
          _sampledAt != null &&
          DateTime.now().difference(_sampledAt!) >
              const Duration(milliseconds: 600)) {
        setState(() {
          _pitch = null;
          _stable = false;
          _samples.clear();
        });
      }
    });
    _sensor =
        (widget.sensorEvents ?? accelerometerEventStream()).listen((event) {
      if (!mounted || _paused || _returning) return;
      try {
        final pitch = phoneElevationDegrees(x: event.x, y: event.y, z: event.z);
        _captureLevel?.observe(pitch, DateTime.now());
        _samples.add(pitch);
        if (_samples.length > 6) _samples.removeAt(0);
        setState(() {
          _pitch = pitch;
          _sampledAt = DateTime.now();
          _stable = _samples.length >= 5 &&
              _samples.reduce(math.max) - _samples.reduce(math.min) <= 1.5;
        });
      } on FormatException {
        _captureLevel?.interrupt();
        _samples.clear();
        setState(() {
          _pitch = null;
          _stable = false;
        });
      }
    }, onError: (Object _) {
      _captureLevel?.interrupt();
      if (mounted) {
        setState(() {
          _pitch = null;
          _stable = false;
        });
      }
    });
  }

  Future<void> _open() async {
    final generation = ++_generation;
    CameraController? controller;
    try {
      await _cameraDisposal;
      if (!mounted || _paused || generation != _generation) return;
      var height = CameraHeightSettings.defaultMeters;
      var heightReady = false;
      try {
        height = await _settings.read();
        heightReady = true;
      } catch (_) {/* Skip remains available. */}
      final cameras = (await availableCameras())
          .where((c) => c.lensDirection == CameraLensDirection.back)
          .toList();
      if (cameras.isEmpty) throw StateError('Rear camera unavailable');
      CameraDescription selected;
      if (defaultTargetPlatform == TargetPlatform.android) {
        final candidates =
            await _metadata.cameras(cameras.map((c) => c.name).toList());
        if (candidates.isEmpty) {
          throw StateError('Main camera could not be established');
        }
        // Native metadata ranks exposed rear sensors by active physical area.
        // CameraX filters by this exact ID; never select the first rear lens blindly.
        selected = cameras.firstWhere((c) => c.name == candidates.first['id']);
      } else {
        selected = cameras.firstWhere((c) => c.lensType == CameraLensType.wide,
            orElse: () => cameras.first);
      }
      controller =
          CameraController(selected, ResolutionPreset.max, enableAudio: false);
      await controller.initialize();
      await controller.setZoomLevel(1.0);
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!mounted || generation != _generation) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _cameraHeight = height;
        _heightReady = heightReady;
        _error = _sessionInterrupted
            ? 'Session interrupted. Retake the trunk before measuring height.'
            : heightReady
                ? null
                : 'Saved camera height unavailable. Open settings or skip measurement.';
      });
    } catch (_) {
      await controller?.dispose();
      if (mounted && generation == _generation) {
        setState(() => _error =
            'Camera or saved settings unavailable. Allow camera access, then retry.');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _paused = true;
      _captureLevel?.interrupt();
      if (_first != null) _sessionInterrupted = true;
      ++_generation;
      _pitch = null;
      _stable = false;
      _samples.clear();
      final camera = _camera;
      // Remove CameraPreview before disposing its controller. Disposal while
      // that widget remains mounted can call buildPreview on a disposed camera.
      setState(() => _camera = null);
      if (camera != null) {
        _cameraDisposal = () async {
          await WidgetsBinding.instance.endOfFrame;
          await camera.dispose();
        }();
      }
    } else if (state == AppLifecycleState.resumed) {
      _paused = false;
      if (_camera == null && !_busy) _open();
    }
  }

  Future<void> _capture({bool skip = false}) async {
    final camera = _camera;
    if (_busy ||
        camera == null ||
        !camera.value.isInitialized ||
        (!skip && !_level) ||
        _stage != _CaptureStage.trunk) {
      return;
    }
    final pitch = _pitch;
    _captureLevel = skip
        ? null
        : CaptureLevelGuard(
            pitch: pitch!, sampledAt: _sampledAt!, now: DateTime.now());
    setState(() => _busy = true);
    try {
      // No imageQuality/maxWidth, ImagePicker, re-encoding, or EXIF edits.
      final shot = await camera.takePicture();
      // The shutter uses its validated sensor snapshot, not UI stability
      // recomputed after JPEG processing. Still reject tilt, gaps or interruption
      // observed during capture; never substitute a missing pitch.
      final moved = !skip && !(_captureLevel?.validAt(DateTime.now()) ?? false);
      _captureLevel = null;
      var metadata = <String, dynamic>{};
      if (!skip && !moved) {
        try {
          metadata = await _metadata.read(shot.path, camera.description.name);
        } catch (_) {
          metadata = {
            'status': 'retake',
            'reason':
                'Camera metadata unavailable. Rebuild the app or skip measurement.'
          };
        }
      }
      if (!mounted) return;
      final capture = LevelPhotoCapture(
          photo: File(shot.path),
          pitchDegrees: pitch,
          cameraHeightMeters: _cameraHeight,
          focalPixels: metadata['f_px'] is num
              ? (metadata['f_px'] as num).toDouble()
              : null,
          skipMeasurement: skip,
          retakeReason: moved
              ? 'Hold the phone level and still, then retake.'
              : !skip &&
                      metadata['status'] != 'ok' &&
                      metadata['status'] != 'exif'
                  ? metadata['reason']?.toString() ??
                      'Camera scale unavailable. Retake or skip measurement.'
                  : null);
      _first = capture;
      if (skip || widget.onMeasureTrunk == null) {
        _complete(skipAll: skip);
        return;
      }
      if (capture.retakeReason != null) {
        setState(() {
          _busy = false;
          _stage = _CaptureStage.retake;
          _error = capture.retakeReason;
        });
        return;
      }
      // Bind the checked sensor readings to original bytes for later gallery use.
      await widget.metadataStore.save(
          capture.photo,
          PhotoCaptureMetadata(
              pitchDegrees: capture.pitchDegrees!,
              cameraHeightMeters: capture.cameraHeightMeters,
              focalPixels: capture.focalPixels));
      if (!mounted) return;
      try {
        final result = await widget.onMeasureTrunk!(capture);
        if (!mounted) return;
        _dbhResponse = result;
        if (!photoMeasurementAccepted(result, baseConfirmed: true)) {
          setState(() {
            _busy = false;
            _stage = _CaptureStage.retake;
            _error = result['reason']?.toString() ??
                'No reliable DBH. Retake the trunk or skip measurement.';
          });
          return;
        }
        if (_sessionInterrupted) {
          setState(() {
            _busy = false;
            _stage = _CaptureStage.retake;
            _error = 'Session interrupted. Retake the trunk.';
          });
          return;
        }
        if (result['needs_base_confirmation'] == true) {
          final bytes = base64Decode(result['preview_png'] as String);
          final codec = await ui.instantiateImageCodec(bytes);
          try {
            final frame = await codec.getNextFrame();
            frame.image.dispose();
          } finally {
            codec.dispose();
          }
          if (!mounted) return;
          setState(() {
            _basePreview = bytes;
            _busy = false;
            _stage = _CaptureStage.confirmBase;
          });
        } else {
          setState(() {
            _baseConfirmed = true;
            _busy = false;
            _stage = _CaptureStage.height;
            _samples.clear();
            _stable = false;
          });
        }
      } catch (error) {
        if (mounted) {
          setState(() {
            _busy = false;
            _stage = _CaptureStage.retake;
            _error = _measurementError(error);
          });
        }
      }
    } catch (_) {
      _captureLevel = null;
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not capture. Please retry.';
        });
        if (!_paused && _camera == null) await _open();
      }
    }
  }

  String _measurementError(Object error, {bool height = false}) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 401) return identificationError(error);
      if (status == 413 && !height) {
        return 'The server rejected the original DBH photo (HTTP 413). Use a backend that accepts full-size originals.';
      }
      if (status == 404) {
        return '${height ? "Height" : "DBH"} service missing (HTTP 404). Restart the updated backend and retry.';
      }
      if (status != null) {
        return '${height ? "Height" : "DBH"} service returned HTTP $status. Retry or check the backend terminal.';
      }
      return 'Cannot reach the measurement backend. Check the connection and retry.';
    }
    return height
        ? 'Height could not be calculated. Retake height or skip.'
        : 'Could not read the DBH result or base preview. Retake or skip measurement.';
  }

  bool get _heightAllowed =>
      !_sessionInterrupted &&
      !_paused &&
      photoMeasurementAccepted(_dbhResponse, baseConfirmed: _baseConfirmed) &&
      captureAngleAllowed(
          pitch: _pitch,
          sampledAt: _sampledAt,
          now: DateTime.now(),
          stable: _stable);

  void _restartTrunk() {
    if (_busy) return;
    setState(() {
      _stage = _CaptureStage.trunk;
      _first = null;
      _dbhResponse = null;
      _heightResponse = null;
      _basePreview = null;
      _baseConfirmed = false;
      _sessionInterrupted = false;
      _error = null;
      _samples.clear();
      _stable = false;
    });
  }

  void _confirmBase() {
    if (_busy || _basePreview == null || _sessionInterrupted) return;
    setState(() {
      _baseConfirmed = true;
      _stage = _CaptureStage.height;
      _samples.clear();
      _stable = false;
      _error = null;
    });
  }

  void _complete({bool skipAll = false}) {
    final first = _first;
    if (first == null || !mounted) return;
    _returning = true;
    Navigator.pop(
        context,
        LevelPhotoCapture(
            photo: first.photo,
            pitchDegrees: first.pitchDegrees,
            cameraHeightMeters: first.cameraHeightMeters,
            focalPixels: first.focalPixels,
            retakeReason: first.retakeReason,
            skipMeasurement: skipAll || first.skipMeasurement,
            dbhResponse: skipAll ? null : _dbhResponse,
            heightResponse: skipAll ? null : _heightResponse,
            baseConfirmed: _baseConfirmed));
  }

  Future<void> _captureHeight() async {
    final camera = _camera;
    if (_busy ||
        camera == null ||
        !_heightAllowed ||
        widget.onMeasureHeight == null) {
      return;
    }
    final pitch = _pitch!;
    _captureLevel = CaptureLevelGuard(
        pitch: pitch,
        sampledAt: _sampledAt!,
        now: DateTime.now(),
        minPitch: 5,
        maxPitch: 85,
        maxChange: 1.5);
    setState(() {
      _busy = true;
      _error = null;
      _heightResponse = null;
    });
    try {
      // A real second shutter capture, but no image analysis/upload or photo log.
      final shot = await camera.takePicture();
      final valid = _captureLevel?.validAt(DateTime.now()) == true &&
          !_sessionInterrupted;
      _captureLevel = null;
      try {
        await File(shot.path).delete();
      } catch (_) {/* Plugin cache cleanup. */}
      if (!mounted) return;
      if (!valid) {
        setState(() {
          _busy = false;
          _error = 'Hold steady at the treetop and retake height.';
        });
        return;
      }
      final result = await widget.onMeasureHeight!(
          pitch,
          _first!.cameraHeightMeters,
          (_dbhResponse!['distance_m_used'] as num).toDouble(),
          _baseConfirmed);
      if (!mounted) return;
      if (_sessionInterrupted) {
        setState(() {
          _busy = false;
          _error = 'Session interrupted. Retake the trunk or skip height.';
        });
        return;
      }
      if (!heightMeasurementAccepted(result)) {
        setState(() {
          _busy = false;
          _error = result['reason']?.toString() ??
              'Height uncertain. Retake height.';
        });
        return;
      }
      _heightResponse = result;
      _complete();
    } catch (error) {
      _captureLevel = null;
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _measurementError(error, height: true);
        });
      }
    }
  }

  Future<void> _heightSetting() async {
    var height = _cameraHeight.clamp(0.5, 2.5).toDouble();
    final saved = await showDialog<double>(
        context: context,
        builder: (context) => StatefulBuilder(
              builder: (context, update) => AlertDialog(
                  title: const Text('Camera height above ground'),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text(
                        'Set once for the height at which you hold the camera. Keep this height for DBH photos.'),
                    Text('${height.toStringAsFixed(2)} m'),
                    Slider(
                        value: height,
                        min: 0.5,
                        max: 2.5,
                        divisions: 200,
                        onChanged: (value) => update(() => height = value)),
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel')),
                    ElevatedButton(
                        onPressed: () => Navigator.pop(context, height),
                        child: const Text('Save setting'))
                  ]),
            ));
    if (saved == null) return;
    try {
      await _settings.save(saved);
      if (mounted) {
        setState(() {
          _cameraHeight = saved;
          _heightReady = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Camera height could not be saved. Please retry.');
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    _freshnessTimer?.cancel();
    _sensor?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final heightStage = _stage == _CaptureStage.height;
    final ready = heightStage ? _heightAllowed : _level;
    return PopScope(
        canPop: !_busy,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
              title: Text(heightStage ? 'Capture tree height' : 'Capture tree'),
              actions: [
                IconButton(
                    onPressed: _busy || _first != null ? null : _heightSetting,
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'Saved camera height'),
              ]),
          body: SafeArea(
              child: Column(children: [
            Expanded(
                child: Stack(fit: StackFit.expand, children: [
              if (camera != null && camera.value.isInitialized)
                Center(child: CameraPreview(camera)),
              if (_stage == _CaptureStage.confirmBase && _basePreview != null)
                ColoredBox(
                    color: Colors.black,
                    child: Image.memory(_basePreview!, fit: BoxFit.contain)),
              Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Card(
                      color: Colors.black87,
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                              heightStage
                                  ? 'Stay in the same spot and keep the phone at the same height. Aim + at the highest point.'
                                  : _stage == _CaptureStage.confirmBase
                                      ? 'Is the green line at the bottom of the tree?'
                                      : 'Include the bottom of the trunk. Hold the phone level.',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 16))))),
              if (_stage == _CaptureStage.trunk || heightStage)
                IgnorePointer(
                    child: Center(
                        child: heightStage
                            ? const Text('+',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 48))
                            : Container(
                                width: 240,
                                height: 2,
                                color: ready
                                    ? Colors.greenAccent
                                    : Colors.amber))),
              if (_stage == _CaptureStage.trunk || heightStage)
                Positioned(
                    bottom: 16,
                    left: 12,
                    right: 12,
                    child: Text(
                        _pitch == null
                            ? 'Waiting for a sensor reading.'
                            : '${_pitch!.toStringAsFixed(1)} degrees - ${ready ? 'Ready' : heightStage ? 'Aim upward and hold steady (5–85 degrees)' : 'Hold the phone level and still'} - 1x',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: ready ? Colors.greenAccent : Colors.amber))),
            ])),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.amber))),
            if (camera == null)
              TextButton(
                  onPressed: _busy ? null : _open,
                  child: const Text('Retry camera')),
            if (_stage == _CaptureStage.confirmBase)
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                ElevatedButton(
                    onPressed:
                        _busy || _sessionInterrupted ? null : _confirmBase,
                    child: const Text('Yes')),
                TextButton(
                    onPressed: _busy ? null : _restartTrunk,
                    child: const Text('Retake')),
              ]),
            if (_stage == _CaptureStage.trunk || heightStage)
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: IconButton.filled(
                      key: Key(heightStage
                          ? 'capture-tree-height'
                          : 'capture-level-dbh'),
                      iconSize: 54,
                      tooltip: heightStage ? 'Capture height' : 'Capture tree',
                      onPressed: _busy || !ready || camera == null
                          ? null
                          : heightStage
                              ? _captureHeight
                              : () => _capture(),
                      icon: const Icon(Icons.camera_alt))),
            if (heightStage) ...[
              TextButton(
                  onPressed: _busy ? null : () => _complete(),
                  child: const Text('Skip height')),
              TextButton(
                  onPressed: _busy ? null : _restartTrunk,
                  child: const Text('I moved - restart trunk capture')),
            ] else ...[
              if (_stage == _CaptureStage.retake)
                TextButton(
                    onPressed: _busy ? null : _restartTrunk,
                    child: const Text('Retake trunk')),
              TextButton(
                  key: const Key('skip-camera-measurement'),
                  onPressed: _busy || (_first == null && camera == null)
                      ? null
                      : () => _first == null
                          ? _capture(skip: true)
                          : _complete(skipAll: true),
                  child: const Text('Skip measurement',
                      style: TextStyle(color: Colors.white))),
            ],
          ])),
        ));
  }
}
