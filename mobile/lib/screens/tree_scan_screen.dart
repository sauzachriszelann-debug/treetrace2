import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/api_service.dart';
import '../services/photo_capture_metadata_store.dart';
import '../services/identification_error.dart';
import '../services/ar_tree_height.dart';
import '../services/dbh_ar_service.dart';
import '../services/tree_scan_result.dart';
import 'guided_tree_camera_screen.dart';
import 'level_dbh_camera_screen.dart';
import '../services/photo_measurement_rules.dart';

/// Add photo opens this session directly. Capture stages advance in the native
/// camera; processing and species identification run automatically afterwards.
class TreeScanScreen extends StatefulWidget {
  final Future<Map<String, dynamic>> Function(File)? predictGallerySize;
  final File? galleryPhoto;
  final PhotoCaptureMetadataStore metadataStore;
  final Future<Map<String, dynamic>> Function(File)? identifyPhoto;
  final Future<Map<String, dynamic>> Function(File, PhotoCaptureMetadata)?
      measurePhoto;
  final bool autoStart;
  final bool advancedAr;
  final ValueChanged<TreeScanResult>? onUse;
  final TreeScanResult? initialResult;
  const TreeScanScreen(
      {super.key,
      this.autoStart = true,
      this.galleryPhoto,
      this.predictGallerySize,
      this.metadataStore = const PhotoCaptureMetadataStore(),
      this.identifyPhoto,
      this.measurePhoto,
      this.initialResult,
      this.advancedAr = false,
      this.onUse});
  @override
  State<TreeScanScreen> createState() => _TreeScanScreenState();
}

class _TreeScanScreenState extends State<TreeScanScreen> {
  Map<String, dynamic>? _galleryPrediction;
  Uint8List? _galleryTrunkPreview;
  Map<String, dynamic>? _photoMeasurement;
  Uint8List? _preview;
  bool _baseConfirmed = false;
  bool _previewReady = false;
  bool _measurementSkipped = false;
  Map<String, dynamic>? _species;
  Map<String, dynamic>? _dbh;
  File? _photo;
  double? _height;
  Map<String, dynamic>? _heightResult;
  bool _busy = false;
  bool _keepingPhoto = false;
  bool _ownsPhoto = false;
  String? _message;
  String? _dbhMessage;
  String? _heightMessage;
  final _form = GlobalKey<FormState>();
  final _common = TextEditingController();
  final _scientific = TextEditingController();
  final _diameter = TextEditingController();
  final _treeHeight = TextEditingController();

  bool get _hasReviewedValues =>
      _species != null ||
      _dbh != null ||
      _height != null ||
      _photo != null ||
      [_common, _scientific, _diameter, _treeHeight]
          .any((c) => c.text.trim().isNotEmpty);

  void _fillSpecies() {
    _common.text = _species?['common_name']?.toString() ?? '';
    _scientific.text = _species?['scientific_name']?.toString() ?? '';
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialResult;
    if (initial != null) {
      _photo = initial.photo;
      _measurementSkipped = initial.measurementSkipped;
      _species = initial.species;
      _dbh = initial.dbh;
      _height = initial.heightMeters;
      _heightResult = initial.heightResult;
      _fillSpecies();
      _common.text = initial.reviewedCommonName ?? _common.text;
      _scientific.text = initial.reviewedScientificName ?? _scientific.text;
      final diameter = initial.reviewedDbhCm ??
          (_dbh == null ? null : acceptedAutomaticDbh(_dbh!));
      _diameter.text = diameter?.toStringAsFixed(1) ?? '';
      _treeHeight.text =
          (initial.reviewedHeightMeters ?? _height)?.toStringAsFixed(2) ?? '';
    }
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (widget.galleryPhoto != null) {
            _scanGallery(widget.galleryPhoto!);
          } else {
            _scan();
          }
        }
      });
    }
  }

  Future<void> _replacePhoto(File photo, {bool owned = false}) async {
    final previous = _photo;
    final deletePrevious = _ownsPhoto;
    _photo = photo;
    _galleryPrediction = null;
    _galleryTrunkPreview = null;
    _ownsPhoto = owned;
    _species = null;
    _fillSpecies();
    if (deletePrevious && previous != null && previous.path != photo.path) {
      try {
        await previous.delete();
      } catch (_) {/* Already removed by cache cleanup. */}
    }
  }

  Future<void> _scanGallery(File photo) async {
    setState(() {
      _busy = true;
      _message = 'Identifying original gallery photo.';
      _dbhMessage = 'Checking saved capture readings.';
      _heightMessage =
          'Height unavailable: this photo has no saved height observation.';
    });
    Future<void>? speciesWork;
    try {
      await _replacePhoto(photo);
      if (!mounted) return;
      speciesWork = _identify(photo);
      final metadata = await widget.metadataStore.read(photo);
      if (!mounted) return;
      if (metadata == null) {
        setState(() => _dbhMessage =
            'DBH unavailable: no saved TreeTrace capture readings for this original photo. Take a level photo to measure DBH.');
        await _predictGallery(photo);
        return;
      }
      final result = await (widget.measurePhoto?.call(photo, metadata) ??
          api.measureDbh(photo,
              referenceHint:
                  'Original gallery photo with saved capture readings',
              method: 'yolo_trunk_v1',
              cameraHeightM: metadata.cameraHeightMeters,
              pitchDeg: metadata.pitchDegrees,
              focalPixels: metadata.focalPixels));
      // Reject retakes/fallbacks BEFORE reading any numeric result fields.
      final valid = photoMeasurementAccepted(result, baseConfirmed: true);
      final preview = await _decodePreview(result['preview_png']);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _previewReady = preview != null;
        _photoMeasurement = valid ? result : null;
        _dbh = valid ? result : null;
        _baseConfirmed = false;
        _diameter.text = valid && result['needs_base_confirmation'] != true
            ? (result['dbh_cm'] as num).toStringAsFixed(1)
            : '';
        _dbhMessage = valid
            ? 'Experimental estimate - validate DBH against tape and height against a clinometer.'
            : result['reason']?.toString() ??
                'No reliable DBH. Retake or skip measurement.';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _dbhMessage = error is DioException &&
                error.response?.statusCode == 413
            ? 'Original photo exceeds the server upload limit (HTTP 413).'
            : 'DBH unavailable. Check the connection or take a new level photo.');
      }
    } finally {
      if (speciesWork != null) await speciesWork;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _predictGallery(File photo) async {
    try {
      final prediction = await (widget.predictGallerySize?.call(photo) ??
          api.predictGallerySize(photo));
      final preview = await _decodePreview(prediction['preview_png']);
      if (!mounted || _photo?.path != photo.path) return;
      setState(() {
        _galleryPrediction = prediction;
        _galleryTrunkPreview = preview;
      });
    } catch (_) {
      if (!mounted || _photo?.path != photo.path) return;
      setState(() => _galleryPrediction = {
            'status': 'unavailable',
            'reason':
                'Gallery size prediction unavailable. Check the connection or updated backend.'
          });
    }
  }

  String _predictionValue(String key, double maximum) {
    final p = _galleryPrediction;
    final value = p?[key];
    if (p?['status'] != 'predicted' ||
        p?['method'] != 'gallery_yolo_vision_prediction' ||
        p?['quality'] != 'unvalidated' ||
        p?['validated_accuracy'] != false ||
        p?['trunk_detected'] != true ||
        p?['fallback'] == true ||
        value is! num ||
        !value.isFinite ||
        value < 1 ||
        value > maximum) {
      return 'Unavailable';
    }
    return value.toStringAsFixed(0);
  }

  Future<void> _scan() => widget.advancedAr ? _scanAr() : _scanLevel();

  Future<void> _scanAr() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = 'Opening guided tree camera…';
    });
    try {
      final native = DbhArService();
      final support = await native.capabilities();
      if (!mounted) return;
      if (support['supported'] != true) {
        _message = support['reason']?.toString() ??
            'AR distance measurement unavailable.';
        await _speciesOnly();
        return;
      }
      // Do not gate camera capture on server readiness: height is local and
      // species identification can still work when the DBH server is missing.
      final capture = await native.scan(unified: true);
      if (!mounted) return;
      if (capture['status'] == 'cancelled') {
        setState(() => _message = 'Capture cancelled. No form fields changed.');
        return;
      }
      if (capture['species_image_base64'] == null) {
        _message = capture['reason']?.toString() ??
            'Automatic scale unavailable on this phone.';
        await _speciesOnly();
        return;
      }
      final encoded = capture['species_image_base64'];
      if (encoded is! String || encoded.isEmpty) {
        throw const FormatException('No upright species photo in scan.');
      }
      final directory = await getApplicationDocumentsDirectory();
      final photo = File(
          '${directory.path}/tree_scan_${DateTime.now().microsecondsSinceEpoch}.jpg');
      await photo.writeAsBytes(base64Decode(encoded), flush: true);
      if (!mounted) {
        await photo.delete();
        return;
      }
      await _replacePhoto(photo, owned: true);
      if (!mounted) return;
      final observation = capture['height_observation'];
      setState(() {
        _dbh = null;
        _diameter.clear();
        _dbhMessage = capture['image_base64'] == null
            ? 'Trunk measurement skipped.'
            : 'Processing trunk depth…';
        _height = observation is Map
            ? heightFromArObservation(Map<String, dynamic>.from(observation))
            : null;
        _treeHeight.text = _height?.toStringAsFixed(2) ?? '';
        _heightMessage = _height == null
            ? capture['height_reason']?.toString() ??
                'No valid height capture. Rescan when the crown is visible.'
            : 'AR distance + crown angle • experimental estimate';
        _message = 'Checking trunk measurement and identifying species…';
      });
      await Future.wait([
        if (capture['image_base64'] != null) _measure(capture),
        _identify(photo)
      ]);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _message = 'The guided scan could not finish. Retry the camera.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _photoAccepted => photoMeasurementAccepted(_photoMeasurement,
      baseConfirmed: _baseConfirmed);
  bool get _canUse =>
      !_busy &&
      (widget.advancedAr
          ? _hasReviewedValues
          : _photo != null && (_measurementSkipped || _photoAccepted));

  Future<void> _scanLevel() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = 'Opening camera.';
    });
    Future<void>? speciesWork;
    try {
      final capture = await Navigator.push<LevelPhotoCapture>(
          context,
          MaterialPageRoute(
              builder: (_) => LevelDbhCameraScreen(
                    onMeasureTrunk: (shot) async {
                      await _replacePhoto(shot.photo);
                      if (!mounted) throw StateError('Scan closed');
                      setState(() {
                        _photoMeasurement = null;
                        _dbh = null;
                        _height = null;
                        _heightResult = null;
                        _baseConfirmed = false;
                        _measurementSkipped = false;
                        _diameter.clear();
                        _treeHeight.clear();
                        _preview = null;
                        _previewReady = false;
                        _dbhMessage = 'Trunk capture not yet accepted.';
                        _heightMessage = 'Height has not been measured.';
                        _message = 'Identifying the captured photo.';
                      });
                      speciesWork = _identify(shot.photo);
                      return api.measureDbh(shot.photo,
                          referenceHint: 'Original level photo',
                          method: 'yolo_trunk_v1',
                          cameraHeightM: shot.cameraHeightMeters,
                          pitchDeg: shot.pitchDegrees,
                          focalPixels: shot.focalPixels);
                    },
                    onMeasureHeight:
                        (pitch, cameraHeight, distance, confirmed) =>
                            api.measureHeight(
                                pitchDeg: pitch,
                                cameraHeightM: cameraHeight,
                                distanceM: distance,
                                baseConfirmed: confirmed),
                  )));
      if (capture == null || !mounted) return;
      if (speciesWork == null) {
        await _replacePhoto(capture.photo);
        if (!mounted) return;
        speciesWork = _identify(capture.photo);
      }
      final dbh = capture.skipMeasurement ? null : capture.dbhResponse;
      final accepted =
          photoMeasurementAccepted(dbh, baseConfirmed: capture.baseConfirmed);
      final height =
          accepted && heightMeasurementAccepted(capture.heightResponse)
              ? capture.heightResponse
              : null;
      final preview = await _decodePreview(dbh?['preview_png']);
      if (!mounted) return;
      setState(() {
        _photoMeasurement = accepted ? dbh : null;
        _dbh = accepted ? dbh : null;
        _baseConfirmed = capture.baseConfirmed;
        _preview = preview;
        _previewReady = preview != null;
        _measurementSkipped = capture.skipMeasurement;
        _heightResult = height;
        _height =
            height == null ? null : (height['height_m'] as num).toDouble();
        _diameter.text =
            accepted ? (dbh!['dbh_cm'] as num).toStringAsFixed(1) : '';
        _treeHeight.text = _height?.toStringAsFixed(1) ?? '';
        _dbhMessage = capture.skipMeasurement
            ? 'Measurement skipped.'
            : accepted
                ? 'Experimental estimate - validate DBH against tape.'
                : capture.retakeReason ??
                    dbh?['reason']?.toString() ??
                    'No reliable DBH. Retake.';
        _heightMessage = height == null
            ? 'Height skipped; no height was measured.'
            : 'Experimental estimate, rounded to 0.5 m - validate against a clinometer.'
                '${height['quality'] == 'low' ? ' Low quality: steep angle.' : ''}';
      });
      await speciesWork;
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'Could not complete this scan. Retake or skip measurement.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Uint8List?> _decodePreview(Object? encoded) async {
    if (encoded is! String || encoded.isEmpty) return null;
    try {
      final bytes = base64Decode(encoded);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      frame.image.dispose();
      codec.dispose();
      return bytes;
    } catch (_) {
      return null;
    }
  }

  void _confirmBase() {
    if (!_previewReady || _busy || _photoMeasurement == null) return;
    setState(() {
      _baseConfirmed = true;
      _diameter.text = (_photoMeasurement!['dbh_cm'] as num).toStringAsFixed(1);
    });
  }

  void _skipAndSave() {
    if (_busy || _photo == null) return;
    setState(() {
      _measurementSkipped = true;
      _photoMeasurement = null;
      _dbh = null;
      _height = null;
      _heightResult = null;
      _diameter.clear();
      _treeHeight.clear();
    });
    _use(saveRequested: true);
  }

  Future<void> _measure(Map<String, dynamic> capture) async {
    try {
      final result = await api.measureDbhAr({
        'image_base64': capture['image_base64'],
        'capture': capture['capture'],
      });
      if (!mounted) return;
      setState(() {
        _dbh = acceptedAutomaticDbh(result) == null ? null : result;
        _diameter.text =
            _dbh == null ? '' : acceptedAutomaticDbh(_dbh!)!.toStringAsFixed(1);
        _dbhMessage = _dbh == null
            ? result['reason']?.toString() ??
                'Trunk measurement uncertain; rescan.'
            : 'Trunk depth estimate • experimental';
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _dbhMessage = switch (e.response?.statusCode) {
            401 => 'Session expired. Sign in again.',
            403 => 'This account cannot use the DBH measurement service.',
            404 => 'Automatic DBH is not deployed on this server yet.',
            _ =>
              'DBH service unavailable. Height and species can still be reviewed.',
          });
    } catch (_) {
      if (mounted) {
        setState(() =>
            _dbhMessage = 'DBH processing failed. No diameter was filled.');
      }
    }
  }

  Future<void> _identify(File photo) async {
    try {
      final result =
          await (widget.identifyPhoto?.call(photo) ?? api.identifyTree(photo));
      if (!mounted || _photo?.path != photo.path) return;
      final name = result['scientific_name']?.toString().trim() ?? '';
      setState(() {
        _species =
            result['not_identified'] != true && name.isNotEmpty ? result : null;
        _fillSpecies();
        _message = _species == null
            ? (result['reason']?.toString() ??
                'Species uncertain. Add a close leaf photo from this same tree.')
            : 'Species suggestion ready. Review the identity and measurements before use.';
      });
    } catch (error) {
      if (mounted && _photo?.path == photo.path) {
        setState(() => _message = identificationError(error));
      }
    }
  }

  /// A phone without metric tracking may identify species, but must not invent
  /// distance, diameter or height from an ordinary camera image.
  Future<void> _speciesOnly() async {
    if (!mounted) return;
    final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Automatic measurements unavailable'),
              content: Text(
                  '${_message ?? ''}\n\nYou can still photograph and identify the species. '
                  'DBH and height will remain unmeasured.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Capture species'))
              ],
            ));
    if (proceed != true || !mounted) return;
    await _leafCapture(resetMeasurements: true);
  }

  Future<void> _leafCapture({bool resetMeasurements = false}) async {
    final capture = await Navigator.push<GuidedTreeCapture>(context,
        MaterialPageRoute(builder: (_) => const GuidedTreeCameraScreen()));
    if (capture == null || !mounted) return;
    if (resetMeasurements) {
      _dbh = null;
      _height = null;
      _heightResult = null;
      _diameter.clear();
      _treeHeight.clear();
      _dbhMessage = 'No metric depth available on this phone.';
      _heightMessage = 'No tracked distance available on this phone.';
    }
    await _replacePhoto(capture.photo);
    if (!mounted) return;
    setState(() => _message = 'Identifying the captured photo…');
    await _identify(capture.photo);
  }

  Future<void> _leaf() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _leafCapture();
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Could not capture the leaf photo. Retry.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retryIdentification() async {
    final photo = _photo;
    if (_busy || photo == null) return;
    setState(() => _busy = true);
    try {
      await _identify(photo);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _use({bool saveRequested = false}) {
    if (!_canUse || !(_form.currentState?.validate() ?? false)) return;
    final result = TreeScanResult(
      species: _species,
      dbh: _dbh,
      heightMeters: _height,
      heightResult: _measurementSkipped ? null : _heightResult,
      photo: _photo,
      reviewedCommonName: _common.text.trim(),
      reviewedScientificName: _scientific.text.trim(),
      reviewedDbhCm:
          _measurementSkipped ? null : double.tryParse(_diameter.text.trim()),
      reviewedHeightMeters:
          _measurementSkipped ? null : double.tryParse(_treeHeight.text.trim()),
      measurementSkipped: _measurementSkipped,
      saveRequested: saveRequested && widget.onUse == null,
    );
    if (!result.hasResults) return;
    _keepingPhoto = true;
    if (widget.onUse != null) {
      widget.onUse!(result);
    } else {
      Navigator.pop(context, result);
    }
  }

  String? _measurement(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final value = double.tryParse(text.trim());
    return value == null || !value.isFinite || value <= 0
        ? 'Enter a positive number or leave empty'
        : null;
  }

  @override
  void dispose() {
    if (_ownsPhoto && !_keepingPhoto && _photo != null) {
      _photo!.delete().catchError((Object _) => _photo!);
    }
    _common.dispose();
    _scientific.dispose();
    _diameter.dispose();
    _treeHeight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
            title:
                Text(widget.advancedAr ? 'Advanced (AR)' : 'Review Tree Scan')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Review your tree',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'Results fill automatically. Check or correct them before continuing.'),
          const SizedBox(height: 16),
          if (_photo != null)
            ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(_photo!, height: 200, fit: BoxFit.cover)),
          if (_galleryPrediction != null)
            Card(
              key: const Key('gallery-size-prediction'),
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('AI-predicted size',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const Text(
                            'Unvalidated prediction; may be inaccurate.'),
                        if (_galleryTrunkPreview != null)
                          Image.memory(_galleryTrunkPreview!,
                              height: 180, fit: BoxFit.contain),
                        Text(
                            'Predicted DBH (cm): ${_predictionValue('predicted_dbh_cm', 300)}'),
                        Text(
                            'Predicted height (m): ${_predictionValue('predicted_height_m', 80)}'),
                        if (_galleryPrediction?['assumptions'] is List)
                          ...(_galleryPrediction!['assumptions'] as List)
                              .whereType<String>()
                              .take(2)
                              .map((assumption) => Text(assumption)),
                        Text(_galleryPrediction?['reason']?.toString() ??
                            'No size prediction.'),
                        const Text(
                            'Trunk detection provides pixels, not physical scale. '
                            'Experimental estimates: validate DBH against tape and height against a clinometer. '
                            'Predictions are not saved as measurements or used for carbon calculations.'),
                      ])),
            ),
          if (_preview != null) ...[
            const SizedBox(height: 12),
            Image.memory(_preview!, fit: BoxFit.contain),
          ],
          if (!widget.advancedAr &&
              _photoMeasurement?['needs_base_confirmation'] == true &&
              !_baseConfirmed) ...[
            const SizedBox(height: 12),
            const Text('Is the green line at the bottom of the tree?'),
            Row(children: [
              Expanded(
                  child: ElevatedButton(
                      key: const Key('confirm-photo-base'),
                      onPressed: _busy || !_previewReady ? null : _confirmBase,
                      child: const Text('Yes'))),
              const SizedBox(width: 12),
              Expanded(
                  child: OutlinedButton(
                      onPressed: _busy ? null : _scan,
                      child: const Text('Retake'))),
            ]),
          ],
          Form(
              key: _form,
              child: Column(children: [
                const SizedBox(height: 16),
                TextFormField(
                    key: const Key('scan-common-name'),
                    controller: _common,
                    readOnly: _busy,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                        labelText: 'Common name',
                        hintText:
                            _busy ? 'Identifying…' : 'Needs identification',
                        helperText: _species == null
                            ? 'Add a closer leaf photo if needed'
                            : 'Filled by AI - review or correct')),
                const SizedBox(height: 12),
                TextFormField(
                    key: const Key('scan-scientific-name'),
                    controller: _scientific,
                    readOnly: _busy,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                        labelText: 'Scientific name',
                        hintText: 'Needs identification')),
                const SizedBox(height: 16),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                      child: TextFormField(
                          key: const Key('scan-dbh'),
                          controller: _diameter,
                          readOnly: _busy || !widget.advancedAr,
                          onChanged: (_) => setState(() {}),
                          validator: _measurement,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                              labelText: 'DBH (cm)', hintText: 'Unavailable'))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: TextFormField(
                          key: const Key('scan-height'),
                          controller: _treeHeight,
                          readOnly: _busy || !widget.advancedAr,
                          onChanged: (_) => setState(() {}),
                          validator: _measurement,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                              labelText: 'Height (m)',
                              hintText: 'Unavailable'))),
                ]),
              ])),
          if (_dbhMessage != null)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('DBH: $_dbhMessage',
                    style: Theme.of(context).textTheme.bodySmall)),
          if (_heightMessage != null)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Height: $_heightMessage',
                    style: Theme.of(context).textTheme.bodySmall)),
          if (_message != null)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Semantics(liveRegion: true, child: Text(_message!))),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 12),
          if (!_busy) ...[
            OutlinedButton.icon(
                onPressed: _scan,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Rescan tree')),
            if (_photo != null) ...[
              OutlinedButton.icon(
                  onPressed: _leaf,
                  icon: const Icon(Icons.eco_outlined),
                  label: const Text('Add closer leaf photo')),
              if (_species == null)
                TextButton(
                    onPressed: _retryIdentification,
                    child: const Text('Retry identification with this photo')),
            ],
          ],
          if (!widget.advancedAr && _photo != null)
            TextButton(
                key: const Key('skip-result-measurement'),
                onPressed: _busy ? null : _skipAndSave,
                child: const Text(
                    'Skip measurement and save without DBH or height')),
          const SizedBox(height: 12),
          Text(widget.advancedAr
              ? 'Use results fills the form and replaces available fields. Empty measurements keep existing form values. Save the tree on the next screen.'
              : 'Check the species suggestion and experimental DBH estimate before using them. Skip measurement to save without DBH or height.'),
          ElevatedButton.icon(
              key: const Key('use-tree-scan'),
              onPressed: _canUse
                  ? () => _use(saveRequested: _measurementSkipped)
                  : null,
              icon: const Icon(Icons.check),
              label: Text(_measurementSkipped
                  ? (widget.onUse == null
                      ? 'Save without measurements'
                      : 'Skip measurement')
                  : 'Use reviewed results')),
        ]),
      ));
}
