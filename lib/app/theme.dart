import 'package:flutter/material.dart';

/// Colours and shapes straight from the PRD's visual-identity section
/// (A7.1): calm, productive/engineering feel, numbers-first, no reliance on
/// colour alone to convey state.
///
/// Light and dark are both derived from the same seed so they stay in step,
/// with the neutrals overridden to a cool slate: a blue-tinted grey keeps
/// the blue from looking washed out, and keeps the two themes visually
/// related without being identical.
class AppColors {
  static const primary = Color(0xFF1565C0);
  static const accent = Color(0xFF00B8D4);
  static const lightBackground = Color(0xFFF4F7FB);
  static const card = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF0F172A);
  static const border = Color(0xFFE2E8F0);
  static const success = Color(0xFF2E7D32);

  static const darkBackground = Color(0xFF0E1319);
  static const darkSurface = Color(0xFF161D25);
  static const darkBorder = Color(0xFF26313D);
  static const darkTextPrimary = Color(0xFFE6EDF3);
  static const darkPrimary = Color(0xFF7CB4FF);
  static const darkAccent = Color(0xFF4DD0E1);
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.accent,
        brightness: Brightness.light,
      ).copyWith(
        surface: AppColors.card,
        outline: AppColors.border,
        outlineVariant: AppColors.border,
        onSurface: AppColors.textPrimary,
      ),
      scaffoldBackgroundColor: AppColors.lightBackground,
    );
    return _finish(
      base,
      background: AppColors.lightBackground,
      surface: AppColors.card,
      border: AppColors.border,
      text: AppColors.textPrimary,
    );
  }

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.darkPrimary,
        secondary: AppColors.darkAccent,
        brightness: Brightness.dark,
      ).copyWith(
        surface: AppColors.darkSurface,
        outline: AppColors.darkBorder,
        outlineVariant: AppColors.darkBorder,
        onSurface: AppColors.darkTextPrimary,
      ),
      scaffoldBackgroundColor: AppColors.darkBackground,
    );
    return _finish(
      base,
      background: AppColors.darkBackground,
      surface: AppColors.darkSurface,
      border: AppColors.darkBorder,
      text: AppColors.darkTextPrimary,
    );
  }

  /// Everything the two themes share: flat bordered cards, soft inputs and
  /// pill-shaped buttons, so the app reads as one surface rather than a
  /// stack of floating boxes.
  static ThemeData _finish(
    ThemeData base, {
    required Color background,
    required Color surface,
    required Color border,
    required Color text,
  }) {
    final radius = BorderRadius.circular(16);
    return base.copyWith(
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: border),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: base.colorScheme.primary,
          foregroundColor: base.colorScheme.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: base.colorScheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, space: 1),
      listTileTheme: ListTileThemeData(iconColor: base.colorScheme.primary),
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}
