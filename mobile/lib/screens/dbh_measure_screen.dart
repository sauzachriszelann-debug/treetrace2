import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../services/theme.dart';

// Result returned to AddTreeScreen
class DBHResult {
  final double dbhCm;
  final double? heightM;
  final String confidence;
  final String method;
  final String notes;
  final bool fallback;
  final bool segmentationUsed;
  final double measurementHeightM;
  final String? accuracyNote;
  DBHResult({
    required this.dbhCm,
    this.heightM,
    required this.confidence,
    required this.method,
    required this.notes,
    this.fallback = false,
    this.segmentationUsed = false,
    this.measurementHeightM = 1.3,
    this.accuracyNote,
  });
}

// ── Reference objects ─────────────────────────────────────────────────────────
class _RefObject {
  final String emoji, name, description, geminiHint;
  const _RefObject(this.emoji, this.name, this.description, this.geminiHint);
}

const _references = [
  _RefObject('📱', 'Smartphone', 'Width ~7cm, Height ~15cm',
      'a smartphone (approx 7cm wide, 15cm tall) is visible next to the trunk'),
  _RefObject('✋', 'Open Hand/Palm', 'Width ~18cm when spread',
      'an open human hand/palm (approx 18cm wide when spread) is visible next to the trunk'),
  _RefObject('💳', 'ID / ATM Card', '8.5cm × 5.4cm',
      'a standard ID or ATM card (8.5cm wide, 5.4cm tall) is visible next to the trunk'),
  _RefObject('📄', 'A4 Paper', '21cm × 29.7cm',
      'an A4 sheet of paper (21cm wide, 29.7cm tall) is visible next to the trunk'),
  _RefObject('💰', '₱5 Coin', 'Diameter 2.7cm',
      'a Philippine ₱5 coin (2.7cm diameter) is visible next to the trunk'),
  _RefObject('💰', '₱1 Coin', 'Diameter 2.4cm',
      'a Philippine ₱1 coin (2.4cm diameter) is visible next to the trunk'),
  _RefObject('📏', 'Ruler / Tape', 'Known measurements visible',
      'a ruler or measuring tape with visible markings is placed next to the trunk'),
  _RefObject('👟', 'Shoe / Boot', 'Length ~28cm',
      'a standard shoe or boot (approx 28cm long) is visible next to the trunk'),
  _RefObject('🧴', 'Water Bottle (500ml)', 'Diameter ~6.5cm',
      'a standard 500ml water bottle (approx 6.5cm diameter) is visible next to the trunk'),
  _RefObject('🌍', 'Ground Only', 'No reference — uses ground & distance',
      'no reference object is present. Use ground perspective, camera height (~1.5m when held normally), and visible surroundings to estimate distance from tree'),
];

// ── Main Screen ───────────────────────────────────────────────────────────────
class DBHMeasureScreen extends StatefulWidget {
  final File? initialPhoto;

  const DBHMeasureScreen({super.key, this.initialPhoto});

  @override
  State<DBHMeasureScreen> createState() => _DBHMeasureScreenState();
}

class _DBHMeasureScreenState extends State<DBHMeasureScreen> {
  int _step = 0; // 0=choose method, 1=choose reference, 2=take photo, 3=result
  bool _quickMode = false;
  _RefObject? _selectedRef;
  File? _photo;
  bool _analyzing = false;
  DBHResult? _result;
  String? _error;
  final _distanceCtrl = TextEditingController();
  final _circumferenceCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _photo = widget.initialPhoto;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: const Text('Measure DBH'),
        backgroundColor: kSidebarBg,
        foregroundColor: Colors.white,
        actions: [
          if (_step > 0)
            TextButton(
              onPressed: () => setState(() {
                _step = 0; _photo = null; _result = null; _error = null;
              }),
              child: const Text('Restart', style: TextStyle(color: Colors.white70)),
            ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _buildStep(),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0: return _buildChooseMethod();
      case 1: return _buildChooseReference();
      case 2: return _buildTakePhoto();
      case 3: return _buildResult();
      default: return _buildChooseMethod();
    }
  }

  // ── Step 0: Choose Method ──────────────────────────────────────────────────
  Widget _buildChooseMethod() => SingleChildScrollView(
    key: const ValueKey(0),
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('How would you like to measure?',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kForeground)),
      const SizedBox(height: 6),
      const Text('Choose the method that works best for your situation.',
          style: TextStyle(color: kMutedFg, fontSize: 13)),
      const SizedBox(height: 24),

      // Quick photo card
      _MethodCard(
        icon: '🌳',
        title: 'Quick Photo',
        subtitle: 'Just take a photo of the tree',
        accuracy: '±20-30 cm accuracy',
        accuracyColor: kFair,
        description: 'AI analyzes trunk thickness relative to surroundings, ground perspective, and estimates distance from camera to tree.',
        onTap: () => setState(() { _quickMode = true; _step = 2; }),
      ),
      const SizedBox(height: 12),

      // Reference object card
      _MethodCard(
        icon: '📏',
        title: 'With Reference Object',
        subtitle: 'Place an object next to the trunk',
        accuracy: '±5-15 cm accuracy',
        accuracyColor: kHealthy,
        description: 'Place any known-size object next to the tree trunk for scale. AI uses it as a reference for much more accurate measurement.',
        badge: 'MORE ACCURATE',
        onTap: () => setState(() { _quickMode = false; _step = 1; }),
      ),
      const SizedBox(height: 12),
      _MethodCard(
        icon: '📐',
        title: 'Manual Circumference',
        subtitle: 'Use tape measure at 1.3m height',
        accuracy: 'Most accurate field method',
        accuracyColor: kHealthy,
        description: 'Enter trunk circumference in centimeters. The app calculates DBH using DBH = circumference / pi.',
        badge: 'BEST',
        onTap: _showManualCalculator,
      ),
      const SizedBox(height: 24),

      // Tips
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: kPrimary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kPrimary.withOpacity(0.2))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.lightbulb_outline, color: kPrimary, size: 16),
            SizedBox(width: 6),
            Text('Tips for best results', style: TextStyle(
                color: kPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
          const SizedBox(height: 8),
          ...[
            '📍 Measure at breast height (1.3m from ground)',
            '☀️ Take photo in good lighting',
            '📐 Include the full trunk width in frame',
            '🚶 Stand 2-5 meters from the tree',
            '🌍 Include some ground in the photo',
          ].map((t) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(t, style: const TextStyle(color: kForeground, fontSize: 12)))),
        ]),
      ),
    ]),
  );

  // ── Step 1: Choose Reference ───────────────────────────────────────────────
  Widget _buildChooseReference() => Column(
    key: const ValueKey(1),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        color: kCard,
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Choose Reference Object',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kForeground)),
          SizedBox(height: 4),
          Text('Select what you\'ll place next to the tree trunk for scale.',
              style: TextStyle(color: kMutedFg, fontSize: 13)),
        ]),
      ),
      Expanded(child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _references.length,
        itemBuilder: (_, i) {
          final ref = _references[i];
          final selected = _selectedRef == ref;
          return GestureDetector(
            onTap: () => setState(() => _selectedRef = ref),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: selected ? kPrimary.withOpacity(0.08) : kCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: selected ? kPrimary : kBorder,
                      width: selected ? 2 : 1)),
              child: Row(children: [
                Text(ref.emoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ref.name, style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14,
                          color: selected ? kPrimary : kForeground)),
                      Text(ref.description, style: const TextStyle(
                          color: kMutedFg, fontSize: 12)),
                    ])),
                if (selected)
                  const Icon(Icons.check_circle, color: kPrimary, size: 20),
              ]),
            ),
          );
        },
      )),
      Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(height: 46, child: ElevatedButton(
          onPressed: _selectedRef == null ? null : () => setState(() => _step = 2),
          child: const Text('Next — Take Photo'),
        )),
      ),
    ],
  );

  // ── Step 2: Take Photo ─────────────────────────────────────────────────────
  Widget _buildTakePhoto() => SingleChildScrollView(
    key: const ValueKey(2),
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Instructions
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: kSidebarBg,
            borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              _quickMode ? '📸 Quick Photo Instructions' : '📸 Photo Instructions',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          if (_quickMode) ...[
            _tip('Stand 2-5 meters from the tree'),
            _tip('Include the full trunk in the frame'),
            _tip('Include some ground at the base'),
            _tip('Take in good lighting'),
          ] else ...[
            _tip('Place ${_selectedRef?.name} next to the trunk at 1.3m height'),
            _tip('Make sure the reference object is clearly visible'),
            _tip('Include the full trunk width in frame'),
            _tip('Stand back enough to see trunk + reference'),
          ],
        ]),
      ),
      const SizedBox(height: 16),

      if (widget.initialPhoto != null && _photo != null) ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kPrimary.withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kPrimary.withOpacity(0.22)),
          ),
          child: const Text(
            'Using the tree photo you already added. Retake only if the trunk or reference object is not clear.',
            style: TextStyle(color: kPrimary, fontSize: 12, height: 1.35),
          ),
        ),
        const SizedBox(height: 12),
      ],

      // Selected reference reminder
      if (!_quickMode && _selectedRef != null)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kPrimary.withOpacity(0.3))),
          child: Row(children: [
            Text(_selectedRef!.emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Using: ${_selectedRef!.name}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kPrimary)),
              Text(_selectedRef!.description,
                  style: const TextStyle(color: kMutedFg, fontSize: 11)),
            ])),
          ]),
        ),
      const SizedBox(height: 16),

      // Photo preview
      GestureDetector(
        onTap: _photo == null ? _takePhoto : null,
        child: Container(
          height: 280,
          decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _photo != null ? kPrimary : kBorder,
                  width: _photo != null ? 2 : 1)),
          child: _photo != null
              ? ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Stack(fit: StackFit.expand, children: [
                Image.file(_photo!, fit: BoxFit.cover, width: double.infinity),
                DBHMeasureOverlay(referenceName: _quickMode ? null : _selectedRef?.name),
              ]))
              : ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Stack(fit: StackFit.expand, children: [
                    Container(color: kSidebarBg.withOpacity(0.04)),
                    DBHMeasureOverlay(referenceName: _quickMode ? null : _selectedRef?.name),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: kCard.withOpacity(0.92),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: kBorder),
                        ),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.camera_alt_outlined, size: 38,
                              color: kPrimary.withOpacity(0.6)),
                          const SizedBox(height: 8),
                          const Text('Tap to take photo',
                              style: TextStyle(color: kForeground, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 3),
                          const Text('Align trunk with the DBH guide',
                              style: TextStyle(color: kMutedFg, fontSize: 11)),
                        ]),
                      ),
                    ),
                  ]),
                ),
        ),
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kPrimary.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kPrimary.withOpacity(0.16)),
        ),
        child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.straighten, color: kPrimary, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Use the guide like an AR tape: keep the ground line at the tree base, align the trunk in the center, and place the reference object on the 1.3m DBH line.',
              style: TextStyle(color: kForeground, fontSize: 12, height: 1.35),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 12),

      TextFormField(
        controller: _distanceCtrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'Distance from tree (optional, meters)',
          hintText: 'e.g., 3',
          prefixIcon: Icon(Icons.social_distance_outlined, size: 18, color: kMutedFg),
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'If you know roughly how far you stood from the trunk, enter it. This helps the camera estimate DBH from perspective.',
        style: TextStyle(color: kMutedFg, fontSize: 11, height: 1.35),
      ),
      const SizedBox(height: 12),

      // Camera/Gallery buttons
      Row(children: [
        Expanded(child: OutlinedButton.icon(
          onPressed: _takePhoto,
          icon: const Icon(Icons.camera_alt_outlined, size: 16),
          label: Text(_photo == null ? 'Camera' : 'Retake'),
        )),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(
          onPressed: _pickGallery,
          icon: const Icon(Icons.photo_library_outlined, size: 16),
          label: const Text('Gallery'),
        )),
      ]),
      const SizedBox(height: 16),

      // Analyze button
      SizedBox(height: 46, child: ElevatedButton(
        onPressed: _photo == null || _analyzing ? null : _analyze,
        child: _analyzing
            ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Analyzing…'),
        ])
            : const Text('Analyze & Estimate DBH'),
      )),

      if (_error != null) ...[
        const SizedBox(height: 12),
        Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: kPoor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kPoor.withOpacity(0.3))),
            child: Text(_error!, style: const TextStyle(color: kPoor, fontSize: 13))),
      ],
    ]),
  );

  // ── Step 3: Result ─────────────────────────────────────────────────────────
  Widget _buildResult() {
    final r = _result!;
    final isFallback = r.fallback || r.method.toLowerCase().contains('safe dbh');
    final confColor = isFallback ? kPoor : r.confidence == 'High' ? kHealthy
        : r.confidence == 'Medium' ? kFair : kPoor;
    final methodLabel = r.segmentationUsed
        ? 'YOLO Segmentation Used'
        : isFallback
            ? 'AI Measurement Unavailable'
            : 'AI Photo Estimate';

    return SingleChildScrollView(
      key: const ValueKey(3),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Photo thumbnail
        if (_photo != null)
          ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 180,
                child: Stack(fit: StackFit.expand, children: [
                  Image.file(_photo!, fit: BoxFit.cover, width: double.infinity),
                  DBHMeasureOverlay(
                    compact: true,
                    referenceName: _quickMode ? null : _selectedRef?.name,
                  ),
                ]),
              )),
        const SizedBox(height: 20),

        if (isFallback) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kPoor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kPoor.withOpacity(0.28)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: kPoor, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This is only a fallback estimate, not a measured DBH. Retake the photo with the trunk and a clear reference object, or use Manual Circumference for accurate records.',
                    style: TextStyle(
                      color: kPoor,
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Main result
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kBorder)),
          child: Column(children: [
            Text(
              isFallback ? 'Fallback DBH Estimate' : 'Estimated DBH',
              style: const TextStyle(color: kMutedFg, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text('${r.dbhCm.toStringAsFixed(1)} cm',
                style: const TextStyle(color: kForeground, fontSize: 48,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                    color: confColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: confColor.withOpacity(0.3))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                      r.confidence == 'High' ? Icons.check_circle
                          : r.confidence == 'Medium' ? Icons.info
                          : Icons.warning_amber,
                      color: confColor, size: 14),
                  const SizedBox(width: 6),
                  Text(isFallback ? 'Fallback Only' : '${r.confidence} Confidence',
                      style: TextStyle(color: confColor,
                          fontWeight: FontWeight.w700, fontSize: 13)),
                ])),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: (r.segmentationUsed ? kHealthy : kPrimary).withOpacity(0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                methodLabel,
                style: TextStyle(
                  color: r.segmentationUsed ? kHealthy : kPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            if (r.heightM != null) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.height, color: kMutedFg, size: 16),
                const SizedBox(width: 6),
                Text('Estimated Height: ${r.heightM!.toStringAsFixed(1)} m',
                    style: const TextStyle(color: kForeground,
                        fontWeight: FontWeight.w600, fontSize: 14)),
              ]),
            ],
            const SizedBox(height: 12),
            if (r.heightM == null) const Divider(),
            if (r.heightM == null) const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.vertical_align_bottom, color: kMutedFg, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'DBH point: ${r.measurementHeightM.toStringAsFixed(1)} m above ground',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: kForeground,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 12),

        // Method used
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: isFallback ? kPoor.withOpacity(0.05) : kPrimary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isFallback ? kPoor.withOpacity(0.18) : kPrimary.withOpacity(0.2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Method Used', style: TextStyle(
                color: isFallback ? kPoor : kPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 4),
            Text(r.method, style: const TextStyle(color: kForeground, fontSize: 13)),
            const SizedBox(height: 8),
            Text(isFallback ? 'What happened' : 'AI Analysis Notes', style: TextStyle(
                color: isFallback ? kPoor : kPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 4),
            Text(r.notes, style: const TextStyle(
                color: kForeground, fontSize: 12, height: 1.5)),
          ]),
        ),
        if (isFallback) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kPrimary.withOpacity(0.18)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'For YOLO DBH to work',
                  style: TextStyle(
                    color: kPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Use With Reference Object. The photo must show the trunk at breast height and a visible A4 paper, ID card, ruler, or phone beside the trunk. Avoid photos that show mostly leaves or canopy.',
                  style: TextStyle(color: kForeground, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),

        // Use this result button
        SizedBox(height: 46, child: ElevatedButton(
          onPressed: isFallback ? null : () => Navigator.pop(context, r),
          child: Text(isFallback ? 'Retake or Use Manual Measurement' : 'Use This Measurement'),
        )),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => setState(() {
            _step = 0; _photo = null; _result = null; _error = null;
          }),
          child: const Text('Try Again'),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────
  Future<void> _takePhoto() async {
    final file = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => DBHCameraScreen(
          referenceName: _quickMode ? null : _selectedRef?.name,
        ),
      ),
    );
    if (file != null) setState(() => _photo = file);
  }

  Future<void> _pickGallery() async {
    final x = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 85, maxWidth: 1400);
    if (x != null) setState(() => _photo = File(x.path));
  }

  Future<void> _analyze() async {
    if (_photo == null) return;
    setState(() { _analyzing = true; _error = null; });

    try {
      final refHint = _quickMode
          ? 'No reference object is present. Use ground perspective, visible surroundings, tree canopy size, and estimate camera distance. The camera was likely held at about 1.5m height.'
          : _selectedRef!.geminiHint;
      final knownDistance = double.tryParse(_distanceCtrl.text.trim());
      final method = _quickMode
          ? 'Quick photo with perspective and optional distance'
          : 'Reference object (${_selectedRef!.name}) with optional distance';
      final json = await api.measureDbh(
        _photo!,
        referenceHint: refHint,
        method: method,
        knownDistanceM: knownDistance,
      );

      final result = DBHResult(
        dbhCm: (json['dbh_cm'] as num).toDouble(),
        heightM: json['height_m'] != null ? (json['height_m'] as num).toDouble() : null,
        confidence: json['confidence'] ?? 'Low',
        method: json['method'] ?? method,
        fallback: json['fallback'] == true || json['error'] == true,
        segmentationUsed: json['segmentation_used'] == true,
        measurementHeightM: json['measurement_height_m'] is num
            ? (json['measurement_height_m'] as num).toDouble()
            : 1.3,
        accuracyNote: json['accuracy_note']?.toString(),
        notes: '${json['analysis_notes'] ?? 'AI visual estimation.'}\n'
            'Distance estimate: ${json['distance_estimate_m'] ?? 'unknown'} m. '
            '${json['accuracy_note'] ?? ''}',
      );

      setState(() { _result = result; _step = 3; });
    } catch (e) {
      setState(() => _error = 'Analysis failed. Check your connection and try again.\n$e');
    } finally {
      setState(() => _analyzing = false);
    }
  }

  void _showManualCalculator() {
    _circumferenceCtrl.clear();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Manual DBH Calculator'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Measure circumference at 1.3 meters from the ground, then enter the value.',
              style: TextStyle(fontSize: 13, color: kMutedFg),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _circumferenceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Circumference (cm)',
                prefixIcon: Icon(Icons.straighten),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final circumference = double.tryParse(_circumferenceCtrl.text.trim());
              if (circumference == null || circumference <= 0) return;
              Navigator.pop(context);
              setState(() {
                _result = DBHResult(
                  dbhCm: circumference / math.pi,
                  confidence: 'High',
                  method: 'Manual circumference measurement',
                  notes: 'Calculated using DBH = circumference / pi. This is the recommended field method.',
                  measurementHeightM: 1.3,
                  accuracyNote: 'High accuracy when circumference is measured with tape at 1.3 meters above ground.',
                );
                _step = 3;
              });
            },
            child: const Text('Calculate'),
          ),
        ],
      ),
    );
  }

  Widget _tip(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('• ', style: TextStyle(color: Colors.white70)),
        Expanded(child: Text(text,
            style: const TextStyle(color: Colors.white70, fontSize: 12))),
      ]));
}

// ── Method Card Widget ────────────────────────────────────────────────────────
class DBHMeasureOverlay extends StatelessWidget {
  final bool compact;
  final String? referenceName;

  const DBHMeasureOverlay({
    super.key,
    this.compact = false,
    this.referenceName,
  });

  @override
  Widget build(BuildContext context) {
    final labelSize = compact ? 9.0 : 11.0;
    return IgnorePointer(
      child: Stack(children: [
        Positioned.fill(
          child: CustomPaint(painter: _DBHGuidePainter(compact: compact)),
        ),
        Positioned(
          left: 14,
          bottom: compact ? 12 : 18,
          child: _overlayLabel('GROUND', Icons.horizontal_rule, labelSize),
        ),
        Positioned(
          right: 12,
          top: compact ? 44 : 70,
          child: _meterRail(compact),
        ),
        Positioned(
          left: 22,
          right: 54,
          top: compact ? 64 : 100,
          child: Row(children: [
            Expanded(
              child: Container(
                height: 1.5,
                decoration: BoxDecoration(
                  color: kFair,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 3,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            _pill('1.3m DBH', kFair, labelSize),
          ]),
        ),
        Positioned(
          left: 22,
          top: compact ? 24 : 34,
          child: _pill('Align trunk center', kPrimary, labelSize),
        ),
        Positioned(
          right: 54,
          top: compact ? 88 : 136,
          child: _pill(
            referenceName == null ? 'Scale object here' : '$referenceName here',
            kHealthy,
            labelSize,
          ),
        ),
      ]),
    );
  }

  static Widget _overlayLabel(String text, IconData icon, double fontSize) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.48),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withOpacity(0.18)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: fontSize + 2),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
            ),
          ),
        ]),
      );

  static Widget _pill(String text, Color color, double fontSize) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.9),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.22), blurRadius: 8),
          ],
        ),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
          ),
        ),
      );

  static Widget _meterRail(bool compact) => Container(
        width: compact ? 34 : 42,
        height: compact ? 120 : 178,
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF5CE2E).withOpacity(0.92),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black.withOpacity(0.18)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 10),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final mark in const ['2m', '1.5', '1m', '.5'])
              Text(
                mark,
                style: TextStyle(
                  color: Colors.black.withOpacity(0.72),
                  fontSize: compact ? 8 : 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
          ],
        ),
      );
}

class DBHCameraScreen extends StatefulWidget {
  final String? referenceName;

  const DBHCameraScreen({super.key, this.referenceName});

  @override
  State<DBHCameraScreen> createState() => _DBHCameraScreenState();
}

class _DBHCameraScreenState extends State<DBHCameraScreen> {
  CameraController? _controller;
  bool _loading = true;
  bool _capturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _setupCamera();
  }

  Future<void> _setupCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _error = 'No camera found on this device.';
          _loading = false;
        });
        return;
      }
      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Camera could not start. Please allow camera permission.';
        _loading = false;
      });
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      final shot = await controller.takePicture();
      if (!mounted) return;
      Navigator.pop(context, File(shot.path));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _capturing = false;
        _error = 'Could not capture photo. Try again.';
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        )
                      : controller == null
                          ? const SizedBox.shrink()
                          : Center(child: CameraPreview(controller)),
            ),
            Positioned.fill(
              child: DBHMeasureOverlay(referenceName: widget.referenceName),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: 14,
              child: Row(
                children: [
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withOpacity(0.48),
                    ),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.46),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        'Align trunk with the DBH guide',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 22,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.46),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'Put the tree base on GROUND and the reference object on the 1.3m DBH line.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 12, height: 1.25),
                    ),
                  ),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: _capture,
                    child: Container(
                      width: 74,
                      height: 74,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: Center(
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: _capturing ? kMutedFg : Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: _capturing
                              ? const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    color: Colors.white,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DBHGuidePainter extends CustomPainter {
  final bool compact;

  _DBHGuidePainter({required this.compact});

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width * 0.50;
    final groundY = size.height * 0.84;
    final dbhY = size.height * (compact ? 0.42 : 0.39);
    final topY = size.height * 0.13;
    final bottomY = size.height * 0.92;

    final shade = Paint()..color = Colors.black.withOpacity(0.12);
    canvas.drawRect(Offset.zero & size, shade);

    final trunkPaint = Paint()
      ..color = Colors.white.withOpacity(0.82)
      ..strokeWidth = compact ? 1.4 : 1.8;
    canvas.drawLine(Offset(centerX, topY), Offset(centerX, bottomY), trunkPaint);

    final groundPaint = Paint()
      ..color = Colors.white.withOpacity(0.86)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(size.width * 0.08, groundY),
      Offset(size.width * 0.92, groundY),
      groundPaint,
    );

    final dbhPaint = Paint()
      ..color = kFair.withOpacity(0.94)
      ..strokeWidth = compact ? 2.2 : 2.8;
    canvas.drawLine(
      Offset(size.width * 0.12, dbhY),
      Offset(size.width * 0.82, dbhY),
      dbhPaint,
    );

    final guidePaint = Paint()
      ..color = kHealthy.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = compact ? 2 : 2.5;
    canvas.drawCircle(Offset(centerX, dbhY), compact ? 26 : 34, guidePaint);

    final refPaint = Paint()
      ..color = kHealthy.withOpacity(0.78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final refRect = Rect.fromCenter(
      center: Offset(size.width * 0.72, dbhY + (compact ? 24 : 34)),
      width: compact ? 38 : 52,
      height: compact ? 52 : 70,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(refRect, const Radius.circular(6)),
      refPaint,
    );

    final tickPaint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..strokeWidth = 1.2;
    final railX = size.width - (compact ? 29 : 35);
    final railTop = compact ? 50.0 : 78.0;
    final tickGap = compact ? 18.0 : 27.0;
    for (var i = 0; i < 7; i++) {
      final y = railTop + i * tickGap;
      final length = i.isEven ? 14.0 : 8.0;
      canvas.drawLine(Offset(railX, y), Offset(railX + length, y), tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DBHGuidePainter oldDelegate) =>
      oldDelegate.compact != compact;
}

class _MethodCard extends StatelessWidget {
  final String icon, title, subtitle, accuracy, description;
  final Color accuracyColor;
  final String? badge;
  final VoidCallback onTap;

  const _MethodCard({
    required this.icon, required this.title, required this.subtitle,
    required this.accuracy, required this.accuracyColor,
    required this.description, required this.onTap, this.badge,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(icon, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: kForeground),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: kHealthy.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: kHealthy.withOpacity(0.3))),
                    child: Text(badge!, style: TextStyle(
                        color: kHealthy, fontSize: 9, fontWeight: FontWeight.w800))),
              ],
            ]),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: kMutedFg, fontSize: 13),
            ),
          ])),
          const Icon(Icons.arrow_forward_ios, size: 14, color: kMutedFg),
        ]),
        const SizedBox(height: 10),
        Text(description, style: const TextStyle(
            color: kForeground, fontSize: 12, height: 1.4)),
        const SizedBox(height: 8),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: accuracyColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Text(accuracy, style: TextStyle(
                color: accuracyColor, fontSize: 11, fontWeight: FontWeight.w600))),
      ]),
    ),
  );
}
