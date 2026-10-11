import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../features/home_layout/domain/app_layout.dart';

// Membangun ThemeData aplikasi. Nilai warna & font bisa diubah admin dari
// App Builder (web) — lihat AppLayoutProvider.
class ThemeProvider {
  // Warna brand utama (pink) — dipakai AppBar & tombol utama
  static const Color brandPink = Color(0xFFFF5FB4);

  // Warna item terpilih di bottom navigation bar
  static const Color bottomNavSelected = Color(0xFFEA4CA1);

  static final ThemeData lightTheme = buildTheme(AppDesign.defaults);

  static ThemeData buildTheme(AppDesign design) {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
          seedColor: design.seedColor, brightness: Brightness.light),
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: design.backgroundColor,
      textTheme: _textTheme(design.fontFamily),
      appBarTheme: AppBarTheme(
        backgroundColor: design.appBarColor,
        titleTextStyle: _font(
          design.fontFamily,
          const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ).copyWith(color: design.appBarTextColor),
        elevation: 0,
        iconTheme: IconThemeData(color: design.appBarTextColor),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        selectedItemColor: design.navSelectedColor ?? bottomNavSelected,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: design.buttonColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }

  // GoogleFonts melempar exception bila nama font tidak dikenal → kembali ke
  // Poppins (font bawaan aplikasi).
  static TextTheme _textTheme(String fontFamily) {
    try {
      return GoogleFonts.getTextTheme(fontFamily);
    } catch (_) {
      return GoogleFonts.poppinsTextTheme();
    }
  }

  static TextStyle _font(String fontFamily, TextStyle style) {
    try {
      return GoogleFonts.getFont(fontFamily, textStyle: style);
    } catch (_) {
      return GoogleFonts.poppins(textStyle: style);
    }
  }
}
