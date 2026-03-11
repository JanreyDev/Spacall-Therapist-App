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

    final tier = userData['user']?['customer_tier'] ?? 'classic';
    final bool isStore = tier == 'store';
    final bool isClassic = tier == 'classic';

    // Determine tab count: 1 for classic (nearby only), 3 for store, 2 for others
    final int tabCount = isClassic ? 1 : (isStore ? 3 : 2);

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
          bottom: tabCount > 1
              ? TabBar(
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
                    if (!isClassic)
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
                )
              : null,
        ),
        body: TabBarView(
          children: [
            NearbyBookingsScreen(
              token: token,
              userData: userData,
              isTab: true,
              onTabSwitch: (index) {
                DefaultTabController.of(context).animateTo(index);
              },
            ),
            if (!isClassic)
              ActiveRequestsScreen(
                token: token,
                userData: userData,
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
