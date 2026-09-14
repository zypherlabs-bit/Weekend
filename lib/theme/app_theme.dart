import 'package:flutter/material.dart';

class AppTheme {
  static const Color sunsetCoral = Color(0xFFFF4B72);
  static const Color sunsetCoralDark = Color(0xFFE0385D);
  static const Color midnightViolet = Color(0xFF1A1429);
  static const Color midnightVioletSurface = Color(0xFF231B38);
  static const Color midnightVioletCard = Color(0xFF2E244A);
  static const Color goldenPeach = Color(0xFFFF9966);
  static const Color goldenPeachLight = Color(0xFFFFB38A);
  static const Color darkBackground = Color(0xFF130E20);
  static const Color darkSurface = Color(0xFF1C162E);
  static const Color darkSurfaceVariant = Color(0xFF2B2244);
  static const Color darkOnBackground = Color(0xFFF3EEFA);
  static const Color darkOnSurface = Color(0xFFF3EEFA);
  static const Color lightBackground = Color(0xFFFCF8F7);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFF6ECE9);
  static const Color lightOnBackground = Color(0xFF211A20);
  static const Color lightOnSurface = Color(0xFF211A20);
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: sunsetCoral,
        onPrimary: Colors.white,
        primaryContainer: Color(0xFFFFD9DF),
        onPrimaryContainer: Color(0xFF3F0013),
        secondary: Color(0xFF4C3F6D),
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFFE9DEFF),
        tertiary: Color(0xFFB55416),
        surface: lightSurface,
        onSurface: lightOnSurface,
        surfaceContainerHighest: lightSurfaceVariant,
        onSurfaceVariant: lightOnBackground,
      ),
      scaffoldBackgroundColor: lightBackground,
      fontFamily: 'Roboto',
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: sunsetCoral,
        onPrimary: Colors.white,
        primaryContainer: midnightVioletCard,
        onPrimaryContainer: goldenPeachLight,
        secondary: goldenPeach,
        onSecondary: midnightViolet,
        secondaryContainer: midnightVioletSurface,
        onSecondaryContainer: goldenPeachLight,
        tertiary: goldenPeachLight,
        surface: darkSurface,
        onSurface: darkOnSurface,
        surfaceContainerHighest: darkSurfaceVariant,
        onSurfaceVariant: darkOnBackground,
      ),
      scaffoldBackgroundColor: darkBackground,
      fontFamily: 'Roboto',
    );
  }
}
