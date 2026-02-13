import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'welcome_screen.dart';
import 'spacall_camera_screen.dart';
import '../api_service.dart';

class RegistrationScreen extends StatefulWidget {
  final String mobileNumber;

  const RegistrationScreen({super.key, required this.mobileNumber});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen>
    with SingleTickerProviderStateMixin {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  final _apiService = ApiService();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  String _gender = 'male';
  DateTime _dob = DateTime.now().subtract(const Duration(days: 365 * 18));
  bool _isLoading = false;

  XFile? _profilePhoto;
  XFile? _idCardPhoto;
  XFile? _idCardBackPhoto;
  XFile? _idSelfiePhoto;

  final ImagePicker _picker = ImagePicker();

  // --- PROFESSIONAL LUXURY CONSTANTS ---
  static const Color _bgPrimary = Color(0xFF0F0F0F);
  static const Color _bgSecondary = Color(0xFF161616);
  static const Color _cardBg = Color(0xFF1E1E1E);
  static const Color _goldPrimary = Color(0xFFD4AF37);
  static const Color _goldAccent = Color(0xFFB8860B);
  static const Color _textPrimary = Colors.white;
  static const Color _textSecondary = Color(0xFF9E9E9E);

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutQuad,
          ),
        );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  // --- LOGIC METHODS ---

  Future<void> _showSourceSelection(String type) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: _cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: _goldPrimary),
              title: const Text(
                'Gallery',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImage(type, source: ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: _goldPrimary),
              title: const Text(
                'Camera',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () async {
                Navigator.pop(context);
                final XFile? result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SpacallCameraScreen(
                      isFace: type == 'profile',
                      isBlinkRequired: false,
                    ),
                  ),
                );
                if (result != null) {
                  setState(() {
                    if (type == 'profile') _profilePhoto = result;
                    if (type == 'id_card') _idCardPhoto = result;
                    if (type == 'id_card_back') _idCardBackPhoto = result;
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(String type, {required ImageSource source}) async {
    final XFile? image = await _picker.pickImage(
      source: source,
      preferredCameraDevice: type == 'profile'
          ? CameraDevice.front
          : CameraDevice.rear,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 50,
    );
    if (image != null) {
      setState(() {
        if (type == 'profile') _profilePhoto = image;
        if (type == 'id_card') _idCardPhoto = image;
        if (type == 'id_card_back') _idCardBackPhoto = image;
        if (type == 'id_selfie') _idSelfiePhoto = image;
      });
    }
  }

  Future<void> _register() async {
    if (_firstNameController.text.isEmpty ||
        _lastNameController.text.isEmpty ||
        _pinController.text.length != 6) {
      _showLuxuryDialog('Please fill all fields correctly', isError: true);
      return;
    }

    if (_pinController.text != _confirmPinController.text) {
      _showLuxuryDialog('PINs do not match', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await _apiService.registerProfile(
        mobileNumber: widget.mobileNumber,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        gender: _gender,
        dob: _dob.toIso8601String().split('T')[0],
        pin: _pinController.text.trim(),
        profilePhoto: _profilePhoto,
        idCardPhoto: _idCardPhoto,
        idCardBackPhoto: _idCardBackPhoto,
        idSelfiePhoto: _idSelfiePhoto,
        role: 'therapist',
      );

      if (!mounted) return;
      _showLuxuryDialog('Registration Successful!');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_mobile_number', widget.mobileNumber);

      if (!mounted) return;

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

  // --- UI BUILDING ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgPrimary,
      appBar: AppBar(
        backgroundColor: _bgPrimary,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'REGISTRATION',
          style: TextStyle(
            color: _goldPrimary,
            fontWeight: FontWeight.bold,
            letterSpacing: 2.0,
            fontSize: 14,
          ),
        ),
        iconTheme: const IconThemeData(color: _goldPrimary),
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildIntroHeader(),
                const SizedBox(height: 32),

                _buildSectionLabel("PERSONAL DETAILS"),
                _buildFormCard([
                  _buildProfessionalTextField(
                    controller: _firstNameController,
                    label: 'First Name',
                    icon: Icons.person_outline,
                  ),
                  const Divider(color: Colors.white10),
                  _buildProfessionalTextField(
                    controller: _lastNameController,
                    label: 'Last Name',
                    icon: Icons.person_outline,
                  ),
                  const Divider(color: Colors.white10),
                  _buildProfessionalDropdown(),
                  const Divider(color: Colors.white10),
                  _buildProfessionalDatePicker(),
                ]),

                const SizedBox(height: 24),
                _buildSectionLabel("SECURITY"),
                _buildFormCard([
                  _buildProfessionalTextField(
                    controller: _pinController,
                    label: '6-Digit PIN',
                    icon: Icons.lock_outline,
                    isNumber: true,
                    isObscure: true,
                    maxLength: 6,
                  ),
                  const Divider(color: Colors.white10),
                  _buildProfessionalTextField(
                    controller: _confirmPinController,
                    label: 'Confirm PIN',
                    icon: Icons.lock_clock_outlined,
                    isNumber: true,
                    isObscure: true,
                    maxLength: 6,
                  ),
                ]),

                const SizedBox(height: 24),
                _buildSectionLabel("DOCUMENTS"),
                _buildImagePickerSection(),

                const SizedBox(height: 48),
                _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: _goldPrimary),
                      )
                    : _buildSubmitButton(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIntroHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Therapist Profile",
          style: TextStyle(
            color: _textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Provide your professional credentials to join our curated marketplace.",
          style: TextStyle(color: _textSecondary, fontSize: 14, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: _goldPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildFormCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: _bgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(children: children),
    );
  }

  // --- REFINED INPUT WIDGETS ---

  Widget _buildProfessionalTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isNumber = false,
    bool isObscure = false,
    int? maxLength,
  }) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      obscureText: isObscure,
      maxLength: maxLength,
      style: const TextStyle(color: _textPrimary, fontSize: 15),
      cursorColor: _goldPrimary,
      decoration: InputDecoration(
        counterText: "",
        labelText: label,
        labelStyle: TextStyle(
          color: _textSecondary.withOpacity(0.6),
          fontSize: 13,
        ),
        floatingLabelStyle: const TextStyle(color: _goldPrimary, fontSize: 13),
        prefixIcon: Icon(icon, color: _goldPrimary.withOpacity(0.5), size: 20),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
    );
  }

  Widget _buildProfessionalDropdown() {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Icon(
              Icons.wc_outlined,
              color: _goldPrimary.withOpacity(0.5),
              size: 20,
            ),
          ),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _gender,
                dropdownColor: _cardBg,
                icon: const Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.white24,
                  size: 20,
                ),
                isExpanded: true,
                style: const TextStyle(color: _textPrimary, fontSize: 15),
                items: ['male', 'female', 'other'].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value[0].toUpperCase() + value.substring(1)),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _gender = val!),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget _buildProfessionalDatePicker() {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _dob,
          firstDate: DateTime(1950),
          lastDate: DateTime.now(),
          builder: (context, child) {
            return Theme(
              data: ThemeData.dark().copyWith(
                colorScheme: const ColorScheme.dark(
                  primary: _goldPrimary,
                  onPrimary: Colors.black,
                  surface: _bgSecondary,
                ),
              ),
              child: child!,
            );
          },
        );
        if (picked != null) setState(() => _dob = picked);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Icon(
                Icons.calendar_today_outlined,
                color: _goldPrimary.withOpacity(0.5),
                size: 20,
              ),
            ),
            Text(
              "Birth Date: ${_dob.toLocal().toString().split(' ')[0]}",
              style: const TextStyle(color: _textPrimary, fontSize: 15),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right, color: Colors.white24),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePickerSection() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        _buildProfessionalImagePicker(
          'Profile',
          _profilePhoto,
          () => _showSourceSelection('profile'),
          Icons.person_add,
        ),
        _buildProfessionalImagePicker(
          'ID Front',
          _idCardPhoto,
          () => _showSourceSelection('id_card'),
          Icons.badge,
        ),
        _buildProfessionalImagePicker(
          'ID Back',
          _idCardBackPhoto,
          () => _showSourceSelection('id_card_back'),
          Icons.badge,
        ),
        _buildProfessionalImagePicker('Face Scan', _idSelfiePhoto, () async {
          final XFile? result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const SpacallCameraScreen(
                isFace: true,
                isBlinkRequired: true,
              ),
            ),
          );
          if (result != null) setState(() => _idSelfiePhoto = result);
        }, Icons.face_retouching_natural),
      ],
    );
  }

  Widget _buildProfessionalImagePicker(
    String label,
    XFile? image,
    VoidCallback onTap,
    IconData icon,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: _bgSecondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: image != null
                ? _goldPrimary.withOpacity(0.4)
                : Colors.white.withOpacity(0.05),
          ),
        ),
        child: image == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: _goldPrimary.withOpacity(0.4), size: 24),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: _textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    kIsWeb
                        ? Image.network(image.path, fit: BoxFit.cover)
                        : Image.file(File(image.path), fit: BoxFit.cover),
                    Container(color: Colors.black38),
                    const Center(
                      child: Icon(
                        Icons.check_circle,
                        color: _goldPrimary,
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(colors: [_goldAccent, _goldPrimary]),
      ),
      child: ElevatedButton(
        onPressed: _register,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Text(
          'COMPLETE REGISTRATION',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }

  void _showLuxuryDialog(String message, {bool isError = false}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _bgSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isError ? Colors.redAccent : _goldPrimary,
            width: 0.5,
          ),
        ),
        title: Text(
          isError ? "Error" : "Success",
          style: TextStyle(
            color: isError ? Colors.redAccent : _goldPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(message, style: const TextStyle(color: _textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "OK",
              style: TextStyle(
                color: isError ? Colors.redAccent : _goldPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
