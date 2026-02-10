import 'package:flutter/material.dart';
import '../api_service.dart';
import 'nearby_bookings_screen.dart';
import 'active_requests_screen.dart';
import 'login_screen.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';

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
  int _requestCount = 0;
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
    // Check immediately
    _checkActiveRequests();
    // Then every 10 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_isOnline) {
        _checkActiveRequests();
      }
    });
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
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Location error: $e. Using default.')),
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
        final provider = widget.userData['provider'];
        if (provider == null || provider['id'] == null) {
          throw Exception(
            'Therapist profile not found. Please log out and back in.',
          );
        }

        final providerId = provider['id'];
        await _apiService.initEcho(widget.userData['token'], providerId);
        _apiService.listenForBookings(providerId, (booking) {
          _checkActiveRequests(); // Refresh count instantly
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'New Booking Request from ${booking['customer']['first_name']}!',
              ),
              action: SnackBarAction(
                label: 'View',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          ActiveRequestsScreen(token: widget.userData['token']),
                    ),
                  );
                },
              ),
            ),
          );
        });
      } else {
        _apiService.disconnectEcho();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update status: $e')));
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
                  ).then((_) => _checkActiveRequests()); // Refresh on return
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
              const CircleAvatar(
                radius: 50,
                child: Icon(Icons.person, size: 50),
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
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
}
