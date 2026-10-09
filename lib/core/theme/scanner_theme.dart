import 'package:flutter/material.dart';

import '../../features/scan/ticket_verdict.dart';

class ScannerColors {
  static const brand = Color(0xFF6366F1);
  static const background = Color(0xFF050814);
  static const surface = Color(0xFF111827);
  static const surfaceHigh = Color(0xFF1F2937);
  static const outline = Color(0xFF334155);
  static const textMuted = Color(0xFF94A3B8);

  static const valid = Color(0xFF16A34A);
  static const warning = Color(0xFFF59E0B);
  static const invalid = Color(0xFFDC2626);

  static Color forLevel(VerdictLevel level) => switch (level) {
    VerdictLevel.valid => valid,
    VerdictLevel.warning => warning,
    VerdictLevel.invalid => invalid,
  };

  static IconData iconForLevel(VerdictLevel level) => switch (level) {
    VerdictLevel.valid => Icons.check_circle_rounded,
    VerdictLevel.warning => Icons.warning_rounded,
    VerdictLevel.invalid => Icons.cancel_rounded,
  };
}

ThemeData buildScannerTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: ScannerColors.brand,
        brightness: Brightness.dark,
      ).copyWith(
        primary: ScannerColors.brand,
        surface: ScannerColors.surface,
        error: ScannerColors.invalid,
      );

  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: ScannerColors.outline),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: ScannerColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: ScannerColors.background,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ScannerColors.surface,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: ScannerColors.brand, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ScannerColors.brand,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        foregroundColor: Colors.white,
        side: const BorderSide(color: ScannerColors.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
