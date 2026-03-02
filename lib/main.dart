import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_provider.dart';
import 'screens/animated_logo_screen.dart';
import 'screens/welcome_screen.dart';
import 'support_chat_provider.dart';
import 'theme_provider.dart';
import 'package:app_links/app_links.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Early fetch of user data to avoid splash if possible
  final prefs = await SharedPreferences.getInstance();
  final userDataStr = prefs.getString('user_data');
  Map<String, dynamic>? userData;

  if (userDataStr != null && userDataStr.isNotEmpty) {
    try {
      userData = jsonDecode(userDataStr);
    } catch (e) {
      debugPrint('[MAIN] Error parsing user data: $e');
    }
  }

  // Catch any early framework errors
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[CRASH] FlutterError: ${details.exception}');
  };

  // Log incoming links at the root level for debugging
  AppLinks().uriLinkStream.listen((uri) {
    debugPrint('[ROOT DEEP LINK] Received: $uri');
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => SupportChatProvider()),
      ],
      child: MyApp(initialUserData: userData),
    ),
  );
}

class MyApp extends StatelessWidget {
  final Map<String, dynamic>? initialUserData;
  const MyApp({super.key, this.initialUserData});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'Spacall Therapist',
      debugShowCheckedModeBanner: false,
      theme: themeProvider.currentTheme,
      onGenerateRoute: (settings) {
        debugPrint(
          '[NAVIGATION] onGenerateRoute Attempted for: ${settings.name}',
        );
        return MaterialPageRoute(
          builder: (context) => initialUserData != null
              ? WelcomeScreen(userData: initialUserData!)
              : const AnimatedLogoScreen(),
        );
      },
      home: initialUserData != null
          ? WelcomeScreen(userData: initialUserData!)
          : const AnimatedLogoScreen(),
    );
  }
}
