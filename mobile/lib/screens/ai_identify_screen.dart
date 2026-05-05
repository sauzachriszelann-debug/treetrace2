import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../services/theme.dart';
import '../widgets/widgets.dart';
import 'add_tree_screen.dart';

class AIIdentifyScreen extends StatefulWidget {
  const AIIdentifyScreen({super.key});
  @override
  State<AIIdentifyScreen> createState() => _AIIdentifyScreenState();
}

class _AIIdentifyScreenState extends State<AIIdentifyScreen> {
  File? _photo;
  bool _identifying = false;
  Map<String, dynamic>? _result;

  Future<void> _pick(ImageSource source) async {
    final x = await ImagePicker().pickImage(
        source: source, imageQuality: 80, maxWidth: 1200);
    if (x == null) return;
    final f = File(x.path);
    setState(() { _photo = f; _result = null; });
    await _identify(f);
  }

  Future<void> _identify(File f) async {
    setState(() => _identifying = true);
    try {
      final r = await api.identifyTree(f);
      setState(() => _result = r);
    } catch (_) {
      setState(() => _result = {'not_identified': true,
        'reason': 'Identification failed. Please ensure you have an active internet connection.'});
    } finally {
      setState(() => _identifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notIdentified = _result?['not_identified'] == true;
    final confidence    = _result?['confidence'] as String?;
    final isProtected   = _result?['protected'] == true;

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: Text('AI Tree Scanner', 
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: kForeground,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Scanner UI / Photo Area ──────────────────────────────────────
            _buildPhotoArea(notIdentified, confidence),

            const SizedBox(height: 24),

            // ── Result Area ──────────────────────────────────────────────────
            if (_result != null && !notIdentified)
              _buildResultCard(isProtected, confidence)
            else if (notIdentified)
              _buildErrorCard()
            else if (!_identifying)
              _buildWelcomeState(),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoArea(bool notIdentified, String? confidence) {
    return GestureDetector(
      onTap: () => _showOptions(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 280,
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
          border: Border.all(
            color: _photo == null ? kPrimary.withOpacity(0.2) : kBorder,
            width: _photo == null ? 2 : 1,
            style: _photo == null ? BorderStyle.solid : BorderStyle.solid,
          ),
        ),
        child: _identifying
            ? _buildLoadingOverlay()
            : _photo != null
                ? _buildImagePreview(notIdentified, confidence)
                : _buildEmptyStatePrompt(),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 50, height: 50,
          child: CircularProgressIndicator(strokeWidth: 3, color: kPrimary),
        ),
        const SizedBox(height: 20),
        Text('Analyzing Species...',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16)),
        const SizedBox(height: 6),
        Text('Checking global botanical databases',
            style: TextStyle(color: kMutedFg, fontSize: 13)),
      ],
    );
  }

  Widget _buildImagePreview(bool notIdentified, String? confidence) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Image.file(_photo!, fit: BoxFit.cover),
        ),
        if (_result != null && !notIdentified)
          Positioned(
            top: 16, right: 16,
            child: HealthBadge(confidence ?? 'High Match', color: kHealthy),
          ),
        Positioned(
          bottom: 16, left: 0, right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Text('Change Photo', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyStatePrompt() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: kPrimary.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.camera_enhance_rounded, size: 48, color: kPrimary),
        ),
        const SizedBox(height: 20),
        Text('Scan a Tree',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18)),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'Take a clear photo of leaves or bark to identify the species instantly.',
            textAlign: TextAlign.center,
            style: TextStyle(color: kMutedFg, fontSize: 13, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _buildResultCard(bool isProtected, String? confidence) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_result!['common_name'] ?? 'Unknown Species',
                            style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(_result!['scientific_name'] ?? '',
                            style: GoogleFonts.inter(fontSize: 14, fontStyle: FontStyle.italic, color: kMutedFg)),
                      ],
                    ),
                  ),
                  if (isProtected)
                    const Icon(Icons.verified_user_rounded, color: Colors.orange, size: 28),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(height: 1),
              ),
              _buildQuickInfoGrid(),
              const SizedBox(height: 20),
              Text('Description', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 8),
              Text(
                _result!['description'] ?? 'No description available for this species.',
                style: TextStyle(color: kForeground.withOpacity(0.8), height: 1.5, fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddTreeScreen(aiResult: _result))),
            icon: const Icon(Icons.add_location_alt_rounded),
            label: const Text('Add to Inventory', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickInfoGrid() {
    return Row(
      children: [
        _InfoPill(Icons.straighten, 'DBH', '${_result!['estimated_dbh_cm'] ?? '--'} cm'),
        const SizedBox(width: 12),
        _InfoPill(Icons.height, 'Height', '${_result!['estimated_height_m'] ?? '--'} m'),
        const SizedBox(width: 12),
        _InfoPill(Icons.category_outlined, 'Family', _result!['family']?.split(' ').last ?? 'N/A'),
      ],
    );
  }

  Widget _buildWelcomeState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Capabilities', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 16),
        _buildCapabilityItem(Icons.auto_awesome, 'Instant Identification', 'Powered by Claude 3.5 Vision AI'),
        _buildCapabilityItem(Icons.security, 'DENR Status Check', 'Real-time endangered species verification'),
        _buildCapabilityItem(Icons.architecture, 'Measurement Estimation', 'AI-driven DBH and height calculation'),
      ],
    );
  }

  Widget _buildCapabilityItem(IconData icon, String title, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: kPrimary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: kPrimary, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: kMutedFg, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.red.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.red.withOpacity(0.2))),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 40),
          const SizedBox(height: 12),
          Text('Identification Failed', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.red)),
          const SizedBox(height: 8),
          Text(_result?['reason'] ?? '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.black54)),
        ],
      ),
    );
  }

  void _showOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            Text('Select Source', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _SourceButton(Icons.camera_alt_rounded, 'Camera', () { Navigator.pop(context); _pick(ImageSource.camera); }),
                _SourceButton(Icons.photo_library_rounded, 'Gallery', () { Navigator.pop(context); _pick(ImageSource.gallery); }),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoPill(this.icon, this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: kBackground, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
        child: Column(
          children: [
            Icon(icon, size: 16, color: kPrimary),
            const SizedBox(height: 6),
            Text(value, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
            Text(label, style: TextStyle(color: kMutedFg, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _SourceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SourceButton(this.icon, this.label, this.onTap);
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(color: kPrimary.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: kPrimary, size: 32),
          ),
          const SizedBox(height: 12),
          Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
