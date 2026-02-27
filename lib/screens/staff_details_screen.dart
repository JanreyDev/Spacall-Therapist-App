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
  bool _isDeleting = false;

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
        if (!mounted || _isDeleting) return;
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
        backgroundColor: const Color(0xFF0A0A0A),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: const Text(
          'REMOVE PROFESSIONAL',
          style: TextStyle(
            color: Color(0xFFEBC14F),
            fontWeight: FontWeight.w900,
            fontSize: 14,
            letterSpacing: 2,
          ),
        ),
        content: const Text(
          'Are you sure you want to remove this therapist profile? This action is permanent.',
          style: TextStyle(color: Colors.white60, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Colors.white24),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'REMOVE',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      setState(() => _isDeleting = true);
      _showLoading();
      try {
        await _apiService.deleteStoreStaff(widget.token, _staff['id']);
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pop(); // Close loading
        Navigator.pop(context, true); // Return to list
      } catch (e) {
        if (!mounted) return;
        setState(() => _isDeleting = false);
        Navigator.of(context, rootNavigator: true).pop(); // Close loading
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
            color: Color(0xFF050505),
            borderRadius: BorderRadius.vertical(top: Radius.circular(0)),
          ),
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'EDIT DOSSIER',
                    style: TextStyle(
                      color: Color(0xFFEBC14F),
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white24),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: () async {
                          final picker = ImagePicker();
                          final img = await picker.pickImage(
                            source: ImageSource.gallery,
                            maxWidth: 800,
                            maxHeight: 1200,
                            imageQuality: 85,
                          );
                          if (img != null) {
                            setModalState(() => selectedImage = img);
                          }
                        },
                        child: Container(
                          width: 140,
                          height: 180,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.02),
                            border: Border.all(
                              color: const Color(0xFFEBC14F).withOpacity(0.2),
                            ),
                          ),
                          child: (selectedImage != null)
                              ? ClipRRect(
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
                              ? Image.network(
                                  ApiService.normalizePhotoUrl(
                                    _staff['profile_photo_url'],
                                  )!,
                                  fit: BoxFit.cover,
                                )
                              : const Center(
                                  child: Icon(
                                    Icons.add_a_photo_outlined,
                                    color: Color(0xFFEBC14F),
                                    size: 30,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      _buildTextField(
                        nameController,
                        'PROFESSIONAL NAME',
                        Icons.person_outline,
                      ),
                      const SizedBox(height: 20),
                      _buildTextField(
                        expController,
                        'YEARS OF EXPERTISE',
                        Icons.workspace_premium_outlined,
                        isNumber: true,
                      ),
                      const SizedBox(height: 20),
                      _buildTextField(
                        bioController,
                        'PROFESSIONAL BIOGRAPHY',
                        Icons.menu_book_outlined,
                        maxLines: 5,
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
                    if (nameController.text.isEmpty) return;
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
                      Navigator.of(context, rootNavigator: true).pop();
                      setState(() => _staff = response);
                      _showSuccess(
                        'DOSSIER UPDATED',
                        'The professional profile has been refined.',
                      );
                    } catch (e) {
                      if (!mounted) return;
                      Navigator.of(context, rootNavigator: true).pop();
                      _showError(e.toString());
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEBC14F),
                    foregroundColor: Colors.black,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                  child: const Text(
                    'SAVE CHANGES',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
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
            color: Color(0xFFEBC14F),
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            prefixIcon: Icon(
              icon,
              color: const Color(0xFFEBC14F).withOpacity(0.5),
              size: 18,
            ),
            filled: true,
            fillColor: Colors.white.withOpacity(0.02),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFEBC14F)),
            ),
            contentPadding: const EdgeInsets.all(20),
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
      SnackBar(
        backgroundColor: const Color(0xFF1A1A1A),
        content: Text(
          message.replaceAll("Exception:", ""),
          style: const TextStyle(color: Colors.redAccent),
        ),
      ),
    );
  }

  Future<void> _toggleStatus() async {
    final originalStatus = _staff['is_active'];
    setState(() => _staff['is_active'] = !originalStatus);
    try {
      final updated = await _apiService.toggleStoreStaffStatus(
        widget.token,
        _staff['id'],
      );
      setState(() => _staff = updated);
    } catch (e) {
      setState(() => _staff['is_active'] = originalStatus);
      _showError(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActive = _staff['is_active'] == true;
    const goldColor = Color(0xFFEBC14F);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: size.height * 0.7,
                backgroundColor: Colors.black,
                elevation: 0,
                pinned: true,
                stretch: true,
                automaticallyImplyLeading: false,
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.pin,
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      _staff['profile_photo_url'] != null
                          ? Image.network(
                              ApiService.normalizePhotoUrl(
                                _staff['profile_photo_url'],
                              )!,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: const Color(0xFF0D0D0D),
                              child: const Icon(
                                Icons.person,
                                size: 120,
                                color: Colors.white10,
                              ),
                            ),

                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: [0.0, 0.4, 0.75, 1.0],
                            colors: [
                              Colors.black26,
                              Colors.transparent,
                              Colors.black87,
                              Colors.black,
                            ],
                          ),
                        ),
                      ),

                      Positioned(
                        bottom: 80,
                        left: 24,
                        right: 24,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'OFFICIAL PROFESSIONAL',
                              style: TextStyle(
                                color: goldColor,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 8,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _staff['name'].toString().toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 44,
                                fontWeight: FontWeight.w200,
                                letterSpacing: 1,
                                height: 0.9,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(height: 1, width: 60, color: goldColor),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Container(
                  color: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 40,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'EXPERTISE',
                                  style: TextStyle(
                                    color: Colors.white24,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 3,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${_staff['years_of_experience']} YEARS PROFESSIONAL',
                                  style: const TextStyle(
                                    color: Color(0xFFEBC14F),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w300,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'STATUS',
                                style: TextStyle(
                                  color: Colors.white24,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 3,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _StatusPulse(isActive: isActive),
                                  const SizedBox(width: 8),
                                  Text(
                                    isActive ? 'ON-DUTY' : 'OFF-DUTY',
                                    style: TextStyle(
                                      color: isActive
                                          ? Colors.white
                                          : Colors.white24,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 60),

                      const Text(
                        'BIOGRAPHICAL DOSSIER',
                        style: TextStyle(
                          color: goldColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        _staff['bio'] ?? 'No formal biography provided.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 15,
                          height: 2.0,
                          fontFamily: 'Serif',
                          fontWeight: FontWeight.w300,
                        ),
                      ),

                      const SizedBox(height: 60),

                      GestureDetector(
                        onTap: _toggleStatus,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 600),
                          width: double.infinity,
                          height: 80,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0A0A0A),
                            border: Border.all(
                              color: isActive ? goldColor : Colors.white10,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                isActive
                                    ? 'SET SESSION TO OFFLINE'
                                    : 'ACTIVATE FOR SERVICE',
                                style: TextStyle(
                                  color: isActive ? goldColor : Colors.white24,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                  letterSpacing: 5,
                                ),
                              ),
                              if (isActive) ...[
                                const SizedBox(height: 8),
                                Container(
                                  width: 40,
                                  height: 1,
                                  color: goldColor.withOpacity(0.3),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 50),

                      const Center(
                        child: Opacity(
                          opacity: 0.05,
                          child: Text(
                            'SPACALL EXCLUSIVE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w100,
                              letterSpacing: 10,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ],
          ),

          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _HeaderButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: () => Navigator.pop(context, true),
                ),
                Row(
                  children: [
                    _HeaderButton(
                      icon: Icons.edit_outlined,
                      onTap: _showEditStaffDialog,
                    ),
                    const SizedBox(width: 12),
                    _HeaderButton(
                      icon: Icons.delete_outline_rounded,
                      iconColor: Colors.redAccent.withOpacity(0.8),
                      onTap: _deleteStaff,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final VoidCallback onTap;
  const _HeaderButton({
    required this.icon,
    this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Icon(icon, color: iconColor ?? Colors.white70, size: 16),
      ),
    );
  }
}

class _StatusPulse extends StatefulWidget {
  final bool isActive;
  const _StatusPulse({required this.isActive});

  @override
  State<_StatusPulse> createState() => _StatusPulseState();
}

class _StatusPulseState extends State<_StatusPulse>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive)
      return Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white10,
        ),
      );
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.greenAccent.withOpacity(
            0.1 + (_controller.value * 0.2),
          ),
        ),
        child: Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.greenAccent,
          ),
        ),
      ),
    );
  }
}
