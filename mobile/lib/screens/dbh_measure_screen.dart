import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../services/theme.dart';

// Result returned to AddTreeScreen
class DBHResult {
  final double dbhCm;
  final double? heightM;
  final String confidence;
  final String method;
  final String notes;
  DBHResult({
    required this.dbhCm,
    this.heightM,
    required this.confidence,
    required this.method,
    required this.notes,
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
  const DBHMeasureScreen({super.key});
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
          height: 220,
          decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _photo != null ? kPrimary : kBorder,
                  width: _photo != null ? 2 : 1)),
          child: _photo != null
              ? ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Image.file(_photo!, fit: BoxFit.cover,
                  width: double.infinity))
              : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.camera_alt_outlined, size: 48,
                color: kPrimary.withOpacity(0.4)),
            const SizedBox(height: 8),
            const Text('Tap to take photo',
                style: TextStyle(color: kMutedFg, fontWeight: FontWeight.w500)),
          ]),
        ),
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
    final confColor = r.confidence == 'High' ? kHealthy
        : r.confidence == 'Medium' ? kFair : kPoor;

    return SingleChildScrollView(
      key: const ValueKey(3),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Photo thumbnail
        if (_photo != null)
          ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(_photo!, height: 160, fit: BoxFit.cover,
                  width: double.infinity)),
        const SizedBox(height: 20),

        // Main result
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kBorder)),
          child: Column(children: [
            const Text('Estimated DBH', style: TextStyle(
                color: kMutedFg, fontSize: 13)),
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
                  Text('${r.confidence} Confidence',
                      style: TextStyle(color: confColor,
                          fontWeight: FontWeight.w700, fontSize: 13)),
                ])),
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
          ]),
        ),
        const SizedBox(height: 12),

        // Method used
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kPrimary.withOpacity(0.2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Method Used', style: TextStyle(
                color: kPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 4),
            Text(r.method, style: const TextStyle(color: kForeground, fontSize: 13)),
            const SizedBox(height: 8),
            const Text('AI Analysis Notes', style: TextStyle(
                color: kPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 4),
            Text(r.notes, style: const TextStyle(
                color: kForeground, fontSize: 12, height: 1.5)),
          ]),
        ),
        const SizedBox(height: 20),

        // Use this result button
        SizedBox(height: 46, child: ElevatedButton(
          onPressed: () => Navigator.pop(context, r),
          child: const Text('Use This Measurement'),
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
    final x = await ImagePicker().pickImage(
        source: ImageSource.camera, imageQuality: 85, maxWidth: 1400);
    if (x != null) setState(() => _photo = File(x.path));
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
      final bytes = await _photo!.readAsBytes();
      final b64 = base64Encode(bytes);

      final refHint = _quickMode
          ? 'No reference object is present. Use ground perspective, visible surroundings, tree canopy size, and estimate camera distance (~2-5m typical). The camera was likely held at ~1.5m height.'
          : _selectedRef!.geminiHint;

      final prompt = '''You are an expert forester and tree measurement specialist in the Philippines.

Analyze this photo and estimate the tree's DBH (Diameter at Breast Height, measured at 1.3m from ground).

Reference information: $refHint

Please analyze:
1. The trunk width relative to any visible reference objects or surroundings
2. Ground perspective to estimate distance from camera to tree
3. Camera height (typically 1.5m when held normally)
4. Any visible scale references (people, buildings, vehicles, vegetation)
5. Tree species characteristics to validate size estimate

Respond ONLY with valid JSON, no markdown:
{
  "dbh_cm": <number>,
  "height_m": <number or null>,
  "confidence": "Low" or "Medium" or "High",
  "method": "<brief description of measurement method used>",
  "analysis_notes": "<2-3 sentences explaining how you estimated the DBH>",
  "distance_estimate_m": <estimated distance from camera to tree in meters>
}''';

      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:generateContent?key=${_getGeminiKey()}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{
            'parts': [
              {'text': prompt},
              {
                'inline_data': {
                  'mime_type': 'image/jpeg',
                  'data': b64,
                }
              }
            ]
          }],
          'generationConfig': {'temperature': 0.2, 'maxOutputTokens': 500},
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('API error: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      var raw = data['candidates'][0]['content']['parts'][0]['text'] as String;
      raw = raw.replaceAll(RegExp(r'^```(?:json)?\s*', multiLine: true), '')
          .replaceAll(RegExp(r'\s*```\s*$', multiLine: true), '')
          .trim();

      final json = jsonDecode(raw);
      final result = DBHResult(
        dbhCm: (json['dbh_cm'] as num).toDouble(),
        heightM: json['height_m'] != null ? (json['height_m'] as num).toDouble() : null,
        confidence: json['confidence'] ?? 'Low',
        method: _quickMode
            ? 'Quick Photo — Ground perspective & visual analysis'
            : 'Reference Object (${_selectedRef!.name}) + Ground perspective',
        notes: json['analysis_notes'] ?? 'AI visual estimation.',
      );

      setState(() { _result = result; _step = 3; });
    } catch (e) {
      setState(() => _error = 'Analysis failed. Check your connection and try again.\n$e');
    } finally {
      setState(() => _analyzing = false);
    }
  }

  String _getGeminiKey() {
    // Read from same key used in api_service
    // You can also hardcode it here temporarily
    const key = String.fromEnvironment('GEMINI_KEY', defaultValue: '');
    return key.isNotEmpty ? key : 'AIzaSyCMmCjul5Y4nM9vyhT1LCRW4CNG9h0Ul3o';
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
            Row(children: [
              Text(title, style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 16, color: kForeground)),
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
            Text(subtitle, style: const TextStyle(color: kMutedFg, fontSize: 13)),
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
