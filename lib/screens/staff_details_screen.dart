import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:spacall_therapist_app/api_service.dart';
import 'package:spacall_therapist_app/widgets/luxury_success_modal.dart';

class StaffDetailsScreen extends StatefulWidget {
  final String token;
  final Map<String, dynamic> staff;

  const StaffDetailsScreen({
    super.key,
    required this.token,
    required this.staff,
  });

  @override
  State<StaffDetailsScreen> createState() => _StaffDetailsScreenState();
}

class _StaffDetailsScreenState extends State<StaffDetailsScreen> {
  final ApiService _apiService = ApiService();
  late Map<String, dynamic> _staff;

  @override
  void initState() {
    super.initState();
    _staff = Map<String, dynamic>.from(widget.staff);
    _setupWebSocket();
  }

  void _setupWebSocket() {
    _apiService.listenForStoreStaffUpdates(
      _staff['store_profile_id'],
      (updatedStaff) {
        if (!mounted) return;
        if (updatedStaff['id'] == _staff['id']) {
          setState(() {
            _staff = updatedStaff;
          });
        }
      },
      (deletedId) {
        if (!mounted) return;
        if (deletedId == _staff['id']) {
          Navigator.pop(context, true);
        }
      },
    );
  }

  Future<void> _deleteStaff() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        title: const Text(
          'DELETE STAFF',
          style: TextStyle(
            color: Color(0xFFEBC14F),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'Are you sure you want to remove this therapist from your store?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Colors.white38),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('DELETE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _showLoading();
      try {
        await _apiService.deleteStoreStaff(widget.token, _staff['id']);
        if (!mounted) return;
        Navigator.pop(context); // Close loading
        Navigator.pop(context, true); // Go back with refresh signal
      } catch (e) {
        if (!mounted) return;
        Navigator.pop(context); // Close loading
        _showError(e.toString());
      }
    }
  }

  void _showEditStaffDialog() {
    final nameController = TextEditingController(text: _staff['name']);
    final bioController = TextEditingController(text: _staff['bio']);
    final expController = TextEditingController(
      text: _staff['years_of_experience'].toString(),
    );
    XFile? selectedImage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (modalContext, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Color(0xFF0A0A0A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'EDIT THERAPIST',
                    style: TextStyle(
                      color: Color(0xFFEBC14F),
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white54),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: () async {
                          final picker = ImagePicker();
                          final img = await picker.pickImage(
                            source: ImageSource.gallery,
                          );
                          if (img != null) {
                            setModalState(() => selectedImage = img);
                          }
                        },
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFEBC14F).withOpacity(0.3),
                            ),
                          ),
                          child: (selectedImage != null)
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(50),
                                  child: kIsWeb
                                      ? Image.network(
                                          selectedImage!.path,
                                          fit: BoxFit.cover,
                                        )
                                      : Image.file(
                                          File(selectedImage!.path),
                                          fit: BoxFit.cover,
                                        ),
                                )
                              : (_staff['profile_photo_url'] != null)
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(50),
                                  child: Image.network(
                                    ApiService.normalizePhotoUrl(
                                      _staff['profile_photo_url'],
                                    )!,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : const Icon(
                                  Icons.add_a_photo_outlined,
                                  color: Color(0xFFEBC14F),
                                  size: 30,
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildTextField(
                        nameController,
                        'FULL NAME',
                        Icons.person_outline,
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        expController,
                        'YEARS OF EXPERIENCE',
                        Icons.star_outline,
                        isNumber: true,
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        bioController,
                        'BIO / DESCRIPTION',
                        Icons.description_outlined,
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.isEmpty ||
                        expController.text.isEmpty)
                      return;
                    Navigator.pop(modalContext);
                    _showLoading();
                    try {
                      final response = await _apiService.updateStoreStaff(
                        token: widget.token,
                        staffId: _staff['id'],
                        name: nameController.text,
                        bio: bioController.text,
                        yearsOfExperience:
                            int.tryParse(expController.text) ?? 0,
                        photo: selectedImage,
                      );
                      if (!mounted) return;
                      Navigator.pop(context); // Close loading
                      setState(() {
                        _staff = response;
                      });
                      _showSuccess(
                        'STAFF UPDATED',
                        'Staff profile has been updated successfully.',
                      );
                    } catch (e) {
                      if (!mounted) return;
                      Navigator.pop(context); // Close loading
                      _showError(e.toString());
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEBC14F),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'UPDATE PROFILE',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ),
              SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool isNumber = false,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: const Color(0xFFEBC14F), size: 20),
            filled: true,
            fillColor: Colors.white.withOpacity(0.03),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
      ],
    );
  }

  void _showLoading() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFEBC14F)),
      ),
    );
  }

  void _showSuccess(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => LuxurySuccessModal(
        title: title,
        message: message,
        onConfirm: () => Navigator.pop(context),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message.replaceAll("Exception:", ""))),
    );
  }

  Future<void> _toggleStatus() async {
    // Optimistic Update
    final originalStatus = _staff['is_active'];
    setState(() {
      _staff['is_active'] = !originalStatus;
    });

    try {
      final updated = await _apiService.toggleStoreStaffStatus(
        widget.token,
        _staff['id'],
      );
      setState(() {
        _staff = updated;
      });
    } catch (e) {
      // Revert on error
      setState(() {
        _staff['is_active'] = originalStatus;
      });
      _showError(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActive = _staff['is_active'] == true;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        children: [
          // Hero Image / Background
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.45,
            child: Container(
              decoration: BoxDecoration(
                image: _staff['profile_photo_url'] != null
                    ? DecorationImage(
                        image: NetworkImage(
                          ApiService.normalizePhotoUrl(
                            _staff['profile_photo_url'],
                          )!,
                        ),
                        fit: BoxFit.cover,
                      )
                    : null,
                color: const Color(0xFF1A1A1A),
              ),
              child: _staff['profile_photo_url'] == null
                  ? const Center(
                      child: Icon(
                        Icons.person,
                        color: Color(0xFFEBC14F),
                        size: 120,
                      ),
                    )
                  : null,
            ),
          ),
          // Gradient Overlay for Hero
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.45,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.6),
                    Colors.transparent,
                    const Color(0xFF0A0A0A).withOpacity(0.8),
                    const Color(0xFF0A0A0A),
                  ],
                ),
              ),
            ),
          ),
          // Back Button
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 20,
            child: GestureDetector(
              onTap: () => Navigator.pop(context, true),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
          // Actions Button
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            right: 20,
            child: Row(
              children: [
                GestureDetector(
                  onTap: _showEditStaffDialog,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: const Icon(
                      Icons.edit_outlined,
                      color: Color(0xFFEBC14F),
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _deleteStaff,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Content
          Positioned.fill(
            top: MediaQuery.of(context).size.height * 0.38,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name & Exp Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      color: const Color(0xFF141414),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _staff['name'].toString().toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.verified_user_rounded,
                              size: 14,
                              color: Color(0xFFEBC14F),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${_staff['years_of_experience']} Years Professional Experience',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Status Section
                  _buildSectionHeader('AVAILABILITY STATUS'),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.white.withOpacity(0.03),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isActive
                                    ? Colors.greenAccent
                                    : Colors.white24,
                                boxShadow: isActive
                                    ? [
                                        BoxShadow(
                                          color: Colors.greenAccent.withOpacity(
                                            0.4,
                                          ),
                                          blurRadius: 8,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              isActive
                                  ? 'ACTIVE & BOOKABLE'
                                  : 'OFFLINE / UNAVAILABLE',
                              style: TextStyle(
                                color: isActive ? Colors.white : Colors.white38,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        Switch.adaptive(
                          value: isActive,
                          onChanged: (_) => _toggleStatus(),
                          activeColor: const Color(0xFFEBC14F),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Bio Section
                  _buildSectionHeader('PROFESSIONAL BIO'),
                  const SizedBox(height: 16),
                  Text(
                    _staff['bio'] ?? 'No bio provided.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 15,
                      height: 1.6,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 100), // Bottom padding
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFFEBC14F),
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.5,
      ),
    );
  }
}
