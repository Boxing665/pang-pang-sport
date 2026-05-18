import 'package:flutter/material.dart';

class AppTheme {
  static const Color _background = Color(0xFF0A1020);
  static const Color _surface = Color(0xFF131C31);
  static const Color _surfaceAlt = Color(0xFF1A2642);
  static const Color _primary = Color(0xFF3DDC97);
  static const Color _secondary = Color(0xFF4FC3F7);
  static const Color _accent = Color(0xFFFFC857);
  static const Color _danger = Color(0xFFFF6B6B);

  static ThemeData get darkTheme {
    const colorScheme = ColorScheme.dark(
      primary: _primary,
      secondary: _secondary,
      tertiary: _accent,
      error: _danger,
      surface: _surface,
      onPrimary: Color(0xFF08120D),
      onSecondary: Colors.white,
      onSurface: Colors.white,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
    );

    return base.copyWith(
      scaffoldBackgroundColor: _background,
      canvasColor: _background,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: _surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(
            color: Color(0x1FFFFFFF),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: _surfaceAlt,
        selectedColor: const Color(0x223DDC97),
        disabledColor: _surfaceAlt,
        side: const BorderSide(color: Color(0x1FFFFFFF)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        secondaryLabelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          color: _primary,
        ),
      ),
      dividerColor: const Color(0x14FFFFFF),
      iconTheme: const IconThemeData(
        color: Colors.white,
      ),
      textTheme: base.textTheme.copyWith(
        headlineMedium: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
        titleLarge: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
        titleMedium: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: const TextStyle(
          color: Color(0xFFF3F6FF),
          height: 1.4,
        ),
        bodyMedium: const TextStyle(
          color: Color(0xFFD0D7E8),
          height: 1.45,
        ),
        bodySmall: const TextStyle(
          color: Color(0xFF95A3BF),
          height: 1.35,
        ),
        labelLarge: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        labelMedium: const TextStyle(
          color: Color(0xFFD0D7E8),
          fontWeight: FontWeight.w600,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.zero,
        textColor: Colors.white,
        iconColor: Colors.white,
      ),
    );
  }

  static const List<Color> heroGradient = <Color>[
    Color(0xFF1B2846),
    Color(0xFF111A2E),
    Color(0xFF0A1020),
  ];

  static const Color primaryAccent = _primary;
  static const Color secondaryAccent = _secondary;
  static const Color highlight = _accent;
  static const Color surface = _surface;
  static const Color surfaceAlt = _surfaceAlt;
}