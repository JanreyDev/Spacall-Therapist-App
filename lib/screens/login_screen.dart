import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pinput/pinput.dart';
import '../api_service.dart';
import 'otp_screen.dart';
import 'welcome_screen.dart';
import '../widgets/luxury_error_modal.dart';
import '../widgets/rotating_flower_loader.dart';

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
  bool _isEnteringPin = false; // New state
  final _pinFocusNode = FocusNode(); // For PIN input

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

    if (phone.length != 11) {
      _showLuxuryDialog(
        'Invalid mobile number. Please check the number carefully.',
        isError: true,
      );
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

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => WelcomeScreen(userData: response),
        ),
      );
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => LuxuryErrorModal(
            title: "ACCESS DENIED",
            message:
                "The security PIN you entered is incorrect. Please double-check and try again.",
            onConfirm: () => Navigator.pop(context),
          ),
        );
      }
      _pinController.clear();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _switchAccount() {
    setState(() {
      _showPinOnly = false;
    });
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      return 'Good morning!';
    } else if (hour >= 12 && hour < 18) {
      return 'Good afternoon!';
    } else {
      return 'Good evening!';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _isEnteringPin
                  ? _buildPinEntryView(constraints)
                  : _buildInitialLoginView(constraints),
            );
          },
        ),
      ),
    );
  }

  Widget _buildInitialLoginView(BoxConstraints constraints) {
    const goldColor = Color(0xFFD4AF37);
    const surfaceColor = Color(0xFF1E1E1E);

    return SingleChildScrollView(
      key: const ValueKey('initial_login'),
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: IntrinsicHeight(
          child: Column(
            children: [
              const SizedBox(height: 40),
              // Centered Vertical Header: Logo + Brand
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/logo.png',
                    width: 140,
                    height: 140,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.spa, color: goldColor, size: 140),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'SPACALL',
                    style: TextStyle(
                      color: goldColor,
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 6,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 100),
              if (_isLoading) ...[
                const RotatingFlowerLoader(size: 80),
                const SizedBox(height: 40),
              ],
              Text(
                _getGreeting(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 24),

              if (_showPinOnly) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: goldColor.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.phone_android,
                        color: goldColor.withOpacity(0.7),
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Center(
                          child: Text(
                            _savedNumber ?? '',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _switchAccount,
                        child: Icon(
                          Icons.compare_arrows_rounded,
                          color: goldColor.withOpacity(0.7),
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _switchAccount,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Not your number? ',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 12,
                        ),
                      ),
                      const Text(
                        'Switch account',
                        style: TextStyle(
                          color: goldColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 60),
                // PIN Login Card
                GestureDetector(
                  onTap: () {
                    setState(() => _isEnteringPin = true);
                    _pinFocusNode.requestFocus();
                  },
                  child: Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      color: goldColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: goldColor.withOpacity(0.4),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Column(
                          children: List.generate(
                            3,
                            (row) => Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(
                                  3,
                                  (col) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 1.5,
                                    ),
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: goldColor,
                                        borderRadius: BorderRadius.circular(
                                          1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'PIN Login',
                          style: TextStyle(
                            color: goldColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  maxLength: 11,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  decoration: InputDecoration(
                    counterText: "", // Hide character counter
                    hintText: '09XXXXXXXXX',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                    prefixIcon: Icon(
                      Icons.phone_android,
                      color: goldColor.withOpacity(0.7),
                    ),
                    filled: true,
                    fillColor: surfaceColor,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide(
                        color: goldColor.withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: const BorderSide(
                        color: goldColor,
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 80),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    "By tapping next, we'll collect your mobile number's network information to be able to send you a One-Time Password (OTP).",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _isLoading
                    ? Container() // Loader is now above greeting
                    : _buildGoldButton(
                        text: 'SEND OTP',
                        onPressed: _handleLogin,
                      ),
              ],

              const SizedBox(height: 32),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildTextLink('Help Center', () {}),
                  _buildTextLink('Forgot PIN?', () {}),
                ],
              ),

              const SizedBox(height: 16),
              Text(
                'Viscaria IT Solutions, Inc. · v1.0.0',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.2),
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinEntryView(BoxConstraints constraints) {
    const goldColor = Color(0xFFD4AF37);
    const surfaceColor = Color(0xFF1E1E1E);

    return SingleChildScrollView(
      key: const ValueKey('pin_entry'),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: IntrinsicHeight(
          child: Column(
            children: [
              const SizedBox(height: 40),
              // Header
              Column(
                children: [
                  Image.asset(
                    'assets/images/logo.png',
                    width: 110,
                    height: 110,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.spa, color: goldColor, size: 110),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'SPACALL',
                    style: TextStyle(
                      color: goldColor,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 5,
                    ),
                  ),
                ],
              ),
              if (_isLoading) ...[
                const SizedBox(height: 24),
                const RotatingFlowerLoader(size: 70),
              ] else
                const SizedBox(height: 40),
              Text(
                _getGreeting(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 24),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: goldColor.withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.phone_android,
                      color: goldColor.withOpacity(0.7),
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Center(
                        child: Text(
                          _savedNumber ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => setState(() => _isEnteringPin = false),
                      child: Icon(
                        Icons.compare_arrows_rounded,
                        color: goldColor.withOpacity(0.7),
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => setState(() => _isEnteringPin = false),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Not your number? ',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                    const Text(
                      'Switch account',
                      style: TextStyle(
                        color: goldColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 60),

              const Text(
                'Enter your PIN',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 24),

              Pinput(
                length: 6,
                controller: _pinController,
                focusNode: _pinFocusNode,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                onCompleted: (pin) => _handlePinLogin(),
                defaultPinTheme: PinTheme(
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
                ),
                focusedPinTheme: PinTheme(
                  width: 48,
                  height: 58,
                  decoration: BoxDecoration(
                    color: goldColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: goldColor, width: 1.5),
                  ),
                ),
              ),

              const SizedBox(height: 40),

              Text(
                'Never share your PIN or OTP with anyone.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 14,
                ),
              ),

              const Spacer(),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildTextLink('Help Center', () {}),
                  _buildTextLink('Forgot PIN?', () {}),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextLink(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withOpacity(0.6),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _showLuxuryDialog(String message, {bool isError = false}) {
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

  // Removed _buildLuxuryTextField as it's no longer used

  Widget _buildGoldButton({
    required String text,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
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
}
