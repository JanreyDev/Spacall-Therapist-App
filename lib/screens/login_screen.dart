import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_service.dart';
import 'otp_screen.dart';
import 'welcome_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();
  final _apiService = ApiService();
  bool _isLoading = false;
  String? _savedNumber;
  bool _showPinOnly = false;

  @override
  void initState() {
    super.initState();
    _checkSavedNumber();
  }

  Future<void> _checkSavedNumber() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('last_mobile_number');
    if (saved != null && saved.isNotEmpty) {
      setState(() {
        _savedNumber = saved;
        _showPinOnly = true;
      });
    }
  }

  Future<void> _handleLogin() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _showLuxuryDialog('Please enter your mobile number', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _apiService.loginEntry(phone);

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => OtpScreen(mobileNumber: phone)),
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

  Future<void> _handlePinLogin() async {
    final pin = _pinController.text.trim();
    if (pin.length != 6) {
      _showLuxuryDialog('Please enter your 6-digit PIN', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await _apiService.loginPin(_savedNumber!, pin);

      if (!mounted) return;

      _showLuxuryDialog('Login Successful!');

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => WelcomeScreen(userData: response),
        ),
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

  void _switchAccount() {
    setState(() {
      _showPinOnly = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    const goldColor = Color(0xFFD4AF37);
    const backgroundColor = Color(0xFF121212);

    return Scaffold(
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      children: [
                        const SizedBox(height: 60),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: goldColor,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'Welcome Back',
                                style: TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.bold,
                                  color: goldColor,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _showPinOnly
                                    ? 'Confirm your PIN to continue'
                                    : 'Sign in to access luxury wellness',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_showPinOnly) ...[
                          Text(
                            _savedNumber ?? '',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: goldColor,
                            ),
                          ),
                          const SizedBox(height: 32),
                          _buildLuxuryTextField(
                            controller: _pinController,
                            label: 'Enter PIN',
                            icon: Icons.lock_outline,
                            isObscure: true,
                            isPin: true,
                          ),
                          const SizedBox(height: 32),
                          _isLoading
                              ? const CircularProgressIndicator(
                                  color: goldColor,
                                )
                              : Column(
                                  children: [
                                    _buildGoldButton(
                                      text: 'LOGIN',
                                      onPressed: _handlePinLogin,
                                    ),
                                    const SizedBox(height: 16),
                                    TextButton(
                                      onPressed: _switchAccount,
                                      child: Text(
                                        'Logged in as something else?',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.5),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ] else ...[
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Mobile Number',
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildLuxuryTextField(
                            controller: _phoneController,
                            label: '',
                            icon: Icons.phone_outlined,
                            hintText: '09XXXXXXX',
                          ),
                          const SizedBox(height: 40),
                          _isLoading
                              ? const CircularProgressIndicator(
                                  color: goldColor,
                                )
                              : _buildGoldButton(
                                  text: 'SEND OTP',
                                  onPressed: _handleLogin,
                                ),
                        ],
                        const SizedBox(height: 40),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            'By continuing, you agree to our Terms of Service and Privacy Policy',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24.0),
                      child: Text(
                        'Viscaria IT Solutions, Inc. - version 1.0.0',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.2),
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showLuxuryDialog(String message, {bool isError = false}) {
    const goldColor = Color(0xFFD4AF37);
    showDialog(
      context: context,
      barrierDismissible: !isError,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: (isError ? Colors.redAccent : goldColor).withOpacity(0.5),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.check_circle_outline,
                color: isError ? Colors.redAccent : goldColor,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                isError ? 'ERROR' : 'SUCCESS',
                style: const TextStyle(
                  color: goldColor,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: isError
                          ? [
                              Colors.redAccent.withOpacity(0.8),
                              Colors.redAccent,
                            ]
                          : [
                              const Color(0xFFB8860B),
                              goldColor,
                              const Color(0xFFFFD700),
                            ],
                    ),
                  ),
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'CONTINUE',
                      style: TextStyle(
                        color: isError ? Colors.white : Colors.black,
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

  Widget _buildLuxuryTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isObscure = false,
    bool isPin = false,
    String? hintText,
  }) {
    const goldColor = Color(0xFFD4AF37);

    return TextField(
      controller: controller,
      obscureText: isObscure,
      keyboardType: TextInputType.number,
      maxLength: isPin ? 6 : null,
      style: const TextStyle(color: Colors.white, fontSize: 18),
      textAlign: TextAlign.start,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
        prefixIcon: Icon(icon, color: goldColor),
        counterText: "",
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: goldColor.withOpacity(0.5), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: goldColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
      ),
    );
  }

  Widget _buildGoldButton({
    required String text,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: double.infinity,
      height: 58,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: [
            Color(0xFFB8860B),
            Color(0xFFD4AF37),
            Color(0xFFFFD700),
            Color(0xFFD4AF37),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD4AF37).withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
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
}
