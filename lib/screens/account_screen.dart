import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pinput/pinput.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/safe_network_image.dart';
import '../api_service.dart';
import '../theme_provider.dart';
import 'login_screen.dart';
import 'support_chat_screen.dart';
import 'edit_profile_screen.dart';
import 'vip_upgrade_screen.dart';
import 'store_profile_screen.dart';
import '../widgets/luxury_error_modal.dart';
import '../widgets/luxury_success_modal.dart';

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
                  setDialogState(() => _isProcessing = true);
                  try {
                    await _apiService.deleteAccount(
                      widget.userData['token'],
                      pin,
                    );
                    if (!mounted) return;
                    Navigator.pop(context); // Close the PIN dialog

                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => LuxurySuccessModal(
                        title: "ACCOUNT DELETED",
                        message:
                            "Your therapist account has been permanently deleted. We're sorry to see you go!",
                        buttonText: "CONTINUE",
                        onConfirm: () async {
                          // Clear saved phone number
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.remove('last_mobile_number');

                          // Close the success dialog
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          // Return to the login screen (Sending OTP screen)
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const LoginScreen(),
                            ),
                            (route) => false,
                          );
                        },
                      ),
                    );
                  } catch (e) {
                    setDialogState(() => _isProcessing = false);
                    showDialog(
                      context: context,
                      builder: (context) => LuxuryErrorModal(
                        title: "VERIFICATION FAILED",
                        message: e.toString().replaceAll('Exception: ', ''),
                        onConfirm: () => Navigator.pop(context),
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
    final backgroundColor = Colors.black;

    final user = widget.userData['user'] ?? {};
    final nickname = user['nickname'];
    final firstName = user['first_name'] ?? 'Therapist';
    final middleName = user['middle_name'] ?? '';
    final lastName = user['last_name'] ?? '';
    final fullName = middleName.isNotEmpty
        ? "$firstName $middleName $lastName"
        : (lastName.isNotEmpty ? "$firstName $lastName" : firstName);
    final displayName = (nickname != null && nickname.toString().isNotEmpty)
        ? nickname
        : fullName;
    final phone = user['mobile_number'] ?? 'No phone provided';
    final email = user['email'] ?? 'No email provided';
    String? profileUrl = ApiService.normalizePhotoUrl(
      user['profile_photo_url'],
    );
    // Use customer_tier as the source of truth, fallback to therapist_tier
    final tier = (user['customer_tier'] ?? user['therapist_tier'] ?? 'standard')
        .toString()
        .toLowerCase();

    // Support real-time pending status from API data
    final provider = widget.userData['provider'] ?? user['provider'] ?? {};
    final therapistProfile = provider['therapist_profile'] ?? {};
    final vipStatus = (therapistProfile['vip_status'] ?? '')
        .toString()
        .toLowerCase();
    final currentTier = provider['current_tier'];
    final int currentLevel = currentTier?['level'] ?? 0;

    final isActuallyPending = _isUpgradePending || vipStatus == 'pending';
    // isVipStatus: true if tier is vip or approved manually (unless explicitly classic)
    final isVipStatus =
        tier == 'vip' || (vipStatus == 'approved' && tier != 'classic');
    // isVip: true if status is VIP OR they have progressed in levels (PRO/EXPERT etc)
    final isVip = isVipStatus || currentLevel > 0;

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
                      alignment: Alignment.center,
                      children: [
                        // Outer Glow
                        Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: goldColor.withOpacity(0.1),
                                blurRadius: 30,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                goldColor,
                                goldColor.withOpacity(0.2),
                                goldColor.withOpacity(0.5),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black,
                              border: Border.all(color: Colors.black, width: 2),
                            ),
                            child: ClipOval(
                              child: profileUrl != null && profileUrl.isNotEmpty
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
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: themeProvider.textColor,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          isActuallyPending
                              ? Icons.hourglass_empty
                              : Icons.verified,
                          color: goldColor,
                          size: 22,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      phone,
                      style: TextStyle(
                        color: themeProvider.textColor.withOpacity(0.5),
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (isActuallyPending)
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
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isVip ? null : goldColor.withOpacity(0.15),
                        gradient: isVip
                            ? const LinearGradient(
                                colors: [
                                  Color(0xFFB8860B),
                                  Color(0xFFD4AF37),
                                  Color(0xFFFFD700),
                                ],
                              )
                            : null,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isVip
                              ? Colors.transparent
                              : goldColor.withOpacity(0.5),
                        ),
                        boxShadow: isVip
                            ? [
                                BoxShadow(
                                  color: goldColor.withOpacity(0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.star,
                            color: isVip ? Colors.black : goldColor,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isVip ? "VIP Membership" : "Classic Membership",
                            style: TextStyle(
                              color: isVip ? Colors.black : goldColor,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),

              // JOIN VIP Promo Banner (Only if NOT already approved or pending)
              if (!isVipStatus && !isActuallyPending && tier != 'store')
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF1A1A1A),
                          const Color(0xFF2A2A2A),
                          goldColor.withOpacity(0.1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: goldColor.withOpacity(0.3),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: goldColor.withOpacity(0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Decorative Background Icon
                        Positioned(
                          right: -20,
                          top: -20,
                          child: Icon(
                            Icons.diamond_rounded,
                            size: 120,
                            color: goldColor.withOpacity(0.05),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: goldColor,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      "PRESTIGE",
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                "JOIN THE VIP CLUB",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "Unlock exclusive benefits, priority bookings, and luxury rewards.",
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFB8860B),
                                        Color(0xFFFFD700),
                                        Color(0xFFD4AF37),
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: goldColor.withOpacity(0.3),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    onPressed: () async {
                                      final result = await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              VipUpgradeScreen(
                                                userData: widget.userData,
                                              ),
                                        ),
                                      );

                                      if (result == true) {
                                        setState(() {
                                          _isUpgradePending = true;
                                        });
                                      }
                                    },
                                    child: const Text(
                                      "UPGRADE NOW",
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // VIP Status & Progress Section (Hide for stores)
              if (tier != 'store') ...[
                const SizedBox(height: 24),
                _buildVipProgressSection(provider, themeProvider),
              ],

              // Store Management Section (Only for Store Tier)
              if (tier == 'store')
                _buildSection("Business Management", [
                  _buildSettingItem(
                    Icons.storefront,
                    "Store Profile",
                    "Update address and physical location",
                    themeProvider,
                    onTap: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              StoreProfileScreen(userData: widget.userData),
                        ),
                      );
                      if (result == true) {
                        setState(() {});
                      }
                    },
                  ),
                ], themeProvider),

              const SizedBox(height: 8),

              // Settings Sections
              _buildSection("Account", [
                _buildSettingItem(
                  Icons.person,
                  "Edit Profile",
                  "Update your personal information",
                  themeProvider,
                  onTap: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            EditProfileScreen(userData: widget.userData),
                      ),
                    );
                    if (result == true) {
                      setState(() {
                        // Triggers rebuild to reflect changes in widget.userData
                      });
                    }
                  },
                ),
                _buildSettingItem(
                  Icons.phone,
                  "Phone Number",
                  phone,
                  themeProvider,
                ),
                _buildSettingItem(
                  Icons.email,
                  "Email Address",
                  email,
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
    final goldColor = const Color(0xFFEBC14F);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              color: titleColor ?? goldColor.withOpacity(0.5),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: goldColor.withOpacity(0.1)),
          ),
          child: Column(
            children: items.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              return Column(
                children: [
                  item,
                  if (idx < items.length - 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Divider(
                        color: goldColor.withOpacity(0.05),
                        height: 1,
                      ),
                    ),
                ],
              );
            }).toList(),
          ),
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

  Widget _buildVipProgressSection(
    Map<String, dynamic> provider,
    ThemeProvider themeProvider,
  ) {
    final goldColor = const Color(0xFFEBC14F);
    final stats = provider['therapist_stat'] ?? {};
    final currentTier = provider['current_tier'];

    // Extract stats
    int onlineMinutes = stats['total_online_minutes'] ?? 0;

    // LIVE PROGRESS: If currently online, calculate minutes elapsed in this session
    final lastOnlineStr = stats['last_online_at'];
    if (lastOnlineStr != null) {
      try {
        final lastOnline = DateTime.parse(
          lastOnlineStr.endsWith('Z') ? lastOnlineStr : '${lastOnlineStr}Z',
        );
        final liveSessionMinutes = DateTime.now()
            .toUtc()
            .difference(lastOnline)
            .inMinutes;
        if (liveSessionMinutes > 0) {
          onlineMinutes += liveSessionMinutes;
        }
      } catch (e) {
        debugPrint("Error parsing last_online_at: $e");
      }
    }

    final int extensions = stats['total_extensions'] ?? 0;
    final int bookings = stats['total_bookings'] ?? 0;

    // Use dynamic tiers from API if available, otherwise fallback to defaults
    final List<dynamic> fetchedTiers = widget.userData['tiers'] ?? [];
    final List<Map<String, dynamic>> allTiers = fetchedTiers.isNotEmpty
        ? fetchedTiers
              .map(
                (t) => {
                  'name': t['name'] ?? 'Tier',
                  'level': t['level'] ?? 0,
                  'minutes':
                      (t['online_minutes_required'] ??
                              (t['online_hours_required'] ?? 0) * 60)
                          .toDouble(),
                  'extensions': (t['extensions_required'] ?? 0).toDouble(),
                  'bookings': (t['bookings_required'] ?? 0).toDouble(),
                },
              )
              .toList()
        : [
            {
              'name': 'Tier 1',
              'level': 1,
              'minutes': 6000.0,
              'extensions': 50.0,
              'bookings': 100.0,
            },
            {
              'name': 'Tier 2',
              'level': 2,
              'minutes': 30000.0,
              'extensions': 150.0,
              'bookings': 250.0,
            },
            {
              'name': 'Tier 3',
              'level': 3,
              'minutes': 60000.0,
              'extensions': 300.0,
              'bookings': 500.0,
            },
          ];

    final int currentLevel = currentTier?['level'] ?? 0;
    Map<String, dynamic>? nextTier;

    // Sort allTiers by level to ensure correct order
    allTiers.sort((a, b) => a['level'].compareTo(b['level']));

    // Find the first tier that has a level higher than currentLevel
    for (var tier in allTiers) {
      if (tier['level'] > currentLevel) {
        nextTier = tier;
        break;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: goldColor.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "VIP STATUS",
                        style: TextStyle(
                          color: goldColor.withOpacity(0.5),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currentTier?['name'] ?? "Standard Account",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                if (nextTier != null) const SizedBox(width: 8),
                if (nextTier != null)
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: goldColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "PROGRESS TO ${nextTier['name'].toUpperCase()}",
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: goldColor,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            if (nextTier != null) ...[
              _buildStatProgress(
                "Online Minutes",
                onlineMinutes.toDouble(),
                nextTier['minutes'].toDouble(),
                Icons.timer_outlined,
                goldColor,
                themeProvider,
              ),
              const SizedBox(height: 16),
              _buildStatProgress(
                "Extensions",
                extensions.toDouble(),
                nextTier['extensions'].toDouble(),
                Icons.add_circle_outline,
                goldColor,
                themeProvider,
              ),
              const SizedBox(height: 16),
              _buildStatProgress(
                "Completed Bookings",
                bookings.toDouble(),
                nextTier['bookings'].toDouble(),
                Icons.check_circle_outline,
                goldColor,
                themeProvider,
              ),
            ] else if (currentLevel > 0) ...[
              const Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.workspace_premium,
                      color: Color(0xFFEBC14F),
                      size: 48,
                    ),
                    SizedBox(height: 8),
                    Text(
                      "MAX TIER REACHED",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Text(
                "Complete the requirements to upgrade your account and unlock premium benefits.",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatProgress(
    String label,
    double current,
    double target,
    IconData icon,
    Color color,
    ThemeProvider themeProvider,
  ) {
    final double progress = (current / target).clamp(0.0, 1.0);
    final bool isCompleted = current >= target;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color.withOpacity(0.7)),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: themeProvider.textColor.withOpacity(0.7),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Text(
              "${current.toInt()} / ${target.toInt()}",
              style: TextStyle(
                color: isCompleted ? Colors.green : themeProvider.textColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Stack(
          children: [
            Container(
              height: 6,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(seconds: 1),
              height: 6,
              width: (MediaQuery.of(context).size.width - 96) * progress,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isCompleted
                      ? [Colors.green.shade400, Colors.green.shade700]
                      : [color.withOpacity(0.5), color],
                ),
                borderRadius: BorderRadius.circular(3),
                boxShadow: [
                  if (isCompleted)
                    BoxShadow(
                      color: Colors.green.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // VIP Upgrade Screen now handles the form and submission.
}
