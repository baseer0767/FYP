import 'package:flutter/material.dart';

class GymColors {
  static const background = Color(0xFF05070A);
  static const surface = Color(0xFF0D1320);
  static const surfaceAlt = Color(0xFF121A28);
  static const accent = Color(0xFFFF8A00);
  static const accentSoft = Color(0xFF8BEA53);
  static const accentCool = Color(0xFF6EA8FE);
}

class GymTheme {
  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: GymColors.accent,
          brightness: Brightness.dark,
          background: GymColors.background,
          surface: GymColors.surface,
        ).copyWith(
          primary: GymColors.accent,
          secondary: GymColors.accentSoft,
          surface: GymColors.surface,
          onSurface: Colors.white,
        );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: GymColors.background,
      useMaterial3: true,
      textTheme: base.textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: GymColors.background,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: GymColors.surface.withOpacity(0.96),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withOpacity(0.08),
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: GymColors.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.74)),
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.32)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
          borderSide: BorderSide(color: GymColors.accent, width: 1.4),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
          borderSide: BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
          borderSide: BorderSide(color: Colors.redAccent, width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: GymColors.accent,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: GymColors.surfaceAlt,
        selectedColor: GymColors.accent,
        labelStyle: const TextStyle(color: Colors.white),
        secondaryLabelStyle: const TextStyle(color: Colors.black),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        side: BorderSide(color: Colors.white.withOpacity(0.10)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }
}
