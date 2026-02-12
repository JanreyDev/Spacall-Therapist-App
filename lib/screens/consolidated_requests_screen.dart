import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme_provider.dart';
import 'active_requests_screen.dart';
import 'nearby_bookings_screen.dart';

class ConsolidatedRequestsScreen extends StatelessWidget {
  final String token;

  const ConsolidatedRequestsScreen({super.key, required this.token});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final goldColor = themeProvider.goldColor;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: themeProvider.backgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          title: const Text(
            'REQUESTS',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              fontSize: 18,
            ),
          ),
          bottom: TabBar(
            indicatorColor: goldColor,
            labelColor: goldColor,
            unselectedLabelColor: Colors.white54,
            indicatorWeight: 3,
            tabs: const [
              Tab(
                child: Text(
                  'NEARBY',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Tab(
                child: Text(
                  'DIRECT',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            NearbyBookingsScreen(token: token, isTab: true),
            ActiveRequestsScreen(token: token, isTab: true),
          ],
        ),
      ),
    );
  }
}
