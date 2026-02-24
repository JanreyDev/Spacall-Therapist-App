import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
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
import '../widgets/luxury_waiver_dialog.dart';

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
  String _currency = '₱';

  // Dashboard Stats
  int _sessions = 0;
  String _rating = '5.0';
  double _earningsToday = 0.0;
  List<dynamic> _transactions = [];
  bool _isTransactionsLoading = true;
  // Store specific

  int get _totalRequestCount =>
      _directRequestCount + _nearbyRequestCount + _storeRequestCount;

  @override
  void initState() {
    super.initState();
    print("WelcomeScreen initialized - Dynamic Dashboard");
    _startPolling();
    // Initialize WebSocket immediately — do NOT wait for GPS/toggleOnline
    _initRealtimeListeners();
    // Check for waiver acceptance
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _checkWaiver();
    });
  }

  void _initRealtimeListeners() {
    var provider = widget.userData['provider'];
    if (provider == null && widget.userData['user'] != null) {
      provider = widget.userData['user']['provider'];
    }
    if (provider == null || provider['id'] == null) return;

    final providerId = provider['id'];
    final token = widget.userData['token'];

    _apiService.initEcho(token, providerId).then((_) {
      if (!mounted) return;
      _apiService.listenForBookings(providerId, (booking) {
        if (!mounted) return;
        _checkActiveRequests();
        _showBookingNotification(booking, isDirect: true);
      });
      debugPrint(
        '[WelcomeScreen] Real-time listener active for provider $providerId',
      );
    });
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
    _fetchTransactions();
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
        _fetchTransactions();
        _updateLiveLocation();
      }
    });
  }

  Future<void> _checkWaiver() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasAgreed = prefs.getBool('waiver_accepted_therapist_v1') ?? false;

      if (!hasAgreed && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => LuxuryWaiverDialog(
            onAccepted: () async {
              await prefs.setBool('waiver_accepted_therapist_v1', true);
              Navigator.of(context).pop();
            },
          ),
        );
      }
    } catch (e) {
      debugPrint("Error checking waiver: $e");
    }
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

          // Auto-offline if balance falls below 1000
          if (_walletBalance < 1000 && _isOnline) {
            _isOnline = false;
            _apiService.updateLocation(
              token: widget.userData['token'],
              latitude: _currentPosition?.latitude ?? 14.5995,
              longitude: _currentPosition?.longitude ?? 120.9842,
              isOnline: false,
            );
          }
        });
      }
    } catch (e) {
      print('Error fetching profile: $e');
    }
  }

  Future<void> _fetchTransactions() async {
    try {
      final transactions = await _apiService.getTransactions(
        widget.userData['token'],
      );
      if (mounted) {
        setState(() {
          _transactions = transactions;
          _isTransactionsLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching transactions: $e');
      if (mounted) {
        setState(() {
          _isTransactionsLoading = false;
        });
      }
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
                    NumberFormat.currency(symbol: '₱', decimalDigits: 2).format(
                      double.tryParse(
                            booking['total_amount']?.toString().replaceAll(
                                  RegExp(r'[^0-9.]'),
                                  '',
                                ) ??
                                '0',
                          ) ??
                          0,
                    ),
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
      timeLimit: const Duration(seconds: 5),
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
                      NumberFormat.currency(
                        symbol: '₱',
                        decimalDigits: 2,
                      ).format(
                        double.tryParse(
                              booking['total_amount']?.toString().replaceAll(
                                    RegExp(r'[^0-9.]'),
                                    '',
                                  ) ??
                                  '0',
                            ) ??
                            0,
                      ),
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
        // WebSocket is already initialized in initState/_initRealtimeListeners.
        // No need to re-init here — just ensure connection is live.
        debugPrint(
          '[WelcomeScreen] Therapist went online — WebSocket already connected.',
        );
      } else {
        _apiService.disconnectEcho();
      }
    } catch (e) {
      if (!mounted) return;
      _showLuxuryDialog(
        e.toString().replaceAll("Exception:", "").trim(),
        isError: true,
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

    final nickname = user?['nickname'];
    final firstName = user?['first_name'] ?? "Therapist";
    final middleName = user?['middle_name'] ?? "";
    final lastName = user?['last_name'] ?? "";
    final fullName = middleName.isNotEmpty
        ? "$firstName $middleName $lastName"
        : (lastName.isNotEmpty ? "$firstName $lastName" : firstName);
    final name = (nickname != null && nickname.toString().isNotEmpty)
        ? nickname
        : fullName;

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
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: goldColor.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                color: goldColor.withOpacity(0.05),
                blurRadius: 10,
                spreadRadius: -2,
              ),
            ],
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

  Future<void> _handleDeposit(double amount, String method) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
      ),
    );

    try {
      final response = await _apiService.deposit(
        token: widget.userData['token'],
        amount: amount,
        method: method,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading
      Navigator.of(context).pop(); // Close deposit dialog

      setState(() {
        // Update balance from response or just add amount
        // ideally response should return new balance
        if (response['balance'] != null) {
          _walletBalance =
              double.tryParse(response['balance'].toString()) ?? _walletBalance;
        } else {
          _walletBalance += amount;
        }
      });

      // Show success
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => LuxurySuccessModal(
          title: 'DEPOSIT SUCCESSFUL',
          message:
              'You have successfully deposited $_currency${NumberFormat('#,##0.00', 'en_US').format(amount)} into your wallet.',
          buttonText: 'OKAY',
          onConfirm: () => Navigator.of(context).pop(),
        ),
      );

      // Refresh profile to sync everything
      _fetchProfile();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Deposit failed: ${e.toString().replaceAll("Exception:", "")}',
          ),
        ),
      );
    }
  }

  void _showDepositDialog() {
    final amountController = TextEditingController();
    String selectedMethod = 'GCash';
    const goldColor = Color(0xFFD4AF37);
    final paymentMethods = ['GCash', 'Debit Card', 'Credit Card'];

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: goldColor.withOpacity(0.5)),
        ),
        child: StatefulBuilder(
          builder: (context, setState) => Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'DEPOSIT FUNDS',
                      style: TextStyle(
                        color: goldColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Amount',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 48,
                  child: TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      prefixText: '$_currency ',
                      prefixStyle: const TextStyle(color: goldColor),
                      filled: true,
                      fillColor: Colors.black.withOpacity(0.3),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: goldColor.withOpacity(0.3),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: goldColor),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Payment Method',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: goldColor.withOpacity(0.3)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedMethod,
                      dropdownColor: const Color(0xFF1E1E1E),
                      icon: const Icon(Icons.arrow_drop_down, color: goldColor),
                      isExpanded: true,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      onChanged: (String? newValue) {
                        setState(() {
                          selectedMethod = newValue!;
                        });
                      },
                      items: paymentMethods.map<DropdownMenuItem<String>>((
                        String value,
                      ) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 45,
                  child: ElevatedButton(
                    onPressed: () {
                      final amount =
                          double.tryParse(amountController.text) ?? 0.0;
                      if (amount > 0) {
                        _handleDeposit(amount, selectedMethod);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: goldColor,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'PROCEED TO PAYMENT',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleWithdraw(
    double amount,
    String method,
    String accountDetails,
  ) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
      ),
    );

    try {
      final response = await _apiService.withdraw(
        token: widget.userData['token'],
        amount: amount,
        method: method,
        accountDetails: accountDetails,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // Dismiss loading

      setState(() {
        if (response['balance'] != null) {
          _walletBalance =
              double.tryParse(response['balance'].toString()) ?? _walletBalance;
        } else {
          _walletBalance -= amount;
        }
      });

      // Show success
      showDialog(
        context: context,
        builder: (context) => LuxurySuccessModal(
          title: 'WITHDRAWAL SUBMITTED',
          message:
              'Your request to withdraw $_currency${NumberFormat('#,##0.00', 'en_US').format(amount)} has been received.',
          buttonText: 'OKAY',
          onConfirm: () => Navigator.of(context).pop(),
        ),
      );

      // Refresh profile
      _fetchProfile();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Dismiss loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Withdrawal failed: ${e.toString().replaceAll("Exception:", "")}',
          ),
        ),
      );
    }
  }

  void _showWithdrawDialog() {
    final amountController = TextEditingController();
    final accountController = TextEditingController();
    String selectedMethod = 'GCash';
    const goldColor = Color(0xFFD4AF37);
    final paymentMethods = ['GCash', 'Bank Transfer'];

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: goldColor.withOpacity(0.5)),
        ),
        child: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'WITHDRAW FUNDS',
                        style: TextStyle(
                          color: goldColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54),
                        onPressed: () => Navigator.of(context).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Amount',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 48,
                    child: TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        prefixText: '$_currency ',
                        prefixStyle: const TextStyle(color: goldColor),
                        filled: true,
                        fillColor: Colors.black.withOpacity(0.3),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: goldColor.withOpacity(0.3),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: goldColor),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Withdraw via',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: goldColor.withOpacity(0.3)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedMethod,
                        dropdownColor: const Color(0xFF1E1E1E),
                        icon: const Icon(
                          Icons.arrow_drop_down,
                          color: goldColor,
                        ),
                        isExpanded: true,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        onChanged: (String? newValue) {
                          setState(() {
                            selectedMethod = newValue!;
                          });
                        },
                        items: paymentMethods.map<DropdownMenuItem<String>>((
                          String value,
                        ) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    selectedMethod == 'GCash'
                        ? 'GCash Number'
                        : 'Account Number',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 48,
                    child: TextField(
                      controller: accountController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.black.withOpacity(0.3),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: goldColor.withOpacity(0.3),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: goldColor),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 45,
                    child: ElevatedButton(
                      onPressed: () {
                        final amount =
                            double.tryParse(amountController.text) ?? 0.0;
                        final account = accountController.text;

                        if (amount <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter a valid amount'),
                            ),
                          );
                          return;
                        }

                        if (amount > _walletBalance) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Insufficient balance'),
                            ),
                          );
                          return;
                        }

                        if (account.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter account details'),
                            ),
                          );
                          return;
                        }

                        Navigator.of(context).pop(); // Close dialog
                        _handleWithdraw(amount, selectedMethod, account);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: goldColor,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'WITHDRAW',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWalletButton({
    required String text,
    required IconData icon,
    required Color color,
    required bool isOutlined,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isOutlined ? Colors.transparent : color,
        foregroundColor: isOutlined ? color : Colors.black,
        elevation: isOutlined ? 0 : 4,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isOutlined
              ? BorderSide(color: color.withOpacity(0.5))
              : BorderSide.none,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletSection(Color goldColor, ThemeProvider themeProvider) {
    return Column(
      children: [
        ClipRRect(
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
                border: Border.all(
                  color: goldColor.withOpacity(0.25),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: goldColor.withOpacity(0.1),
                    blurRadius: 30,
                    spreadRadius: -5,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
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
                      '$_currency ${NumberFormat('#,##0.00', 'en_US').format(_walletBalance)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: _buildWalletButton(
                          text: 'Deposit',
                          icon: Icons.add,
                          color: goldColor,
                          isOutlined: false,
                          onPressed: _showDepositDialog,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildWalletButton(
                          text: 'Withdraw',
                          icon: Icons.arrow_outward,
                          color: goldColor,
                          isOutlined: true,
                          onPressed: _showWithdrawDialog,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "RECENT TRANSACTIONS",
              style: TextStyle(
                color: goldColor,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            if (!_isTransactionsLoading && _transactions.isNotEmpty)
              Text(
                "SEE ALL",
                style: TextStyle(
                  color: goldColor.withOpacity(0.5),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _isTransactionsLoading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
                ),
              )
            : _transactions.isEmpty
            ? Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        color: Colors.white.withOpacity(0.2),
                        size: 40,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "No transactions yet",
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.3),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _transactions.length > 5 ? 5 : _transactions.length,
                itemBuilder: (context, index) {
                  final tx = _transactions[index];
                  return _buildTransactionCard(tx, themeProvider, goldColor);
                },
              ),
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildTransactionCard(
    Map<String, dynamic> tx,
    ThemeProvider themeProvider,
    Color goldColor,
  ) {
    final type = tx['type']?.toString().toLowerCase() ?? '';
    final status = tx['status']?.toString().toLowerCase() ?? '';
    final amount = double.tryParse(tx['amount']?.toString() ?? '0') ?? 0.0;
    final createdAt =
        DateTime.tryParse(tx['created_at'] ?? '') ?? DateTime.now();
    final dateStr = DateFormat('MMM dd, yyyy • hh:mm a').format(createdAt);

    bool isCredit = true;
    IconData icon = Icons.payment;
    String title = 'Transaction';

    if (type == 'deposit') {
      title = 'Wallet Top-up';
      icon = Icons.add_circle_outline;
      isCredit = true;
    } else if (type == 'withdrawal') {
      title = 'Wallet Withdrawal';
      icon = Icons.remove_circle_outline;
      isCredit = false;
    } else if (type == 'booking') {
      title = 'Session Payment';
      icon = Icons.spa_outlined;
      isCredit = true; // For therapist, booking is credit!
    }

    // Use meta description if available
    if (tx['meta'] != null) {
      try {
        final meta = tx['meta'] is String ? jsonDecode(tx['meta']) : tx['meta'];
        if (meta['description'] != null) {
          title = meta['description'];
        }
      } catch (e) {
        // Ignore JSON parse errors
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: goldColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: goldColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  dateStr,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "${isCredit ? '+' : '-'} ₱${NumberFormat('#,##0.00', 'en_US').format(amount.abs())}",
                style: TextStyle(
                  color: isCredit ? Colors.greenAccent : Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (status != 'completed')
                Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    color: status == 'pending' ? Colors.orange : Colors.red,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
            ],
          ),
        ],
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
            _fetchTransactions(); // Refresh transactions
            _fetchDashboardStats();
          }
        }
      } catch (e) {
        debugPrint("[PAYMENT MONITOR] Error during payment check: $e");
      }
    });
  }
}
