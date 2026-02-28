import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../theme_provider.dart';
import '../api_service.dart';

class VipUpgradeScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const VipUpgradeScreen({super.key, required this.userData});

  @override
  State<VipUpgradeScreen> createState() => _VipUpgradeScreenState();
}

class _VipUpgradeScreenState extends State<VipUpgradeScreen> {
  final PageController _pageController = PageController();
  final ApiService _apiService = ApiService();
  final ImagePicker _picker = ImagePicker();

  int _currentStep = 0;
  final int _totalSteps = 3;
  bool _isLoading = false;

  // Form Controllers
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _expController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();

  // Gallery
  final List<XFile> _galleryImages = [];

  final Color goldColor = const Color(0xFFEBC14F);

  void _prevStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _pickGalleryImages() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage(
        imageQuality: 25,
        maxWidth: 1000,
      );
      if (images.isNotEmpty) {
        setState(() {
          _galleryImages.addAll(images);
        });
      }
    } catch (e) {
      debugPrint('Error picking images: $e');
    }
  }

  void _removeGalleryImage(int index) {
    setState(() {
      _galleryImages.removeAt(index);
    });
  }

  Future<void> _submitApplication() async {
    setState(() => _isLoading = true);

    try {
      final String token = widget.userData['token'];

      // 1. Upload Gallery Images (Sequential)
      for (var image in _galleryImages) {
        await _apiService.uploadProfileImage(
          token: token,
          type: 'gallery_photo',
          imageFile: image,
        );
      }

      // 2. Submit Upgrade Request Details
      await _apiService.submitVipApplication(
        token: token,
        nickname: _nicknameController.text,
        age: int.tryParse(_ageController.text) ?? 18,
        address: null, // Removed from UI as requested
        experience: int.tryParse(_expController.text) ?? 0,
        skills: 'General', // Default value since it was removed
        bio: _bioController.text,
      );

      if (!mounted) return;

      _showSuccessDialog();
    } catch (e) {
      debugPrint('Error submitting application: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: goldColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_outline,
                color: goldColor,
                size: 64,
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              "Application Submitted",
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              "Your VIP upgrade request has been received. Our team will review your professional profile within 24-48 hours.",
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(
                    context,
                    true,
                  ); // Go back to Account with success signal
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: goldColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  "BACK TO PROFILE",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 20,
          ),
          onPressed: _prevStep,
        ),
        title: Text(
          "VIP Application",
          style: TextStyle(
            color: goldColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _buildStepIndicator(),
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (int step) {
                setState(() => _currentStep = step);
              },
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildStep1(themeProvider), // Nickname & Age
                _buildStep2(themeProvider), // Experience & Bio
                _buildStep3(themeProvider), // Photos
              ],
            ),
          ),
          _isLoading
              ? Container(
                  padding: const EdgeInsets.all(20),
                  child: const Center(
                    child: CircularProgressIndicator(color: Color(0xFFEBC14F)),
                  ),
                )
              : _buildBottomNavbar(),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        children: List.generate(_totalSteps, (index) {
          bool isActive = index <= _currentStep;
          return Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: index < _totalSteps - 1 ? 8 : 0),
              decoration: BoxDecoration(
                color: isActive ? goldColor : Colors.white12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStep1(ThemeProvider themeProvider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            "Public Profile",
            "This information will be visible to potential clients on the platform.",
          ),
          const SizedBox(height: 32),
          _buildFormField(
            "Nickname",
            _nicknameController,
            Icons.face_unlock_outlined,
            "Enter your brand name...",
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              "Note: This will be your screen name (e.g., your professional alias).",
              style: TextStyle(
                color: goldColor.withOpacity(0.6),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildFormField(
            "Age",
            _ageController,
            Icons.cake_outlined,
            "Enter your age (18-35 only)...",
            keyboardType: TextInputType.number,
          ),
        ],
      ),
    );
  }

  Widget _buildStep2(ThemeProvider themeProvider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            "Professional Background",
            "Tell us about your experience and providing a brief bio.",
          ),
          const SizedBox(height: 32),
          _buildFormField(
            "Years of Experience",
            _expController,
            Icons.history,
            "Enter number of years...",
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 24),
          _buildFormField(
            "About Me (Bio)",
            _bioController,
            Icons.description_outlined,
            "Description of yourself and your service...",
            maxLines: 4,
          ),
          const SizedBox(height: 32),
          _buildReviewCard(),
        ],
      ),
    );
  }

  Widget _buildStep3(ThemeProvider themeProvider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            "VIP Portfolio Gallery",
            "Please upload exactly 3 clear professional photos of yourself.",
          ),
          const SizedBox(height: 32),
          _buildLabel("Upload 3 Photos"),
          const SizedBox(height: 16),
          _buildGalleryGrid(),
          const SizedBox(height: 24),
          if (_galleryImages.length < 3) _buildAddImageButton(),
        ],
      ),
    );
  }

  Widget _buildGalleryGrid() {
    if (_galleryImages.isEmpty) {
      return Container(
        height: 200,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white12, style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_library_outlined,
              color: goldColor.withOpacity(0.3),
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              "Your gallery is empty",
              style: TextStyle(color: Colors.white.withOpacity(0.3)),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _galleryImages.length,
      itemBuilder: (context, index) {
        return Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                image: DecorationImage(
                  image: FileImage(File(_galleryImages[index].path)),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () => _removeGalleryImage(index),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 14),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAddImageButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _pickGalleryImages,
        icon: const Icon(Icons.add_a_photo_outlined, size: 20),
        label: const Text("ADD GALLERY IMAGES"),
        style: OutlinedButton.styleFrom(
          foregroundColor: goldColor,
          side: BorderSide(color: goldColor.withOpacity(0.5)),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: goldColor.withOpacity(0.9),
        fontSize: 14,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildFormField(
    String label,
    TextEditingController controller,
    IconData icon,
    String hint, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(label),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
            prefixIcon: Icon(icon, color: goldColor.withOpacity(0.5)),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: goldColor.withOpacity(0.5)),
            ),
          ),
        ),
      ],
    );
  }

  void _nextStep() {
    // Step 0: Nickname and Age Validation
    if (_currentStep == 0) {
      if (_nicknameController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a nickname')),
        );
        return;
      }
      final age = int.tryParse(_ageController.text) ?? 0;
      if (age < 18 || age > 35) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Age must be between 18 and 35 years old'),
          ),
        );
        return;
      }
    }

    // Step 1: Experience & Bio
    if (_currentStep == 1) {
      if (_expController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter your years of experience'),
          ),
        );
        return;
      }
      if (_bioController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please provide an "About Me" description'),
          ),
        );
        return;
      }
    }

    // Step 2: Photos (exactly 3)
    if (_currentStep == 2) {
      if (_galleryImages.length < 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please upload at least 3 photos')),
        );
        return;
      }
    }

    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _submitApplication();
    }
  }

  Widget _buildReviewCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: goldColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: goldColor.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_outlined, color: goldColor, size: 20),
              const SizedBox(width: 8),
              const Text(
                "VIP Standards Check",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            "By submitting, you agree to Spacall VIP quality standards and community guidelines.",
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavbar() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: 60,
          child: ElevatedButton(
            onPressed: _nextStep,
            style: ElevatedButton.styleFrom(
              backgroundColor: goldColor,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            child: Text(
              _currentStep == _totalSteps - 1
                  ? "SUBMIT APPLICATION"
                  : "CONTINUE",
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
