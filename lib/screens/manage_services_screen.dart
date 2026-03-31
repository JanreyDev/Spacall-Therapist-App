import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../api_service.dart';
import '../theme_provider.dart';
import '../widgets/luxury_error_modal.dart';
import '../widgets/luxury_success_modal.dart';
import '../widgets/safe_network_image.dart';

class ManageServicesScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const ManageServicesScreen({super.key, required this.userData});

  @override
  State<ManageServicesScreen> createState() => _ManageServicesScreenState();
}

class _EditableService {
  final int serviceId;
  final String name;
  final String categoryName;
  final String description;
  final String? imageUrl;
  final double basePrice;
  bool enabled;
  final TextEditingController priceController;

  _EditableService({
    required this.serviceId,
    required this.name,
    required this.categoryName,
    required this.description,
    required this.imageUrl,
    required this.basePrice,
    required this.enabled,
    required this.priceController,
  });
}

class _CategoryOption {
  final int id;
  final String name;

  _CategoryOption({required this.id, required this.name});
}

class _ManageServicesScreenState extends State<ManageServicesScreen> {
  final ApiService _apiService = ApiService();
  final List<_EditableService> _services = [];
  final List<_CategoryOption> _categories = [];

  bool _isLoading = true;
  bool _isSaving = false;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final service in _services) {
      service.priceController.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final token = widget.userData['token'].toString();
      final catalog = await _apiService.getServiceCatalog();
      final existing = await _apiService.getTherapistServices(token);

      final existingMap = <int, Map<String, dynamic>>{};
      for (final item in existing) {
        final serviceId = int.tryParse(item['id']?.toString() ?? '');
        if (serviceId != null) {
          existingMap[serviceId] = Map<String, dynamic>.from(item);
        }
      }

      final built = <_EditableService>[];
      final categoryList = <_CategoryOption>[];
      for (final rawCategory in catalog) {
        final category = Map<String, dynamic>.from(rawCategory);
        final categoryName = (category['name'] ?? 'General').toString();
        final categoryId = int.tryParse(category['id']?.toString() ?? '');
        if (categoryId != null) {
          categoryList.add(_CategoryOption(id: categoryId, name: categoryName));
        }

        final categoryServices = (category['services'] as List?) ?? const [];
        for (final rawService in categoryServices) {
          final service = Map<String, dynamic>.from(rawService);
          final serviceId = int.tryParse(service['id']?.toString() ?? '');
          if (serviceId == null) continue;

          final existingService = existingMap[serviceId];
          final pivot = existingService?['pivot'] is Map
              ? Map<String, dynamic>.from(existingService!['pivot'])
              : <String, dynamic>{};

          final defaultPrice =
              double.tryParse(service['base_price']?.toString() ?? '') ?? 0.0;
          final currentPrice =
              double.tryParse(pivot['price']?.toString() ?? '') ?? defaultPrice;
          final enabled =
              pivot.isNotEmpty ? (pivot['is_available'] != false) : false;

          built.add(
            _EditableService(
              serviceId: serviceId,
              name: (service['name'] ?? 'Service').toString(),
              categoryName: categoryName,
              description: (service['description'] ?? '').toString(),
              imageUrl: ApiService.normalizePhotoUrl(
                service['image_url']?.toString(),
              ),
              basePrice: defaultPrice,
              enabled: enabled,
              priceController: TextEditingController(
                text: currentPrice > 0 ? currentPrice.toStringAsFixed(2) : '',
              ),
            ),
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _services
          ..clear()
          ..addAll(built);
        _categories
          ..clear()
          ..addAll(categoryList);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showDialog(
        context: context,
        builder: (context) => LuxuryErrorModal(
          title: "LOAD FAILED",
          message: e.toString().replaceAll('Exception: ', ''),
          onConfirm: () => Navigator.pop(context),
        ),
      );
    }
  }

  Future<void> _openAddCustomServiceScreen() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => _AddCustomServiceScreen(
          token: widget.userData['token'].toString(),
          apiService: _apiService,
        ),
      ),
    );

    if (created == true) {
      await _load();
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => LuxurySuccessModal(
          title: "SERVICE CREATED",
          message: "Custom service added successfully.",
          onConfirm: () => Navigator.pop(context),
        ),
      );
    }
  }

  Future<void> _save() async {
    final token = widget.userData['token'].toString();
    final payload = <Map<String, dynamic>>[];
    for (final s in _services.where((x) => x.enabled)) {
      final parsedPrice = double.tryParse(s.priceController.text.trim());
      if (parsedPrice == null || parsedPrice < 0) continue;
      payload.add({
        'service_id': s.serviceId,
        'price': parsedPrice,
        'is_available': true,
      });
    }

    if (payload.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => LuxuryErrorModal(
          title: "NO SERVICES",
          message: "Enable at least one service and set a valid price.",
          onConfirm: () => Navigator.pop(context),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _apiService.saveTherapistServices(token, payload);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => LuxurySuccessModal(
          title: "SERVICES UPDATED",
          message: "Your offered services were saved successfully.",
          onConfirm: () {
            Navigator.pop(context);
            Navigator.pop(context, true);
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => LuxuryErrorModal(
          title: "SAVE FAILED",
          message: e.toString().replaceAll('Exception: ', ''),
          onConfirm: () => Navigator.pop(context),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final gold = const Color(0xFFEBC14F);

    final visible = _services.where((s) {
      final q = _search.trim().toLowerCase();
      if (q.isEmpty) return true;
      return s.name.toLowerCase().contains(q) ||
          s.categoryName.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("MY SERVICES"),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          onChanged: (v) => setState(() => _search = v),
                          style: TextStyle(color: theme.textColor),
                          decoration: InputDecoration(
                            hintText: "Search services...",
                            hintStyle: TextStyle(color: theme.subtextColor),
                            filled: true,
                            fillColor: const Color(0xFF1A1A1A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: gold.withOpacity(0.15),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: gold.withOpacity(0.15),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: gold,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _openAddCustomServiceScreen,
                        icon: const Icon(Icons.add),
                        label: const Text("ADD"),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final item = visible[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: gold.withOpacity(0.15)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SafeNetworkImage(
                                url: item.imageUrl ?? '',
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                                errorWidget: Container(
                                  width: 64,
                                  height: 64,
                                  color: Colors.black26,
                                  child: Icon(
                                    Icons.spa_outlined,
                                    color: gold.withOpacity(0.6),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.categoryName,
                                    style: TextStyle(
                                      color: gold.withOpacity(0.8),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    item.description.isNotEmpty
                                        ? item.description
                                        : "No description provided.",
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: theme.subtextColor,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 120,
                                        child: TextField(
                                          controller: item.priceController,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          style: const TextStyle(fontSize: 13),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            prefixText: "P ",
                                            hintText: item.basePrice
                                                .toStringAsFixed(2),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: SwitchListTile(
                                          dense: true,
                                          contentPadding: EdgeInsets.zero,
                                          title: const Text(
                                            "Offer",
                                            style: TextStyle(fontSize: 12),
                                          ),
                                          value: item.enabled,
                                          activeColor: gold,
                                          onChanged: (v) =>
                                              setState(() => item.enabled = v),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: gold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      "SAVE SERVICES",
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddCustomServiceScreen extends StatefulWidget {
  final String token;
  final ApiService apiService;

  const _AddCustomServiceScreen({
    required this.token,
    required this.apiService,
  });

  @override
  State<_AddCustomServiceScreen> createState() => _AddCustomServiceScreenState();
}

class _AddCustomServiceScreenState extends State<_AddCustomServiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _normalPriceController = TextEditingController();
  final _vipPriceController = TextEditingController();
  final _durationController = TextEditingController(text: '60');
  final ImagePicker _picker = ImagePicker();

  bool _isSubmitting = false;
  XFile? _thumbnailFile;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _normalPriceController.dispose();
    _vipPriceController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _pickThumbnail() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked == null || !mounted) return;
    setState(() => _thumbnailFile = picked);
  }

  InputDecoration _inputDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFF1A1A1A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: const Color(0xFFEBC14F).withOpacity(0.15)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: const Color(0xFFEBC14F).withOpacity(0.15)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFEBC14F), width: 1.4),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final normalPrice = double.tryParse(_normalPriceController.text.trim());
    final vipRaw = _vipPriceController.text.trim();
    final vipPrice = vipRaw.isEmpty ? null : double.tryParse(vipRaw);
    final duration = int.tryParse(_durationController.text.trim());

    if (normalPrice == null || duration == null) {
      return;
    }

    if (vipPrice != null && vipPrice > normalPrice) {
      showDialog(
        context: context,
        builder: (context) => LuxuryErrorModal(
          title: "INVALID VIP PRICE",
          message: "VIP price must be less than or equal to normal price.",
          onConfirm: () => Navigator.pop(context),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await widget.apiService.createCustomService(
        widget.token,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        durationMinutes: duration,
        price: normalPrice,
        vipPrice: vipPrice,
        photo: _thumbnailFile,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => LuxuryErrorModal(
          title: "CREATE FAILED",
          message: e.toString().replaceAll('Exception: ', ''),
          onConfirm: () => Navigator.pop(context),
        ),
      );
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    const gold = Color(0xFFEBC14F);

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("ADD SERVICE"),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      colors: [
                        gold.withOpacity(0.22),
                        const Color(0xFF1A1A1A),
                        Colors.black,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: gold.withOpacity(0.25)),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 76,
                          height: 76,
                          color: const Color(0xFF121212),
                          child: _thumbnailFile == null
                              ? const Icon(Icons.image_outlined, color: gold)
                              : Image.file(
                                  File(_thumbnailFile!.path),
                                  fit: BoxFit.cover,
                                ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Create Your Service",
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "Set details and pricing for your custom offer.",
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.subtextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _nameController,
                  decoration: _inputDecoration("Service Name", hint: "Swedish Massage"),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? "Service name is required." : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  minLines: 3,
                  maxLines: 4,
                  decoration: _inputDecoration("Description", hint: "Describe this service..."),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: gold.withOpacity(0.15)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _thumbnailFile == null
                              ? "Upload service thumbnail"
                              : "Thumbnail selected",
                          style: TextStyle(
                            color: _thumbnailFile == null
                                ? theme.subtextColor
                                : Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _pickThumbnail,
                        icon: const Icon(Icons.upload_rounded),
                        label: const Text("UPLOAD"),
                        style: TextButton.styleFrom(
                          foregroundColor: gold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _normalPriceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _inputDecoration("Normal Price", hint: "500"),
                        validator: (value) {
                          final parsed = double.tryParse(value?.trim() ?? '');
                          if (parsed == null || parsed <= 0) {
                            return "Enter valid price.";
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _vipPriceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _inputDecoration("VIP Price", hint: "450"),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return null;
                          final parsed = double.tryParse(value.trim());
                          if (parsed == null || parsed < 0) {
                            return "Invalid VIP.";
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _durationController,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration("Duration (minutes)", hint: "60"),
                  validator: (value) {
                    final parsed = int.tryParse(value?.trim() ?? '');
                    if (parsed == null || parsed <= 0) {
                      return "Enter valid duration.";
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 54,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: gold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      "CREATE SERVICE",
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
