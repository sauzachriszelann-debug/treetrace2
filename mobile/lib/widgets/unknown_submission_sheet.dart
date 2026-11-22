import '../services/scan_profile_payload.dart';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../services/gps_capture.dart';
import '../services/photo_measurement_rules.dart';
import 'expandable_photo.dart';
import 'tree_age_card.dart';

/// Returns reviewed submission evidence to the scanner's online/offline save path.
class UnknownSubmissionSheet extends StatefulWidget {
  const UnknownSubmissionSheet(
      {super.key, required this.photo, required this.result});
  final File photo;
  final Map<String, dynamic> result;

  @override
  State<UnknownSubmissionSheet> createState() => _UnknownSubmissionSheetState();
}

class _UnknownSubmissionSheetState extends State<UnknownSubmissionSheet> {
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  final _barangay = TextEditingController();
  final _notes = TextEditingController();
  Map<String, dynamic>? _prediction;
  File? _base;
  File? _top;
  bool _analyzing = false;
  bool _gpsLoading = false;
  String? _error;
  Map<String, dynamic>? _ageEstimate;

  Map<String, dynamic> get _candidate {
    final suggestion = widget.result['suggested_species'];
    if (suggestion is Map) return Map<String, dynamic>.from(suggestion);
    final candidates = widget.result['possible_candidates'];
    if (candidates is List &&
        candidates.isNotEmpty &&
        candidates.first is Map) {
      return Map<String, dynamic>.from(candidates.first as Map);
    }
    return widget.result;
  }

  double? _value(String key, String originalKey, double max) {
    if (_prediction != null) {
      return acceptedGalleryValue(_prediction!, key, max);
    }
    final value = widget.result[originalKey];
    return value is num && value.isFinite && value > 0 && value <= max
        ? value.toDouble()
        : null;
  }

  double? get _dbh => _value('predicted_dbh_cm', 'estimated_dbh_cm', 300);
  double? get _height => _value('predicted_height_m', 'estimated_height_m', 80);

  @override
  void initState() {
    super.initState();
    final existing = widget.result['measurement_prediction'];
    if (existing is Map) {
      _prediction = Map<String, dynamic>.from(existing);
    } else {
      _analyze();
    }
  }

  @override
  void dispose() {
    for (final controller in [_latitude, _longitude, _barangay, _notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _analyze({File? base, File? top}) async {
    if (_analyzing) return;
    setState(() {
      _analyzing = true;
      _error = null;
    });
    try {
      final result = await api.predictGallerySize(widget.photo,
          treebasePhoto: base ?? _base, treetopPhoto: top ?? _top);
      if (!mounted) return;
      final baseMatched = base == null || result['treebase_photo_used'] == true;
      final topMatched = top == null || result['treetop_photo_used'] == true;
      if (!baseMatched || !topMatched) {
        setState(() => _error = (base != null
                    ? result['dbh_reason']
                    : result['height_reason'])
                ?.toString() ??
            result['reason']?.toString() ??
            'The added photo could not be matched to this tree. Include overlapping trunk or branches.');
        return;
      }
      setState(() {
        _prediction = result;
        _base = base ?? _base;
        _top = top ?? _top;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Photo analysis could not finish. Try again.');
      }
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _addPhoto(bool base) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.camera_alt_outlined), title: const Text('Take a photo'),
          onTap: () => Navigator.pop(sheetContext, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from gallery'),
          onTap: () => Navigator.pop(sheetContext, ImageSource.gallery)),
      ])),
    );
    if (source == null || !mounted) return;
    final picked = await ImagePicker().pickImage(source: source);
    if (picked == null || !mounted) return;
    final file = File(picked.path);
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(base ? 'Tree base photo' : 'Treetop photo'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                Image.file(file, height: 180, fit: BoxFit.contain),
                const Text(
                    'Does this show the same tree, with overlapping trunk or branches?'),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Analyze photos')),
              ],
            ));
    if (confirmed == true && mounted) {
      await _analyze(base: base ? file : null, top: base ? null : file);
    }
  }

  Future<void> _captureGps() async {
    setState(() => _gpsLoading = true);
    try {
      final outcome = await GpsCaptureService().capture();
      if (!mounted) return;
      final position = outcome.position;
      if (position == null) {
        setState(() => _error =
            'Could not capture GPS. Enable location access or enter coordinates.');
        return;
      }
      _latitude.text = position.latitude.toString();
      _longitude.text = position.longitude.toString();
      _barangay.clear();
      try {
        final location = await api.getBarangayLocation(
            position.latitude, position.longitude, position.accuracy);
        if (!mounted) return;
        if (location['status'] == 'resolved') {
          _barangay.text = location['barangay']?.toString() ?? '';
        } else {
          setState(() =>
              _error = 'GPS captured. Check the barangay before submitting.');
        }
      } catch (_) {
        if (mounted) {
          setState(() => _error = 'GPS captured. Enter the barangay manually.');
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'GPS unavailable. Enter coordinates manually.');
      }
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  void _submit() {
    final latError = coordinateErrorText(_latitude.text, isLatitude: true);
    final lngError = coordinateErrorText(_longitude.text, isLatitude: false);
    if (latError != null ||
        lngError != null ||
        (_latitude.text.trim().isEmpty != _longitude.text.trim().isEmpty)) {
      setState(() => _error = latError ??
          lngError ??
          'Enter both coordinates or leave both blank.');
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'scan_profile': scanProfilePayload({...widget.result, ..._candidate, 'estimated_dbh_cm': _dbh, 'estimated_height_m': _height, if (_ageEstimate != null) 'age_estimate': _ageEstimate}),
      'dbh_cm': _dbh,
      'height_m': _height,
      'barangay': _barangay.text.trim().isEmpty ? null : _barangay.text.trim(),
      'location_description': _latitude.text.trim().isEmpty
          ? null
          : '${_latitude.text.trim()}, ${_longitude.text.trim()}',
      'submitter_notes': _notes.text.trim(),
      'ai_candidates': [_candidate],
    });
  }

  @override
  Widget build(BuildContext context) {
    final dbh = _dbh;
    final height = _height;
    final carbon = dbh != null && height != null
        ? 0.0673 * math.pow(0.6 * dbh * dbh * height, 0.976) * 0.47
        : null;
    final confidence = _candidate['confidence_percent'];
    final needsBase = _prediction?['needs_treebase_photo'] == true || dbh == null;
    final needsTop = _prediction?['needs_treetop_photo'] == true || height == null;
    return SafeArea(
        child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .9,
        child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Expanded(
                      child: Text('Species needs expert review',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold))),
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close))
                ]),
                const Text(
                    'Review the suggested species, measurements, and location before submitting.'),
                const SizedBox(height: 12),
                ExpandablePhoto(
                    image: FileImage(widget.photo),
                    height: 180,
                    fit: BoxFit.contain),
                const SizedBox(height: 12),
                Text(
                    'Suggested common name: ${_candidate['common_name'] ?? 'Unavailable'}'),
                Text(
                    'Suggested scientific name: ${_candidate['scientific_name'] ?? 'Unavailable'}'),
                Text(
                    'Confidence: ${confidence is num ? '$confidence%' : 'Unavailable'}'),
                const SizedBox(height: 12),
                Text('DBH: ${dbh == null ? 'Unavailable' : '$dbh cm'}'),
                Text('Height: ${height == null ? 'Unavailable' : '$height m'}'),
                Text(
                    'Carbon stock: ${carbon == null ? 'Unavailable' : '${carbon.toStringAsFixed(2)} kg'}'),
                const Text('Photo measurements are unvalidated estimates. Carbon is preliminary and is computed only when both DBH and height are available.', style: TextStyle(fontSize: 12, height: 1.4)),
                if (_analyzing)
                  const Padding(
                      padding: EdgeInsets.all(12),
                      child: LinearProgressIndicator()),
                if (_prediction?['dbh_reason'] != null)
                  Text('${_prediction!['dbh_reason']}'),
                if (_prediction?['height_reason'] != null)
                  Text('${_prediction!['height_reason']}'),
                if (needsBase)
                  OutlinedButton(
                      onPressed: _analyzing ? null : () => _addPhoto(true),
                      child: const Text('Add tree base photo')),
                if (needsTop)
                  OutlinedButton(
                      onPressed: _analyzing ? null : () => _addPhoto(false),
                      child: const Text('Add tree top photo')),
                if (needsBase || needsTop)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Include overlapping trunk or branches so the added photo can be matched to the same tree. Measurements remain unavailable if the evidence is insufficient.')),
                if (_base != null || _top != null)
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    if (_base != null) ExpandablePhoto(image: FileImage(_base!), label: 'Accepted tree base photo', width: 96, height: 120, fit: BoxFit.contain),
                    if (_top != null) ExpandablePhoto(image: FileImage(_top!), label: 'Accepted tree top photo', width: 96, height: 120, fit: BoxFit.contain),
                  ]),
                OutlinedButton(
                    onPressed: _analyzing ? null : () => _analyze(),
                    child: const Text('Re-analyze')),
                if (_candidate['scientific_name'] is String) ...[
                  const Text('Preliminary age based on the suggested species.'),
                  TreeAgeCard(
                      scientificName: _candidate['scientific_name'],
                      onEstimated: (age) { _ageEstimate = age; },
                      dbhCm: dbh,
                      heightM: height),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                    onPressed: _gpsLoading ? null : _captureGps,
                    icon: const Icon(Icons.my_location),
                    label: Text(
                        _gpsLoading ? 'Getting location…' : 'Capture GPS')),
                TextField(
                    controller: _latitude,
                    decoration: const InputDecoration(labelText: 'Latitude'),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true)),
                TextField(
                    controller: _longitude,
                    decoration: const InputDecoration(labelText: 'Longitude'),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true)),
                TextField(
                    controller: _barangay,
                    decoration: const InputDecoration(labelText: 'Barangay')),
                TextField(
                    controller: _notes,
                    decoration: const InputDecoration(labelText: 'Notes'),
                    maxLines: 3),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: _analyzing || _gpsLoading ? null : _submit,
                    child: const Text('Submit for Expert Review')),
              ],
            )),
      ),
    ));
  }
}
