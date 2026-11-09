import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../services/tree_height_measurement.dart';

class GuidedTreeCapture {
  final File photo;
  final double? heightMeters;
  const GuidedTreeCapture(this.photo, {this.heightMeters});
}

/// Owns the Flutter camera only while this route is visible. The native AR
/// scanner runs on a separate route after this controller has been disposed.
class GuidedTreeCameraScreen extends StatefulWidget {
  final bool height;
  const GuidedTreeCameraScreen({super.key, this.height = false});
  @override
  State<GuidedTreeCameraScreen> createState() => _GuidedTreeCameraScreenState();
}

class _GuidedTreeCameraScreenState extends State<GuidedTreeCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  StreamSubscription<AccelerometerEvent>? _sensors;
  final _distance = TextEditingController();
  double? _angle;
  double? _base;
  String? _error;
  String? _angleError;
  bool _busy = false;
  int _generation = 0;
  DateTime? _lastSensor;
  final List<double> _samples = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
    if (widget.height) {
      _sensors = accelerometerEventStream().listen((event) {
        if (!mounted) return;
        try {
          final angle =
              phoneElevationDegrees(x: event.x, y: event.y, z: event.z);
          _samples.add(angle);
          if (_samples.length > 8) _samples.removeAt(0);
          final spread = _samples.reduce(math.max) - _samples.reduce(math.min);
          setState(() {
            _angle = _samples.length >= 5 && spread < 2 ? angle : null;
            _angleError =
                _angle == null ? 'Hold still to stabilize the angle' : null;
            _lastSensor = DateTime.now();
          });
        } on FormatException catch (e) {
          _samples.clear();
          setState(() {
            _angle = null;
            _angleError = e.message;
          });
        }
      }, onError: (Object _) {
        if (mounted) {
          setState(() {
            _angle = null;
            _angleError = 'Phone angle sensor unavailable';
          });
        }
      });
    }
  }

  Future<void> _open() async {
    final generation = ++_generation;
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      final rear =
          cameras.where((c) => c.lensDirection == CameraLensDirection.back);
      if (rear.isEmpty) throw StateError('Rear camera unavailable');
      controller = CameraController(rear.first, ResolutionPreset.high,
          enableAudio: false);
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!mounted || generation != _generation) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _error = null;
      });
    } catch (_) {
      await controller?.dispose();
      if (mounted && generation == _generation) {
        setState(() => _error =
            'Camera unavailable. Allow camera permission in Settings, then retry.');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      ++_generation;
      final old = _camera;
      _camera = null;
      _angle = null;
      _base = null; // Position may have changed while the app was hidden.
      _samples.clear();
      old?.dispose();
    } else if (state == AppLifecycleState.resumed && _camera == null) {
      _open();
    }
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (_busy || camera == null || !camera.value.isInitialized) return;
    double? height;
    if (widget.height) {
      final angle = _angle;
      if (angle == null ||
          _lastSensor == null ||
          DateTime.now().difference(_lastSensor!) >
              const Duration(seconds: 1)) {
        setState(
            () => _error = _angleError ?? 'Wait for a stable phone angle.');
        return;
      }
      final distance = double.tryParse(_distance.text.trim());
      if (distance == null || !distance.isFinite || distance <= 0) {
        setState(() => _error =
            'Enter the measured horizontal distance to this tree in metres.');
        return;
      }
      if (_base == null) {
        setState(() {
          _base = angle;
          _error = null;
          _samples.clear();
          _angle = null;
        });
        return;
      }
      try {
        height = calculateTreeHeightMeters(
            horizontalDistanceMeters: distance,
            topAngleDegrees: angle,
            baseAngleDegrees: _base!);
      } on FormatException catch (e) {
        setState(() => _error = e.message);
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final image = await camera.takePicture();
      // Release before returning, so native AR can safely own the camera next.
      await camera.dispose();
      _camera = null;
      if (mounted) {
        Navigator.pop(
            context, GuidedTreeCapture(File(image.path), heightMeters: height));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Capture failed. Please retry.';
        });
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    _sensors?.cancel();
    _camera?.dispose();
    _distance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final instruction = !widget.height
        ? 'Frame clear leaves from this tree. Include flowers or fruit when available.'
        : _base == null
            ? 'Stand at your measured distance. Aim the crosshair at the trunk base.'
            : 'Stay in exactly the same position. Aim at the highest visible crown point.';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
          title: Text(
              widget.height ? 'Scan Tree • Height' : 'Scan Tree • Species')),
      body: SafeArea(
          child: Column(children: [
        if (widget.height)
          Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _distance,
                enabled: _base == null,
                style: const TextStyle(color: Colors.white),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    filled: true,
                    fillColor: Colors.white24,
                    labelText: 'Measured horizontal distance (m)',
                    labelStyle: TextStyle(color: Colors.white),
                    helperText:
                        'Measure this distance first. No distance is assumed.',
                    helperStyle: TextStyle(color: Colors.white70)),
              )),
        Expanded(
            child: Stack(fit: StackFit.expand, children: [
          if (camera != null && camera.value.isInitialized)
            Center(child: CameraPreview(camera))
          else
            const Center(
                child: Icon(Icons.camera_alt_outlined,
                    color: Colors.white54, size: 64)),
          IgnorePointer(
              child: Center(
                  child: Container(
            width: widget.height ? 180 : 240,
            height: widget.height ? 180 : 280,
            decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 2),
                borderRadius: BorderRadius.circular(20)),
            child: const Center(
                child: Icon(Icons.add, color: Colors.white, size: 42)),
          ))),
          Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.all(12),
                color: Colors.black87,
                child: Text(instruction,
                    style: const TextStyle(color: Colors.white, fontSize: 16)),
              )),
          if (widget.height)
            Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.black87,
                    child: Text(
                        _angle == null
                            ? (_angleError ?? 'Waiting for phone angle…')
                            : 'Elevation ${_angle!.toStringAsFixed(1)}° • Hold upright',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 18)))),
        ])),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.all(12),
              child:
                  Text(_error!, style: const TextStyle(color: Colors.amber))),
        Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 12, children: [
              if (widget.height && _base != null)
                TextButton(
                    onPressed:
                        _busy ? null : () => setState(() => _base = null),
                    child: const Text('Restart base reading')),
              if (camera == null)
                TextButton(onPressed: _open, child: const Text('Retry camera')),
              ElevatedButton.icon(
                  onPressed: _busy || camera == null ? null : _capture,
                  icon: const Icon(Icons.camera_alt),
                  label: Text(_busy
                      ? 'Capturing…'
                      : !widget.height
                          ? 'Capture species photo'
                          : _base == null
                              ? 'Capture base angle'
                              : 'Capture crown and height')),
            ])),
      ])),
    );
  }
}
