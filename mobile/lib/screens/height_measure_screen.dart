import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../services/theme.dart';
import '../services/tree_height_measurement.dart';

class HeightMeasurementResult {
  final double heightMeters;

  const HeightMeasurementResult(this.heightMeters);
}

/// Offline-capable phone clinometer. An injected stream is used by tests;
/// production uses the device accelerometer stream from sensors_plus.
class HeightMeasureScreen extends StatefulWidget {
  final Stream<AccelerometerEvent>? sensorEvents;

  const HeightMeasureScreen({super.key, this.sensorEvents});

  @override
  State<HeightMeasureScreen> createState() => _HeightMeasureScreenState();
}

class _HeightMeasureScreenState extends State<HeightMeasureScreen> {
  final _topAngleController = TextEditingController();
  final _baseAngleController = TextEditingController();
  final _correctedHeightController = TextEditingController();
  StreamSubscription<AccelerometerEvent>? _sensorSubscription;
  Timer? _sensorTimeout;
  double? _liveAngle;
  double? _estimatedHeight;
  String? _sensorMessage;
  String? _error;
  final List<double> _recentAngles = [];

  @override
  void initState() {
    super.initState();
    _sensorTimeout = Timer(const Duration(seconds: 2), () {
      if (mounted && _liveAngle == null && _sensorMessage == null) {
        setState(() => _sensorMessage =
            'Phone sensor is not responding. Enter top and base angles manually.');
      }
    });
    try {
      _sensorSubscription =
          (widget.sensorEvents ?? accelerometerEventStream()).listen(
        _onSensorEvent,
        onError: (Object _) {
          _sensorTimeout?.cancel();
          if (mounted) {
            setState(() => _sensorMessage =
                'Phone sensor is unavailable. Enter top and base angles manually.');
          }
        },
        onDone: () {
          _sensorTimeout?.cancel();
          if (mounted) {
            setState(() => _sensorMessage =
                'Phone sensor is unavailable. Enter top and base angles manually.');
          }
        },
        cancelOnError: false,
      );
    } catch (_) {
      _sensorTimeout?.cancel();
      _sensorMessage =
          'Phone sensor is unavailable. Enter top and base angles manually.';
    }
  }

  void _onSensorEvent(AccelerometerEvent event) {
    try {
      final angle = phoneElevationDegrees(x: event.x, y: event.y, z: event.z);
      if (!mounted) return;
      _sensorTimeout?.cancel();
      _recentAngles.add(angle);
      if (_recentAngles.length > 7) _recentAngles.removeAt(0);
      final stableAngle = _recentAngles.reduce((sum, sample) => sum + sample) /
          _recentAngles.length;
      setState(() {
        _liveAngle = stableAngle;
        _sensorMessage = null;
      });
    } on FormatException catch (exception) {
      if (mounted) setState(() => _sensorMessage = exception.message);
    }
  }

  @override
  void dispose() {
    _sensorTimeout?.cancel();
    _sensorSubscription?.cancel();
    _topAngleController.dispose();
    _baseAngleController.dispose();
    _correctedHeightController.dispose();
    super.dispose();
  }

  void _captureAngle(TextEditingController controller, String label) {
    if (_liveAngle == null) {
      setState(() => _error =
          'A stable sensor angle is not available. Enter the $label angle manually.');
      return;
    }
    setState(() {
      controller.text = _liveAngle!.toStringAsFixed(1);
      _error = null;
      _estimatedHeight = null;
    });
  }

  void _calculate() {
    final top = double.tryParse(_topAngleController.text.trim());
    final base = double.tryParse(_baseAngleController.text.trim());
    if (top == null || base == null) {
      setState(() => _error =
          'Capture both readings or enter readings from a clinometer.');
      return;
    }
    try {
      final height = calculateTreeHeightMeters(
        horizontalDistanceMeters: 10,
        topAngleDegrees: top,
        baseAngleDegrees: base,
      );
      setState(() {
        _estimatedHeight = height;
        _correctedHeightController.text = height.toStringAsFixed(2);
        _error = null;
      });
    } on FormatException catch (exception) {
      setState(() {
        _estimatedHeight = null;
        _error = exception.message;
      });
    }
  }

  void _accept() {
    final corrected = double.tryParse(_correctedHeightController.text.trim());
    if (corrected == null || !corrected.isFinite || corrected <= 0) {
      setState(() => _error = 'Enter a corrected height greater than zero.');
      return;
    }
    Navigator.pop(context, HeightMeasurementResult(corrected));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: kBackground,
        appBar: AppBar(
          title: const Text('Measure Tree Height'),
          backgroundColor: kSidebarBg,
          foregroundColor: Colors.white,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _instructions(),
              const SizedBox(height: 16),
              const Text('Horizontal distance: 10 m'),
              const SizedBox(height: 16),
              _angleField(
                controller: _topAngleController,
                label: 'Upper clinometer reading (°)',
                keyName: 'top-angle',
              ),
              const SizedBox(height: 12),
              _angleField(
                controller: _baseAngleController,
                label: 'Base clinometer reading (°)',
                keyName: 'base-angle',
              ),
              if (_sensorMessage != null) ...[
                const SizedBox(height: 10),
                Text(_sensorMessage!,
                    key: const Key('sensor-status'),
                    style: const TextStyle(color: kFair, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _calculate,
                  icon: const Icon(Icons.calculate_outlined),
                  label: const Text('Calculate Estimated Height'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    key: const Key('height-error'),
                    style: const TextStyle(color: kPoor)),
              ],
              if (_estimatedHeight != null) ...[
                const SizedBox(height: 18),
                _resultPanel(),
              ],
            ],
          ),
        ),
      );

  Widget _instructions() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kPrimary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kPrimary.withValues(alpha: 0.22)),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Field instructions',
                style: TextStyle(fontWeight: FontWeight.w700, color: kPrimary)),
            SizedBox(height: 8),
            Text(
                'Stand 10 m horizontally from the trunk at ground level. Hold the phone upright in portrait orientation and aim its rear camera at the highest visible point of the crown.'),
            SizedBox(height: 6),
            Text(
                'Capture the crown reading, then aim at the trunk where it meets the ground and capture the base reading. A point below horizontal has a negative reading.'),
            SizedBox(height: 6),
            Text(
                'Stand safely where both points are visible. Reposition if the tree leans, the top or base is hidden, or the phone cannot be held steady. The result is an estimate; check and correct it before accepting.'),
          ],
        ),
      );

  Widget _angleField({
    required TextEditingController controller,
    required String label,
    required String keyName,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_liveAngle == null)
            _numberField(
              controller: controller,
              label: label,
              hint: 'Enter a reading from a clinometer',
              keyName: keyName,
            )
          else
            Text(controller.text.isEmpty
                ? label
                : '$label: ${controller.text}°'),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            key: Key('capture-$keyName'),
            onPressed: _liveAngle == null
                ? null
                : () => _captureAngle(controller, keyName),
            icon: const Icon(Icons.my_location, size: 16),
            label: Text(_liveAngle == null
                ? 'Sensor angle unavailable'
                : 'Use phone angle: ${_liveAngle!.toStringAsFixed(1)}°'),
          ),
        ],
      );

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required String keyName,
  }) =>
      TextField(
        key: Key(keyName),
        controller: controller,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: true),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) {
          if (_estimatedHeight != null || _error != null) {
            setState(() {
              _estimatedHeight = null;
              _error = null;
            });
          }
        },
      );

  Widget _resultPanel() => Container(
        key: const Key('height-estimate-result'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kHealthy.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kHealthy.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Estimated tree height',
                style: TextStyle(fontWeight: FontWeight.w700, color: kPrimary)),
            const SizedBox(height: 4),
            Text('${_estimatedHeight!.toStringAsFixed(2)} m'),
            const SizedBox(height: 12),
            TextField(
              key: const Key('corrected-height'),
              controller: _correctedHeightController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Correct height if needed (m)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    key: const Key('accept-height'),
                    onPressed: _accept,
                    child: const Text('Use Height'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}
