import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'welcome_screen.dart';
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
  final Random _random = Random();

  @override
  void initState() {
    super.initState();

    _mainController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    // Begin the location check flow
    _checkLocationAndProceed();
  }

  Future<void> _checkLocationAndProceed() async {
    // Wait for at least part of the splash animation to play (e.g. 2 seconds min)
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    bool serviceEnabled = false;
    try {
      // Check if location services are enabled with a timeout
      serviceEnabled = await Geolocator.isLocationServiceEnabled().timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
    } catch (e) {
      debugPrint('[Splash] Location check error: $e');
    }

    if (!serviceEnabled) {
      // If it hangs or is disabled, we still proceed for now or show dialog
      // For better UX during deep linking, if it fails quickly we just proceed
      _proceedToNextScreen();
      return;
    }
    if (!serviceEnabled) {
      _showLocationRequiredDialog(
        'Location Services Disabled',
        'Please enable location services in your device settings to use the Spacall app.',
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showLocationRequiredDialog(
          'Permission Denied',
          'Location permissions are required to use the Therapist app. Please grant permissions.',
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showLocationRequiredDialog(
        'Permission Denied Forever',
        'Location permissions are permanently denied, we cannot request permissions. Please enable them from system settings.',
      );
      return;
    }

    // Permission granted and services enabled, proceed!
    _proceedToNextScreen();
  }

  Future<void> _proceedToNextScreen() async {
    if (!mounted) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataStr = prefs.getString('user_data');

      if (userDataStr != null && userDataStr.isNotEmpty) {
        final userData = jsonDecode(userDataStr);
        if (userData != null && userData['token'] != null) {
          debugPrint(
            '[AUTO-LOGIN] User session found. Redirecting to WelcomeScreen.',
          );
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => WelcomeScreen(userData: userData),
            ),
          );
          return;
        }
      }
    } catch (e) {
      debugPrint('[AUTO-LOGIN] Error parsing user data: $e');
    }

    debugPrint(
      '[AUTO-LOGIN] No session found. Redirecting to OnboardingScreen.',
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const OnboardingScreen()),
    );
  }

  void _showLocationRequiredDialog(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text(
            title,
            style: const TextStyle(color: const Color(0xFFD4AF37)),
          ),
          content: Text(message, style: const TextStyle(color: Colors.white70)),
          actions: <Widget>[
            TextButton(
              child: const Text(
                'Try Again',
                style: TextStyle(color: const Color(0xFFD4AF37)),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _checkLocationAndProceed(); // Retry checking
              },
            ),
          ],
        );
      },
    );
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
