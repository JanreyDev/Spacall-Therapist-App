import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../api_service.dart';
import '../theme_provider.dart';
import '../widgets/safe_network_image.dart';
import '../widgets/luxury_success_modal.dart';
import '../widgets/luxury_error_modal.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const EditProfileScreen({super.key, required this.userData});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final ApiService _apiService = ApiService();
  final ImagePicker _picker = ImagePicker();

  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _nicknameController;
  late TextEditingController _dobController;
  late TextEditingController _emailController;

  String? _gender;
  File? _imageFile;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final user = widget.userData['user'] ?? {};
    _firstNameController = TextEditingController(text: user['first_name']);
    _lastNameController = TextEditingController(text: user['last_name']);
    _nicknameController = TextEditingController(
      text: user['nickname'] ?? user['middle_name'],
    );
    _emailController = TextEditingController(text: user['email']);
    _dateOfBirth = user['date_of_birth'];
    _dobController = TextEditingController(
      text: _dateOfBirth != null
          ? DateFormat('MMMM d, yyyy').format(DateTime.parse(_dateOfBirth!))
          : '',
    );
    _gender = user['gender'];
  }

  String? _dateOfBirth;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _nicknameController.dispose();
    _dobController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 600,
      maxHeight: 600,
      imageQuality: 70,
    );

    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth != null
          ? DateTime.tryParse(_dateOfBirth!) ?? DateTime(2000)
          : DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFEBC14F),
              onPrimary: Colors.black,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF1E1E1E),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _dateOfBirth = DateFormat('yyyy-MM-dd').format(picked);
        _dobController.text = DateFormat('MMMM d, yyyy').format(picked);
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final updatedData = await _apiService.updateUserProfile(
        token: widget.userData['token'],
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        nickname: _nicknameController.text.trim(),
        dateOfBirth: _dateOfBirth,
        email: _emailController.text.trim(),
        gender: _gender,
        imageFile: _imageFile,
      );

      if (!mounted) return;

      setState(() {
        widget.userData['user'] = updatedData['user'];
      });

      showDialog(
        context: context,
        builder: (context) => LuxurySuccessModal(
          title: 'PROFILE UPDATED',
          message: 'Your personal information has been successfully updated.',
          onConfirm: () {
            Navigator.pop(context); // Close dialog
            Navigator.pop(context, true); // Close screen
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => LuxuryErrorModal(
          title: 'UPDATE FAILED',
          message: e.toString().replaceAll("Exception:", "").trim(),
          onConfirm: () => Navigator.pop(context),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final goldColor = const Color(0xFFEBC14F);
    final backgroundColor = isDark ? Colors.black : Colors.white;
    final cardColor = isDark
        ? const Color(0xFF1A1A1A)
        : const Color(0xFFF5F5F5);
    final textColor = themeProvider.textColor;
    final hintColor = textColor.withOpacity(0.5);

    final user = widget.userData['user'] ?? {};
    String? profileUrl = ApiService.normalizePhotoUrl(
      user['profile_photo_url'],
    );

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Edit Profile",
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_isLoading)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: goldColor,
                  ),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _saveProfile,
              child: Text(
                "SAVE",
                style: TextStyle(
                  color: goldColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile Picture
                Center(
                  child: Stack(
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: goldColor.withOpacity(0.5),
                            width: 2,
                          ),
                          color: cardColor,
                        ),
                        child: ClipOval(
                          child: _imageFile != null
                              ? Image.file(_imageFile!, fit: BoxFit.cover)
                              : (profileUrl != null && profileUrl.isNotEmpty
                                    ? SafeNetworkImage(
                                        url: profileUrl,
                                        fit: BoxFit.cover,
                                        errorWidget: Icon(
                                          Icons.person,
                                          size: 60,
                                          color: goldColor,
                                        ),
                                      )
                                    : Icon(
                                        Icons.person,
                                        size: 60,
                                        color: goldColor,
                                      )),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _pickImage,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: goldColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: backgroundColor,
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              size: 16,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Form Fields
                _buildLabel("First Name", textColor),
                _buildTextField(
                  controller: _firstNameController,
                  hint: "Enter your first name",
                  icon: Icons.person_outline,
                  cardColor: cardColor,
                  textColor: textColor,
                  hintColor: hintColor,
                  goldColor: goldColor,
                ),
                const SizedBox(height: 20),

                _buildLabel("Last Name", textColor),
                _buildTextField(
                  controller: _lastNameController,
                  hint: "Enter your last name",
                  icon: Icons.person_outline,
                  cardColor: cardColor,
                  textColor: textColor,
                  hintColor: hintColor,
                  goldColor: goldColor,
                ),
                const SizedBox(height: 20),

                _buildLabel("Nickname", textColor),
                _buildTextField(
                  controller: _nicknameController,
                  hint: "Enter your nickname",
                  icon: Icons.badge_outlined,
                  cardColor: cardColor,
                  textColor: textColor,
                  hintColor: hintColor,
                  goldColor: goldColor,
                ),
                const SizedBox(height: 20),

                _buildLabel("Date of Birth & Age", textColor),
                GestureDetector(
                  onTap: () => _selectDate(context),
                  child: AbsorbPointer(
                    child: _buildTextField(
                      controller: _dobController,
                      hint: "Select your date of birth",
                      icon: Icons.calendar_today_outlined,
                      cardColor: cardColor,
                      textColor: textColor,
                      hintColor: hintColor,
                      goldColor: goldColor,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                _buildLabel("Email Address", textColor),
                _buildTextField(
                  controller: _emailController,
                  hint: "Enter your email",
                  icon: Icons.email_outlined,
                  cardColor: cardColor,
                  textColor: textColor,
                  hintColor: hintColor,
                  goldColor: goldColor,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 20),

                _buildLabel("Gender", textColor),
                Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.transparent),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _gender,
                      dropdownColor: cardColor,
                      icon: Icon(Icons.arrow_drop_down, color: goldColor),
                      style: TextStyle(color: textColor, fontSize: 16),
                      hint: Text(
                        "Select Gender",
                        style: TextStyle(color: hintColor),
                      ),
                      items: ['male', 'female', 'lgbt'].map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(
                            value[0].toUpperCase() + value.substring(1),
                          ),
                        );
                      }).toList(),
                      onChanged: (newValue) {
                        setState(() {
                          _gender = newValue;
                        });
                      },
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

  Widget _buildLabel(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required Color cardColor,
    required Color textColor,
    required Color hintColor,
    required Color goldColor,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.transparent),
      ),
      child: TextFormField(
        controller: controller,
        style: TextStyle(color: textColor),
        keyboardType: keyboardType,
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'This field is required';
          }
          return null;
        },
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: hintColor),
          prefixIcon: Icon(icon, color: goldColor.withOpacity(0.7)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}
