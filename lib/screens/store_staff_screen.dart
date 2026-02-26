import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:spacall_therapist_app/api_service.dart';
import 'package:spacall_therapist_app/widgets/luxury_success_modal.dart';

class StoreStaffScreen extends StatefulWidget {
  final String token;

  const StoreStaffScreen({super.key, required this.token});

  @override
  State<StoreStaffScreen> createState() => _StoreStaffScreenState();
}

class _StoreStaffScreenState extends State<StoreStaffScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  List<dynamic> _staff = [];

  @override
  void initState() {
    super.initState();
    _fetchStaff();
  }

  Future<void> _fetchStaff() async {
    setState(() => _isLoading = true);
    try {
      final staff = await _apiService.getStoreStaff(widget.token);
      setState(() {
        _staff = staff;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError(e.toString());
    }
  }

  Future<void> _toggleStatus(int id) async {
    try {
      await _apiService.toggleStoreStaffStatus(widget.token, id);
      _fetchStaff();
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message.replaceAll("Exception:", ""))),
    );
  }

  void _showAddStaffDialog() {
    final nameController = TextEditingController();
    final bioController = TextEditingController();
    final expController = TextEditingController();
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
                    'ADD THERAPIST',
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
                          child: selectedImage != null
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
                        expController.text.isEmpty) {
                      return;
                    }
                    Navigator.pop(modalContext);
                    _showLoading();
                    try {
                      await _apiService.addStoreStaff(
                        token: widget.token,
                        name: nameController.text,
                        bio: bioController.text,
                        yearsOfExperience:
                            int.tryParse(expController.text) ?? 0,
                        photo: selectedImage,
                      );
                      if (!mounted) return;
                      Navigator.of(
                        context,
                        rootNavigator: true,
                      ).pop(); // Close loading
                      _fetchStaff();
                      _showSuccess();
                    } catch (e) {
                      if (!mounted) return;
                      Navigator.of(
                        context,
                        rootNavigator: true,
                      ).pop(); // Close loading
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
                    'SAVE THERAPIST',
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

  void _showSuccess() {
    showDialog(
      context: context,
      builder: (context) => LuxurySuccessModal(
        title: 'STAFF ADDED',
        message: 'The therapist has been successfully added to your store.',
        onConfirm: () => Navigator.pop(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text(
          'STAFF MANAGEMENT',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 1.5,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _showAddStaffDialog,
            icon: const Icon(
              Icons.add_circle_outline,
              color: Color(0xFFEBC14F),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFEBC14F)),
            )
          : _staff.isEmpty
          ? _buildEmptyState()
          : _buildStaffList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people_outline_rounded,
            color: Colors.white.withOpacity(0.1),
            size: 100,
          ),
          const SizedBox(height: 24),
          const Text(
            'NO THERAPISTS ADDED',
            style: TextStyle(
              color: Colors.white38,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _showAddStaffDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEBC14F).withOpacity(0.1),
              foregroundColor: const Color(0xFFEBC14F),
              side: const BorderSide(color: Color(0xFFEBC14F)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('ADD YOUR FIRST STAFF'),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffList() {
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _staff.length,
      itemBuilder: (context, index) {
        final member = _staff[index];
        final isActive = member['is_active'] == true;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  image: member['profile_photo_url'] != null
                      ? DecorationImage(
                          image: NetworkImage(
                            ApiService.normalizePhotoUrl(
                              member['profile_photo_url'],
                            )!,
                          ),
                          fit: BoxFit.cover,
                        )
                      : null,
                  color: Colors.white.withOpacity(0.05),
                ),
                child: member['profile_photo_url'] == null
                    ? const Icon(Icons.person, color: Color(0xFFEBC14F))
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member['name'].toString().toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${member['years_of_experience']} Years Exp.',
                      style: TextStyle(
                        color: const Color(0xFFEBC14F).withOpacity(0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  Text(
                    isActive ? 'ACTIVE' : 'INACTIVE',
                    style: TextStyle(
                      color: isActive ? Colors.greenAccent : Colors.white38,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Switch.adaptive(
                    value: isActive,
                    onChanged: (_) => _toggleStatus(member['id']),
                    activeColor: const Color(0xFFEBC14F),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
