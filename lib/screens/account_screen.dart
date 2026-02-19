import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pinput/pinput.dart';

import '../api_service.dart';
import '../theme_provider.dart';
import 'login_screen.dart';
import 'support_chat_screen.dart';

class AccountScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const AccountScreen({super.key, required this.userData});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  // ignore: unused_field
  final ApiService _apiService = ApiService();
  bool _isProcessing = false;
  bool _isUpgradePending = false;

  void _handleLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Logout", style: TextStyle(color: Color(0xFFEBC14F))),
        content: const Text(
          "Are you sure you want to log out?",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "CANCEL",
              style: TextStyle(color: Colors.white.withOpacity(0.5)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              // Perform any additional cleanup if necessary (e.g. disconnect sockets)
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text(
              "LOGOUT",
              style: TextStyle(
                color: Color(0xFFFF5252),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleDeleteAccount(BuildContext context, ThemeProvider themeProvider) {
    final goldColor = const Color(0xFFEBC14F);
    final pinController = TextEditingController();

    final defaultPinTheme = PinTheme(
      width: 45,
      height: 50,
      textStyle: TextStyle(
        fontSize: 20,
        color: goldColor,
        fontWeight: FontWeight.bold,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: goldColor.withOpacity(0.3)),
      ),
    );

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text(
            "Delete Account",
            style: TextStyle(color: Color(0xFFFF5252)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Warning: This action is permanent. All your data will be lost. Please enter your PIN to confirm.",
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 24),
              Pinput(
                length: 6,
                controller: pinController,
                defaultPinTheme: defaultPinTheme,
                obscureText: true,
                onCompleted: (pin) async {
                  // Verify PIN and delete
                  // Note using 'pin' field from user data for verification
                  if (pin == widget.userData['user']?['pin']) {
                    setDialogState(() => _isProcessing = true);
                    try {
                      await _apiService.deleteAccount(widget.userData['token']);
                      if (!mounted) return;
                      Navigator.pop(context); // Close dialog
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const LoginScreen(),
                        ),
                        (route) => false,
                      );
                    } catch (e) {
                      setDialogState(() => _isProcessing = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(e.toString()),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Incorrect PIN"),
                        backgroundColor: Colors.red,
                      ),
                    );
                    pinController.clear();
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                "CANCEL",
                style: TextStyle(color: Colors.white.withOpacity(0.5)),
              ),
            ),
            if (_isProcessing)
              const Padding(
                padding: EdgeInsets.only(right: 16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFFF5252),
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
    final goldColor = const Color(0xFFEBC14F);
    final backgroundColor = themeProvider.isDarkMode
        ? const Color(0xFF000000)
        : Colors.white;
    final cardColor = themeProvider.isDarkMode
        ? const Color(0xFF1E1E1E) // Match therapist app card color
        : const Color(0xFFF5F5F5);

    final user = widget.userData['user'] ?? {};
    final firstName = user['first_name'] ?? 'Therapist';
    final middleName = user['middle_name'] ?? '';
    final lastName = user['last_name'] ?? '';
    final fullName = middleName.isNotEmpty
        ? "$firstName $middleName $lastName"
        : (lastName.isNotEmpty ? "$firstName $lastName" : firstName);
    final email = user['email'] ?? 'No email provided';
    final phone = user['mobile_number'] ?? 'No phone provided';
    String? profileUrl = ApiService.normalizePhotoUrl(
      user['profile_photo_url'],
    );
    // Therapist app might not have 'customer_tier', handling gracefully
    final tier = (user['therapist_tier'] ?? 'standard')
        .toString()
        .toLowerCase();

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 40),

              // Profile Header
              Center(
                child: Column(
                  children: [
                    Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: goldColor, width: 2),
                          ),
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cardColor,
                            ),
                            child: ClipOval(
                              child: profileUrl != null && profileUrl.isNotEmpty
                                  ? Image.network(
                                      profileUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                            return Icon(
                                              Icons.person,
                                              size: 60,
                                              color: goldColor,
                                            );
                                          },
                                    )
                                  : Icon(
                                      Icons.person,
                                      size: 60,
                                      color: goldColor,
                                    ),
                            ),
                          ),
                        ),
                        PositionImage(
                          bottom: 0,
                          right: 0,
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
                              Icons.edit,
                              size: 16,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          fullName,
                          style: TextStyle(
                            color: themeProvider.textColor,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          _isUpgradePending
                              ? Icons.hourglass_empty
                              : Icons.verified,
                          color: goldColor,
                          size: 22,
                        ),
                      ],
                    ),
                    if (_isUpgradePending)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          "PENDING APPROVAL",
                          style: TextStyle(
                            color: goldColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      email != 'No email provided' ? email : phone,
                      style: TextStyle(
                        color: themeProvider.textColor.withOpacity(0.5),
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),

              if (tier != 'vip' && !_isUpgradePending) ...[
                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: goldColor.withOpacity(0.3)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: goldColor.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.star, color: goldColor, size: 22),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Upgrade to VIP",
                                style: TextStyle(
                                  color: goldColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                "Unlock premium features",
                                style: TextStyle(
                                  color: themeProvider.textColor.withOpacity(
                                    0.5,
                                  ),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () =>
                              _showUpgradeForm(context, themeProvider),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: goldColor,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            "APPLY",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 40),

              // Settings Sections
              _buildSection("Account", [
                _buildSettingItem(
                  Icons.person,
                  "Edit Profile",
                  "Update your personal information",
                  themeProvider,
                ),
                _buildSettingItem(
                  Icons.phone,
                  "Phone Number",
                  phone,
                  themeProvider,
                ),
                _buildSettingItem(
                  Icons.work_outline,
                  "Service Area",
                  "Manage your service location",
                  themeProvider,
                ),
              ], themeProvider),

              _buildSection("Preferences", [
                _buildSettingItem(
                  Icons.settings,
                  "App Settings",
                  "Notifications, language, privacy",
                  themeProvider,
                ),
                _buildSettingItem(
                  Icons.notifications,
                  "Notifications",
                  "Manage alerts & reminders",
                  themeProvider,
                ),
              ], themeProvider),

              _buildSection("Support", [
                _buildSettingItem(
                  Icons.help_outline,
                  "Help & Support",
                  "FAQs & contact support",
                  themeProvider,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            SupportChatScreen(userData: widget.userData),
                      ),
                    );
                  },
                ),
                _buildSettingItem(
                  Icons.info_outline,
                  "About Spacall",
                  "Version 1.0.0",
                  themeProvider,
                ),
              ], themeProvider),

              _buildSection(
                "Account Actions",
                [
                  _buildSettingItem(
                    Icons.logout,
                    "Logout",
                    "Sign out from your account",
                    themeProvider,
                    isDestructive: true,
                    onTap: () => _handleLogout(context),
                  ),
                  _buildSettingItem(
                    Icons.delete_outline,
                    "Delete Account",
                    "Permanently delete your account",
                    themeProvider,
                    isDestructive: true,
                    onTap: () => _handleDeleteAccount(context, themeProvider),
                  ),
                ],
                themeProvider,
                titleColor: const Color(0xFFFF5252),
              ),

              const SizedBox(height: 120),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(
    String title,
    List<Widget> items,
    ThemeProvider themeProvider, {
    Color? titleColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
          child: Text(
            title,
            style: TextStyle(
              color: titleColor ?? const Color(0xFFEBC14F),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 0),
          decoration: BoxDecoration(
            color: themeProvider.isDarkMode
                ? const Color(0xFF1E1E1E) // Match dashboard card color
                : const Color(0xFFF9F9F9),
          ),
          child: Column(children: items),
        ),
      ],
    );
  }

  Widget _buildSettingItem(
    IconData icon,
    String title,
    String subtitle,
    ThemeProvider themeProvider, {
    bool isDestructive = false,
    VoidCallback? onTap,
  }) {
    final goldColor = const Color(0xFFEBC14F);
    final destructiveColor = const Color(0xFFFF5252);

    return InkWell(
      onTap: onTap ?? () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDestructive
                    ? destructiveColor.withOpacity(0.1)
                    : (themeProvider.isDarkMode
                          ? Colors.white.withOpacity(0.05)
                          : Colors.black.withOpacity(0.05)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isDestructive ? destructiveColor : goldColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isDestructive
                          ? destructiveColor
                          : themeProvider.textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isDestructive
                          ? destructiveColor.withOpacity(0.6)
                          : themeProvider.textColor.withOpacity(0.4),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: themeProvider.textColor.withOpacity(0.2),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _showUpgradeForm(BuildContext context, ThemeProvider themeProvider) {
    final goldColor = const Color(0xFFEBC14F);
    final expController = TextEditingController();
    final skillsController = TextEditingController();
    final bioController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF121212),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(32),
            topRight: Radius.circular(32),
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                "VIP Application",
                style: TextStyle(
                  color: goldColor,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Please provide additional professional details for our verification team.",
                style: TextStyle(
                  color: themeProvider.textColor.withOpacity(0.6),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 32),
              _buildFormField(
                "Years of Experience",
                expController,
                Icons.history,
                goldColor,
                themeProvider,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 20),
              _buildFormField(
                "Specialized Skills",
                skillsController,
                Icons.auto_awesome_outlined,
                goldColor,
                themeProvider,
                placeholder: "e.g., Deep Tissue, Stone Massage...",
              ),
              const SizedBox(height: 20),
              _buildFormField(
                "Professional Bio",
                bioController,
                Icons.description_outlined,
                goldColor,
                themeProvider,
                maxLines: 4,
                placeholder: "Tell us about your professional journey...",
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _submitUpgradeRequest(context, themeProvider);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: goldColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    "SUBMIT APPLICATION",
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormField(
    String label,
    TextEditingController controller,
    IconData icon,
    Color goldColor,
    ThemeProvider themeProvider, {
    int maxLines = 1,
    String? placeholder,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: themeProvider.textColor.withOpacity(0.8),
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: placeholder,
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
            prefixIcon: Icon(icon, color: goldColor.withOpacity(0.5), size: 20),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
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

  void _submitUpgradeRequest(
    BuildContext context,
    ThemeProvider themeProvider,
  ) {
    final goldColor = const Color(0xFFEBC14F);

    setState(() {
      _isUpgradePending = true;
    });

    showDialog(
      context: context,
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
                Icons.hourglass_top_rounded,
                color: goldColor,
                size: 48,
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              "Application Received",
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              "Your VIP upgrade request has been submitted successfully.\n\nOur team will review your details and documents. This process usually takes 24-48 hours.",
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 14,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: goldColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: goldColor.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline, color: goldColor, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    "STATUS: FOR APPROVAL",
                    style: TextStyle(
                      color: goldColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.05),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  "UNDERSTOOD",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PositionImage extends StatelessWidget {
  final Widget child;
  final double? top;
  final double? bottom;
  final double? left;
  final double? right;

  const PositionImage({
    super.key,
    required this.child,
    this.top,
    this.bottom,
    this.left,
    this.right,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: child,
    );
  }
}
