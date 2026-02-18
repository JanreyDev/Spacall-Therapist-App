import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'welcome_screen.dart';
import 'spacall_camera_screen.dart';
import 'package:geolocator/geolocator.dart';
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
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  final _storeNameController = TextEditingController();
  final _apiService = ApiService();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  String _gender = 'male';
  String _subscriptionTier = 'classic';
  double? _latitude;
  double? _longitude;
  DateTime _dob = DateTime.now().subtract(const Duration(days: 365 * 18));
  bool _isLoading = false;

  XFile? _profilePhoto;
  XFile? _idCardPhoto;
  XFile? _idCardBackPhoto;
  XFile? _idSelfiePhoto;
  XFile? _licensePhoto;
  List<XFile> _certificates = [];

  final ImagePicker _picker = ImagePicker();
  int _currentStep =
      0; // 0: Personal Details, 1: Security, 2: Documents & Creds

  // --- PROFESSIONAL LUXURY CONSTANTS ---
  static const Color _bgPrimary = Color(0xFF0F0F0F);
  static const Color _bgSecondary = Color(0xFF161616);
  static const Color _cardBg = Color(0xFF1E1E1E);
  static const Color _goldPrimary = Color(0xFFD4AF37);
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
    _middleNameController.dispose();
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
                    if (type == 'license') _licensePhoto = result;
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
      maxWidth: 600,
      maxHeight: 600,
      imageQuality: 25,
    );
    if (image != null) {
      setState(() {
        if (type == 'profile') _profilePhoto = image;
        if (type == 'id_card') _idCardPhoto = image;
        if (type == 'id_card_back') _idCardBackPhoto = image;
        if (type == 'id_selfie') _idSelfiePhoto = image;
        if (type == 'license') _licensePhoto = image;
        if (type == 'certificate') _certificates.add(image);
      });
    }
  }

  void _nextStep() {
    if (_currentStep < 2) {
      // Step 1 Validation (Personal Details)
      if (_currentStep == 0) {
        if (_firstNameController.text.trim().isEmpty ||
            _lastNameController.text.trim().isEmpty) {
          _showLuxuryDialog(
            'Please fill in your first and last name',
            isError: true,
          );
          return;
        }
      }
      // Step 2 Validation (Security)
      if (_currentStep == 1) {
        if (_pinController.text.length != 6 ||
            _pinController.text != _confirmPinController.text) {
          _showLuxuryDialog(
            'Please enter matching 6-digit PINs',
            isError: true,
          );
          return;
        }
      }

      setState(() => _currentStep++);
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        children: [
          _buildStepCircle(0, "Personal"),
          _buildStepLine(0),
          _buildStepCircle(1, "Security"),
          _buildStepLine(1),
          _buildStepCircle(2, "Verification"),
        ],
      ),
    );
  }

  Widget _buildStepCircle(int step, String label) {
    bool isActive = _currentStep >= step;
    bool isCurrent = _currentStep == step;

    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? _goldPrimary : Colors.transparent,
            border: Border.all(
              color: isActive ? _goldPrimary : _textSecondary.withOpacity(0.3),
              width: 2,
            ),
            boxShadow: isCurrent
                ? [
                    BoxShadow(
                      color: _goldPrimary.withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ]
                : [],
          ),
          child: Center(
            child: isActive
                ? Icon(
                    _currentStep > step ? Icons.check : Icons.circle,
                    size: 14,
                    color: _bgPrimary,
                  )
                : Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white12,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: isCurrent ? _goldPrimary : _textSecondary,
            fontSize: 10,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildStepLine(int afterStep) {
    bool isActive = _currentStep > afterStep;
    return Expanded(
      child: Container(
        height: 1,
        margin: const EdgeInsets.only(bottom: 20, left: 8, right: 8),
        color: isActive ? _goldPrimary : Colors.white10,
      ),
    );
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

    // MANDATORY PHOTO VALIDATION
    if (_profilePhoto == null) {
      _showLuxuryDialog('Profile photo is required', isError: true);
      return;
    }
    if (_idCardPhoto == null) {
      _showLuxuryDialog('ID card front photo is required', isError: true);
      return;
    }
    if (_idCardBackPhoto == null) {
      _showLuxuryDialog('ID card back photo is required', isError: true);
      return;
    }
    if (_idSelfiePhoto == null) {
      _showLuxuryDialog('Face scan selfie is required', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Initial Registration (Text Only)
      final response = await _apiService.registerProfile(
        mobileNumber: widget.mobileNumber,
        firstName: _firstNameController.text.trim(),
        middleName: _middleNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        gender: _gender,
        dob: _dob.toIso8601String().split('T')[0],
        pin: _pinController.text.trim(),
        profilePhoto: null,
        idCardPhoto: null,
        idCardBackPhoto: null,
        idSelfiePhoto: null,
        role: 'therapist',
        customerTier: _subscriptionTier,
        storeName: _subscriptionTier == 'store'
            ? _storeNameController.text.trim()
            : null,
        latitude: _latitude,
        longitude: _longitude,
      );

      final token = response['token'];
      if (token == null) throw Exception('No token returned');

      try {
        // 2a. Mandatory Photos
        final mandatoryUploads = {
          'profile_photo': _profilePhoto,
          'id_card_photo': _idCardPhoto,
          'id_card_back_photo': _idCardBackPhoto,
          'id_selfie_photo': _idSelfiePhoto,
        };

        for (var entry in mandatoryUploads.entries) {
          if (entry.value != null) {
            debugPrint("Uploading ${entry.key}...");
            await _apiService.uploadProfileImage(
              token: token,
              type: entry.key,
              imageFile: entry.value,
            );
          }
        }

        // 2b. Optional Credentials
        if (_licensePhoto != null) {
          debugPrint("Uploading License...");
          await _apiService.uploadProfileImage(
            token: token,
            type: 'license_photo',
            imageFile: _licensePhoto,
          );
        }

        for (var i = 0; i < _certificates.length; i++) {
          debugPrint("Uploading Certificate ${i + 1}...");
          await _apiService.uploadProfileImage(
            token: token,
            type: 'certificate_photo',
            imageFile: _certificates[i],
          );
        }
      } catch (e) {
        debugPrint("Sequential Upload Error: $e");
        _showLuxuryDialog(
          'Profile created, but some credentials failed to upload. You can update them later in your profile.\nError: $e',
          isError: true,
        );
        // We still consider registration "successful" enough to proceed
      }

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

  Widget _buildGoldButton({
    required String text,
    required VoidCallback onPressed,
    bool isSmall = false,
  }) {
    return Container(
      width: double.infinity,
      height: isSmall ? 48 : 58,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: [
            Color(0xFFB8860B),
            _goldPrimary,
            Color(0xFFFFD700),
            _goldPrimary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          _goldPrimary
              .withOpacity(0.3)
              .asShadow(blur: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- UI BUILDING ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgPrimary,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: _bgPrimary,
        elevation: 0,
        centerTitle: true,
        leading: _currentStep > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: _previousStep,
              )
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
        title: const Text(
          'THERAPIST REGISTRATION',
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
          child: SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildIntroHeader(),
                  const SizedBox(height: 24),
                  _buildStepIndicator(),
                  const SizedBox(height: 8),

                  if (_currentStep == 0) ...[
                    _buildSectionLabel("PERSONAL DETAILS"),
                    _buildFormCard([
                      _buildProfessionalTextField(
                        controller: _firstNameController,
                        label: 'First Name',
                        icon: Icons.person_outline,
                      ),
                      const Divider(color: Colors.white10),
                      _buildProfessionalTextField(
                        controller: _middleNameController,
                        label: 'Middle Name (Optional)',
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
                      const Divider(color: Colors.white10),
                      _buildProfessionalTierSelector(),
                      if (_subscriptionTier == 'store') ...[
                        const Divider(color: Colors.white10),
                        _buildProfessionalTextField(
                          controller: _storeNameController,
                          label: 'Store / Business Name',
                          icon: Icons.storefront_outlined,
                        ),
                      ],
                    ]),
                  ],

                  if (_currentStep == 1) ...[
                    _buildSectionLabel("SECURITY"),
                    Text(
                      "Create a 6-digit PIN for your therapist portal access.",
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
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
                  ],

                  if (_currentStep == 2) ...[
                    _buildSectionLabel("MANDATORY DOCUMENTS"),
                    Text(
                      "High-quality ID and face scans are required for verification.",
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildImagePickerSection(),

                    const SizedBox(height: 32),
                    _buildSectionLabel("PROFESSIONAL CREDENTIALS (OPTIONAL)"),
                    _buildCredentialsSection(),
                    const SizedBox(height: 24),
                  ],

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 8,
          bottom: MediaQuery.of(context).padding.bottom + 16,
        ),
        child: _isLoading
            ? const SizedBox(
                height: 58,
                child: Center(
                  child: CircularProgressIndicator(color: _goldPrimary),
                ),
              )
            : Row(
                children: [
                  if (_currentStep > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _previousStep,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: _goldPrimary),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          "BACK",
                          style: TextStyle(
                            color: _goldPrimary,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ),
                  if (_currentStep > 0) const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: _buildGoldButton(
                      text: _currentStep == 2 ? "PROCEED" : "NEXT STEP",
                      onPressed: _currentStep == 2 ? _register : _nextStep,
                    ),
                  ),
                ],
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
                items: ['male', 'female', 'lgbt'].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(
                      value == 'lgbt'
                          ? 'LGBT'
                          : value[0].toUpperCase() + value.substring(1),
                    ),
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

  Widget _buildProfessionalTierSelector() {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Icon(
              Icons.star_outline_rounded,
              color: _goldPrimary.withOpacity(0.5),
              size: 20,
            ),
          ),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _subscriptionTier,
                dropdownColor: _cardBg,
                icon: const Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.white24,
                  size: 20,
                ),
                isExpanded: true,
                style: const TextStyle(color: _textPrimary, fontSize: 15),
                items:
                    [
                      {'value': 'classic', 'label': 'Classic Tier'},
                      {'value': 'store', 'label': 'Store Tier'},
                    ].map((tier) {
                      return DropdownMenuItem<String>(
                        value: tier['value'],
                        child: Text(tier['label']!),
                      );
                    }).toList(),
                onChanged: (val) {
                  setState(() => _subscriptionTier = val!);
                  if (val == 'store') {
                    _getCurrentLocation();
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
        });
      }
    } catch (e) {
      debugPrint("Error fetching location: $e");
    }
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
          isRequired: true,
        ),
        _buildProfessionalImagePicker(
          'ID Front',
          _idCardPhoto,
          () => _showSourceSelection('id_card'),
          Icons.badge,
          isRequired: true,
        ),
        _buildProfessionalImagePicker(
          'ID Back',
          _idCardBackPhoto,
          () => _showSourceSelection('id_card_back'),
          Icons.badge,
          isRequired: true,
        ),
        _buildProfessionalImagePicker(
          'Face Scan',
          _idSelfiePhoto,
          () async {
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
          },
          Icons.face_retouching_natural,
          isRequired: true,
        ),
      ],
    );
  }

  Widget _buildProfessionalImagePicker(
    String label,
    XFile? image,
    VoidCallback onTap,
    IconData icon, {
    bool isRequired = false,
  }) {
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

  Widget _buildCredentialsSection() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        _buildProfessionalImagePicker(
          'License',
          _licensePhoto,
          () => _showSourceSelection('license'),
          Icons.card_membership_rounded,
          isRequired: false,
        ),
        _buildAddCertificateButton(),
        ...List.generate(
          _certificates.length,
          (index) => _buildCertificateItem(index),
        ),
      ],
    );
  }

  Widget _buildAddCertificateButton() {
    return GestureDetector(
      onTap: () => _pickImage('certificate', source: ImageSource.gallery),
      child: Container(
        decoration: BoxDecoration(
          color: _bgSecondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              color: _goldPrimary.withOpacity(0.4),
              size: 24,
            ),
            const SizedBox(height: 8),
            const Text(
              "Add Certificate",
              style: TextStyle(
                color: _textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCertificateItem(int index) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _goldPrimary.withOpacity(0.4), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          fit: StackFit.expand,
          children: [
            kIsWeb
                ? Image.network(_certificates[index].path, fit: BoxFit.cover)
                : Image.file(
                    File(_certificates[index].path),
                    fit: BoxFit.cover,
                  ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54],
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () => setState(() => _certificates.removeAt(index)),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 14),
                ),
              ),
            ),
            const Positioned(
              bottom: 8,
              left: 8,
              child: Icon(
                Icons.verified_user_rounded,
                color: _goldPrimary,
                size: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLuxuryDialog(String message, {bool isError = false}) {
    showDialog(
      context: context,
      barrierDismissible: !isError,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: (isError ? Colors.redAccent : _goldPrimary).withOpacity(0.5),
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
                color: isError ? Colors.redAccent : _goldPrimary,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                isError ? 'ERROR' : 'SUCCESS',
                style: const TextStyle(
                  color: _goldPrimary,
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
              _buildGoldButton(
                text: 'CONTINUE',
                onPressed: () => Navigator.pop(context),
                isSmall: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension ColorExtension on Color {
  BoxShadow asShadow({
    double blur = 10,
    Offset offset = const Offset(0, 4),
    double spread = 0,
  }) {
    return BoxShadow(
      color: this,
      blurRadius: blur,
      offset: offset,
      spreadRadius: spread,
    );
  }
}
