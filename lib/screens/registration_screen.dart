import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import '../api_service.dart';
import 'welcome_screen.dart';

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
  final _apiService = ApiService();

  String _gender = 'male';
  DateTime _dob = DateTime.now().subtract(const Duration(days: 365 * 18));
  bool _isLoading = false;

  XFile? _profilePhoto;
  XFile? _idCardPhoto;
  XFile? _idSelfiePhoto;

  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(String type) async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        if (type == 'profile') _profilePhoto = image;
        if (type == 'id_card') _idCardPhoto = image;
        if (type == 'id_selfie') _idSelfiePhoto = image;
      });
    }
  }

  void _fillMockData() {
    setState(() {
      _firstNameController.text = 'John';
      _lastNameController.text = 'Doe';
      _pinController.text = '123456';
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
        idSelfiePhoto: _idSelfiePhoto,
        role: 'therapist', // Default role for this app
      );

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
              () => _pickImage('profile'),
            ),
            _buildImagePicker(
              'ID Card',
              _idCardPhoto,
              () => _pickImage('id_card'),
            ),
            _buildImagePicker(
              'ID Selfie',
              _idSelfiePhoto,
              () => _pickImage('id_selfie'),
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

  Widget _buildImagePicker(String label, XFile? image, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 100,
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(8),
          ),
          child: image == null
              ? Center(child: Text(label))
              : kIsWeb
              ? Image.network(image.path, fit: BoxFit.cover)
              : Image.file(File(image.path), fit: BoxFit.cover),
        ),
      ),
    );
  }
}
