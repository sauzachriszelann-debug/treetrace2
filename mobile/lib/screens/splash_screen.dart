import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: const Color(0xFF07190F),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF07190F),
        body: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final progress = 0.22 + (0.58 * _controller.value);

            return Stack(
              fit: StackFit.expand,
              children: [
                const _SplashBackground(),
                SafeArea(
                  child: Center(
                    child: Transform.translate(
                      offset: const Offset(0, -14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 230,
                            height: 230,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CustomPaint(
                                  size: const Size.square(230),
                                  painter: _SplashRingsPainter(
                                    progress: _controller.value,
                                  ),
                                ),
                                Container(
                                  width: 96,
                                  height: 96,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0B2416),
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: kHealthy.withOpacity(0.22),
                                        blurRadius: 38,
                                        spreadRadius: 6,
                                      ),
                                    ],
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Image.asset(
                                    'assets/landing/logo.png',
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _StatusDot(color: kSidebarPrimary),
                              const SizedBox(width: 16),
                              Text(
                                'TreeTrace'.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 4,
                                ),
                              ),
                              const SizedBox(width: 16),
                              _StatusDot(color: kFair.withOpacity(0.75)),
                            ],
                          ),
                          const SizedBox(height: 44),
                          SizedBox(
                            width: 230,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                height: 8,
                                color: Colors.white.withOpacity(0.12),
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor:
                                      progress.clamp(0.0, 0.88).toDouble(),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(999),
                                      gradient: const LinearGradient(
                                        colors: [
                                          kSidebarPrimary,
                                          kHealthy,
                                          kFair,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          Text(
                            'Preparing Panabo tree inventory...',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.72),
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SplashBackground extends StatelessWidget {
  const _SplashBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF08190F),
            Color(0xFF12371F),
            Color(0xFF07190F),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _SplashGridPainter()),
          Positioned(
            top: 90,
            right: -70,
            child: _GlowOrb(
              size: 190,
              color: kSidebarPrimary.withOpacity(0.18),
            ),
          ),
          Positioned(
            bottom: 80,
            left: -90,
            child: _GlowOrb(
              size: 240,
              color: kHealthy.withOpacity(0.16),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final Color color;

  const _StatusDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.5),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withOpacity(0)],
        ),
      ),
    );
  }
}

class _SplashGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.045)
      ..strokeWidth = 1;
    const step = 86.0;

    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SplashRingsPainter extends CustomPainter {
  final double progress;

  _SplashRingsPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.4
      ..color = Colors.white.withOpacity(0.10);
    final dashedPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.2
      ..color = kSidebarPrimary.withOpacity(0.85);

    canvas.drawCircle(center, 74, basePaint);
    canvas.drawCircle(
      center,
      112,
      basePaint..color = Colors.white.withOpacity(0.08),
    );

    final rect = Rect.fromCircle(center: center, radius: 112);
    final rotation = progress * math.pi * 2;
    const dashSweep = math.pi / 18;
    const gapSweep = math.pi / 8;

    for (double angle = rotation;
        angle < math.pi * 2 + rotation;
        angle += dashSweep + gapSweep) {
      final isAccent =
          ((angle - rotation) / (dashSweep + gapSweep)).round().isEven;
      dashedPaint.color = isAccent
          ? kSidebarPrimary.withOpacity(0.85)
          : kFair.withOpacity(0.75);
      canvas.drawArc(rect, angle, dashSweep, false, dashedPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SplashRingsPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
