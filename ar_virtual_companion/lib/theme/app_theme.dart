import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // SumOne-inspired Pastel Color Palette
  static const Color pastelPink = Color(0xFFFFD1DC); // Soft pink background
  static const Color pastelCream = Color(0xFFFFFDF5); // Creamy/Ivory background (SumOne style)
  static const Color pastelBlue = Color(0xFFAEC6CF); // Soft blue
  static const Color pastelGreen = Color(0xFF77DD77); // Pastel green
  static const Color pastelPurple = Color(0xFFB39EB5); // Pastel purple
  static const Color pastelOrange = Color(0xFFFFB347); // Pastel orange
  
  // Primary Action Colors
  static const Color primaryColor = Color(0xFFC4A484); // Light Brown (浅啡色) for primary actions
  static const Color secondaryColor = Color(0xFF4ECDC4); // Teal for secondary actions
  
  // Neutral Colors
  static const Color surfaceColor = Color(0xFFFFFDF5); // Creamy/Ivory background
  static const Color surfaceVariant = Color(0xFFF8F0F2);
  static const Color onSurface = Color(0xFF5D5D5D); // Dark brownish-grey text (softer than black)
  static const Color onSurfaceVariant = Color(0xFF8C8C8C);
  
  // Status Colors
  static const Color errorColor = Color(0xFFFF6B6B);
  static const Color successColor = Color(0xFF77DD77);
  static const Color warningColor = Color(0xFFFFB347);

  // Dark Theme Colors (Muted Pastels)
  static const Color darkBackground = Color(0xFF2D2D2D);
  static const Color darkSurface = Color(0xFF383838);
  static const Color darkPrimary = Color(0xFFFF8E8E);
  static const Color darkOnSurface = Color(0xFFE0E0E0);

  static TextTheme get textTheme {
    return GoogleFonts.mPlusRounded1cTextTheme(
      const TextTheme(
        displayLarge: TextStyle(fontSize: 57, fontWeight: FontWeight.bold, letterSpacing: -0.25),
        displayMedium: TextStyle(fontSize: 45, fontWeight: FontWeight.bold),
        displaySmall: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
        headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
        headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
        headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.15),
        titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1),
        bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, letterSpacing: 0.5),
        bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, letterSpacing: 0.25),
        bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, letterSpacing: 0.4),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 1.0),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.light,
        primary: primaryColor,
        secondary: secondaryColor,
        surface: surfaceColor,
        error: errorColor,
        onSurface: onSurface,
        background: pastelPink.withOpacity(0.1),
      ),
      scaffoldBackgroundColor: surfaceColor,
      textTheme: textTheme.apply(
        bodyColor: onSurface,
        displayColor: onSurface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceColor,
        foregroundColor: onSurface,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.mPlusRounded1c(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: onSurface,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24), // Pill shape
          ),
          textStyle: GoogleFonts.mPlusRounded1c(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 4,
        shadowColor: pastelPink.withOpacity(0.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24), // More rounded
        ),
        margin: const EdgeInsets.all(8),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: pastelPink.withOpacity(0.5), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primaryColor,
        unselectedItemColor: onSurfaceVariant,
        selectedLabelStyle: GoogleFonts.mPlusRounded1c(fontWeight: FontWeight.bold),
        unselectedLabelStyle: GoogleFonts.mPlusRounded1c(fontWeight: FontWeight.w500),
        elevation: 10,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: darkPrimary,
        brightness: Brightness.dark,
        primary: darkPrimary,
        surface: darkSurface,
        onSurface: darkOnSurface,
        background: darkBackground,
      ),
      scaffoldBackgroundColor: darkBackground,
      textTheme: textTheme.apply(
        bodyColor: darkOnSurface,
        displayColor: darkOnSurface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: darkOnSurface,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkPrimary,
          foregroundColor: darkBackground,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
