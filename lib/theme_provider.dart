import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode = true; // Default to dark mode for luxury vibe

  bool get isDarkMode => _isDarkMode;

  ThemeProvider() {
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('isDarkMode') ?? true;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', _isDarkMode);
    notifyListeners();
  }

  // Common colors for Therapist App (matched with Client App)
  Color get goldColor => const Color(0xFFD4AF37);
  Color get backgroundColor =>
      _isDarkMode ? const Color(0xFF121212) : const Color(0xFFFAFAFA);
  Color get textColor => _isDarkMode ? Colors.white : Colors.black87;
  Color get subtextColor =>
      _isDarkMode ? Colors.white.withOpacity(0.5) : Colors.black54;
  Color get cardColor =>
      _isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white;

  ThemeData get currentTheme {
    final baseTheme = _isDarkMode ? ThemeData.dark() : ThemeData.light();

    return baseTheme.copyWith(
      primaryColor: goldColor,
      scaffoldBackgroundColor: backgroundColor,
      colorScheme: baseTheme.colorScheme.copyWith(
        primary: goldColor,
        secondary: goldColor,
        surface: cardColor,
        background: backgroundColor,
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      textTheme: GoogleFonts.outfitTextTheme(baseTheme.textTheme).copyWith(
        bodyLarge: TextStyle(color: textColor),
        bodyMedium: TextStyle(color: textColor),
        titleLarge: TextStyle(color: textColor, fontWeight: FontWeight.bold),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: backgroundColor,
        selectedItemColor: goldColor,
        unselectedItemColor: subtextColor,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }
}
