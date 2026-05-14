import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../services/auth_provider.dart';
import '../services/api_service.dart';
import '../services/theme.dart';
import '../widgets/widgets.dart';
import 'add_tree_screen.dart';
import 'upgrade_screen.dart';

class AIIdentifyScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const AIIdentifyScreen({super.key, this.onBack});
  @override
  State<AIIdentifyScreen> createState() => _AIIdentifyScreenState();
}

class _AIIdentifyScreenState extends State<AIIdentifyScreen> {
  File? _photo;
  bool _identifying = false;
  Map<String, dynamic>? _result;
  Map<String, dynamic>? _usage;

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  Future<void> _loadUsage() async {
    try {
      final usage = await api.getAiUsage();
      if (mounted) setState(() => _usage = usage);
    } catch (_) {
      // Usage badges are helpful, but scanning should still work if this call fails.
    }
  }

  Map<String, dynamic>? get _aiUsage =>
      _usage?['ai'] is Map ? Map<String, dynamic>.from(_usage!['ai']) : null;

  Map<String, dynamic>? get _unknownUsage =>
      _usage?['unknown'] is Map ? Map<String, dynamic>.from(_usage!['unknown']) : null;

  void _incrementUsage(String key) {
    final current = _usage;
    if (current == null || current[key] is! Map) return;
    final bucket = Map<String, dynamic>.from(current[key]);
    if (bucket['unlimited'] == true) return;
    final used = (bucket['used_today'] as num?)?.toInt() ?? 0;
    final limit = (bucket['daily_limit'] as num?)?.toInt();
    bucket['used_today'] = used + 1;
    if (limit != null) {
      bucket['remaining'] = (limit - used - 1).clamp(0, limit);
    }
    setState(() => _usage = {...current, key: bucket});
  }

  Future<void> _pick(ImageSource source) async {
    final x = await ImagePicker().pickImage(
        source: source, imageQuality: 68, maxWidth: 900);
    if (x == null) return;
    final f = File(x.path);
    setState(() {
      _photo = f;
      _result = null;
      _identifying = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await _identify(f, markLoading: false);
  }

  Future<void> _identify(File f, {bool markLoading = true}) async {
    if (markLoading) {
      setState(() {
        _photo ??= f;
        _identifying = true;
      });
    }
    try {
      final r = await api.identifyTree(f);
      _incrementUsage('ai');
      setState(() => _result = r);
    } catch (e) {
      debugPrint('AI identify failed: $e');
      final isLimit = e is DioException && e.response?.statusCode == 402;
      if (e is DioException) {
        debugPrint('AI identify status: ${e.response?.statusCode}');
        debugPrint('AI identify response: ${e.response?.data}');
        debugPrint('AI identify type: ${e.type}');
        debugPrint('AI identify message: ${e.message}');
      }
      final responseData = e is DioException ? e.response?.data : null;
      final detail = responseData is Map ? responseData['detail'] : null;
      final statusCode = e is DioException ? e.response?.statusCode : null;
      final errorType = e is DioException ? e.type : null;
      final errorText = detail?.toString();
      final fallbackReason = errorType == DioExceptionType.connectionTimeout ||
              errorType == DioExceptionType.receiveTimeout ||
              errorType == DioExceptionType.sendTimeout
          ? 'AI identification is taking too long. Render or the AI service may still be waking up. Please try again in a moment.'
          : errorType == DioExceptionType.connectionError
              ? 'AI identification could not connect to the backend. Check internet connection or wake Render.'
              : 'AI identification could not connect. Please check internet connection, or submit this photo for expert review.';
      setState(() => _result = {
        'not_identified': true,
        'limit_reached': isLimit,
        'reason': isLimit
            ? detail ?? 'Free AI limit reached. Upgrade to Pro for unlimited scans.'
            : errorText != null && errorText.isNotEmpty
                ? errorText
                : statusCode != null
                    ? 'AI identification service returned error $statusCode. You can still submit this photo for expert review.'
                    : fallbackReason
      });
    } finally {
      setState(() => _identifying = false);
    }
  }

  Future<void> _submitUnknown() async {
    if (_photo == null) return;
    setState(() => _identifying = true);
    try {
      final payload = {
        'photo_url': '',
        'possible_name': _result?['common_name'],
        'submitter_notes': _result?['reason'] ?? 'Submitted from mobile AI scanner',
        'ai_candidates': _result?['possible_candidates'] ?? [],
      };

      if (await api.isOnline()) {
        payload['photo_url'] = await api.uploadPhoto(_photo!) ?? '';
        await api.submitUnknownSpecies(payload);
        _incrementUsage('unknown');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Submitted for expert review.'),
              backgroundColor: kHealthy));
        }
      } else {
        await api.queueOfflineAction('SUBMIT_UNKNOWN', payload, photoPath: _photo!.path);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Saved offline. Unknown species will sync later.'),
              backgroundColor: kHealthy));
        }
      }
    } catch (e) {
      if (mounted) {
        final isLimit = e is DioException && e.response?.statusCode == 402;
        final responseData = e is DioException ? e.response?.data : null;
        final detail = responseData is Map ? responseData['detail'] : null;
        if (isLimit) {
          setState(() => _result = {
                ...?_result,
                'unknown_limit_reached': true,
                'unknown_limit_reason': detail ??
                    'Unknown species submission limit reached. Upgrade for higher daily access.',
              });
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(isLimit
                ? (detail?.toString() ?? 'Unknown species submission limit reached.')
                : 'Submission failed: $e'),
            backgroundColor: kPoor));
      }
    } finally {
      if (mounted) setState(() => _identifying = false);
    }
  }

  void _handleBack() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.maybePop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notIdentified = _result?['not_identified'] == true;
    final hasPartialResult = notIdentified &&
        ((_result?['common_name']?.toString().trim().isNotEmpty ?? false) ||
            (_result?['scientific_name']?.toString().trim().isNotEmpty ??
                false) ||
            (_result?['partial'] == true));
    final confidence    = _result?['confidence'] as String?;
    final isProtected   = _result?['protected'] == true;
    final isCitizen     = context.watch<AuthProvider>().user?.role == 'citizen';

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _handleBack,
        ),
        title: Text(
          'AI Tree Scanner',
          style: GoogleFonts.inter(
            color: kForeground,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: kForeground,
        iconTheme: const IconThemeData(color: kForeground),
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 140),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildUsageStrip(),
            const SizedBox(height: 12),
            // ── Scanner UI / Photo Area ──────────────────────────────────────
            _buildPhotoArea(notIdentified, confidence),

            const SizedBox(height: 24),

            // ── Result Area ──────────────────────────────────────────────────
            if (_result != null && (!notIdentified || hasPartialResult))
              _buildResultCard(isProtected, confidence, isCitizen)
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
        child: _identifying && _photo != null
            ? _buildAnalyzingImagePreview()
            : _identifying
                ? _buildLoadingOverlay()
                : _photo != null
                    ? _buildImagePreview(notIdentified, confidence)
                    : _buildEmptyStatePrompt(),
      ),
    );
  }

  Widget _buildUsageStrip() {
    return Row(
      children: [
        Expanded(
          child: _UsagePanel(
            icon: Icons.auto_awesome,
            title: 'AI Scan',
            usage: _aiUsage,
            fallback: 'Loading',
            onTap: () => showUpgradeSheet(context),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _UsagePanel(
            icon: Icons.science_outlined,
            title: 'Expert Review',
            usage: _unknownUsage,
            fallback: 'Loading',
            onTap: () => showUpgradeSheet(context),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingOverlay() {
    if (_photo != null) {
      return _buildAnalyzingImagePreview();
    }

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

  Widget _buildAnalyzingImagePreview() {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Image.file(_photo!, fit: BoxFit.cover),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Container(color: Colors.black.withOpacity(0.28)),
        ),
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 42),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.36),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.22)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 38,
                  height: 38,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Analyzing Species...',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Checking botanical and conservation data',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.82),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
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
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            color: kPrimary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: kPrimary.withOpacity(0.28),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.camera_alt_rounded, size: 44, color: Colors.white),
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

  Widget _buildResultCard(bool isProtected, String? confidence, bool isCitizen) {
    final partial = _result?['not_identified'] == true || _result?['partial'] == true;
    final commonName = _textValue('common_name', fallback: 'Unknown Species');
    final scientificName = _textValue('scientific_name', fallback: '');
    final status = _textValue('endangered_status', fallback: 'Not Listed');
    final family = _textValue('family', fallback: 'Unknown');
    final habitat = _textValue('habitat', fallback: 'Philippines / Southeast Asia');
    final description = _textValue('description',
        fallback: 'No description is available yet for this species.');
    final features = _textValue('distinguishing_features',
        fallback: 'Leaf form, bark texture, branching pattern, flowers, and fruit are used for identification.');
    final lookAlikes = _textValue('look_alikes',
        fallback: 'No look-alike species were returned by the AI.');
    final uses = _textValue('uses',
        fallback: 'Provides shade, habitat value, carbon storage, and ecological benefits.');

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: kSidebarBg,
            borderRadius: BorderRadius.circular(22),
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
                        Text(commonName,
                            style: GoogleFonts.inter(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Colors.white)),
                        const SizedBox(height: 4),
                        Text(scientificName,
                            style: GoogleFonts.inter(
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                                color: kSidebarText)),
                      ],
                    ),
                  ),
                  if (isProtected)
                    const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 30),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MiniBadge(Icons.auto_awesome, confidence ?? 'AI Match'),
                  _MiniBadge(Icons.shield_outlined, status),
                  _MiniBadge(Icons.category_outlined, family),
                ],
              ),
              if (isProtected) ...[
                const SizedBox(height: 16),
                _buildCuttingWarning(),
              ],
              if (partial) ...[
                const SizedBox(height: 16),
                _buildPartialIdentificationNotice(),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildQuickInfoGrid(),
        const SizedBox(height: 16),
        _buildEncyclopediaSection(
          title: 'Overview',
          icon: Icons.menu_book_outlined,
          child: Text(description,
              style: TextStyle(
                  color: kForeground.withOpacity(0.82),
                  height: 1.5,
                  fontSize: 14)),
        ),
        const SizedBox(height: 12),
        _buildEncyclopediaSection(
          title: 'Basic Info',
          icon: Icons.info_outline,
          child: Column(
            children: [
              _InfoRow('Scientific Name', scientificName.isEmpty ? 'Unknown' : scientificName),
              _InfoRow('Family', family),
              _InfoRow('Habitat', habitat),
              _InfoRow('Conservation Status', status),
              _InfoRow('Cutting Rule',
                  _result?['cutting_allowed'] == true ? 'Permit required if regulated' : 'Do not cut'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildEncyclopediaSection(
          title: 'Characteristics',
          icon: Icons.local_florist_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow('Diagnostic Features', features),
              _InfoRow('Look-alikes', lookAlikes),
              _InfoRow('DBH Method',
                  _textValue('dbh_method', fallback: 'Photo-based visual estimate only')),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildEncyclopediaSection(
          title: 'Care Profile',
          icon: Icons.spa_outlined,
          child: Column(
            children: const [
              _CareTile(Icons.wb_sunny_outlined, 'Sunlight', 'Full sun to partial shade'),
              _CareTile(Icons.water_drop_outlined, 'Watering', 'Water young trees regularly; mature trees tolerate short dry periods'),
              _CareTile(Icons.grass_outlined, 'Soil', 'Well-draining loamy soil is preferred'),
              _CareTile(Icons.content_cut_outlined, 'Pruning', 'Remove dead, diseased, or crossing branches only'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildEncyclopediaSection(
          title: 'Uses & Ecological Value',
          icon: Icons.eco_outlined,
          child: Text(uses,
              style: TextStyle(
                  color: kForeground.withOpacity(0.82),
                  height: 1.5,
                  fontSize: 14)),
        ),
        const SizedBox(height: 20),
        if (_result?['unknown_limit_reached'] == true) ...[
          _buildUnknownLimitBanner(),
          const SizedBox(height: 12),
        ],
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: isCitizen
                ? _submitUnknown
                : () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddTreeScreen(aiResult: _result))),
            icon: Icon(isCitizen ? Icons.science_outlined : Icons.add_location_alt_rounded),
            label: Text(
              isCitizen ? 'Submit for Expert Review' : 'Add to Inventory',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        if (!isCitizen) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _submitUnknown,
              icon: const Icon(Icons.science_outlined),
              label: const Text('Submit for Expert Review'),
              style: OutlinedButton.styleFrom(
                foregroundColor: kPrimary,
                side: const BorderSide(color: kPrimary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPartialIdentificationNotice() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withOpacity(0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: Colors.orange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _result?['reason']?.toString() ??
                  'TreeTrace returned a partial AI result. Submit this photo for expert review if the species is uncertain.',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _textValue(String key, {required String fallback}) {
    final value = _result?[key];
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty || text.toLowerCase() == 'null' ? fallback : text;
  }

  Widget _buildEncyclopediaSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: kPrimary, size: 19),
              const SizedBox(width: 8),
              Text(title,
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildCuttingWarning() {
    final code = _result?['status_code'] ?? '';
    final status = _result?['endangered_status'] ?? 'Protected';
    final strictlyProhibited = _result?['cutting_allowed'] != true;
    final color = code == 'CR' ? Colors.red : Colors.orange;
    final title = code == 'CR'
        ? 'DO NOT CUT - Critically Endangered'
        : code == 'EN'
            ? 'Protected - Cutting Prohibited'
            : 'Protected Species Warning';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: color, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
              const SizedBox(height: 4),
              Text(
                'Listed as $status under DENR DAO 2017-11. Cutting or transporting is '
                '${strictlyProhibited ? 'strictly prohibited' : 'allowed only with proper permit'}.',
                style: const TextStyle(fontSize: 12, height: 1.35, color: kForeground),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildUnknownLimitBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.workspace_premium_outlined, color: Colors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Submission limit reached',
                  style: TextStyle(fontWeight: FontWeight.w800, color: kForeground)),
              const SizedBox(height: 4),
              Text(
                _result?['unknown_limit_reason']?.toString() ??
                    'Upgrade for higher unknown species submission limits.',
                style: const TextStyle(fontSize: 12, color: kMutedFg, height: 1.35),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => showUpgradeSheet(context),
                child: const Text('View Plans'),
              ),
            ]),
          ),
        ],
      ),
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
        _buildCapabilityItem(Icons.auto_awesome, 'Instant Identification', 'TreeTrace AI-assisted visual analysis'),
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
    final limitReached = _result?['limit_reached'] == true;
    final reason = _result?['reason']?.toString() ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.red.withOpacity(0.05), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.red.withOpacity(0.2))),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 34),
          const SizedBox(height: 10),
          Text(
            limitReached ? 'Daily Limit Reached' : 'Could Not Identify',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: Colors.red),
          ),
          const SizedBox(height: 8),
          Text(
            reason,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.black54, height: 1.35),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: limitReached
                  ? () => showUpgradeSheet(context)
                  : _photo == null
                      ? null
                      : _submitUnknown,
              icon: Icon(limitReached ? Icons.workspace_premium_outlined : Icons.upload_file),
              label: Text(limitReached ? 'View Pro Plans' : 'Submit Unknown Species'),
              style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
            ),
          ),
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

class _MiniBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MiniBadge(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: kSidebarPrimary, size: 14),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _UsagePanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final Map<String, dynamic>? usage;
  final String fallback;
  final VoidCallback onTap;

  const _UsagePanel({
    required this.icon,
    required this.title,
    required this.usage,
    required this.fallback,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final data = usage;
    final unlimited = data?['unlimited'] == true;
    final remaining = (data?['remaining'] as num?)?.toInt();
    final limit = (data?['daily_limit'] as num?)?.toInt();
    final isCritical = !unlimited && remaining != null && remaining <= 2;
    final color = isCritical ? Colors.orange : kPrimary;
    final value = data == null
        ? fallback
        : unlimited
            ? 'Unlimited'
            : remaining != null && limit != null
                ? '$remaining / $limit left'
                : fallback;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.22)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withOpacity(0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: kMutedFg,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
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

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(label,
                style: const TextStyle(
                    color: kMutedFg,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: kForeground,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.35)),
          ),
        ],
      ),
    );
  }
}

class _CareTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  const _CareTile(this.icon, this.title, this.description);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder.withOpacity(0.65)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: kPrimary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 3),
                Text(description,
                    style: const TextStyle(
                        color: kMutedFg, fontSize: 12, height: 1.3)),
              ],
            ),
          ),
        ],
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
