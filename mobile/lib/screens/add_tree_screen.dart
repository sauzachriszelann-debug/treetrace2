import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_provider.dart';
import '../services/theme.dart';
import 'dbh_measure_screen.dart';
import 'tree_detail_screen.dart';

class AddTreeScreen extends StatefulWidget {
  final Map<String, dynamic>? aiResult;
  final File? initialPhoto;
  const AddTreeScreen({super.key, this.aiResult, this.initialPhoto});
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
  final _exactLocationCtrl = TextEditingController();
  final _cityCtrl = TextEditingController(text: 'Panabo City');
  final _provinceCtrl = TextEditingController(text: 'Davao del Norte');
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
  String? _pendingKey;
  Map<String, dynamic>? _restoredSnapshot;

  @override
  void initState() {
    super.initState();
    _photo = widget.initialPhoto;
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
      if (mounted) {
        _captureGps(automatic: true);
        _offerDraftRecovery();
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _sciCtrl.dispose();
    _dbhCtrl.dispose();
    _heightCtrl.dispose();
    _barangayCtrl.dispose();
    _exactLocationCtrl.dispose();
    _cityCtrl.dispose();
    _provinceCtrl.dispose();
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

  bool _sameIdentity(
      Map<String, dynamic> snapshot, Map<String, dynamic> payload) {
    String norm(Object? v) => (v ?? '').toString().trim().toLowerCase();
    double? coord(Object? v) {
      final text = (v ?? '').toString().trim();
      if (text.isEmpty) return null;
      final parsed = double.tryParse(text);
      if (parsed == null || !parsed.isFinite) return null;
      return (parsed * 1e7).round() / 1e7;
    }

    return norm(snapshot['common_name']) == norm(payload['common_name']) &&
        norm(snapshot['scientific_name']) == norm(payload['scientific_name']) &&
        coord(snapshot['lat']) == coord(payload['lat']) &&
        coord(snapshot['lng']) == coord(payload['lng']) &&
        norm(snapshot['barangay']) == norm(payload['barangay']);
  }

  Map<String, dynamic> _currentSnapshot({String? exactLocation}) => {
        'common_name': _nameCtrl.text.trim(),
        'scientific_name': _sciCtrl.text.trim(),
        'dbh_text': _dbhCtrl.text.trim(),
        'height_text': _heightCtrl.text.trim(),
        'health': _health,
        'barangay': _barangayCtrl.text.trim(),
        'exact_location': exactLocation ?? _exactLocationCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'province': _provinceCtrl.text.trim(),
        'lat': _latCtrl.text.trim(),
        'lng': _lngCtrl.text.trim(),
        'notes': _notesCtrl.text.trim(),
      };

  Future<void> _offerDraftRecovery() async {
    final result = await api.readPendingDraftResult();
    final draft = result['draft'] as Map<String, dynamic>?;
    if (!mounted) return;
    if (result['error'] == 'storage') {
      // Secure storage could not be read: nothing was discarded and no
      // submission key will be created or replaced silently.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Could not check secure storage for a previous submission. Nothing was discarded.'),
          backgroundColor: kPoor));
      return;
    }
    if (result['error'] == 'unreadable') {
      await _offerUnreadableDraftRecovery(result['raw']?.toString());
      return;
    }
    if (draft == null) return;
    final snapshot = Map<String, dynamic>.from(draft['snapshot'] ?? {});
    final uncertain =
        draft['status'] == 'uncertain' || draft['status'] == 'in_flight';
    final submitted =
        Map<String, dynamic>.from(draft['submitted_payload'] ?? {});
    final canRetry = uncertain && submitted.isNotEmpty;
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Recover previous submission?'),
        content: Text(
          '${snapshot['common_name'] ?? 'Unnamed tree'} — saved ${draft['created_at'] ?? 'earlier'}'
          '${uncertain ? '\n\nA previous save may have reached the server. Resuming keeps the same submission key, so retrying cannot create a duplicate.' : '\n\nResume to continue this draft, or discard it to start fresh.'}',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, 'discard'),
              child: const Text('Discard')),
          TextButton(
              onPressed: () => Navigator.pop(context, 'resume'),
              child: const Text('Resume')),
          if (canRetry)
            ElevatedButton(
                onPressed: () => Navigator.pop(context, 'retry'),
                child: const Text('Retry original submission')),
        ],
      ),
    );
    if (choice == 'discard') {
      // Explicit confirmation: the pending key and payload are discarded.
      await api.clearPendingDraft();
      return;
    }
    if (choice == 'retry') {
      await _retryOriginalSubmission(draft);
      return;
    }
    if (choice != 'resume') {
      // Dialog dismissed without a choice: keep the pending submission
      // (key and payload) untouched.
      return;
    }
    if (!mounted) return;
    setState(() {
      _pendingKey = draft['key']?.toString();
      _restoredSnapshot = snapshot;
      _nameCtrl.text = snapshot['common_name']?.toString() ?? '';
      _sciCtrl.text = snapshot['scientific_name']?.toString() ?? '';
      _dbhCtrl.text = snapshot['dbh_text']?.toString() ?? '';
      _heightCtrl.text = snapshot['height_text']?.toString() ?? '';
      _barangayCtrl.text = snapshot['barangay']?.toString() ?? '';
      _exactLocationCtrl.text = snapshot['exact_location']?.toString() ?? '';
      _latCtrl.text = snapshot['lat']?.toString() ?? '';
      _lngCtrl.text = snapshot['lng']?.toString() ?? '';
      _notesCtrl.text = snapshot['notes']?.toString() ?? '';
      final photoPath = draft['photo_path']?.toString();
      if (photoPath != null &&
          photoPath.isNotEmpty &&
          File(photoPath).existsSync()) {
        _photo = File(photoPath);
      }
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Draft restored. Saving reuses the same submission key; the original payload stays retryable.'),
          backgroundColor: kHealthy));
    }
  }

  /// A stored pending submission exists but cannot be parsed. Its bytes are
  /// preserved unless the user explicitly discards them.
  Future<void> _offerUnreadableDraftRecovery(String? raw) async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Previous submission could not be read'),
        content: SingleChildScrollView(
          child: Text(
            'A pending submission was found on this device but could not be '
            'read. It has NOT been deleted.\n\n'
            '${raw == null || raw.isEmpty ? '' : 'Stored data:\n$raw\n\n'}'
            'Keep it (nothing changes), or discard it explicitly to start fresh.',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep It')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kPoor),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard Unreadable Draft',
                  style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (discard == true) {
      await api.clearPendingDraft();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Unreadable submission data discarded.'),
            backgroundColor: kHealthy));
      }
    }
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
      final location = await _locationFromCoordinates(
        position.latitude,
        position.longitude,
      );
      setState(() {
        // Preserve restored or manually entered values (G2 draft recovery).
        if (_latCtrl.text.isEmpty) {
          _latCtrl.text = position.latitude.toStringAsFixed(7);
        }
        if (_lngCtrl.text.isEmpty) {
          _lngCtrl.text = position.longitude.toStringAsFixed(7);
        }
        if (location.exactLocation != null && _exactLocationCtrl.text.isEmpty) {
          _exactLocationCtrl.text = location.exactLocation!;
        }
        if (location.barangay != null && _barangayCtrl.text.isEmpty) {
          _barangayCtrl.text = location.barangay!;
        }
        if (location.city != null) {
          _cityCtrl.text = location.city!;
        }
        if (location.province != null) {
          _provinceCtrl.text = location.province!;
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(location.barangay == null
              ? 'GPS captured. Add the exact place if needed.'
              : 'GPS and full address captured!'),
          backgroundColor: kHealthy,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(automatic
              ? 'Tap Capture GPS & Address to try location again.'
              : 'Could not capture GPS: $e'),
          backgroundColor: kPoor,
        ));
      }
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  Future<_ResolvedLocation> _locationFromCoordinates(
      double lat, double lng) async {
    _ResolvedLocation? phoneLocation;
    try {
      final marks = await placemarkFromCoordinates(lat, lng);
      if (marks.isNotEmpty) {
        final place = marks.first;
        final barangay = _firstCleanBarangay([
          place.subLocality,
          place.locality,
          place.subAdministrativeArea,
        ]);
        final city = _cleanCity(place.locality) ??
            _cleanCity(place.subAdministrativeArea);
        final province = _cleanProvince(place.administrativeArea);
        phoneLocation = _ResolvedLocation(
          exactLocation: _cleanFullAddress([
            place.name,
            place.street,
            place.thoroughfare,
            place.subThoroughfare,
            barangay,
            city,
            province,
            place.country,
          ]),
          barangay: barangay,
          city: city,
          province: province,
        );
      }
    } catch (_) {}

    final onlineLocation = phoneLocation?.barangay == null
        ? await _lookupOnlineLocation(lat, lng)
        : null;
    final barangay = phoneLocation?.barangay ??
        onlineLocation?.barangay ??
        _nearestPanaboBarangay(lat, lng);
    final city = phoneLocation?.city ?? onlineLocation?.city ?? 'Panabo City';
    final province = phoneLocation?.province ??
        onlineLocation?.province ??
        'Davao del Norte';

    return _ResolvedLocation(
      exactLocation: _cleanFullAddress([
        phoneLocation?.exactLocation,
        onlineLocation?.exactLocation,
        barangay,
        city,
        province,
      ]),
      barangay: barangay,
      city: city,
      province: province,
    );
  }

  Future<_ResolvedLocation?> _lookupOnlineLocation(
      double lat, double lng) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': lat.toString(),
        'lon': lng.toString(),
        'zoom': '18',
        'addressdetails': '1',
      });
      final response = await http.get(uri, headers: {
        'User-Agent': 'TreeTrace Mobile'
      }).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return null;
      final address = data['address'];
      if (address is! Map) return null;
      final a = Map<String, dynamic>.from(address);
      final barangay = _firstCleanBarangay([
        a['neighbourhood']?.toString(),
        a['suburb']?.toString(),
        a['quarter']?.toString(),
        a['village']?.toString(),
        a['hamlet']?.toString(),
        a['city_district']?.toString(),
      ]);
      final city = _cleanCity(a['city']?.toString()) ??
          _cleanCity(a['town']?.toString()) ??
          _cleanCity(a['municipality']?.toString()) ??
          _cleanCity(a['county']?.toString());
      final province = _cleanProvince(a['state']?.toString());
      return _ResolvedLocation(
        exactLocation: _cleanFullAddress([
          a['house_number']?.toString(),
          a['road']?.toString(),
          a['neighbourhood']?.toString(),
          a['suburb']?.toString(),
          a['village']?.toString(),
          city,
          province,
        ]),
        barangay: barangay,
        city: city,
        province: province,
      );
    } catch (_) {
      return null;
    }
  }

  String? _nearestPanaboBarangay(double lat, double lng) {
    const barangays = [
      _BarangayPoint('Gredu', 7.3076, 125.6847),
      _BarangayPoint('San Francisco', 7.3140, 125.6722),
      _BarangayPoint('New Visayas', 7.3028, 125.6851),
      _BarangayPoint('Quezon', 7.2962, 125.6817),
      _BarangayPoint('San Pedro', 7.3017, 125.6734),
      _BarangayPoint('San Vicente', 7.2922, 125.6779),
      _BarangayPoint('Santo Nino', 7.2888, 125.6908),
      _BarangayPoint('Cagangohan', 7.3354, 125.6666),
      _BarangayPoint('J.P. Laurel', 7.3288, 125.6846),
      _BarangayPoint('New Pandan', 7.3221, 125.6946),
      _BarangayPoint('San Nicolas', 7.3168, 125.6993),
      _BarangayPoint('San Roque', 7.2876, 125.7043),
      _BarangayPoint('Santa Cruz', 7.2809, 125.6861),
      _BarangayPoint('Kauswagan', 7.2719, 125.6902),
      _BarangayPoint('Little Panay', 7.2730, 125.6718),
      _BarangayPoint('Dapco', 7.2566, 125.6868),
      _BarangayPoint('Lower Panaga', 7.2595, 125.6725),
      _BarangayPoint('Mabunao', 7.2476, 125.6794),
      _BarangayPoint('Maduao', 7.2361, 125.6604),
      _BarangayPoint('Malativas', 7.2597, 125.7085),
      _BarangayPoint('Katipunan', 7.2463, 125.7152),
      _BarangayPoint('Katualan', 7.2345, 125.7068),
      _BarangayPoint('Kasilak', 7.2205, 125.6969),
      _BarangayPoint('Nanyo', 7.2188, 125.7163),
      _BarangayPoint('A.O. Floirendo', 7.2097, 125.6845),
      _BarangayPoint('Buenavista', 7.2022, 125.6687),
      _BarangayPoint('Consolacion', 7.1902, 125.6823),
      _BarangayPoint('Salvacion', 7.1982, 125.7048),
      _BarangayPoint('New Malaga', 7.1808, 125.7018),
      _BarangayPoint('New Malitbog', 7.1690, 125.7136),
      _BarangayPoint('Sindaton', 7.1644, 125.6949),
      _BarangayPoint('Manay', 7.1510, 125.7040),
      _BarangayPoint('Kiotoy', 7.3416, 125.7097),
      _BarangayPoint('Tibungol', 7.3492, 125.6953),
      _BarangayPoint('Tagpore', 7.3675, 125.7025),
      _BarangayPoint('Upper Licanan', 7.3781, 125.7177),
      _BarangayPoint('Waterfall', 7.3930, 125.7275),
      _BarangayPoint('Southern Davao', 7.1714, 125.6702),
    ];

    _BarangayPoint? nearest;
    var nearestKm = double.infinity;
    for (final barangay in barangays) {
      final distance = Geolocator.distanceBetween(
            lat,
            lng,
            barangay.lat,
            barangay.lng,
          ) /
          1000;
      if (distance < nearestKm) {
        nearestKm = distance;
        nearest = barangay;
      }
    }
    if (nearest == null || nearestKm > 18) return null;
    return 'Brgy. ${nearest.name}';
  }

  String? _firstCleanBarangay(List<String?> values) {
    for (final value in values) {
      final cleaned = _cleanBarangay(value);
      if (cleaned != null) return cleaned;
    }
    return null;
  }

  String? _cleanBarangay(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    final lower = text.toLowerCase();
    if (_looksLikePlusCode(text) ||
        lower == 'panabo' ||
        lower == 'panabo city' ||
        lower == 'davao del norte' ||
        lower == 'philippines') {
      return null;
    }
    return text
        .replaceFirst(RegExp(r'^barangay\s+', caseSensitive: false), 'Brgy. ')
        .replaceFirst(RegExp(r'^brgy\.\s*', caseSensitive: false), 'Brgy. ');
  }

  String? _cleanExactLocation(List<String?> values) {
    final cleaned = values
        .map((value) => value?.trim())
        .whereType<String>()
        .where((value) =>
            value.isNotEmpty &&
            !_looksLikePlusCode(value) &&
            value.toLowerCase() != 'philippines')
        .toSet()
        .toList();
    if (cleaned.isEmpty) return null;
    return cleaned.take(2).join(', ');
  }

  String? _cleanFullAddress(List<String?> values) {
    final cleaned = <String>[];
    for (final raw in values) {
      final value = raw?.trim();
      if (value == null ||
          value.isEmpty ||
          _looksLikePlusCode(value) ||
          value.toLowerCase() == 'philippines') {
        continue;
      }
      if (!cleaned.any((item) => item.toLowerCase() == value.toLowerCase())) {
        cleaned.add(value);
      }
    }
    if (cleaned.isEmpty) return null;
    return cleaned.take(5).join(', ');
  }

  String? _cleanCity(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    if (_looksLikePlusCode(text)) return null;
    return text == 'Panabo' ? 'Panabo City' : text;
  }

  String? _cleanProvince(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty || _looksLikePlusCode(text)) return null;
    return text;
  }

  bool _looksLikePlusCode(String value) =>
      RegExp(r'^[23456789CFGHJMPQRVWX]{4,}\+').hasMatch(value.trim());

  String? _validateOptionalMeasurement(String? value, String label) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;

    final measurement = double.tryParse(text);
    if (measurement == null || !measurement.isFinite || measurement <= 0) {
      return '$label must be a finite positive number.';
    }
    return null;
  }

  double? _parseOptionalMeasurement(String value) {
    final text = value.trim();
    return text.isEmpty ? null : double.tryParse(text);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final dbhCm = _parseOptionalMeasurement(_dbhCtrl.text);
    final heightM = _parseOptionalMeasurement(_heightCtrl.text);

    double? lat;
    double? lng;
    final rawLat = _latCtrl.text.trim();
    if (rawLat.isNotEmpty) {
      lat = double.tryParse(rawLat);
      if (lat == null || !lat.isFinite || lat < -90 || lat > 90) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Latitude must be a number between -90 and 90, or leave it empty.'),
            backgroundColor: kPoor));
        return;
      }
    }
    final rawLng = _lngCtrl.text.trim();
    if (rawLng.isNotEmpty) {
      lng = double.tryParse(rawLng);
      if (lng == null || !lng.isFinite || lng < -180 || lng > 180) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Longitude must be a number between -180 and 180, or leave it empty.'),
            backgroundColor: kPoor));
        return;
      }
    }

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
    // G4: citizens submit PENDING tree submissions for expert review; only
    // staff records become official inventory trees.
    final isCitizen = context.read<AuthProvider>().user?.role == 'citizen';
    try {
      String? photoUrl;
      final exactLocation = _exactLocationCtrl.text.trim();
      final rawNotes = _notesCtrl.text.trim();
      final notes = [
        if (exactLocation.isNotEmpty) 'Exact location: $exactLocation',
        if (rawNotes.isNotEmpty) rawNotes,
      ].join('\n\n');
      final payload = {
        'common_name': _nameCtrl.text.trim(),
        'scientific_name':
            _sciCtrl.text.trim().isEmpty ? null : _sciCtrl.text.trim(),
        'health_status': _health,
        'barangay': _barangayCtrl.text.trim().isEmpty
            ? null
            : _barangayCtrl.text.trim(),
        'dbh_cm': dbhCm,
        'height_m': heightM,
        'lat': lat,
        'lng': lng,
        'city': _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
        'province': _provinceCtrl.text.trim().isEmpty
            ? null
            : _provinceCtrl.text.trim(),
        'notes': notes.isEmpty ? null : notes,
        'photo_url': photoUrl,
      };

      // ── Idempotent submission key (G2) ─────────────────────────────────
      // A pending submission from an earlier attempt (possibly already on
      // the server) must never be replaced silently: its key and payload
      // are preserved until the user explicitly confirms a new submission.
      var key = _pendingKey;
      final pendingRead = await api.readPendingDraftResult();
      if (pendingRead['error'] != null) {
        // Never overwrite pending data that could not be read back.
        final keepGoing = await _confirmUnreadablePendingOverwrite(
          pendingRead['error'] == 'storage'
              ? 'Secure storage could not be read'
              : 'The pending submission on this device could not be read',
          pendingRead['raw']?.toString(),
        );
        if (keepGoing != true) return; // save aborted; data untouched
      }
      final stored = pendingRead['draft'] as Map<String, dynamic>?;
      final storedKey = stored?['key']?.toString();
      if (stored != null && (key == null || key != storedKey)) {
        // Another pending submission owns the envelope (for example the
        // recovery dialog was dismissed). Ask before replacing it.
        final replace = await _confirmReplacePending(stored);
        if (replace != true) return; // everything preserved; save aborted
        await api.clearPendingDraft();
        key = null;
        _restoredSnapshot = null;
      } else if (key != null &&
          stored != null &&
          _restoredSnapshot != null &&
          !_sameIdentity(_restoredSnapshot!, payload)) {
        // Same pending key, but the form now describes a different tree.
        final replace = await _confirmReplacePending(stored);
        if (replace != true) return; // previous key + payload preserved
        await api.clearPendingDraft();
        key = null;
        _restoredSnapshot = null;
      }
      // ── Nearby matching suggestions (G3) ─────────────────────────────
      // Advisory duplicate prevention for NEW submissions only: G2 flows
      // that reuse an existing key (retry/edit of a pending submission)
      // skip it, and offline saves queue without it - the queue
      // confirmation below states that limitation explicitly.
      if (!isCitizen &&
          key == null &&
          lat != null &&
          lng != null &&
          await api.isOnline()) {
        final proceed = await _runNearbyCheck(
          lat,
          lng,
          commonName: _nameCtrl.text.trim(),
          scientificName: _sciCtrl.text.trim(),
        );
        if (proceed != true) return; // nothing written or sent yet
      }

      final createdAt = (stored != null && storedKey == key)
          ? stored['created_at']?.toString()
          : null;
      key ??= api.generateClientUuid();
      _pendingKey = key;
      payload['client_uuid'] = key;

      if (await api.isOnline()) {
        if (_photo != null)
          payload['photo_url'] = await api.uploadPhoto(_photo!,
              purpose: isCitizen ? 'unknown_species' : 'tree_photo');
        // Persist key + an immutable copy of the exact payload BEFORE the
        // request: if it reaches the server and the response is lost, the
        // retry carries the same key and payload. submitted_payload is
        // written ONCE per key: an edited Save never replaces it, so
        // "Retry original submission" always stays possible.
        final priorSubmitted = stored != null &&
                storedKey == key &&
                stored['submitted_payload'] is Map
            ? Map<String, dynamic>.from(stored['submitted_payload'] as Map)
            : null;
        try {
          await api.writePendingDraft({
            'key': key,
            'created_at': createdAt ?? DateTime.now().toIso8601String(),
            'status': 'in_flight',
            'snapshot': _currentSnapshot(exactLocation: exactLocation),
            'photo_path': _photo?.path,
            'submitted_payload':
                priorSubmitted ?? Map<String, dynamic>.from(payload),
          });
        } catch (e) {
          // Surface a failed persistence instead of proceeding silently
          // without local recovery data.
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    'Warning: could not secure this submission on this device ($e). If the save fails, it may not be recoverable.'),
                backgroundColor: kPoor));
          }
        }
        final result = isCitizen
            ? await api.createTreeSubmission({...payload, 'source': 'mobile'})
            : await api.createTree(payload);
        await api.clearPendingDraft();
        _pendingKey = null;
        _restoredSnapshot = null;
        // Staff replays carry idempotent_replay; G4 submission replays are
        // recognised by a decided status (a fresh submission is 'pending').
        if (result['idempotent_replay'] == true ||
            (isCitizen &&
                result['status'] != null &&
                result['status'] != 'pending')) {
          final differences =
              Map<String, dynamic>.from(result['replayed_differences'] ?? {});
          if (mounted) {
            final summary = differences.keys.join(', ');
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(differences.isEmpty
                    ? (isCitizen
                        ? 'This submission was already recorded - no duplicate was created.'
                        : 'Already recorded as tree #${result['id']} - no duplicate was created.')
                    : 'Already recorded as tree #${result['id']}. Not overwritten; differences: $summary. Review the record to update it.'),
                backgroundColor: kHealthy));
            Navigator.pop(context, true);
          }
          return;
        }
        if (_addToEvaluation && !isCitizen) {
          try {
            await _saveEvaluationRow();
          } catch (_) {}
        }
      } else if (isCitizen) {
        // G4 (decision 8): citizen submissions are online-only; the offline
        // queue stays a staff tool. The pending key/payload written above
        // are discarded only because nothing was ever sent.
        await api.clearPendingDraft();
        _pendingKey = null;
        _restoredSnapshot = null;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Tree submissions need an internet connection. Please try again when you are back online.'),
              backgroundColor: kPoor));
        }
        return;
      } else {
        await api.queueOfflineAction('CREATE_TREE', payload,
            photoPath: _photo?.path);
        // The offline queue now owns the pending submission (payload + key);
        // its replay is idempotent through client_uuid.
        await api.clearPendingDraft();
        _pendingKey = null;
        _restoredSnapshot = null;
      }
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(isCitizen
                ? 'Submitted for expert review! Track it under My Submissions.'
                : await api.isOnline()
                    ? 'Tree saved!'
                    : 'Saved offline - the nearby duplicate check was skipped. '
                        'Review it in Field Sync before uploading.'),
            backgroundColor: kHealthy));
      }
    } on DioException catch (e) {
      // Preserve the pending submission: the request MAY have reached the
      // server. Retrying with the same key and the immutable
      // submitted_payload copy cannot create a duplicate.
      if (_pendingKey != null) {
        final pendingRead = await api.readPendingDraftResult();
        if (pendingRead['error'] == 'storage') {
          // The stored draft could not be read; overwriting it could destroy
          // the only copy of an earlier original payload.
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text(
                    'Could not update the saved submission on this device (secure storage error). Nothing was deleted.'),
                backgroundColor: kPoor));
          }
        } else {
          final stored = pendingRead['draft'] as Map<String, dynamic>?;
          await api.writePendingDraft({
            'key': _pendingKey,
            'created_at':
                stored?['created_at'] ?? DateTime.now().toIso8601String(),
            'status': e.response == null ? 'uncertain' : 'conflict',
            'snapshot': _currentSnapshot(),
            'photo_path': _photo?.path,
            'submitted_payload': stored?['submitted_payload'],
            if (pendingRead['error'] == 'unreadable')
              'previous_unreadable_raw': pendingRead['raw'],
          });
        }
      }
      if (e.response?.statusCode == 409) {
        final detail =
            e.response?.data is Map ? e.response?.data['detail'] : null;
        final existingId = detail is Map ? detail['existing_tree_id'] : null;
        if (mounted) {
          final choice = await showDialog<String>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('This key belongs to a different tree'),
              content: Text(
                  'Nothing was merged or overwritten.${existingId != null ? ' The existing record is tree #$existingId.' : ''}'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, 'new'),
                    child: const Text('Start new submission')),
                if (existingId != null)
                  ElevatedButton(
                      onPressed: () => Navigator.pop(context, 'open'),
                      child: const Text('Open existing record')),
              ],
            ),
          );
          if (choice == 'open') {
            await api.clearPendingDraft();
            _pendingKey = null;
            _restoredSnapshot = null;
            if (mounted) Navigator.pop(context, true);
          } else if (choice == 'new') {
            await api.clearPendingDraft();
            _pendingKey = null;
            _restoredSnapshot = null;
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                      'Start a fresh save - a new submission key will be used.'),
                  backgroundColor: kHealthy));
            }
          }
          // Dismissed without a choice: keep the pending key and payload.
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Connection problem - your submission is saved. Retrying will not create a duplicate.'),
            backgroundColor: kPoor));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: kPoor));
    } finally {
      setState(() => _saving = false);
    }
  }

  /// Asks for explicit confirmation before replacing a different pending
  /// submission. The previous key and payload stay untouched until the
  /// user picks "Discard & start new".
  Future<bool> _confirmReplacePending(Map<String, dynamic> stored) async {
    final snapshot = Map<String, dynamic>.from(stored['snapshot'] ?? {});
    final uncertain =
        stored['status'] == 'uncertain' || stored['status'] == 'in_flight';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Start a new submission?'),
        content: Text(
            'A pending submission for "${snapshot['common_name'] ?? 'Unnamed tree'}" '
            '${uncertain ? 'may already have reached the server' : 'is still saved'} '
            'and keeps its submission key until you confirm.\n\n'
            'Discard it and submit this form as a new tree?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep pending submission')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kPoor),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard & start new',
                  style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    return confirmed == true;
  }

  /// Explicit confirmation required before a save may overwrite pending
  /// submission data that could not be read back.
  Future<bool> _confirmUnreadablePendingOverwrite(
      String reason, String? raw) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Unreadable pending submission'),
        content: SingleChildScrollView(
          child: Text(
            '$reason. Overwriting it would lose the original submission key '
            'and payload.\n\n'
            '${raw == null || raw.isEmpty ? '' : 'Stored data:\n$raw\n\n'}'
            'Cancel to keep everything as-is, or overwrite explicitly to '
            'start this save as a new submission.',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel (keep pending data)')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kPoor),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Overwrite & Start New',
                  style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    return confirmed == true;
  }

  /// Advisory G3 lookup. Returns true when the save should proceed.
  /// A failed check is NEVER treated as "no matches": the user must
  /// explicitly choose to continue without it. Candidates are presented
  /// with distance, species-match label, and barangay; tapping one opens
  /// the existing record (the existing-record link). Nothing is merged,
  /// overwritten, or rejected automatically.
  Future<bool> _runNearbyCheck(
    double lat,
    double lng, {
    required String commonName,
    required String scientificName,
  }) async {
    List<Map<String, dynamic>> candidates;
    try {
      candidates = await api.getNearbyTrees(
        lat: lat,
        lng: lng,
        commonName: commonName,
        scientificName: scientificName,
      );
    } catch (_) {
      if (!mounted) return false;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Nearby check could not be completed'),
          content: const Text(
              'Possible existing trees could not be verified (network or server problem). '
              'This is NOT the same as "no matches" - your registration is simply unchecked.\n\n'
              'Continue without the nearby check?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue without check')),
          ],
        ),
      );
      return proceed == true;
    }

    if (!mounted) return false;
    if (candidates.isEmpty) return true;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Possible existing trees nearby'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: candidates.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final candidate = candidates[index];
              final distance =
                  (candidate['distance_m'] as num?)?.toDouble() ?? 0;
              final match = candidate['species_match']?.toString();
              final matchLabel = match == 'exact'
                  ? 'same species'
                  : match == 'unknown'
                      ? 'species not provided'
                      : 'different species';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${candidate['common_name'] ?? 'Unnamed tree'}'
                  '${candidate['scientific_name'] != null ? ' (${candidate['scientific_name']})' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text('~${distance.round()} m away'
                    '${candidate['barangay'] != null ? ' · ${candidate['barangay']}' : ''}'
                    ' · $matchLabel'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  final treeId = candidate['tree_id'];
                  if (treeId is int) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => TreeDetailScreen(treeId: treeId)),
                    );
                  }
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Register as a new tree')),
        ],
      ),
    );
    return proceed == true;
  }

  /// Re-sends the immutable original payload with its original key.
  /// Nothing from the current form is used, so no data can be silently
  /// replaced, and the same UUID is reused.
  Future<void> _retryOriginalSubmission(Map<String, dynamic> draft) async {
    final key = draft['key']?.toString();
    final original =
        Map<String, dynamic>.from(draft['submitted_payload'] ?? {});
    if (key == null || original.isEmpty) return;
    original['client_uuid'] = key;

    if (!await api.isOnline()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Still offline - the original submission is kept for later.'),
            backgroundColor: kPoor));
      }
      return;
    }

    setState(() => _saving = true);
    try {
      await api.writePendingDraft({
        'key': key,
        'created_at': draft['created_at'],
        'status': 'in_flight',
        'snapshot': draft['snapshot'],
        'photo_path': draft['photo_path'],
        'submitted_payload': original,
      });
      final result = await api.createTree(original);
      await api.clearPendingDraft();
      _pendingKey = null;
      _restoredSnapshot = null;
      if (!mounted) return;
      if (result['idempotent_replay'] == true) {
        final differences =
            Map<String, dynamic>.from(result['replayed_differences'] ?? {});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(differences.isEmpty
                ? 'Already recorded as tree #${result['id']} - no duplicate was created.'
                : 'Already recorded as tree #${result['id']}. Not overwritten; differences: ${differences.keys.join(', ')}. Review the record to update it.'),
            backgroundColor: kHealthy));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Tree saved!'), backgroundColor: kHealthy));
      }
      Navigator.pop(context, true);
    } on DioException catch (e) {
      final stored = await api.readPendingDraft();
      await api.writePendingDraft({
        'key': key,
        'created_at': stored?['created_at'] ?? draft['created_at'],
        'status': e.response == null ? 'uncertain' : 'conflict',
        'snapshot': stored?['snapshot'] ?? draft['snapshot'],
        'photo_path': stored?['photo_path'] ?? draft['photo_path'],
        'submitted_payload': stored?['submitted_payload'] ?? original,
      });
      if (mounted) {
        if (e.response?.statusCode == 409) {
          final detail =
              e.response?.data is Map ? e.response?.data['detail'] : null;
          final existingId = detail is Map ? detail['existing_tree_id'] : null;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Submission conflict: this key already belongs to a different tree.'
                  '${existingId != null ? ' The existing record is tree #$existingId.' : ''}'
                  ' Nothing was merged or overwritten - the original submission is kept.'),
              backgroundColor: kPoor));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Connection problem - the original submission is kept. Retrying will not create a duplicate.'),
              backgroundColor: kPoor));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: kPoor));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
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
                    validator: (value) =>
                        _validateOptionalMeasurement(value, 'DBH'),
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
                    validator: (value) =>
                        _validateOptionalMeasurement(value, 'Height'),
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
            _label('Exact Location / Purok / Barangay / City / Province'),
            TextFormField(
              controller: _exactLocationCtrl,
              minLines: 1,
              maxLines: 2,
              decoration: const InputDecoration(
                  hintText: 'Auto-filled from GPS, or type Purok / landmark',
                  prefixIcon:
                      Icon(Icons.place_outlined, size: 18, color: kMutedFg)),
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
                        : 'Capture GPS & Address'),
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
                            prefixIcon:
                                Icon(Icons.public, size: 18, color: kMutedFg),
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
                clipBehavior: Clip.antiAlias,
                child: _photo != null
                    ? Image.file(_photo!, fit: BoxFit.cover)
                    : const Icon(Icons.auto_awesome_rounded,
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
              _AiPreviewPill(
                  Icons.record_voice_over_outlined, _pronunciation(common)),
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

class _ResolvedLocation {
  final String? exactLocation;
  final String? barangay;
  final String? city;
  final String? province;

  const _ResolvedLocation({
    this.exactLocation,
    this.barangay,
    this.city,
    this.province,
  });
}

class _BarangayPoint {
  final String name;
  final double lat;
  final double lng;

  const _BarangayPoint(this.name, this.lat, this.lng);
}
