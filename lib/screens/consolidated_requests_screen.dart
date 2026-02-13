import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme_provider.dart';
import 'active_requests_screen.dart';
import 'nearby_bookings_screen.dart';

import 'store_requests_screen.dart';

class ConsolidatedRequestsScreen extends StatelessWidget {
  final String token;
  final Map<String, dynamic> userData;
  final Function(int) onTabSwitch;

  const ConsolidatedRequestsScreen({
    super.key,
    required this.token,
    required this.userData,
    required this.onTabSwitch,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final goldColor = themeProvider.goldColor;

    final bool isStore = userData['user']?['customer_tier'] == 'store';
    final int tabCount = isStore ? 3 : 2;

    return DefaultTabController(
      length: tabCount,
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
            tabs: [
              const Tab(
                child: Text(
                  'NEARBY',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const Tab(
                child: Text(
                  'DIRECT',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (isStore)
                const Tab(
                  child: Text(
                    'STORE',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            NearbyBookingsScreen(
              token: token,
              isTab: true,
              onTabSwitch: onTabSwitch,
            ),
            ActiveRequestsScreen(
              token: token,
              isTab: true,
              onTabSwitch: onTabSwitch,
            ),
            if (isStore)
              StoreRequestsScreen(
                token: token,
                isTab: true,
                onTabSwitch: onTabSwitch,
              ),
          ],
        ),
      ),
    );
  }
}
