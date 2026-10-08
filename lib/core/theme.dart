import 'package:flutter/material.dart';

/// Casino-table palette. Deep felt green with brass and cream accents, chosen
/// so the six symbols stay legible at small dice sizes.
class GameColors {
  const GameColors._();

  static const Color feltDark = Color(0xFF0D3B2A);
  static const Color feltMid = Color(0xFF12513A);
  static const Color feltLight = Color(0xFF1B6B4C);

  static const Color brass = Color(0xFFD4A94E);
  static const Color brassDark = Color(0xFF8C6B26);
  static const Color cream = Color(0xFFF6F1E3);
  static const Color ink = Color(0xFF14202A);

  static const Color win = Color(0xFF4ADE80);
  static const Color lose = Color(0xFFF87171);
  static const Color dieFace = Color(0xFFFBF7EC);
  static const Color dieEdge = Color(0xFFD9D2BE);
}

class GameTheme {
  const GameTheme._();

  static ThemeData build() {
    final ColorScheme scheme =
        ColorScheme.fromSeed(
          seedColor: GameColors.feltLight,
          brightness: Brightness.dark,
        ).copyWith(
          surface: GameColors.feltDark,
          primary: GameColors.brass,
          secondary: GameColors.cream,
          error: GameColors.lose,
        );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: GameColors.feltDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: GameColors.cream,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
        iconTheme: IconThemeData(color: GameColors.cream),
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          color: GameColors.cream,
          fontWeight: FontWeight.w800,
        ),
        titleMedium: TextStyle(
          color: GameColors.cream,
          fontWeight: FontWeight.w700,
        ),
        bodyMedium: TextStyle(color: GameColors.cream),
        bodySmall: TextStyle(color: Color(0xFFB9C9C0)),
        labelLarge: TextStyle(
          color: GameColors.cream,
          fontWeight: FontWeight.w700,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: GameColors.brass,
          foregroundColor: GameColors.ink,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            letterSpacing: 0.6,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: GameColors.brass,
          side: const BorderSide(color: GameColors.brassDark, width: 1.6),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      dividerTheme: const DividerThemeData(color: Color(0x33FFFFFF), space: 1),
    );
  }
}
