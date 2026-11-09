import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../services/api_service.dart';
import '../services/dbh_ar_service.dart';
import '../services/theme.dart';

class AutomaticDbhScreen extends StatefulWidget {
  final ValueChanged<Map<String, dynamic>> onUse;
  const AutomaticDbhScreen({super.key, required this.onUse});

  @override
  State<AutomaticDbhScreen> createState() => _AutomaticDbhScreenState();
}

class _AutomaticDbhScreenState extends State<AutomaticDbhScreen> {
  final _native = DbhArService();
  final _api = ApiService();
  bool _busy = false;
  bool _ready = false;
  String _message = 'Checking phone and measurement service…';
  Map<String, dynamic>? _result;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _ready = false;
      _result = null;
    });
    try {
      final device = await _native.capabilities();
      if (!mounted) return;
      if (device['supported'] != true) {
        setState(() => _message =
            device['reason']?.toString() ?? 'This phone is not supported.');
        return;
      }
      final server = await _api.dbhArStatus();
      if (!mounted) return;
      setState(() {
        _ready = server['ready'] == true;
        _message = _ready
            ? 'Ready. The scanner will check depth support, then guide you through ground and trunk capture.'
            : 'Automatic DBH is not available on the measurement server yet. Please try again later.';
      });
    } on DioException catch (e) {
      if (mounted) {
        setState(() => _message = switch (e.response?.statusCode) {
          401 => 'Your session expired. Sign in again before scanning.',
          403 => 'This account cannot access the DBH measurement service.',
          404 => 'This server does not have the automatic DBH endpoints yet. Update the backend before scanning.',
          _ => 'The DBH measurement server could not be reached. Check the connection and try again.',
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'Could not check automatic DBH. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    setState(() {
      _busy = true;
      _result = null;
      _message = 'Opening guided camera…';
    });
    try {
      final capture = await _native.scan();
      if (!mounted) return;
      if (capture['image_base64'] == null) {
        setState(() =>
            _message = capture['reason']?.toString() ?? 'Scan cancelled.');
        return;
      }
      setState(() => _message = 'Checking trunk shape and depth at 1.3 m…');
      final response = await _api.measureDbhAr(capture);
      if (!mounted) return;
      final dbh = acceptedAutomaticDbh(response);
      setState(() {
        _result = dbh != null ? response : null;
        _message = dbh != null
            ? 'Estimated DBH: ${dbh.toStringAsFixed(1)} cm'
            : response['reason']?.toString() ??
                'Measurement was uncertain. Please rescan.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'The scan could not be completed. Check your connection and rescan.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Automatic DBH')),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          const Icon(Icons.view_in_ar, size: 64, color: kPrimary),
          const SizedBox(height: 20),
          const Text('Scan the trunk without reference objects',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Text(
              '1. Move slowly and aim at level ground beside the tree base.\n\n'
              '2. Set the ground when the scanner detects it.\n\n'
              '3. Aim at the trunk around 1.3 m above that ground, move slightly sideways, and capture. '
              'Keep the whole trunk width visible. The base can leave the frame after ground setup.'),
          const SizedBox(height: 16),
          const Text(
              'Use a straight, single trunk on locally level ground. Forked, leaning, '
              'buttressed or heavily obstructed trunks are outside this prototype’s supported conditions.'),
          const SizedBox(height: 20),
          Semantics(
              liveRegion: true,
              child: Text(_message, style: const TextStyle(fontSize: 17))),
          if (_busy)
            const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator())),
          if (_result != null) ...[
            const SizedBox(height: 12),
            const Text(
                'Experimental estimate. Field accuracy has not yet been validated. '
                'Tree height is not measured by this scan.'),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: !_busy && _ready ? _scan : null,
            icon: const Icon(Icons.camera_alt),
            label: Text(_result == null ? 'Start / rescan' : 'Rescan'),
          ),
          OutlinedButton(
            onPressed:
                !_busy && _result != null ? () => widget.onUse(_result!) : null,
            child: const Text('Use This Measurement'),
          ),
          TextButton(
              onPressed: _busy ? null : _check,
              child: const Text('Check availability again')),
        ]),
      );
}
