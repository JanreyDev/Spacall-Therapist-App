import 'package:flutter/material.dart';
import '../api_service.dart';
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
        isOnline: true,
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
    final user = widget.userData['user'];
    final token = widget.userData['token'];
    final name = user != null
        ? "${user['first_name']} ${user['last_name']}"
        : "Therapist";

    return Scaffold(
      appBar: AppBar(
        title: const Text('Therapist Dashboard'),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_none),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ActiveRequestsScreen(token: token),
                    ),
                  ).then((_) => _checkActiveRequests());
                },
              ),
              if (_requestCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '$_requestCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _handleLogout(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 48),
              CircleAvatar(
                radius: 50,
                backgroundImage: user?['profile_photo_url'] != null
                    ? NetworkImage(
                        ApiService.normalizePhotoUrl(
                          user?['profile_photo_url'],
                        )!,
                      )
                    : null,
                child: user?['profile_photo_url'] == null
                    ? const Icon(Icons.person, size: 50)
                    : null,
              ),
              const SizedBox(height: 24),
              Text(
                'Welcome, $name!',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _isOnline ? Colors.green : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isOnline ? 'ONLINE' : 'OFFLINE',
                    style: TextStyle(
                      color: _isOnline ? Colors.green : Colors.grey,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text(
                  'Availability Status',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  _isOnline
                      ? 'You are visible to clients'
                      : 'You are hidden from clients',
                ),
                value: _isOnline,
                onChanged: _isUpdating ? null : _toggleOnline,
                activeColor: Colors.green,
                secondary: Icon(
                  _isOnline ? Icons.visibility : Icons.visibility_off,
                  color: _isOnline ? Colors.green : Colors.grey,
                ),
              ),
              const Divider(),
              const Text(
                'Your profile is currently under review.',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              if (_ongoingBooking != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.green.shade800, Colors.green.shade600],
                      ),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      leading: const CircleAvatar(
                        backgroundColor: Colors.white24,
                        child: Icon(Icons.play_arrow, color: Colors.white),
                      ),
                      title: const Text(
                        'ONGOING JOB',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      subtitle: Text(
                        '${_ongoingBooking!['service']['name']} - ${_ongoingBooking!['status'].toUpperCase()}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white,
                        size: 16,
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => JobProgressScreen(
                              booking: _ongoingBooking!,
                              token: token,
                            ),
                          ),
                        ).then((_) => _checkOngoingJob());
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                          ),
                          title: const Text('Current Location'),
                          subtitle: Text(_currentAddress),
                        ),
                        const Divider(),
                        const ListTile(
                          leading: Icon(Icons.info_outline),
                          title: Text('Account Status'),
                          subtitle: Text('Pending Verification'),
                        ),
                        const Divider(),
                        ListTile(
                          leading: const Icon(Icons.work_outline),
                          title: const Text('Role'),
                          subtitle: Text(user?['role'] ?? 'Therapist'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            NearbyBookingsScreen(token: token),
                      ),
                    );
                  },
                  icon: const Icon(Icons.search),
                  label: const Text('Find Nearby Jobs'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
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
    const goldColor = Color(0xFFD4AF37);
    showDialog(
      context: context,
      barrierDismissible: !isError,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
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
                style: const TextStyle(
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
                style: const TextStyle(color: Colors.white70, fontSize: 16),
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
                            color: Colors.white.withOpacity(0.3),
                          ),
                          foregroundColor: Colors.white,
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
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFFB8860B),
                              goldColor,
                              Color(0xFFFFD700),
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
