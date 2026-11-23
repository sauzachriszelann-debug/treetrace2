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
      {super.key,
      required this.photo,
      required this.result,
      this.captureLocation,
      this.lookupLocation});
  final Future<GpsCaptureOutcome> Function()? captureLocation;
  final Future<Map<String, dynamic>> Function(double, double, double)?
      lookupLocation;
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
  String? _gpsMessage;
  bool _gpsFailed = false;
  bool _addressResolved = false;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _captureGps();
    });
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
      builder: (sheetContext) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.camera)),
        ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
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
    if (_gpsLoading) return;
    setState(() {
      _gpsLoading = true;
      _gpsFailed = false;
      _gpsMessage = null;
    });
    try {
      final outcome = await (widget.captureLocation?.call() ??
          GpsCaptureService().capture());
      if (!mounted) return;
      final position = outcome.position;
      if (position == null) {
        setState(() {
          _gpsFailed = true;
          _gpsMessage = outcome.failure == null
              ? 'GPS unavailable. Enable location access and try again.'
              : gpsFailureMessage(outcome.failure!);
        });
        return;
      }
      setState(() {
        _latitude.text = position.latitude.toString();
        _longitude.text = position.longitude.toString();
        _barangay.clear();
        _addressResolved = false;
        _gpsMessage = 'GPS captured. Looking up barangay...';
      });
      try {
        final location = await (widget.lookupLocation?.call(
                position.latitude, position.longitude, position.accuracy) ??
            api.getBarangayLocation(
                position.latitude, position.longitude, position.accuracy));
        if (!mounted) return;
        setState(() {
          _addressResolved = location['status'] == 'resolved';
          if (_addressResolved) {
            _barangay.text = location['barangay']?.toString() ?? '';
            _gpsMessage = 'Location tagged automatically.';
          } else {
            _gpsMessage = 'GPS captured. Barangay could not be verified.';
          }
        });
      } catch (_) {
        if (mounted) {
          setState(() =>
              _gpsMessage = 'GPS captured. Barangay lookup is unavailable.');
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _gpsFailed = true;
          _gpsMessage =
              'GPS unavailable. Enable location access and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  void _submit() {
    if (_gpsLoading || _latitude.text.isEmpty || _longitude.text.isEmpty) {
      setState(() => _error = 'Wait for GPS before submitting.');
      return;
    }
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
      'scan_profile': scanProfilePayload({
        ...widget.result,
        ..._candidate,
        'estimated_dbh_cm': _dbh,
        'estimated_height_m': _height,
        if (_ageEstimate != null) 'age_estimate': _ageEstimate
      }),
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

  Widget _section(String title, List<Widget> children) => Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: .2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        const SizedBox(height: 10),
        ...children,
      ]));

  Widget _measurement(String label, String value) => Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ]));

  @override
  Widget build(BuildContext context) {
    final dbh = _dbh;
    final height = _height;
    final carbon = dbh != null && height != null
        ? 0.0673 * math.pow(0.6 * dbh * dbh * height, 0.976) * 0.47
        : null;
    final confidence = _candidate['confidence_percent'];
    final serviceUnavailable = _prediction?['status'] == 'unavailable';
    final needsBase = _prediction?['needs_treebase_photo'] == true ||
        (!serviceUnavailable && _prediction != null && dbh == null);
    final needsTop = _prediction?['needs_treetop_photo'] == true ||
        (!serviceUnavailable && _prediction != null && height == null);
    final reasons = <String>{
      for (final key in [
        'dbh_reason',
        'height_reason',
        if (dbh == null && height == null) 'reason'
      ])
        if (_prediction?[key]?.toString().trim().isNotEmpty == true)
          _prediction![key].toString().trim(),
    };
    final gpsColor = _gpsFailed
        ? Theme.of(context).colorScheme.error
        : _addressResolved
            ? const Color(0xFF2E683B)
            : const Color(0xFF946200);
    return SafeArea(
        child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .9,
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
              child: Row(children: [
                const Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Expert review',
                          style: TextStyle(
                              fontSize: 21, fontWeight: FontWeight.bold)),
                      Text('Confirm the details before submitting.',
                          style: TextStyle(fontSize: 13)),
                    ])),
                IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ])),
          Expanded(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: ExpandablePhoto(
                                image: FileImage(widget.photo),
                                height: 210,
                                fit: BoxFit.contain)),
                        const SizedBox(height: 14),
                        _section('AI suggestion', [
                          Text(
                              '${_candidate['common_name'] ?? 'Not identified'}',
                              style: const TextStyle(
                                  fontSize: 19, fontWeight: FontWeight.w600)),
                          Text(
                              '${_candidate['scientific_name'] ?? 'Scientific name unavailable'}',
                              style:
                                  const TextStyle(fontStyle: FontStyle.italic)),
                          const SizedBox(height: 8),
                          Text(
                              'Confidence: ${confidence is num ? '${confidence.toStringAsFixed(2)}%' : 'Unavailable'}'),
                          const Text(
                              'The species will be confirmed by a reviewer.',
                              style: TextStyle(fontSize: 12)),
                        ]),
                        _section('Measurements', [
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _measurement('DBH',
                                    dbh == null ? 'Unavailable' : '$dbh cm'),
                                _measurement(
                                    'Height',
                                    height == null
                                        ? 'Unavailable'
                                        : '$height m'),
                                _measurement(
                                    'Carbon stock',
                                    carbon == null
                                        ? 'Unavailable'
                                        : '${carbon.toStringAsFixed(2)} kg'),
                              ]),
                          const SizedBox(height: 10),
                          const Text(
                              'Photo estimates need field verification. Carbon requires both DBH and height.',
                              style: TextStyle(fontSize: 12, height: 1.4)),
                          if (_analyzing)
                            const Padding(
                                padding: EdgeInsets.all(12),
                                child: LinearProgressIndicator()),
                          if (serviceUnavailable)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _prediction?['reason']?.toString() ??
                                    'The measurement service is unavailable. Try re-analyzing later.',
                                style: const TextStyle(
                                    color: Color(0xFF946200), fontSize: 13),
                              ),
                            ),
                          if (reasons.isNotEmpty && !serviceUnavailable)
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: const Text('Measurement details',
                                  style: TextStyle(fontSize: 14)),
                              children: [
                                for (final reason in reasons)
                                  Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Text(reason,
                                          style: const TextStyle(fontSize: 12)))
                              ],
                            ),
                          if (needsBase)
                            OutlinedButton(
                                onPressed:
                                    _analyzing ? null : () => _addPhoto(true),
                                child: const Text('Add tree base photo')),
                          if (needsTop)
                            OutlinedButton(
                                onPressed:
                                    _analyzing ? null : () => _addPhoto(false),
                                child: const Text('Add tree top photo')),
                          if (needsBase || needsTop)
                            const Text(
                                'Include overlapping trunk or branches to match the same tree.',
                                style: TextStyle(fontSize: 12)),
                          if (_base != null || _top != null)
                            Wrap(spacing: 10, runSpacing: 10, children: [
                              if (_base != null)
                                ExpandablePhoto(
                                    image: FileImage(_base!),
                                    label: 'Accepted tree base photo',
                                    width: 96,
                                    height: 120,
                                    fit: BoxFit.contain),
                              if (_top != null)
                                ExpandablePhoto(
                                    image: FileImage(_top!),
                                    label: 'Accepted tree top photo',
                                    width: 96,
                                    height: 120,
                                    fit: BoxFit.contain),
                            ]),
                          TextButton.icon(
                              onPressed: _analyzing ? null : () => _analyze(),
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('Re-analyze measurements')),
                          if (_candidate['scientific_name'] is String)
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: const Text('Estimated age',
                                  style: TextStyle(fontSize: 14)),
                              children: [
                                const Text(
                                    'Preliminary estimate based on the suggested species.',
                                    style: TextStyle(fontSize: 12)),
                                TreeAgeCard(
                                    scientificName:
                                        _candidate['scientific_name'],
                                    onEstimated: (age) {
                                      _ageEstimate = age;
                                    },
                                    dbhCm: dbh,
                                    heightM: height)
                              ],
                            ),
                        ]),
                        _section('Geotagged location', [
                          if (_gpsLoading)
                            const Row(children: [
                              SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                              SizedBox(width: 10),
                              Expanded(
                                  child: Text(
                                      'Getting your location automatically...')),
                            ]),
                          if (_latitude.text.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(children: [
                              const Icon(Icons.location_on_outlined, size: 18),
                              const SizedBox(width: 6),
                              Expanded(
                                  child: Text(
                                      '${_latitude.text}, ${_longitude.text}',
                                      style: const TextStyle(fontSize: 14)))
                            ]),
                            if (_barangay.text.isNotEmpty)
                              Text(_barangay.text,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                          ],
                          if (_gpsMessage != null)
                            Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(_gpsMessage!,
                                    style: TextStyle(
                                        color: gpsColor, fontSize: 13))),
                          if (_gpsFailed && !_gpsLoading)
                            OutlinedButton.icon(
                                onPressed: _captureGps,
                                icon: const Icon(Icons.my_location),
                                label: const Text('Retry location')),
                        ]),
                        _section('Notes', [
                          TextField(
                              controller: _notes,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                  hintText:
                                      'Additional observations (optional)',
                                  border: OutlineInputBorder()))
                        ]),
                        if (_error != null)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(_error!,
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error))),
                      ]))),
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed:
                          _analyzing || _gpsLoading || _latitude.text.isEmpty
                              ? null
                              : _submit,
                      child: const Text('Submit for Expert Review')))),
        ]),
      ),
    ));
  }
}
