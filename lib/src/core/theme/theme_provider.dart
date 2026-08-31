import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// This class is now a simple container for the application's light theme data.
class ThemeProvider {
  // Warna brand utama (pink) — dipakai AppBar & tombol utama
  static const Color brandPink = Color(0xFFFF5FB4);

  // Warna item terpilih di bottom navigation bar
  static const Color bottomNavSelected = Color(0xFFEA4CA1);

  static final ThemeData lightTheme = ThemeData(
    colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue, brightness: Brightness.light),
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF5F5F7),
    textTheme: GoogleFonts.poppinsTextTheme(),
    appBarTheme: AppBarTheme(
      backgroundColor: const Color.fromARGB(255, 252, 74, 169),
      titleTextStyle: GoogleFonts.poppins(
          fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.white),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      selectedItemColor: bottomNavSelected,
      unselectedItemColor: Colors.grey,
      showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: brandPink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 15),
      ),
    ),
  );
}
