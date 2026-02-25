import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'onboarding_screen.dart';

class AnimatedLogoScreen extends StatefulWidget {
  const AnimatedLogoScreen({super.key});

  @override
  State<AnimatedLogoScreen> createState() => _AnimatedLogoScreenState();
}

class _AnimatedLogoScreenState extends State<AnimatedLogoScreen>
    with TickerProviderStateMixin {
  late AnimationController _mainController;
  final List<SparkleData> _sparkles = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();

    _mainController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    // Navigate to OnboardingScreen after 10 seconds
    Timer(const Duration(seconds: 10), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const OnboardingScreen()),
        );
      }
    });
  }

  void _updateSparkles() {
    if (_sparkles.length < 40 && _random.nextDouble() > 0.5) {
      _sparkles.add(
        SparkleData(
          // Inside the red box: top-right near the hand's curve
          x: _random.nextDouble() * 50 + 60,
          y: _random.nextDouble() * 60 - 130,
          size: _random.nextDouble() * 5 + 3,
          opacity: 0.9,
          speed: _random.nextDouble() * 0.025 + 0.01,
        ),
      );
    }

    for (var sparkle in _sparkles) {
      sparkle.opacity -= sparkle.speed;
    }
    _sparkles.removeWhere((s) => s.opacity <= 0);
  }

  @override
  void dispose() {
    _mainController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Central Content (Logo + Branding)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo Stack
                Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    // Base Logo
                    Image.asset(
                      'assets/images/logo_base.png',
                      width: 280,
                      height: 280,
                      fit: BoxFit.contain,
                    ),

                    // Spinning Flower - Positioned precisely on the left arc
                    Positioned(
                      left: 0,
                      bottom: 0,
                      child: RotationTransition(
                        turns: _mainController,
                        child: Image.asset(
                          'assets/images/flower.png',
                          width: 110,
                          height: 110,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10), // Space between logo and text
                // Branding Text & Loading
                Column(
                  children: [
                    const Text(
                      'SPACALL',
                      style: TextStyle(
                        color: Color(0xFFEBC14F),
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 10,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'PREMIUM WELLNESS SERVICES',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.3),
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 30),
                    // Premium subtle loading bar
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0.0, end: 1.0),
                      duration: const Duration(seconds: 10),
                      builder: (context, value, child) {
                        return SizedBox(
                          width: 120,
                          height: 2,
                          child: LinearProgressIndicator(
                            value: value,
                            backgroundColor: Colors.white.withOpacity(0.05),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFFEBC14F),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. Foreground Sparkle Layer (Absolute Top)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _mainController,
              builder: (context, child) {
                _updateSparkles();
                return CustomPaint(
                  painter: SparklePainter(
                    sparkles: _sparkles,
                    center: Offset(
                      MediaQuery.of(context).size.width / 2,
                      MediaQuery.of(context).size.height / 2,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class SparkleData {
  double x, y, size, opacity, speed;
  SparkleData({
    required this.x,
    required this.y,
    required this.size,
    required this.opacity,
    required this.speed,
  });
}

class SparklePainter extends CustomPainter {
  final List<SparkleData> sparkles;
  final Offset center;

  SparklePainter({required this.sparkles, required this.center});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (var sparkle in sparkles) {
      if (sparkle.opacity <= 0) continue;

      // Premium gold color with elegant opacity
      paint.color = const Color(0xFFEBC14F).withOpacity(sparkle.opacity * 0.85);

      final sx = center.dx + sparkle.x;
      final sy = center.dy + sparkle.y;

      // Draw elegant square sparkle
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(sx, sy),
          width: sparkle.size,
          height: sparkle.size,
        ),
        paint,
      );

      // Add a soft, elegant glow
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(sx, sy),
          width: sparkle.size * 1.5,
          height: sparkle.size * 1.5,
        ),
        Paint()
          ..color = const Color(0xFFEBC14F).withOpacity(sparkle.opacity * 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
