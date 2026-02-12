import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api_service.dart';
import '../theme_provider.dart';
import 'consolidated_requests_screen.dart';

import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'job_progress_screen.dart';
import 'booking_history_screen.dart';
import 'account_screen.dart';
import '../widgets/luxury_success_modal.dart';

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
  int _directRequestCount = 0;
  int _nearbyRequestCount = 0;
  Map<String, dynamic>? _ongoingBooking;
  Timer? _pollingTimer;
  int _selectedIndex = 0;
  int? _lastNearbyBookingId;
  int? _lastDirectBookingId;

  int get _totalRequestCount => _directRequestCount + _nearbyRequestCount;

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
    _checkNearbyBookings();
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isOnline) {
        _checkActiveRequests();
        _checkOngoingJob();
        _checkNearbyBookings();
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

      if (requests.isNotEmpty) {
        // Sort by created_at desc to get latest
        // (Assuming API returns sorted, but good to be safe if we rely on "latest")
        // actually API sorts by created_at desc.

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

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: themeProvider.isDarkMode
            ? const Color(0xFF1E1E1E)
            : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: goldColor.withOpacity(0.3), width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header with Gradient
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    goldColor.withOpacity(0.15),
                    goldColor.withOpacity(0.05),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
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
                    child: Icon(
                      Icons.notifications_active,
                      color: goldColor,
                      size: 32,
                    ),
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
                      isDirect ? 'DIRECT REQUEST' : 'NEW NEARBY JOB',
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
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 20),

                  // Customer & Location
                  _buildModalRow(
                    Icons.person_outline,
                    'Client: ${customer['first_name']} ${customer['last_name']}',
                    themeProvider,
                  ),
                  const SizedBox(height: 12),
                  _buildModalRow(
                    Icons.location_on_outlined,
                    booking['location']['address'],
                    themeProvider,
                  ),

                  if (booking['customer_notes'] != null &&
                      booking['customer_notes'].toString().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildModalRow(
                      Icons.note_alt_outlined,
                      booking['customer_notes'],
                      themeProvider,
                    ),
                  ],

                  const SizedBox(height: 32),

                  // Action Button
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

                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'DISMISS',
                      style: TextStyle(
                        color: themeProvider.textColor.withOpacity(0.5),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1.1,
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

  Widget _buildModalRow(
    IconData icon,
    String text,
    ThemeProvider themeProvider,
  ) {
    return Row(
      children: [
        Icon(icon, color: themeProvider.goldColor, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: themeProvider.textColor.withOpacity(0.7),
              fontSize: 15,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
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
          ConsolidatedRequestsScreen(token: widget.userData['token']),
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
    final user = widget.userData['user'];
    final goldColor = themeProvider.goldColor;
    final textColor = themeProvider.textColor;

    final name = user != null
        ? "${user['first_name']} ${user['last_name']}"
        : "Therapist";

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // New Header Layout
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Location
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.location_on, color: goldColor, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _currentAddress,
                        style: TextStyle(
                          color: themeProvider.subtextColor,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              // Status Toggle
              const SizedBox(width: 16),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
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
                  const SizedBox(width: 8),
                  Transform.scale(
                    scale: 0.8,
                    child: Switch.adaptive(
                      value: _isOnline,
                      onChanged: _isUpdating ? null : _toggleOnline,
                      activeColor: goldColor,
                      activeTrackColor: goldColor.withOpacity(0.3),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Greeting & Profile
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Gold Verification Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: goldColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: goldColor.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified, color: goldColor, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            'VERIFIED',
                            style: TextStyle(
                              color: goldColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Welcome back,',
                      style: TextStyle(
                        color: themeProvider.subtextColor,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      name,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: goldColor.withOpacity(0.5),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: goldColor.withOpacity(0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
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
                      ? Icon(Icons.person, color: goldColor, size: 32)
                      : null,
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

          // Ongoing Job
          if (_ongoingBooking != null) ...[
            _buildOngoingJobCard(goldColor, themeProvider),
            const SizedBox(height: 24),
          ],

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
            value: '12', // Mock data
            icon: Icons.spa_outlined,
            goldColor: goldColor,
            themeProvider: themeProvider,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            title: 'Rating',
            value: '4.9', // Mock data
            icon: Icons.star_border_rounded,
            goldColor: goldColor,
            themeProvider: themeProvider,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            title: 'Earnings',
            value: '₱2.5k', // Mock data
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Icon(icon, color: goldColor, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: themeProvider.textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(color: themeProvider.subtextColor, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletSection(Color goldColor, ThemeProvider themeProvider) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [goldColor.withOpacity(0.2), goldColor.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: goldColor.withOpacity(0.2), width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Wallet Balance',
                  style: TextStyle(
                    color: themeProvider.subtextColor,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '₱ 12,450.00', // Mock data
                  style: TextStyle(
                    color: goldColor,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              // TODO: Implement withdraw functionality
              _showLuxuryDialog('Withdraw feature coming soon!');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: goldColor,
              foregroundColor: Colors.black,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Withdraw',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // _buildStatusCard removed

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
        ).then((result) {
          if (result == 'switch_to_sessions') {
            setState(() => _selectedIndex = 3);
          }
          _checkOngoingJob();
        });
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
}
