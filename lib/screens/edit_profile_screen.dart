import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
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
  late TextEditingController _middleNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _nicknameController;
  late TextEditingController _dobController;
  late TextEditingController _ageController;
  late TextEditingController _emailController;

  String? _gender;
  File? _imageFile;
  bool _isLoading = false;
  String? _dateOfBirth;

  @override
  void initState() {
    super.initState();
    final user = widget.userData['user'] ?? {};
    _firstNameController = TextEditingController(text: user['first_name']);
    _middleNameController = TextEditingController(text: user['middle_name']);
    _lastNameController = TextEditingController(text: user['last_name']);
    _nicknameController = TextEditingController(text: user['nickname']);
    _emailController = TextEditingController(text: user['email']);
    _dateOfBirth = user['date_of_birth'];
    _dobController = TextEditingController(
      text: _dateOfBirth != null && _dateOfBirth!.isNotEmpty
          ? DateFormat('MMMM d, yyyy').format(DateTime.parse(_dateOfBirth!))
          : '',
    );
    _ageController = TextEditingController(text: user['age']?.toString() ?? '');
    _gender = user['gender'];

    if (_ageController.text.isEmpty && _dateOfBirth != null) {
      _calculateAge(DateTime.parse(_dateOfBirth!));
    }
  }

  void _calculateAge(DateTime birthDate) {
    DateTime today = DateTime.now();
    int age = today.year - birthDate.year;
    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    setState(() {
      _ageController.text = age.toString();
    });
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _nicknameController.dispose();
    _dobController.dispose();
    _ageController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
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
        _calculateAge(picked);
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
        middleName: _middleNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        nickname: _nicknameController.text.trim(),
        age: _ageController.text.trim(),
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
          message:
              'Your profile has been successfully updated with the new information.',
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
    const goldColor = Color(0xFFEBC14F);
    final backgroundColor = isDark ? Colors.black : const Color(0xFFF8F8F8);
    final cardColor = isDark ? const Color(0xFF121212) : Colors.white;
    final textColor = themeProvider.textColor;

    final user = widget.userData['user'] ?? {};
    String? profileUrl = ApiService.normalizePhotoUrl(
      user['profile_photo_url'],
    );

    return Scaffold(
      backgroundColor: backgroundColor,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(backgroundColor, textColor),
          SliverToBoxAdapter(
            child: Form(
              key: _formKey,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    _buildProfileImagePicker(
                      profileUrl,
                      goldColor,
                      backgroundColor,
                    ),
                    const SizedBox(height: 40),

                    _buildFullWidthSection("BASIC INFORMATION", [
                      _buildPremiumField(
                        label: "Nickname",
                        controller: _nicknameController,
                        hint: "Expert Nickname",
                        icon: Icons.alternate_email_rounded,
                        textColor: textColor,
                        goldColor: goldColor,
                        cardColor: cardColor,
                      ),
                      const SizedBox(height: 20),
                      _buildPremiumField(
                        label: "First Name",
                        controller: _firstNameController,
                        hint: "Enter first name",
                        icon: Icons.person_outline_rounded,
                        textColor: textColor,
                        goldColor: goldColor,
                        cardColor: cardColor,
                      ),
                      const SizedBox(height: 20),
                      _buildPremiumField(
                        label: "Middle Name",
                        controller: _middleNameController,
                        hint: "Optional middle name",
                        icon: Icons.person_outline_rounded,
                        textColor: textColor,
                        goldColor: goldColor,
                        cardColor: cardColor,
                        required: false,
                      ),
                      const SizedBox(height: 20),
                      _buildPremiumField(
                        label: "Last Name",
                        controller: _lastNameController,
                        hint: "Enter last name",
                        icon: Icons.person_outline_rounded,
                        textColor: textColor,
                        goldColor: goldColor,
                        cardColor: cardColor,
                      ),
                    ]),

                    const SizedBox(height: 32),

                    _buildFullWidthSection("PERSONAL DETAILS", [
                      GestureDetector(
                        onTap: () => _selectDate(context),
                        child: AbsorbPointer(
                          child: _buildPremiumField(
                            label: "Date of Birth",
                            controller: _dobController,
                            hint: "Select birth date",
                            icon: Icons.calendar_month_rounded,
                            textColor: textColor,
                            goldColor: goldColor,
                            cardColor: cardColor,
                            readOnly: true,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildPremiumField(
                        label: "Age",
                        controller: _ageController,
                        hint: "Calculated age",
                        icon: Icons.auto_graph_rounded,
                        textColor: textColor,
                        goldColor: goldColor,
                        cardColor: cardColor,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 20),
                      _buildGenderPicker(textColor, goldColor, cardColor),
                    ]),

                    const SizedBox(height: 32),

                    _buildFullWidthSection("CONTACT INFO", [
                      _buildPremiumField(
                        label: "Email Address",
                        controller: _emailController,
                        hint: "your@email.com",
                        icon: Icons.email_outlined,
                        textColor: textColor,
                        goldColor: goldColor,
                        cardColor: cardColor,
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ]),

                    const SizedBox(height: 60),
                    _buildSaveButton(goldColor),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(Color bgColor, Color textColor) {
    return SliverAppBar(
      backgroundColor: bgColor,
      floating: true,
      elevation: 0,
      centerTitle: true,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: textColor,
            size: 18,
          ),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        "EDIT PROFILE",
        style: GoogleFonts.outfit(
          color: textColor,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildProfileImagePicker(
    String? profileUrl,
    Color goldColor,
    Color bgColor,
  ) {
    return Center(
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [goldColor, goldColor.withOpacity(0.2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: goldColor.withOpacity(0.2),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(shape: BoxShape.circle, color: bgColor),
              child: ClipOval(
                child: _imageFile != null
                    ? Image.file(_imageFile!, fit: BoxFit.cover)
                    : (profileUrl != null && profileUrl.isNotEmpty
                          ? SafeNetworkImage(
                              url: profileUrl,
                              fit: BoxFit.cover,
                              errorWidget: Icon(
                                Icons.person_rounded,
                                size: 60,
                                color: goldColor.withOpacity(0.5),
                              ),
                            )
                          : Icon(
                              Icons.person_rounded,
                              size: 60,
                              color: goldColor.withOpacity(0.5),
                            )),
              ),
            ),
          ),
          Positioned(
            bottom: 4,
            right: 4,
            child: GestureDetector(
              onTap: _pickImage,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: goldColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: bgColor, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  size: 18,
                  color: Colors.black,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullWidthSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 16),
          child: Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: const Color(0xFFEBC14F).withOpacity(0.7),
              letterSpacing: 1.5,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _buildPremiumField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required Color textColor,
    required Color goldColor,
    required Color cardColor,
    bool required = true,
    bool readOnly = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: TextFormField(
            controller: controller,
            readOnly: readOnly,
            style: GoogleFonts.outfit(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            keyboardType: keyboardType,
            validator: required
                ? (value) =>
                      (value == null || value.isEmpty) ? 'Required' : null
                : null,
            decoration: InputDecoration(
              labelText: label,
              labelStyle: GoogleFonts.outfit(
                color: textColor.withOpacity(0.4),
                fontSize: 13,
              ),
              hintText: hint,
              hintStyle: TextStyle(color: textColor.withOpacity(0.2)),
              prefixIcon: Icon(
                icon,
                color: goldColor.withOpacity(0.6),
                size: 20,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGenderPicker(Color textColor, Color goldColor, Color cardColor) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButtonFormField<String>(
          value: _gender,
          dropdownColor: cardColor,
          elevation: 16,
          decoration: InputDecoration(
            labelText: "Gender",
            labelStyle: GoogleFonts.outfit(
              color: textColor.withOpacity(0.4),
              fontSize: 13,
            ),
            border: InputBorder.none,
            prefixIcon: Icon(
              Icons.transgender_rounded,
              color: goldColor.withOpacity(0.6),
              size: 20,
            ),
            contentPadding: EdgeInsets.zero,
          ),
          icon: Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Icon(Icons.expand_more_rounded, color: goldColor),
          ),
          style: GoogleFonts.outfit(
            color: textColor,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          hint: Text(
            "Select Gender",
            style: TextStyle(color: textColor.withOpacity(0.2)),
          ),
          items: ['male', 'female', 'lgbt'].map((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value[0].toUpperCase() + value.substring(1)),
            );
          }).toList(),
          onChanged: (newValue) => setState(() => _gender = newValue),
          validator: (value) => value == null ? 'Required' : null,
        ),
      ),
    );
  }

  Widget _buildSaveButton(Color goldColor) {
    return GestureDetector(
      onTap: _isLoading ? null : _saveProfile,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: _isLoading
                ? [Colors.grey.shade800, Colors.grey.shade900]
                : [const Color(0xFFB8860B), goldColor, const Color(0xFFFFD700)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            if (!_isLoading)
              BoxShadow(
                color: goldColor.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
          ],
        ),
        child: Center(
          child: _isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  'UPDATE PROFILE',
                  style: GoogleFonts.outfit(
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 2,
                  ),
                ),
        ),
      ),
    );
  }
}
