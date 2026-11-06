import 'package:flutter/material.dart';

class AppTheme {
  static const emerald = Color(0xFF10B981);
  static const darkGreen = Color(0xFF064E3B);
  static const pageBackground = Color(0xFFF5F7F7);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: emerald,
      brightness: Brightness.light,
    ).copyWith(
      primary: emerald,
      onPrimary: Colors.white,
      secondary: darkGreen,
      surface: Colors.white,
      onSurface: const Color(0xFF1F2937),
    );

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: pageBackground,
      useMaterial3: true,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: pageBackground,
        foregroundColor: Color(0xFF111827),
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: emerald, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: emerald.withValues(alpha: 0.14),
        labelTextStyle: WidgetStatePropertyAll(
          const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
      ),
    );
  }
}
