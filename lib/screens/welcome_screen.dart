import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api_service.dart';
import '../theme_provider.dart';
import 'nearby_bookings_screen.dart';
import 'active_requests_screen.dart';
import 'login_screen.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'job_progress_screen.dart';

class WelcomeScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const WelcomeScreen({super.key, required this.userData});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final ApiService _apiService = ApiService();
  bool _isOnline = false;
  bool _isUpdating = false;
  String _currentAddress = 'Not set';
  int _requestCount = 0;
  Map<String, dynamic>? _ongoingBooking;
  Timer? _pollingTimer;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _checkActiveRequests();
    _checkOngoingJob();
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isOnline) {
        _checkActiveRequests();
        _checkOngoingJob();
        _updateLiveLocation();
      }
    });
  }

  Future<void> _updateLiveLocation() async {
    try {
      final position = await _determinePosition();
      await _apiService.updateLocation(
        token: widget.userData['token'],
        latitude: position.latitude,
        longitude: position.longitude,
        isOnline: _isOnline,
      );
      await _getAddressFromLatLng(position);
    } catch (e) {
      print('Periodic location update error: $e');
    }
  }

  Future<void> _checkActiveRequests() async {
    try {
      final response = await _apiService.getActiveRequests(
        token: widget.userData['token'],
      );
      final List<dynamic> requests = response['bookings'] ?? [];
      if (mounted) {
        setState(() {
          _requestCount = requests.length;
        });
      }
    } catch (e) {
      print('Polling error: $e');
    }
  }

  Future<void> _checkOngoingJob() async {
    try {
      final response = await _apiService.getCurrentBookings(
        token: widget.userData['token'],
      );
      final List<dynamic> current = response['current'] ?? [];

      // Look for any job that is NOT pending but still active
      final ongoingStatuses = [
        'accepted',
        'en_route',
        'arrived',
        'in_progress',
      ];
      final ongoing = current.firstWhere(
        (b) => ongoingStatuses.contains(b['status']),
        orElse: () => null,
      );

      if (mounted) {
        setState(() {
          _ongoingBooking = ongoing;
        });
      }
    } catch (e) {
      print('Ongoing job check error: $e');
    }
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
        'Location permissions are permanently denied, we cannot request permissions.',
      );
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 15),
    );
  }

  Future<void> _getAddressFromLatLng(Position position) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        if (mounted) {
          setState(() {
            _currentAddress =
                "${place.street}, ${place.locality}, ${place.administrativeArea}";
          });
        }
      }
    } catch (e) {
      print("Geocoding error: $e");
      if (mounted) {
        setState(() {
          _currentAddress = "Address unavailable";
        });
      }
    }
  }

  Future<void> _toggleOnline(bool value) async {
    setState(() {
      _isUpdating = true;
    });

    try {
      double latitude = 14.5995;
      double longitude = 120.9842;

      if (value) {
        try {
          final position = await _determinePosition();
          latitude = position.latitude;
          longitude = position.longitude;
          await _getAddressFromLatLng(position);
        } catch (e) {
          if (!mounted) return;
          _showLuxuryDialog(
            'Location error: $e. Using default.',
            isError: true,
          );
        }
      }

      await _apiService.updateLocation(
        token: widget.userData['token'],
        latitude: latitude,
        longitude: longitude,
        isOnline: value,
      );
      setState(() {
        _isOnline = value;
        _isUpdating = false;
      });

      if (value) {
        // Defensive: Check top level, then nested in user
        var provider = widget.userData['provider'];
        if (provider == null && widget.userData['user'] != null) {
          provider = widget.userData['user']['provider'];
        }

        if (provider == null || provider['id'] == null) {
          throw Exception(
            'Therapist profile not found. Please log out and back in.',
          );
        }

        final providerId = provider['id'];
        await _apiService.initEcho(widget.userData['token'], providerId);
        _apiService.listenForBookings(providerId, (booking) {
          _checkActiveRequests();
          if (!mounted) return;
          _showLuxuryDialog(
            'New Booking Request from ${booking['customer']['first_name']}!',
            actionLabel: 'View',
            onActionPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      ActiveRequestsScreen(token: widget.userData['token']),
                ),
              );
            },
          );
        });
      } else {
        _apiService.disconnectEcho();
      }
    } catch (e) {
      if (!mounted) return;
      _showLuxuryDialog('Failed to update status: $e', isError: true);
      setState(() {
        _isUpdating = false;
      });
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final goldColor = themeProvider.goldColor;
    final backgroundColor = themeProvider.backgroundColor;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildDashboard(themeProvider),
          ActiveRequestsScreen(token: widget.userData['token'], isTab: true),
          NearbyBookingsScreen(token: widget.userData['token'], isTab: true),
          _buildProfile(themeProvider),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(goldColor, themeProvider),
    );
  }

  Widget _buildBottomNav(Color goldColor, ThemeProvider themeProvider) {
    return Container(
      decoration: BoxDecoration(
        color: themeProvider.backgroundColor,
        border: Border(
          top: BorderSide(
            color: themeProvider.isDarkMode
                ? Colors.white.withOpacity(0.05)
                : Colors.black.withOpacity(0.05),
            width: 1,
          ),
        ),
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: goldColor,
        unselectedItemColor: themeProvider.subtextColor,
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Stack(
              children: [
                const Icon(Icons.notifications_none_rounded),
                if (_requestCount > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 12,
                        minHeight: 12,
                      ),
                    ),
                  ),
              ],
            ),
            activeIcon: const Icon(Icons.notifications_rounded),
            label: 'Requests',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.explore_outlined),
            activeIcon: Icon(Icons.explore),
            label: 'Nearby',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline_rounded),
            activeIcon: Icon(Icons.person_rounded),
            label: 'Account',
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard(ThemeProvider themeProvider) {
    final user = widget.userData['user'];
    final goldColor = themeProvider.goldColor;
    final textColor = themeProvider.textColor;

    final name = user != null
        ? "${user['first_name']} ${user['last_name']}"
        : "Therapist";

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Custom Luxury Header
          Container(
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 32),
            decoration: BoxDecoration(
              color: themeProvider.isDarkMode
                  ? Colors.white.withOpacity(0.02)
                  : Colors.black.withOpacity(0.02),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: goldColor.withOpacity(0.1),
                  backgroundImage: user?['profile_photo_url'] != null
                      ? NetworkImage(
                          ApiService.normalizePhotoUrl(
                            user!['profile_photo_url'],
                          )!,
                        )
                      : null,
                  child: user?['profile_photo_url'] == null
                      ? Icon(Icons.person, color: goldColor, size: 30)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome back,',
                        style: TextStyle(
                          color: themeProvider.subtextColor,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        name,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _handleLogout(context),
                  icon: Icon(
                    Icons.power_settings_new_rounded,
                    color: Colors.red.shade400,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Availability Section
                _buildStatusCard(goldColor, themeProvider),

                const SizedBox(height: 24),

                if (_ongoingBooking != null) ...[
                  _buildOngoingJobCard(goldColor, themeProvider),
                  const SizedBox(height: 24),
                ],

                // Location Card
                _buildInfoCard(
                  Icons.location_on_outlined,
                  'Current Location',
                  _currentAddress,
                  themeProvider,
                  iconColor: Colors.red.shade300,
                ),

                const SizedBox(height: 16),

                // Review Status
                _buildInfoCard(
                  Icons.verified_user_outlined,
                  'Verification Status',
                  'Under Review', // Dynamically check verification_status if available
                  themeProvider,
                  iconColor: Colors.orange.shade300,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(Color goldColor, ThemeProvider themeProvider) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: themeProvider.isDarkMode
            ? Colors.white.withOpacity(0.05)
            : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _isOnline ? goldColor.withOpacity(0.3) : Colors.transparent,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_isOnline ? goldColor : Colors.grey).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isOnline ? Icons.visibility : Icons.visibility_off,
                  color: _isOnline ? goldColor : Colors.grey,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Service Visibility',
                      style: TextStyle(
                        color: themeProvider.textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _isOnline
                          ? 'Available for bookings'
                          : 'Hidden from clients',
                      style: TextStyle(
                        color: themeProvider.subtextColor,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _isOnline,
                onChanged: _isUpdating ? null : _toggleOnline,
                activeColor: goldColor,
                activeTrackColor: goldColor.withOpacity(0.3),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
    IconData icon,
    String title,
    String value,
    ThemeProvider themeProvider, {
    Color? iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: themeProvider.isDarkMode
            ? Colors.white.withOpacity(0.03)
            : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor ?? themeProvider.goldColor, size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: themeProvider.subtextColor,
                    fontSize: 12,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: themeProvider.textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOngoingJobCard(Color goldColor, ThemeProvider themeProvider) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => JobProgressScreen(
              booking: _ongoingBooking!,
              token: widget.userData['token'],
            ),
          ),
        ).then((_) => _checkOngoingJob());
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.green.shade800.withOpacity(0.9),
              Colors.green.shade600.withOpacity(0.9),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.spa_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ONGOING JOB',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _ongoingBooking!['service']['name'],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfile(ThemeProvider themeProvider) {
    final user = widget.userData['user'];
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 60,
            backgroundImage: user?['profile_photo_url'] != null
                ? NetworkImage(
                    ApiService.normalizePhotoUrl(user!['profile_photo_url'])!,
                  )
                : null,
            child: user?['profile_photo_url'] == null
                ? Icon(Icons.person, size: 60, color: themeProvider.goldColor)
                : null,
          ),
          const SizedBox(height: 24),
          Text(
            user?['first_name'] ?? 'User',
            style: TextStyle(
              color: themeProvider.textColor,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 40),
          _buildInfoCard(
            Icons.verified_outlined,
            'Status',
            'Verified',
            themeProvider,
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            Icons.settings_outlined,
            'Settings',
            'Preferences',
            themeProvider,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => _handleLogout(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.withOpacity(0.1),
              foregroundColor: Colors.red,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  void _showLuxuryDialog(
    String message, {
    bool isError = false,
    String? actionLabel,
    VoidCallback? onActionPressed,
  }) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final goldColor = themeProvider.goldColor;

    showDialog(
      context: context,
      barrierDismissible: !isError,
      builder: (context) => Dialog(
        backgroundColor: themeProvider.isDarkMode
            ? const Color(0xFF1E1E1E)
            : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: (isError ? Colors.redAccent : goldColor).withOpacity(0.5),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.check_circle_outline,
                color: isError ? Colors.redAccent : goldColor,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                isError ? 'ERROR' : 'SUCCESS',
                style: TextStyle(
                  color: goldColor,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: themeProvider.textColor.withOpacity(0.7),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  if (actionLabel != null && onActionPressed != null) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: themeProvider.textColor.withOpacity(0.3),
                          ),
                          foregroundColor: themeProvider.textColor,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('DISMISS'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFFB8860B),
                              goldColor,
                              const Color(0xFFFFD700),
                            ],
                          ),
                        ),
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            onActionPressed();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            actionLabel.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ] else
                    Expanded(
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            colors: isError
                                ? [
                                    Colors.redAccent.withOpacity(0.8),
                                    Colors.redAccent,
                                  ]
                                : [
                                    const Color(0xFFB8860B),
                                    goldColor,
                                    const Color(0xFFFFD700),
                                  ],
                          ),
                        ),
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'CONTINUE',
                            style: TextStyle(
                              color: isError ? Colors.white : Colors.black,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
