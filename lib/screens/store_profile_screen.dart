import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../api_service.dart';
import '../theme_provider.dart';
import '../widgets/luxury_success_modal.dart';
import '../widgets/luxury_error_modal.dart';
import '../widgets/safe_network_image.dart';

class StoreProfileScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const StoreProfileScreen({super.key, required this.userData});

  @override
  State<StoreProfileScreen> createState() => _StoreProfileScreenState();
}

class _StoreProfileScreenState extends State<StoreProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final ApiService _apiService = ApiService();

  late TextEditingController _nameController;
  late TextEditingController _addressController;
  late TextEditingController _descriptionController;

  double? _latitude;
  double? _longitude;
  String? _city;
  String? _province;
  String? _existingPhotoUrl;
  File? _selectedImage;
  bool _isLoading = false;
  bool _isGettingLocation = false;

  @override
  void initState() {
    super.initState();
    final provider = widget.userData['provider'] ?? {};
    final storeProfile = provider['store_profile'] ?? {};

    _nameController = TextEditingController(text: storeProfile['store_name']);
    _addressController = TextEditingController(text: storeProfile['address']);
    _descriptionController = TextEditingController(
      text: storeProfile['description'],
    );
    _latitude = double.tryParse(storeProfile['latitude']?.toString() ?? '');
    _longitude = double.tryParse(storeProfile['longitude']?.toString() ?? '');

    final photos = storeProfile['photos'];
    if (photos != null && photos is List && photos.isNotEmpty) {
      _existingPhotoUrl = photos[0];
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception("Location permissions are permanently denied.");
      }

      Position position = await Geolocator.getCurrentPosition();

      // Reverse geocode to get address string
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          if (placemarks.isNotEmpty) {
            Placemark place = placemarks[0];
            _addressController.text =
                "${place.street}, ${place.locality}, ${place.administrativeArea}";
            _city = place.locality ?? place.subAdministrativeArea;
            _province = place.administrativeArea;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => LuxuryErrorModal(
            title: 'LOCATION ERROR',
            message: e.toString().replaceAll("Exception:", "").trim(),
            onConfirm: () => Navigator.pop(context),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _saveStoreProfile() async {
    if (!_formKey.currentState!.validate()) return;
    if (_latitude == null || _longitude == null) {
      showDialog(
        context: context,
        builder: (context) => LuxuryErrorModal(
          title: 'REQUIRED FIELD',
          message: 'Please set the store location coordinates first.',
          onConfirm: () => Navigator.pop(context),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _apiService.updateStoreProfile(
        token: widget.userData['token'],
        storeName: _nameController.text.trim(),
        address: _addressController.text.trim(),
        latitude: _latitude!,
        longitude: _longitude!,
        description: _descriptionController.text.trim(),
        city: _city,
        province: _province,
        photoPath: _selectedImage?.path,
      );

      if (!mounted) return;

      // Update local data
      setState(() {
        if (widget.userData['provider'] == null) {
          widget.userData['provider'] = {};
        }
        widget.userData['provider']['store_profile'] = result['store_profile'];
      });

      showDialog(
        context: context,
        builder: (context) => LuxurySuccessModal(
          title: 'PROFILE UPDATED',
          message: 'Store settings have been successfully saved.',
          onConfirm: () {
            Navigator.pop(context); // Close dialog
            Navigator.pop(context, true); // Close screen
          },
        ),
      );
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => LuxuryErrorModal(
            title: 'UPDATE FAILED',
            message: e.toString(),
            onConfirm: () => Navigator.pop(context),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final goldColor = const Color(0xFFEBC14F);
    final isDark = themeProvider.isDarkMode;
    final backgroundColor = isDark ? Colors.black : Colors.white;
    final textColor = themeProvider.textColor;
    final cardColor = isDark
        ? const Color(0xFF1A1A1A)
        : const Color(0xFFF5F5F5);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        title: Text(
          "Store Settings",
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Store Thumbnail
              Center(
                child: Stack(
                  children: [
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: goldColor, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: goldColor.withOpacity(0.2),
                            blurRadius: 15,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: _selectedImage != null
                            ? Image.file(_selectedImage!, fit: BoxFit.cover)
                            : SafeNetworkImage(
                                url: _existingPhotoUrl ?? '',
                                fit: BoxFit.cover,
                                placeholder: Icon(
                                  Icons.store,
                                  size: 50,
                                  color: goldColor.withOpacity(0.5),
                                ),
                              ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _isGettingLocation ? null : _pickImage,
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
                            size: 20,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              Text(
                "Establishment Details",
                style: TextStyle(
                  color: goldColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Set your fixed business location. Customers will see this exact spot.",
                style: TextStyle(
                  color: textColor.withOpacity(0.5),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 32),

              _buildLabel("Store Name", textColor),
              _buildTextField(
                controller: _nameController,
                hint: "e.g. My House Spa",
                icon: Icons.store_outlined,
                cardColor: cardColor,
                textColor: textColor,
                goldColor: goldColor,
                validator: (v) => v!.isEmpty ? "Store Name is required" : null,
              ),
              const SizedBox(height: 20),

              _buildLabel("Physical Address", textColor),
              _buildTextField(
                controller: _addressController,
                hint: "Street, Barangay, City",
                icon: Icons.location_city_outlined,
                cardColor: cardColor,
                textColor: textColor,
                goldColor: goldColor,
                maxLines: 2,
                validator: (v) => v!.isEmpty ? "Address is required" : null,
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isGettingLocation ? null : _getCurrentLocation,
                  icon: _isGettingLocation
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFEBC14F),
                          ),
                        )
                      : const Icon(Icons.my_location, size: 18),
                  label: Text(
                    _isGettingLocation
                        ? "GETTING LOCATION..."
                        : "USE MY CURRENT LOCATION",
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: goldColor,
                    side: BorderSide(color: goldColor.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              if (_latitude != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: goldColor.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: goldColor.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: goldColor, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Location Pins Set: ${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)}",
                          style: TextStyle(
                            color: textColor.withOpacity(0.7),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 20),

              _buildLabel("Short Description", textColor),
              _buildTextField(
                controller: _descriptionController,
                hint: "Tell customers about your place...",
                icon: Icons.description_outlined,
                cardColor: cardColor,
                textColor: textColor,
                goldColor: goldColor,
                maxLines: 4,
              ),

              const SizedBox(height: 48),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveStoreProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: goldColor,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 8,
                    shadowColor: goldColor.withOpacity(0.3),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.black)
                      : const Text(
                          "SAVE STORE SETTINGS",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
            ],
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
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required Color cardColor,
    required Color textColor,
    required Color goldColor,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextFormField(
        controller: controller,
        style: TextStyle(color: textColor),
        maxLines: maxLines,
        validator: validator,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: textColor.withOpacity(0.3)),
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
