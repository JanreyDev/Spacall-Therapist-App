import 'package:flutter/material.dart';
import 'package:pinput/pinput.dart';
import '../api_service.dart';
import '../widgets/luxury_error_modal.dart';
import '../widgets/rotating_flower_loader.dart';
import 'login_screen.dart';

class ResetPinScreen extends StatefulWidget {
  final String mobileNumber;
  final String otp;

  const ResetPinScreen({
    super.key,
    required this.mobileNumber,
    required this.otp,
  });

  @override
  State<ResetPinScreen> createState() => _ResetPinScreenState();
}

class _ResetPinScreenState extends State<ResetPinScreen> {
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  final _apiService = ApiService();
  bool _isLoading = false;
  final _pinFocusNode = FocusNode();

  Future<void> _handleResetPin() async {
    final pin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();

    if (pin.length != 6) {
      _showLuxuryDialog('Please enter a 6-digit PIN', isError: true);
      return;
    }

    if (pin != confirmPin) {
      _showLuxuryDialog('PINs do not match', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _apiService.resetPin(
        mobileNumber: widget.mobileNumber,
        otp: widget.otp,
        newPin: pin,
      );

      if (!mounted) return;

      _showLuxuryDialog(
        'Your security PIN has been reset successfully. Please log in with your new PIN.',
        onConfirm: () {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
            (route) => false,
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      _showLuxuryDialog(
        e.toString().replaceAll('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const goldColor = Color(0xFFD4AF37);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const SizedBox(height: 60),
              Image.asset(
                'assets/images/logo.png',
                width: 100,
                height: 100,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.spa, color: goldColor, size: 100),
              ),
              const SizedBox(height: 24),
              const Text(
                'RESET PIN',
                style: TextStyle(
                  color: goldColor,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Create a new 6-digit security PIN for your account.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 60),
              if (_isLoading) ...[
                const RotatingFlowerLoader(size: 70),
                const SizedBox(height: 40),
              ],

              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'New PIN',
                  style: TextStyle(
                    color: goldColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Pinput(
                length: 6,
                controller: _pinController,
                focusNode: _pinFocusNode,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                defaultPinTheme: _pinTheme(goldColor),
                focusedPinTheme: _focusedPinTheme(goldColor),
              ),

              const SizedBox(height: 32),

              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Confirm New PIN',
                  style: TextStyle(
                    color: goldColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Pinput(
                length: 6,
                controller: _confirmPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                defaultPinTheme: _pinTheme(goldColor),
                focusedPinTheme: _focusedPinTheme(goldColor),
                onCompleted: (pin) => _handleResetPin(),
              ),

              const SizedBox(height: 60),

              if (!_isLoading)
                _buildGoldButton(text: 'RESET PIN', onPressed: _handleResetPin),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  PinTheme _pinTheme(Color goldColor) {
    return PinTheme(
      width: 45,
      height: 55,
      textStyle: const TextStyle(
        fontSize: 22,
        color: Colors.white,
        fontWeight: FontWeight.bold,
      ),
      decoration: BoxDecoration(
        color: goldColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: goldColor.withOpacity(0.3)),
      ),
    );
  }

  PinTheme _focusedPinTheme(Color goldColor) {
    return _pinTheme(goldColor).copyDecorationWith(
      color: goldColor.withOpacity(0.15),
      border: Border.all(color: goldColor, width: 1.5),
    );
  }

  Widget _buildGoldButton({
    required String text,
    required VoidCallback onPressed,
  }) {
    const goldColor = Color(0xFFD4AF37);
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFFB8860B), goldColor, Color(0xFFFFD700), goldColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: goldColor.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showLuxuryDialog(
    String message, {
    bool isError = false,
    VoidCallback? onConfirm,
  }) {
    if (isError) {
      showDialog(
        context: context,
        builder: (context) => LuxuryErrorModal(
          title: "ERROR",
          message: message,
          onConfirm: () => Navigator.pop(context),
        ),
      );
      return;
    }
    const goldColor = Color(0xFFD4AF37);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: goldColor.withOpacity(0.5), width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: goldColor,
                size: 48,
              ),
              const SizedBox(height: 16),
              const Text(
                'SUCCESS',
                style: TextStyle(
                  color: goldColor,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFB8860B), goldColor, Color(0xFFFFD700)],
                    ),
                  ),
                  child: ElevatedButton(
                    onPressed: onConfirm ?? () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'CONTINUE',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
