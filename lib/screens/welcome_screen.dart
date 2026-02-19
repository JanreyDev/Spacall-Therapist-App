import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api_service.dart';
import '../theme_provider.dart';
import 'consolidated_requests_screen.dart';
import 'package:intl/intl.dart';

import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'job_progress_screen.dart';
import 'booking_history_screen.dart';
import 'account_screen.dart';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';
import '../widgets/luxury_success_modal.dart';

class WelcomeScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const WelcomeScreen({super.key, required this.userData});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final ApiService _apiService = ApiService();
  bool _isOnline = true;
  bool _isUpdating = false;
  String _currentAddress = 'Not set';
  int _directRequestCount = 0;
  int _nearbyRequestCount = 0;
  int _storeRequestCount = 0;
  Map<String, dynamic>? _ongoingBooking;
  Timer? _pollingTimer;
  Timer? _monitorPaymentTimer;
  int _selectedIndex = 0;
  Position? _currentPosition;
  int? _lastNearbyBookingId;

  int? _lastDirectBookingId;
  double _walletBalance = 0.00;
  String _verificationStatus = 'pending'; // pending, verified, rejected
  String _currency = 'PHP';

  // Dashboard Stats
  int _sessions = 0;
  String _rating = '5.0';
  double _earningsToday = 0.0;
  // Store specific

  int get _totalRequestCount =>
      _directRequestCount + _nearbyRequestCount + _storeRequestCount;

  @override
  void initState() {
    super.initState();
    print("WelcomeScreen initialized - Dynamic Dashboard");
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _fetchProfile();
    _checkActiveRequests();
    _checkOngoingJob();
    _checkNearbyBookings();
    _fetchDashboardStats(); // Initial fetch
    if (widget.userData['user']?['customer_tier'] == 'store') {
      _checkStoreRequests();
    }
    // Auto-online on login
    _toggleOnline(true);
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isOnline) {
        _fetchProfile();
        _fetchDashboardStats(); // Periodic fetch
        _checkActiveRequests();
        _checkOngoingJob();
        _checkNearbyBookings();
        if (widget.userData['user']?['customer_tier'] == 'store') {
          _checkStoreRequests();
        }
        _updateLiveLocation();
      }
    });
  }

  Future<void> _updateLiveLocation() async {
    try {
      final position = await _determinePosition();
      setState(() {
        _currentPosition = position;
      });
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

  Future<void> _fetchProfile() async {
    try {
      final profile = await _apiService.getProfile(widget.userData['token']);
      final user = profile['user'];
      if (mounted) {
        setState(() {
          // Adjust parsing based on actual API response structure
          _walletBalance =
              double.tryParse(user['wallet_balance'].toString()) ?? 0.00;
          // Map is_verified (bool) to status string
          bool isVerified =
              user['is_verified'] == true || user['is_verified'] == 1;
          _verificationStatus = isVerified ? 'verified' : 'pending';

          // _currency = user['currency'] ?? 'PHP';
        });
      }
    } catch (e) {
      print('Error fetching profile: $e');
    }
  }

  Future<void> _fetchDashboardStats() async {
    try {
      final stats = await _apiService.getDashboardStats(
        widget.userData['token'],
      );
      if (mounted) {
        setState(() {
          _sessions = stats['sessions'] ?? 0;
          _rating = stats['rating']?.toString() ?? '5.0';
          _earningsToday =
              double.tryParse(stats['earnings_today']?.toString() ?? '0') ??
              0.0;
        });
      }
    } catch (e) {
      print('Error fetching stats: $e');
    }
  }

  Future<void> _checkActiveRequests() async {
    try {
      final response = await _apiService.getActiveRequests(
        token: widget.userData['token'],
        bookingType: 'home_service',
      );
      final List<dynamic> requests = response['bookings'] ?? [];

      if (requests.isNotEmpty) {
        final latestBooking = requests.first;
        final latestId = latestBooking['id'];

        if (_lastDirectBookingId != latestId) {
          _lastDirectBookingId = latestId;
          if (mounted) {
            _showBookingNotification(latestBooking, isDirect: true);
          }
        }
      }

      if (mounted) {
        setState(() {
          _directRequestCount = requests.length;
        });
      }
    } catch (e) {
      print('Polling error: $e');
    }
  }

  Future<void> _checkStoreRequests() async {
    try {
      final response = await _apiService.getActiveRequests(
        token: widget.userData['token'],
        bookingType: 'in_store',
      );
      final List<dynamic> requests = response['bookings'] ?? [];

      if (mounted) {
        setState(() {
          _storeRequestCount = requests.length;
        });
      }
    } catch (e) {
      print('Polling error (Store): $e');
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

  Future<void> _checkNearbyBookings() async {
    if (!_isOnline) return;

    try {
      final response = await _apiService.getNearbyBookings(
        token: widget.userData['token'],
      );
      final List<dynamic> bookings = response['bookings'] ?? [];

      if (bookings.isNotEmpty) {
        final latestBooking = bookings.first;
        final latestId = latestBooking['id'];

        // Only notify if it's a new booking we haven't shown yet
        if (_lastNearbyBookingId != latestId) {
          _lastNearbyBookingId = latestId;
          if (mounted) {
            _showBookingNotification(latestBooking, isDirect: false);
          }
        }

        // Update nearby count for the tab badge
        if (mounted) {
          setState(() {
            _nearbyRequestCount = bookings.length;
          });
        }
      } else {
        // Clear nearby count if no bookings
        if (mounted) {
          setState(() {
            _nearbyRequestCount = 0;
          });
        }
      }
    } catch (e) {
      print('Nearby job polling error: $e');
    }
  }

  void _showBookingNotification(
    Map<String, dynamic> booking, {
    bool isDirect = false,
  }) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final goldColor = themeProvider.goldColor;
    final customer = booking['customer'];
    final service = booking['service'];
    final bookingType = booking['booking_type'] ?? 'home_service';
    final isStore = bookingType == 'in_store';

    String label = isDirect
        ? 'SOMEONE REQUESTED YOU'
        : 'NEW NEARBY OPPORTUNITY';
    IconData icon = isDirect
        ? Icons.person_pin_outlined
        : Icons.explore_outlined;

    if (isStore) {
      label = 'NEW STORE APPOINTMENT';
      icon = Icons.storefront_outlined;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: themeProvider.isDarkMode
            ? const Color(0xFF1E1E1E)
            : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(
            color: isStore ? goldColor : goldColor.withOpacity(0.3),
            width: isStore ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with Gradient
            Container(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    goldColor.withOpacity(isStore ? 0.3 : 0.15),
                    goldColor.withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: goldColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: goldColor, size: 32),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: goldColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: goldColor.withOpacity(0.4),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: goldColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                children: [
                  // Client Avatar & Distance
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: goldColor, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: goldColor.withOpacity(0.2),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(35),
                          child: customer['profile_photo_url'] != null
                              ? Image.network(
                                  ApiService.normalizePhotoUrl(
                                    customer['profile_photo_url'],
                                  )!,
                                  fit: BoxFit.cover,
                                )
                              : Icon(Icons.person, color: goldColor, size: 40),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${customer['first_name']} ${customer['last_name']}',
                            style: TextStyle(
                              color: themeProvider.textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Builder(
                            builder: (context) {
                              double distanceKm = 0.0;
                              final loc = booking['location'];
                              if (loc != null && _currentPosition != null) {
                                distanceKm =
                                    Geolocator.distanceBetween(
                                      _currentPosition!.latitude,
                                      _currentPosition!.longitude,
                                      double.parse(loc['latitude'].toString()),
                                      double.parse(loc['longitude'].toString()),
                                    ) /
                                    1000;
                              }
                              return Text(
                                '${distanceKm.toStringAsFixed(1)} KM AWAY',
                                style: TextStyle(
                                  color: goldColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  Text(
                    service['name'] ?? 'Luxury Service',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: themeProvider.textColor,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '₱${booking['total_amount']}',
                    style: TextStyle(
                      color: goldColor,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 20),

                  const SizedBox(height: 32),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _showBookingDetails(booking);
                          },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: goldColor.withOpacity(0.5)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'DETAILS',
                            style: TextStyle(
                              color: goldColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.redAccent),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'DECLINE',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Main Accept Button
                  Container(
                    width: double.infinity,
                    height: 54,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFFB8860B),
                          goldColor,
                          const Color(0xFFFFD700),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
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
                      onPressed: () {
                        Navigator.pop(context);
                        _acceptBooking(booking['id']);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'ACCEPT JOB NOW',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: 1.1,
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
    );
  }

  Future<void> _acceptBooking(int bookingId) async {
    try {
      final response = await _apiService.updateBookingStatus(
        token: widget.userData['token'],
        bookingId: bookingId,
        status: 'accepted',
      );

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => LuxurySuccessModal(
          title: 'SUCCESS',
          message: 'Booking ACCEPTED! You can now start your journey.',
          onConfirm: () {
            Navigator.of(dialogContext).pop(); // Close modal

            // Redirect to job progress
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => JobProgressScreen(
                  booking: response['booking'],
                  token: widget.userData['token'],
                ),
              ),
            ).then((result) {
              if (result == 'switch_to_sessions') {
                setState(() => _selectedIndex = 2);
                _monitorPaymentRelease(bookingId);
              }
              _checkOngoingJob();
            });
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => LuxurySuccessModal(
          isError: true,
          title: 'ERROR',
          message: e.toString().replaceAll('Exception: ', ''),
          onConfirm: () => Navigator.of(context).pop(),
        ),
      );
    }
  }

  Future<void> _handleLogout() async {
    try {
      // Disconnect Echo & Polling
      _apiService.disconnectEcho();
      _pollingTimer?.cancel();

      // Backend logout (silent failure ok)
      try {
        await _apiService.logout(widget.userData['token']);
      } catch (e) {
        print('Backend logout failed: $e');
      }

      // Clear local auth token
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');

      if (!mounted) return;

      // Navigate back to LoginScreen
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      print('Logout sequence error: $e');
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
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

  void _showBookingDetails(Map<String, dynamic> booking) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final goldColor = themeProvider.goldColor;
    final customer = booking['customer'];
    final service = booking['service'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: themeProvider.isDarkMode
              ? const Color(0xFF121212)
              : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'SESSION DETAILS',
              style: TextStyle(
                color: goldColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            const Divider(color: Colors.white10),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Client Info Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundImage:
                                customer['profile_photo_url'] != null
                                ? NetworkImage(
                                    ApiService.normalizePhotoUrl(
                                      customer['profile_photo_url'],
                                    )!,
                                  )
                                : null,
                            child: customer['profile_photo_url'] == null
                                ? const Icon(Icons.person)
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${customer['first_name']} ${customer['last_name']}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Text(
                                  'Premium Client',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    _buildDetailSection(
                      'SERVICE',
                      service['name'] ?? 'Luxury Spa Treatment',
                      Icons.spa,
                    ),
                    _buildDetailSection(
                      'TOTAL PAYOUT',
                      '₱${booking['total_amount']}',
                      Icons.payments,
                    ),
                    Builder(
                      builder: (context) {
                        double distanceKm = 0.0;
                        final loc = booking['location'];
                        if (loc != null && _currentPosition != null) {
                          distanceKm =
                              Geolocator.distanceBetween(
                                _currentPosition!.latitude,
                                _currentPosition!.longitude,
                                double.parse(loc['latitude'].toString()),
                                double.parse(loc['longitude'].toString()),
                              ) /
                              1000;
                        }
                        return _buildDetailSection(
                          'DISTANCE',
                          '${distanceKm.toStringAsFixed(1)} KM AWAY',
                          Icons.map_outlined,
                        );
                      },
                    ),
                    _buildDetailSection(
                      'LOCATION',
                      booking['location']?['address'] ?? 'Customer address',
                      Icons.location_on,
                    ),
                    _buildDetailSection(
                      'GENDER PREFERENCE',
                      (booking['gender_preference'] ?? 'Any')
                          .toString()
                          .toUpperCase(),
                      Icons.people_outline,
                    ),
                    _buildDetailSection(
                      'MASSAGE INTENSITY',
                      (booking['intensity_preference'] ?? 'Medium')
                          .toString()
                          .toUpperCase(),
                      Icons.fitness_center_outlined,
                    ),
                    if (booking['customer_notes'] != null &&
                        booking['customer_notes'].toString().isNotEmpty)
                      _buildDetailSection(
                        'SPECIAL NOTES',
                        booking['customer_notes'],
                        Icons.note_alt,
                      ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'CLOSE',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Container(
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [goldColor, const Color(0xFFFFD700)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _acceptBooking(booking['id']);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'ACCEPT NOW',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
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
    );
  }

  Widget _buildDetailSection(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFD4AF37), size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 10,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
            String name = place.name ?? "";
            String street = place.street ?? "";
            String locality = place.locality ?? "";

            if (street.isNotEmpty && street != name) {
              _currentAddress = "$street, $locality";
            } else if (name.isNotEmpty) {
              _currentAddress = "$name, $locality";
            } else {
              _currentAddress = locality;
            }

            if (_currentAddress.isEmpty) _currentAddress = "Tarlac City, PH";
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

          if (e.toString().contains('Location services are disabled')) {
            bool opened = await Geolocator.openLocationSettings();
            if (opened) {
              // Should we retry?
              // For now, let's just use default but warn user gently or just return
            }

            _showLuxuryDialog(
              'Location services disabled. Using default location.',
              isError: false, // Not an error strictly, just a warning
            );
          } else {
            _showLuxuryDialog(
              'Location error: $e. Using default.',
              isError: true,
            );
          }
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
          _showBookingNotification(booking, isDirect: true);
        });
      } else {
        _apiService.disconnectEcho();
      }
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => LuxurySuccessModal(
          isError: true,
          title: 'ERROR',
          message: 'Failed to update status: $e',
          onConfirm: () => Navigator.of(context).pop(),
        ),
      );
      setState(() {
        _isUpdating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final goldColor = themeProvider.goldColor;

    return Scaffold(
      backgroundColor: themeProvider.backgroundColor,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildDashboard(themeProvider),
          ConsolidatedRequestsScreen(
            token: widget.userData['token'],
            userData: widget.userData,
            onTabSwitch: (index) {
              setState(() => _selectedIndex = index);
            },
          ),
          BookingHistoryScreen(
            token: widget.userData['token'],
            showAppBar: false,
          ),
          AccountScreen(userData: widget.userData),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(goldColor, themeProvider),
    );
  }

  Widget _buildBottomNav(Color goldColor, ThemeProvider themeProvider) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        border: Border(top: BorderSide(color: Colors.white12, width: 1)),
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
                if (_totalRequestCount > 0)
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
                      child: Text(
                        '$_totalRequestCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            activeIcon: const Icon(Icons.notifications_rounded),
            label: 'Requests',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            activeIcon: Icon(Icons.history),
            label: "Sessions",
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: "Account",
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard(ThemeProvider themeProvider) {
    return _buildTherapistDashboard(themeProvider);
  }

  Widget _buildTherapistDashboard(ThemeProvider themeProvider) {
    final user = widget.userData['user'];
    final goldColor = themeProvider.goldColor;
    final textColor = themeProvider.textColor;

    final firstName = user?['first_name'] ?? "Therapist";
    final middleName = user?['middle_name'] ?? "";
    final lastName = user?['last_name'] ?? "";
    final name = middleName.isNotEmpty
        ? "$firstName $middleName $lastName"
        : (lastName.isNotEmpty ? "$firstName $lastName" : firstName);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Refined Header Layout
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Logout Button (Far Left)
              IconButton(
                onPressed: _handleLogout,
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: textColor.withOpacity(0.4),
                  size: 20,
                ),
                tooltip: 'Logout',
              ),
              // Status Group (Right)
              Row(
                children: [
                  // Location Indicator
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          user?['customer_tier'] == 'store'
                              ? Icons.storefront
                              : Icons.location_on,
                          color: goldColor,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 100),
                          child: Text(
                            _currentAddress,
                            style: TextStyle(
                              color: textColor.withOpacity(0.7),
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Online Toggle
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: _isOnline ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                            boxShadow: _isOnline
                                ? [
                                    BoxShadow(
                                      color: Colors.green.withOpacity(0.5),
                                      blurRadius: 4,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        Transform.scale(
                          scale: 0.7,
                          child: Switch.adaptive(
                            value: _isOnline,
                            onChanged: _isUpdating ? null : _toggleOnline,
                            activeColor: goldColor,
                            activeTrackColor: goldColor.withOpacity(0.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 32),

          // 2. Hero Section: Greeting & Avatar (Standard Professional Layout)
          Row(
            children: [
              // Glowing Avatar
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: goldColor.withOpacity(0.2),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: goldColor.withOpacity(0.1),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: goldColor.withOpacity(0.1),
                  backgroundImage: user?['profile_photo_url'] != null
                      ? NetworkImage(
                          ApiService.normalizePhotoUrl(
                            user!['profile_photo_url'],
                          )!,
                        )
                      : null,
                  child: user?['profile_photo_url'] == null
                      ? Icon(
                          user?['customer_tier'] == 'store'
                              ? Icons.storefront
                              : Icons.person,
                          color: goldColor,
                          size: 32,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Welcome back,',
                          style: TextStyle(
                            color: themeProvider.subtextColor,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (user?['customer_tier'] != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: goldColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: goldColor.withOpacity(0.4),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              user!['customer_tier'].toString().toUpperCase(),
                              style: TextStyle(
                                color: goldColor,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: ShaderMask(
                            shaderCallback: (bounds) => LinearGradient(
                              colors: [textColor, goldColor.withOpacity(0.8)],
                            ).createShader(bounds),
                            child: Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                height: 1.1,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if (_verificationStatus == 'verified') ...[
                          const SizedBox(width: 8),
                          Icon(Icons.verified, color: goldColor, size: 20),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 40),

          // Reordered Content: Wallet FIRST
          _buildWalletSection(goldColor, themeProvider),
          const SizedBox(height: 24),

          // Stats SECOND
          _buildStatsSection(goldColor, themeProvider),
          const SizedBox(height: 24),

          // Ongoing Job - REMOVED per user request
          // if (_ongoingBooking != null) ...[
          //   _buildOngoingJobCard(goldColor, themeProvider),
          //   const SizedBox(height: 24),
          // ],

          // Extra bottom padding for scrolling
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildStatsSection(Color goldColor, ThemeProvider themeProvider) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            title: 'Sessions',
            value: '$_sessions',
            icon: Icons.spa_outlined,
            goldColor: goldColor,
            themeProvider: themeProvider,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            title: 'Rating',
            value: _rating,
            icon: Icons.star_border_rounded,
            goldColor: goldColor,
            themeProvider: themeProvider,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            title: 'Earnings',
            value: '₱${NumberFormat('#,##0').format(_earningsToday)}',
            icon: Icons.account_balance_wallet_outlined,
            goldColor: goldColor,
            themeProvider: themeProvider,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color goldColor,
    required ThemeProvider themeProvider,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: goldColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: goldColor, size: 20),
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: TextStyle(
                  color: themeProvider.textColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  color: themeProvider.subtextColor,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWalletSection(Color goldColor, ThemeProvider themeProvider) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                goldColor.withOpacity(0.15),
                goldColor.withOpacity(0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: goldColor.withOpacity(0.25), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.account_balance_wallet_rounded,
                          color: goldColor.withOpacity(0.5),
                          size: 14,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'WALLET BALANCE',
                          style: TextStyle(
                            color: goldColor.withOpacity(0.5),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Colors.white, Color(0xFFFFD700)],
                      ).createShader(bounds),
                      child: Text(
                        '$_currency ${NumberFormat('#,##0', 'en_US').format(_walletBalance)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: goldColor.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () {
                    _showLuxuryDialog('Withdraw feature coming soon!');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: goldColor,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Withdraw',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // _buildStatusCard removed

  void _showLuxuryDialog(
    String message, {
    bool isError = false,
    String? actionLabel,
    VoidCallback? onActionPressed,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) => LuxurySuccessModal(
        isError: isError,
        title: isError ? 'ERROR' : 'SUCCESS',
        message: message,
        buttonText: actionLabel?.toUpperCase() ?? 'CONTINUE',
        onConfirm: () {
          Navigator.of(dialogContext).pop();
          if (onActionPressed != null) {
            onActionPressed();
          }
        },
      ),
    );
  }

  void _monitorPaymentRelease(int bookingId) {
    debugPrint("[PAYMENT MONITOR] Starting monitor for booking $bookingId");
    _monitorPaymentTimer?.cancel();
    int checks = 0;

    _monitorPaymentTimer = Timer.periodic(const Duration(seconds: 5), (
      timer,
    ) async {
      checks++;
      if (checks > 60) {
        // 5 minutes (300s / 5s = 60 checks)
        timer.cancel();
        return;
      }

      try {
        final statusData = await _apiService.getBookingStatus(
          bookingId,
          widget.userData['token'],
        );

        final booking = statusData['booking'] ?? statusData;
        final paymentStatus = booking['payment_status'];

        debugPrint(
          "[PAYMENT MONITOR] Booking $bookingId status: $paymentStatus",
        );

        if (paymentStatus == 'paid' || paymentStatus == 'released') {
          timer.cancel();
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => LuxurySuccessModal(
                title: "PAYMENT RECEIVED",
                message:
                    "Client has submitted their review and payment has been released to your wallet!",
                onConfirm: () => Navigator.pop(context),
              ),
            );
            _fetchProfile(); // Refresh wallet balance
            _fetchDashboardStats();
          }
        }
      } catch (e) {
        debugPrint("[PAYMENT MONITOR] Error during payment check: $e");
      }
    });
  }
}
