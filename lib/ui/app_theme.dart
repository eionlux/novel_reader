import 'package:flutter/material.dart';

/// 应用配色：黑白 / 夜间 / 纸质
enum AppPalette { mono, night, paper }

class AppTheme {
  AppTheme._();

  static AppPalette palette = AppPalette.mono;

  static bool get isNight => palette == AppPalette.night;
  static bool get isPaper => palette == AppPalette.paper;

  static Color get accent => switch (palette) {
    AppPalette.mono => const Color(0xFF1C1C1E),
    AppPalette.night => const Color(0xFFC9A86A),
    AppPalette.paper => const Color(0xFF8A5E3B),
  };

  static Color get onAccent => switch (palette) {
    AppPalette.mono => Colors.white,
    AppPalette.night => const Color(0xFF1A150C),
    AppPalette.paper => Colors.white,
  };

  static Color get canvas => switch (palette) {
    AppPalette.mono => const Color(0xFFFFFFFF),
    AppPalette.night => const Color(0xFF0F1113),
    AppPalette.paper => const Color(0xFFF5EDDF),
  };

  static Color get surface => switch (palette) {
    AppPalette.mono => const Color(0xFFFFFFFF),
    AppPalette.night => const Color(0xFF1B1E21),
    AppPalette.paper => const Color(0xFFFCF6EA),
  };

  static Color get subtleCanvas => switch (palette) {
    AppPalette.mono => const Color(0xFFF4F4F4),
    AppPalette.night => const Color(0xFF17191C),
    AppPalette.paper => const Color(0xFFEEE2CE),
  };

  static Color get primaryText => switch (palette) {
    AppPalette.mono => const Color(0xFF141416),
    AppPalette.night => const Color(0xFFECEDEF),
    AppPalette.paper => const Color(0xFF33291F),
  };

  static Color get secondaryText => switch (palette) {
    AppPalette.mono => const Color(0xFF73757A),
    AppPalette.night => const Color(0xFF9BA1A8),
    AppPalette.paper => const Color(0xFF8C7A64),
  };

  static Color get divider => switch (palette) {
    AppPalette.mono => const Color(0xFFE6E6E6),
    AppPalette.night => const Color(0xFF2B2F34),
    AppPalette.paper => const Color(0xFFDFD0B8),
  };

  static Color get shadow => switch (palette) {
    AppPalette.mono => const Color(0x14000000),
    AppPalette.night => const Color(0x66000000),
    AppPalette.paper => const Color(0x1A4A3520),
  };

  static LinearGradient get backgroundGradient => switch (palette) {
    AppPalette.mono => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFBFBFB), Color(0xFFF0F0F1), Color(0xFFFCFCFC)],
      stops: [0, 0.56, 1],
    ),
    AppPalette.night => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0D0F11), Color(0xFF15181B), Color(0xFF101214)],
      stops: [0, 0.56, 1],
    ),
    AppPalette.paper => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF7F0E3), Color(0xFFEFE3CF), Color(0xFFF8F1E6)],
      stops: [0, 0.56, 1],
    ),
  };

  static String get paletteLabel => switch (palette) {
    AppPalette.mono => '黑白配色',
    AppPalette.night => '夜间配色',
    AppPalette.paper => '纸质配色',
  };

  static ThemeData get light {
    final brightness = isNight ? Brightness.dark : Brightness.light;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: onAccent,
      secondary: accent,
      onSecondary: onAccent,
      error: const Color(0xFFB3261E),
      onError: Colors.white,
      surface: surface,
      onSurface: primaryText,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      cardColor: surface,
      fontFamily: 'Microsoft YaHei',
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: primaryText,
        ),
        contentTextStyle: TextStyle(fontSize: 13, color: primaryText),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: primaryText,
        ),
        iconTheme: IconThemeData(color: secondaryText),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: accent.withValues(alpha: 0.10),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11.5,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.normal,
            color: states.contains(WidgetState.selected)
                ? accent
                : secondaryText,
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        width: 340,
      ),
      dividerTheme: DividerThemeData(color: divider, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        hintStyle: TextStyle(fontSize: 13, color: secondaryText),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: accent.withValues(alpha: 0.22),
        selectionHandleColor: accent,
      ),
    );
  }
}
