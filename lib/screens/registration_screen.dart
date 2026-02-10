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

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  final _apiService = ApiService();

  String _gender = 'male';
  DateTime _dob = DateTime.now().subtract(const Duration(days: 365 * 18));
  bool _isLoading = false;

  XFile? _profilePhoto;
  XFile? _idCardPhoto;
  XFile? _idCardBackPhoto;
  XFile? _idSelfiePhoto;

  final ImagePicker _picker = ImagePicker();

  Future<void> _showSourceSelection(String type) async {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(type, source: ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () async {
                Navigator.pop(context);
                final XFile? result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SpacallCameraScreen(
                      isFace: type == 'profile',
                      isBlinkRequired:
                          false, // No blink required for simple profile/id photos
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

  void _fillMockData() {
    setState(() {
      _firstNameController.text = 'John';
      _lastNameController.text = 'Doe';
      _pinController.text = '123456';
      _confirmPinController.text = '123456';
      _gender = 'male';
      _dob = DateTime(1990, 1, 1);
    });
  }

  Future<void> _register() async {
    if (_firstNameController.text.isEmpty ||
        _lastNameController.text.isEmpty ||
        _pinController.text.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields correctly')),
      );
      return;
    }

    if (_pinController.text != _confirmPinController.text) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('PINs do not match')));
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
        role: 'therapist', // Default role for this app
      );

      if (!mounted) return;

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Therapist Registration'),
        actions: [
          TextButton(
            onPressed: _fillMockData,
            child: const Text(
              'Mock Data',
              style: TextStyle(color: Colors.blue),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _firstNameController,
              decoration: const InputDecoration(labelText: 'First Name'),
            ),
            TextField(
              controller: _lastNameController,
              decoration: const InputDecoration(labelText: 'Last Name'),
            ),
            const SizedBox(height: 16),
            const Text('Gender'),
            DropdownButton<String>(
              value: _gender,
              isExpanded: true,
              items: ['male', 'female', 'other'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (val) => setState(() => _gender = val!),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: Text("Date of Birth: ${_dob.toLocal()}".split(' ')[0]),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _dob,
                  firstDate: DateTime(1950),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _dob = picked);
              },
            ),
            TextField(
              controller: _pinController,
              decoration: const InputDecoration(labelText: '6-Digit PIN'),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
            ),
            TextField(
              controller: _confirmPinController,
              decoration: const InputDecoration(
                labelText: 'Confirm 6-Digit PIN',
              ),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
            ),
            const SizedBox(height: 16),
            const Text(
              'Verification Documents (Optional for Testing)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildImagePicker(
              'Profile Photo',
              _profilePhoto,
              () => _showSourceSelection('profile'),
              icon: Icons.person_add_outlined,
            ),
            _buildImagePicker(
              'ID Card (Front)',
              _idCardPhoto,
              () => _showSourceSelection('id_card'),
              icon: Icons.badge_outlined,
            ),
            _buildImagePicker(
              'ID Card (Back)',
              _idCardBackPhoto,
              () => _showSourceSelection('id_card_back'),
              icon: Icons.badge_outlined,
            ),
            _buildImagePicker(
              'Facial Scan (ID Selfie)',
              _idSelfiePhoto,
              () async {
                final XFile? result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SpacallCameraScreen(
                      isFace: true,
                      isBlinkRequired: true, // Verification scan requires blink
                    ),
                  ),
                );
                if (result != null) {
                  setState(() => _idSelfiePhoto = result);
                }
              },
              icon: Icons.face_retouching_natural,
              isScanner: true,
            ),
            const SizedBox(height: 32),
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _register,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 56),
                    ),
                    child: const Text('Complete Registration'),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePicker(
    String label,
    XFile? image,
    VoidCallback onTap, {
    IconData? icon,
    bool isScanner = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(
              color: isScanner && image == null ? Colors.blue : Colors.grey,
              width: isScanner && image == null ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
            color: isScanner && image == null
                ? Colors.blue.withOpacity(0.05)
                : null,
          ),
          child: image == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon ?? Icons.add_a_photo_outlined,
                      color: isScanner ? Colors.blue : Colors.grey[600],
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      style: TextStyle(
                        color: isScanner ? Colors.blue : Colors.grey[600],
                        fontWeight: isScanner
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    if (isScanner)
                      const Text(
                        '(Tap to start facial scan)',
                        style: TextStyle(fontSize: 10, color: Colors.blue),
                      ),
                  ],
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: kIsWeb
                            ? Image.network(image.path, fit: BoxFit.cover)
                            : Image.file(File(image.path), fit: BoxFit.cover),
                      ),
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
