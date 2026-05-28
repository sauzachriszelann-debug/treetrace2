import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../services/theme.dart';
import 'dbh_measure_screen.dart';

class AddTreeScreen extends StatefulWidget {
  final Map<String, dynamic>? aiResult;
  const AddTreeScreen({super.key, this.aiResult});
  @override
  State<AddTreeScreen> createState() => _AddTreeScreenState();
}

class _AddTreeScreenState extends State<AddTreeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _sciCtrl = TextEditingController();
  final _dbhCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _barangayCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  File? _photo;
  String _health = 'Healthy';
  bool _saving = false;
  bool _identifying = false;
  bool _gpsLoading = false;
  bool _addToEvaluation = true;
  String? _dbhConfidence; // Low / Medium / High
  String? _dbhMethod;
  Map<String, dynamic>? _aiPrediction;
  double? _predictedDbhCm;

  @override
  void initState() {
    super.initState();
    if (widget.aiResult != null) {
      final r = widget.aiResult!;
      _aiPrediction = r;
      _nameCtrl.text = r['common_name'] ?? '';
      _sciCtrl.text = r['scientific_name'] ?? '';
      _dbhCtrl.text = r['estimated_dbh_cm']?.toString() ?? '';
      _heightCtrl.text = r['estimated_height_m']?.toString() ?? '';
      _predictedDbhCm = (r['estimated_dbh_cm'] as num?)?.toDouble();
      _notesCtrl.text = _usefulAiNote(r['description']) ?? '';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _captureGps(automatic: true);
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _sciCtrl.dispose();
    _dbhCtrl.dispose();
    _heightCtrl.dispose();
    _barangayCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String? _usefulAiNote(dynamic value) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) return null;
    final lower = text.toLowerCase();
    const blocked = [
      'detailed treetrace vision enrichment is unavailable',
      'identified using plantnet botanical image matching',
      'gemini details are temporarily unavailable',
      'species match is based on plantnet',
    ];
    if (blocked.any(lower.contains)) return null;
    return text;
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final x = await ImagePicker()
        .pickImage(source: source, imageQuality: 80, maxWidth: 1200);
    if (x == null) return;
    final f = File(x.path);
    setState(() {
      _photo = f;
    });
    if (widget.aiResult == null) await _autoIdentify(f);
  }

  Future<void> _autoIdentify(File f) async {
    setState(() => _identifying = true);
    try {
      final r = await api.identifyTree(f);
      if (r['not_identified'] != true) {
        setState(() {
          _aiPrediction = r;
          if (_nameCtrl.text.isEmpty) _nameCtrl.text = r['common_name'] ?? '';
          if (_sciCtrl.text.isEmpty) _sciCtrl.text = r['scientific_name'] ?? '';
          if (_dbhCtrl.text.isEmpty)
            _dbhCtrl.text = r['estimated_dbh_cm']?.toString() ?? '';
          _predictedDbhCm ??= (r['estimated_dbh_cm'] as num?)?.toDouble();
          if (_heightCtrl.text.isEmpty)
            _heightCtrl.text = r['estimated_height_m']?.toString() ?? '';
          if (_notesCtrl.text.isEmpty)
            _notesCtrl.text = _usefulAiNote(r['description']) ?? '';
        });
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('AI identified: ${r['common_name']}'),
              backgroundColor: kHealthy));
      }
    } catch (_) {
    } finally {
      setState(() => _identifying = false);
    }
  }

  Future<void> _openDBHMeasure() async {
    final result = await Navigator.push<DBHResult>(
      context,
      MaterialPageRoute(builder: (_) => DBHMeasureScreen(initialPhoto: _photo)),
    );
    if (result != null) {
      setState(() {
        _dbhCtrl.text = result.dbhCm.toStringAsFixed(1);
        if (result.heightM != null)
          _heightCtrl.text = result.heightM!.toStringAsFixed(1);
        _dbhConfidence = result.confidence;
        _dbhMethod = result.method;
        _predictedDbhCm = result.dbhCm;
      });
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('DBH set to ${result.dbhCm.toStringAsFixed(1)} cm '
                '(${result.confidence} confidence)'),
            backgroundColor: kHealthy));
    }
  }

  Future<void> _captureGps({bool automatic = false}) async {
    setState(() => _gpsLoading = true);
    try {
      final servicesEnabled = await Geolocator.isLocationServiceEnabled();
      if (!servicesEnabled) {
        throw Exception('Location services are turned off.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission was denied.');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final barangay = await _barangayFromCoordinates(
        position.latitude,
        position.longitude,
      );
      setState(() {
        _latCtrl.text = position.latitude.toStringAsFixed(7);
        _lngCtrl.text = position.longitude.toStringAsFixed(7);
        if (barangay != null && barangay.isNotEmpty) {
          _barangayCtrl.text = barangay;
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(barangay == null
              ? 'GPS coordinates captured. Barangay can be entered manually.'
              : 'GPS and barangay captured!'),
          backgroundColor: kHealthy,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(automatic
              ? 'Tap Capture GPS & Barangay to try location again.'
              : 'Could not capture GPS: $e'),
          backgroundColor: kPoor,
        ));
      }
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  Future<String?> _barangayFromCoordinates(double lat, double lng) async {
    try {
      final marks = await placemarkFromCoordinates(lat, lng);
      if (marks.isEmpty) return null;
      final place = marks.first;
      final candidates = [
        place.subLocality,
        place.thoroughfare,
        place.street,
        place.locality,
      ];
      for (final value in candidates) {
        final cleaned = _cleanBarangay(value);
        if (cleaned != null) return cleaned;
      }
    } catch (_) {}
    return null;
  }

  String? _cleanBarangay(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    final lower = text.toLowerCase();
    if (lower == 'panabo' ||
        lower == 'panabo city' ||
        lower == 'davao del norte' ||
        lower == 'philippines') {
      return null;
    }
    return text
        .replaceFirst(RegExp(r'^barangay\s+', caseSensitive: false), 'Brgy. ')
        .replaceFirst(RegExp(r'^brgy\.\s*', caseSensitive: false), 'Brgy. ');
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final endangered = _checkEndangered(_nameCtrl.text.trim().toLowerCase());
    if (endangered != null) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Row(children: [
            Text(
                endangered['code'] == 'CR'
                    ? '⛔'
                    : endangered['code'] == 'EN'
                        ? '🚫'
                        : '⚠️',
                style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
                    endangered['code'] == 'CR'
                        ? 'Critically Endangered!'
                        : endangered['code'] == 'EN'
                            ? 'Protected Species!'
                            : 'Vulnerable Species',
                    style: const TextStyle(fontSize: 16))),
          ]),
          content: Text(
              '${_nameCtrl.text.trim()} is listed as ${endangered['status']} '
              'under DENR DAO 2017-11.\n\n'
              'Cutting or transporting is STRICTLY PROHIBITED without a DENR permit.\n\n'
              'Do you still want to record this tree in the inventory?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: kPoor),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Record Anyway',
                    style: TextStyle(color: Colors.white))),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _saving = true);
    try {
      String? photoUrl;
      final payload = {
        'common_name': _nameCtrl.text.trim(),
        'scientific_name':
            _sciCtrl.text.trim().isEmpty ? null : _sciCtrl.text.trim(),
        'health_status': _health,
        'barangay': _barangayCtrl.text.trim().isEmpty
            ? null
            : _barangayCtrl.text.trim(),
        'dbh_cm': double.tryParse(_dbhCtrl.text),
        'height_m': double.tryParse(_heightCtrl.text),
        'lat': double.tryParse(_latCtrl.text),
        'lng': double.tryParse(_lngCtrl.text),
        'city': 'Panabo City',
        'province': 'Davao del Norte',
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'photo_url': photoUrl,
      };

      if (await api.isOnline()) {
        if (_photo != null)
          payload['photo_url'] = await api.uploadPhoto(_photo!);
        await api.createTree(payload);
        if (_addToEvaluation) {
          try {
            await _saveEvaluationRow();
          } catch (_) {}
        }
      } else {
        await api.queueOfflineAction('CREATE_TREE', payload,
            photoPath: _photo?.path);
      }
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(await api.isOnline()
                ? 'Tree saved!'
                : 'Saved offline. It will sync when signal returns.'),
            backgroundColor: kHealthy));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: kPoor));
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _saveEvaluationRow() async {
    final actualSpecies = _nameCtrl.text.trim();
    if (actualSpecies.isEmpty) return;

    final actualConservation = _conservationStatusFor(actualSpecies);
    final predictedSpecies =
        (_aiPrediction?['common_name'] ?? actualSpecies).toString();
    final predictedConservation = (_aiPrediction?['endangered_status'] ??
            _aiPrediction?['status'] ??
            actualConservation)
        .toString();
    final actualDbh = double.tryParse(_dbhCtrl.text.trim());

    await (api as dynamic).createEvaluationRow({
      'image_id': 'TREE_${DateTime.now().millisecondsSinceEpoch}',
      'actual_species': actualSpecies,
      'predicted_species': predictedSpecies,
      'actual_conservation': actualConservation,
      'predicted_conservation': predictedConservation,
      'actual_dbh_cm': actualDbh,
      'predicted_dbh_cm': _predictedDbhCm ?? actualDbh,
      'scan_success': _aiPrediction != null || _dbhConfidence != null,
      'app_success': true,
      'latency_ms': null,
    });
  }

  String _conservationStatusFor(String name) {
    final found = _checkEndangered(name.trim().toLowerCase());
    return found?['status']?.toString() ?? 'Not Listed';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Add Tree'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // ── Photo ────────────────────────────────────────────────────
            GestureDetector(
              onTap: _showPhotoOptions,
              child: Container(
                height: 180,
                decoration: BoxDecoration(
                    color: kCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kBorder)),
                child: _identifying
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                            const CircularProgressIndicator(color: kPrimary),
                            const SizedBox(height: 10),
                            const Text('AI identifying species…',
                                style: TextStyle(color: kMutedFg)),
                          ])
                    : _photo != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.file(_photo!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: 180))
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                                Icon(Icons.add_a_photo_outlined,
                                    size: 36, color: kMutedFg.withOpacity(0.5)),
                                const SizedBox(height: 8),
                                const Text('Add photo',
                                    style: TextStyle(
                                        color: kMutedFg,
                                        fontWeight: FontWeight.w500)),
                                const SizedBox(height: 4),
                                const Text(
                                    'AI identifies species automatically',
                                    style: TextStyle(
                                        color: kMutedFg, fontSize: 12)),
                              ]),
              ),
            ),
            const SizedBox(height: 16),

            if (_aiPrediction != null) ...[
              _buildAiProfilePreview(),
              const SizedBox(height: 16),
            ],

            _label('Common Name *'),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                  hintText: 'e.g., Narra, Mahogany',
                  prefixIcon:
                      Icon(Icons.park_outlined, size: 18, color: kMutedFg)),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),

            _label('Scientific Name'),
            TextFormField(
              controller: _sciCtrl,
              decoration: const InputDecoration(
                  hintText: 'e.g., Pterocarpus indicus',
                  prefixIcon:
                      Icon(Icons.science_outlined, size: 18, color: kMutedFg)),
            ),
            const SizedBox(height: 12),

            _label('Health Status'),
            DropdownButtonFormField<String>(
              value: _health,
              decoration: const InputDecoration(
                  prefixIcon:
                      Icon(Icons.favorite_outline, size: 18, color: kMutedFg)),
              items: ['Healthy', 'Fair', 'Poor']
                  .map((s) => DropdownMenuItem(
                      value: s,
                      child: Row(children: [
                        Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: healthColor(s), shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Text(s),
                      ])))
                  .toList(),
              onChanged: (v) => setState(() => _health = v!),
            ),
            const SizedBox(height: 12),

            // ── DBH & Height with Measure button ─────────────────────────
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('DBH (cm)'),
                  TextFormField(
                    controller: _dbhCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        hintText: '30',
                        prefixIcon: const Icon(Icons.straighten,
                            size: 18, color: kMutedFg),
                        suffixIcon: _dbhConfidence != null
                            ? Padding(
                                padding: const EdgeInsets.all(8),
                                child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: (_dbhConfidence == 'High'
                                                ? kHealthy
                                                : _dbhConfidence == 'Medium'
                                                    ? kFair
                                                    : kPoor)
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8)),
                                    child: Text(_dbhConfidence!,
                                        style: TextStyle(
                                            color: _dbhConfidence == 'High'
                                                ? kHealthy
                                                : _dbhConfidence == 'Medium'
                                                    ? kFair
                                                    : kPoor,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700))))
                            : null),
                  ),
                ],
              )),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Height (m)'),
                  TextFormField(
                    controller: _heightCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        hintText: '10',
                        prefixIcon:
                            Icon(Icons.height, size: 18, color: kMutedFg)),
                  ),
                ],
              )),
            ]),
            const SizedBox(height: 8),

            // Measure with camera button
            OutlinedButton.icon(
              onPressed: _openDBHMeasure,
              icon: const Icon(Icons.camera_alt_outlined, size: 16),
              label: Text(_dbhConfidence == null
                  ? '📷 Measure DBH with Camera'
                  : '📷 Re-measure DBH with Camera'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: kPrimary,
                  side: const BorderSide(color: kPrimary),
                  padding: const EdgeInsets.symmetric(vertical: 10)),
            ),

            // Show method used if measured
            if (_dbhMethod != null) ...[
              const SizedBox(height: 6),
              Text('Method: $_dbhMethod',
                  style: const TextStyle(color: kMutedFg, fontSize: 11)),
            ],

            const SizedBox(height: 12),
            _label('Barangay'),
            TextFormField(
              controller: _barangayCtrl,
              decoration: const InputDecoration(
                  hintText: 'e.g., Brgy. Kakar',
                  prefixIcon: Icon(Icons.location_on_outlined,
                      size: 18, color: kMutedFg)),
            ),
            const SizedBox(height: 12),

            _label('GPS Location'),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: _gpsLoading ? null : _captureGps,
                    icon: _gpsLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location, size: 16),
                    label: Text(_gpsLoading
                        ? 'Getting Location...'
                        : 'Capture GPS & Barangay'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kPrimary,
                      side: const BorderSide(color: kPrimary),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _latCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true, signed: true),
                          decoration: const InputDecoration(
                            hintText: 'Latitude',
                            prefixIcon: Icon(Icons.pin_drop_outlined,
                                size: 18, color: kMutedFg),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _lngCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true, signed: true),
                          decoration: const InputDecoration(
                            hintText: 'Longitude',
                            prefixIcon: Icon(Icons.public,
                                size: 18, color: kMutedFg),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            _label('Notes'),
            TextFormField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                  hintText: 'Additional observations…',
                  prefixIcon: Icon(Icons.notes, size: 18, color: kMutedFg),
                  alignLabelWithHint: true),
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kPrimary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kPrimary.withOpacity(0.16)),
              ),
              child: CheckboxListTile(
                value: _addToEvaluation,
                onChanged: (value) =>
                    setState(() => _addToEvaluation = value ?? true),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: kPrimary,
                title: const Text(
                  'Add to evaluation test results',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, color: kForeground),
                ),
                subtitle: const Text(
                  'Saves this record to the evaluation database so Project Evaluation can calculate accuracy, DBH error, and app success from real saved trees.',
                  style: TextStyle(color: kMutedFg, fontSize: 12, height: 1.3),
                ),
              ),
            ),
            const SizedBox(height: 24),

            SizedBox(
                height: 46,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Save Tree'),
                )),
            const SizedBox(height: 32),
          ]),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w500, color: kForeground)));

  Widget _buildAiProfilePreview() {
    final result = _aiPrediction ?? {};
    final common = (result['common_name'] ?? 'AI identified tree').toString();
    final scientific = (result['scientific_name'] ?? '').toString();
    final status = (result['endangered_status'] ?? 'Not Listed').toString();
    final habitat =
        (result['habitat'] ?? 'Philippines / Southeast Asia').toString();
    final description = _usefulAiNote(result['description']) ??
        'TreeTrace AI filled the species fields. Review the record before saving.';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSidebarBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kSidebarPrimary.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: kSidebarPrimary.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: kSidebarPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(common,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900)),
                    if (scientific.isNotEmpty)
                      Text(scientific,
                          style: const TextStyle(
                              color: kSidebarText,
                              fontStyle: FontStyle.italic,
                              fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _AiPreviewPill(Icons.record_voice_over_outlined,
                  _pronunciation(common)),
              _AiPreviewPill(Icons.shield_outlined, status),
              _AiPreviewPill(Icons.public_rounded, habitat),
            ],
          ),
          const SizedBox(height: 12),
          Text(description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: kSidebarText, fontSize: 12, height: 1.4)),
        ],
      ),
    );
  }

  String _pronunciation(String value) {
    final text = value.trim();
    if (text.isEmpty) return 'Not available';
    return text
        .split(RegExp(r'\s+|-'))
        .where((part) => part.isNotEmpty)
        .map((part) => part.toLowerCase())
        .join(' - ');
  }

  Map<String, dynamic>? _checkEndangered(String name) {
    const endangered = {
      'narra': {'status': 'Endangered', 'code': 'EN', 'cut': false},
      'almaciga': {
        'status': 'Critically Endangered',
        'code': 'CR',
        'cut': false
      },
      'molave': {'status': 'Endangered', 'code': 'EN', 'cut': false},
      'ipil': {'status': 'Endangered', 'code': 'EN', 'cut': false},
      'apitong': {'status': 'Endangered', 'code': 'EN', 'cut': false},
      'dao': {'status': 'Endangered', 'code': 'EN', 'cut': false},
      'kamagong': {'status': 'Vulnerable', 'code': 'VU', 'cut': false},
      'yakal': {'status': 'Vulnerable', 'code': 'VU', 'cut': false},
      'philippine teak': {
        'status': 'Critically Endangered',
        'code': 'CR',
        'cut': false
      },
      'lauan': {'status': 'Vulnerable', 'code': 'VU', 'cut': false},
      'red lauan': {'status': 'Endangered', 'code': 'EN', 'cut': false},
      'pterocarpus indicus': {
        'status': 'Endangered',
        'code': 'EN',
        'cut': false
      },
      'diospyros philippinensis': {
        'status': 'Vulnerable',
        'code': 'VU',
        'cut': false
      },
      'philippine ebony': {'status': 'Vulnerable', 'code': 'VU', 'cut': false},
      'shorea astylosa': {'status': 'Vulnerable', 'code': 'VU', 'cut': false},
      'agathis philippinensis': {
        'status': 'Critically Endangered',
        'code': 'CR',
        'cut': false
      },
      'tectona philippinensis': {
        'status': 'Critically Endangered',
        'code': 'CR',
        'cut': false
      },
    };
    if (endangered[name] != null) return endangered[name];
    for (final entry in endangered.entries) {
      if (name.contains(entry.key) || entry.key.contains(name))
        return entry.value;
    }
    return null;
  }

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
            leading: const Icon(Icons.camera_alt_outlined, color: kPrimary),
            title: const Text('Take Photo'),
            onTap: () {
              Navigator.pop(context);
              _pickPhoto(ImageSource.camera);
            }),
        ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: kPrimary),
            title: const Text('Choose from Gallery'),
            onTap: () {
              Navigator.pop(context);
              _pickPhoto(ImageSource.gallery);
            }),
      ])),
    );
  }
}

class _AiPreviewPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _AiPreviewPill(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: kSidebarPrimary),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
