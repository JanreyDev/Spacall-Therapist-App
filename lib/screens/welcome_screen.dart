import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'nearby_bookings_screen.dart';
import 'login_screen.dart';

class WelcomeScreen extends StatelessWidget {
  final Map<String, dynamic> userData;

  const WelcomeScreen({super.key, required this.userData});

  Future<void> _handleLogout(BuildContext context) async {
    // Just navigate back to LoginScreen.
    // We KEEP the last_mobile_number in prefs so it remains "linked" for PIN login.
    // If they want to switch, they can use the "Switch Account" button on the LoginScreen.
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = userData['user'];
    final token = userData['token'];
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
              const Text(
                'Your profile is currently under review.',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 48),
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
