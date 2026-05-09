import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/api_service.dart';
import '../services/theme.dart';
import '../models/models.dart';
import '../widgets/widgets.dart';
import 'tree_detail_screen.dart';

class ScanQRScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const ScanQRScreen({super.key, this.onBack});
  @override
  State<ScanQRScreen> createState() => _ScanQRScreenState();
}

class _ScanQRScreenState extends State<ScanQRScreen> with SingleTickerProviderStateMixin {
  final _ctrl = MobileScannerController();
  bool _scanned = false;
  bool _loading = false;
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_scanned) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null) return;
    setState(() => _scanned = true);
    _ctrl.stop();

    // Regex to extract tree ID from URL format: .../tree/ID or .../public/tree/ID
    final regex = RegExp(r'/(?:public/)?tree/([a-zA-Z0-9\-]+)');
    final match = regex.firstMatch(code);

    if (match == null) {
      _showError('Invalid QR Code', 'This does not appear to be a valid TreeTrace QR code.\n\nCode: $code');
      return;
    }

    setState(() => _loading = true);
    try {
      final data = await api.getPublicTree(match.group(1)!);
      final tree = TreeModel.fromJson(data);
      if (mounted) {
        setState(() => _loading = false);
        _showResult(tree);
      }
    } catch (_) {
      _showError('Connection Error', 'We couldn\'t find a tree associated with this code. Please check your internet connection.');
    }
  }

  void _reset() {
    setState(() { _scanned = false; _loading = false; });
    _ctrl.start();
  }

  void _handleBack() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.maybePop(context);
    }
  }

  void _showError(String title, String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: Text(msg, style: const TextStyle(color: kMutedFg)),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(context); _reset(); },
            child: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.w600)),
          )
        ],
      ),
    );
  }

  void _showResult(TreeModel tree) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: kBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: DraggableScrollableSheet(
          expand: false, initialChildSize: 0.6,
          builder: (_, scrollCtrl) => SingleChildScrollView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 24),
                
                // Image Header
                if (tree.photoUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.network(tree.photoUrl!, height: 180, width: double.infinity, fit: BoxFit.cover),
                  )
                else
                  Container(
                    height: 100, width: double.infinity,
                    decoration: BoxDecoration(color: kPrimary.withOpacity(0.1), borderRadius: BorderRadius.circular(24)),
                    child: const Icon(Icons.park_rounded, color: kPrimary, size: 48),
                  ),

                const SizedBox(height: 24),
                
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tree.commonName, style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800, color: kForeground)),
                          const SizedBox(height: 4),
                          Text(tree.scientificName ?? 'Scientific Name N/A', 
                            style: GoogleFonts.inter(fontSize: 14, fontStyle: FontStyle.italic, color: kMutedFg)),
                        ],
                      ),
                    ),
                    HealthBadge(tree.healthStatus),
                  ],
                ),
                
                const SizedBox(height: 20),
                
                // Location row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
                  child: Row(children: [
                    const Icon(Icons.location_on_rounded, size: 16, color: kPrimary),
                    const SizedBox(width: 8),
                    Text(tree.barangay ?? 'Unknown Location', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                  ]),
                ),

                const SizedBox(height: 20),
                
                // Measurement Info Pills
                Row(
                  children: [
                    _InfoPill(Icons.straighten, 'DBH', '${tree.dbhCm?.toStringAsFixed(1) ?? "--"} cm'),
                    const SizedBox(width: 12),
                    _InfoPill(Icons.height, 'Height', '${tree.heightM?.toStringAsFixed(1) ?? "--"} m'),
                  ],
                ),

                const SizedBox(height: 32),
                
                Row(children: [
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(builder: (_) => TreeDetailScreen(treeId: tree.id)));
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('View Full Profile', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 56,
                    child: OutlinedButton(
                      onPressed: () { Navigator.pop(context); _reset(); },
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Icon(Icons.qr_code_scanner_rounded),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() { 
    _ctrl.dispose(); 
    _animCtrl.dispose();
    super.dispose(); 
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _handleBack,
        ),
        title: Text(
          'Scan Tree Tag',
          style: GoogleFonts.inter(
            color: kForeground,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: kForeground,
        iconTheme: const IconThemeData(color: kForeground),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(children: [
        MobileScanner(controller: _ctrl, onDetect: _onDetect),

        // Dark overlay with transparent scanner window.
        IgnorePointer(
          child: CustomPaint(
            size: Size.infinite,
            painter: _ScannerOverlayPainter(
              cutoutSize: 250,
              radius: 24,
              overlayColor: Colors.black.withOpacity(0.58),
            ),
          ),
        ),

        // Animated Scanning Line
        Center(
          child: AnimatedBuilder(
            animation: _animCtrl,
            builder: (context, child) {
              return Container(
                width: 230,
                height: 250,
                alignment: Alignment(0, _animCtrl.value * 2 - 1),
                child: Container(
                  width: double.infinity,
                  height: 2,
                  decoration: BoxDecoration(
                    color: kSidebarPrimary,
                    boxShadow: [
                      BoxShadow(color: kSidebarPrimary.withOpacity(0.5), blurRadius: 10, spreadRadius: 2),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // Frame corners
        Center(
          child: Container(
            width: 250, height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
        ..._buildCorners(),

        // Instructions
        Positioned(
          bottom: 100, left: 0, right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(30)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Text('Align QR code within the frame', 
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        ),

        if (_loading)
          Container(
            color: Colors.black87,
            child: Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: kSidebarPrimary),
                const SizedBox(height: 20),
                Text('Fetching Tree Data...', style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            )),
          ),
      ]),
    );
  }

  List<Widget> _buildCorners() {
    const size = 30.0;
    const thickness = 4.0;
    final color = kSidebarPrimary;
    return [
      Positioned(top: MediaQuery.of(context).size.height / 2 - 125, left: MediaQuery.of(context).size.width / 2 - 125,
          child: _corner(top: true, left: true, color: color, size: size, thickness: thickness)),
      Positioned(top: MediaQuery.of(context).size.height / 2 - 125, right: MediaQuery.of(context).size.width / 2 - 125,
          child: _corner(top: true, left: false, color: color, size: size, thickness: thickness)),
      Positioned(bottom: MediaQuery.of(context).size.height / 2 - 125, left: MediaQuery.of(context).size.width / 2 - 125,
          child: _corner(top: false, left: true, color: color, size: size, thickness: thickness)),
      Positioned(bottom: MediaQuery.of(context).size.height / 2 - 125, right: MediaQuery.of(context).size.width / 2 - 125,
          child: _corner(top: false, left: false, color: color, size: size, thickness: thickness)),
    ];
  }

  Widget _corner({required bool top, required bool left, required Color color, required double size, required double thickness}) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        border: Border(
          top: top ? BorderSide(color: color, width: thickness) : BorderSide.none,
          bottom: !top ? BorderSide(color: color, width: thickness) : BorderSide.none,
          left: left ? BorderSide(color: color, width: thickness) : BorderSide.none,
          right: !left ? BorderSide(color: color, width: thickness) : BorderSide.none,
        ),
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  final double cutoutSize;
  final double radius;
  final Color overlayColor;

  const _ScannerOverlayPainter({
    required this.cutoutSize,
    required this.radius,
    required this.overlayColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutoutRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: cutoutSize,
      height: cutoutSize,
    );
    final cutoutPath = Path()
      ..addRRect(RRect.fromRectAndRadius(cutoutRect, Radius.circular(radius)));
    final path = Path.combine(PathOperation.difference, overlayPath, cutoutPath);
    canvas.drawPath(path, Paint()..color = overlayColor);
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) {
    return cutoutSize != oldDelegate.cutoutSize ||
        radius != oldDelegate.radius ||
        overlayColor != oldDelegate.overlayColor;
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
        decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: kBorder)),
        child: Column(
          children: [
            Icon(icon, size: 16, color: kPrimary),
            const SizedBox(height: 6),
            Text(value, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14)),
            Text(label, style: TextStyle(color: kMutedFg, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
