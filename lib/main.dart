import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/animated_logo_screen.dart';
import 'theme_provider.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'Spacall Therapist',
      debugShowCheckedModeBanner: false,
      theme: themeProvider.currentTheme,
      home: const AnimatedLogoScreen(),
    );
  }
}
