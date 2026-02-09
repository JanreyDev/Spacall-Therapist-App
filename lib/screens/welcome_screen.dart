import 'package:flutter/material.dart';
import '../api_service.dart';
import 'nearby_bookings_screen.dart';
import 'login_screen.dart';

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

  @override
  void initState() {
    super.initState();
    // In a real app, we'd fetch the current status from the backend.
    // For now, let's default to false.
  }

  Future<void> _toggleOnline(bool value) async {
    setState(() {
      _isUpdating = true;
    });

    try {
      // For development, we use hardcoded Manila coordinates
      await _apiService.updateLocation(
        token: widget.userData['token'],
        latitude: 14.5995,
        longitude: 120.9842,
        isOnline: value,
      );
      setState(() {
        _isOnline = value;
        _isUpdating = false;
      });
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
