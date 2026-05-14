import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/theme.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  void _openLogin(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void _openRegister(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSidebarBg,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      kSidebarBg,
                      kSidebarBg,
                      kPrimary.withOpacity(0.94),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: -70,
              top: 90,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kSidebarPrimary.withOpacity(0.08),
                ),
              ),
            ),
            Positioned(
              left: -80,
              bottom: 140,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top -
                      MediaQuery.of(context).padding.bottom -
                      48,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.asset(
                            'assets/landing/logo.png',
                            width: 42,
                            height: 42,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'TreeTrace',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => _openLogin(context),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          child: const Text('Log In'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 52),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.12),
                        ),
                      ),
                      child: const Text(
                        'AI-powered geo-spatial tree inventory',
                        style: TextStyle(
                          color: kSidebarPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Know Every Tree.\nGuard Every Root.',
                      style: GoogleFonts.playfairDisplay(
                        color: Colors.white,
                        fontSize: 42,
                        height: 1.02,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'TreeTrace helps citizens and field workers map trees, scan QR tags, identify species, and flag protected trees before cutting.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.72),
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => _openRegister(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kSidebarPrimary,
                          foregroundColor: kForeground,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Get Started',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton(
                        onPressed: () => _openLogin(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withOpacity(0.22),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('Log In'),
                      ),
                    ),
                    const SizedBox(height: 28),
                    _PreviewCard(),
                    const SizedBox(height: 18),
                    Row(
                      children: const [
                        Expanded(
                          child: _LandingMetric(
                            value: 'QR',
                            label: 'Tree profiles',
                            icon: Icons.qr_code_scanner_rounded,
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: _LandingMetric(
                            value: 'AI',
                            label: 'Species ID',
                            icon: Icons.auto_awesome_rounded,
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: _LandingMetric(
                            value: 'GPS',
                            label: 'Mapping',
                            icon: Icons.map_rounded,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: kSidebarPrimary.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: kSidebarPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Cannot Cut Warning',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Protected species are flagged immediately.',
                      style: TextStyle(color: kSidebarText, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 126,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset(
                      'assets/landing/images7.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: kPrimary.withOpacity(0.25),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.58),
                        ],
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  left: 14,
                  bottom: 12,
                  child: Text(
                    'Public Tree Map',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LandingMetric extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  const _LandingMetric({
    required this.value,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: kSidebarPrimary, size: 18),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withOpacity(0.62),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
