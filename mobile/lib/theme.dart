import 'package:flutter/material.dart';

/// Accessible theme for Anchor.
///
/// Contract (SPEC §9): main text 26 logical px, primary touch targets at least
/// 56 px, high contrast dark-on-light, large icons *and* text labels, and a
/// layout that survives text scaling up to 1.6x without overflow.
abstract final class AnchorTheme {
  /// Main reading size. Never go below 24 (SPEC §9 hard minimum).
  static const double baseTextSize = 26;

  /// Minimum size of anything the user must tap.
  static const double minTouchTarget = 56;

  /// Height of the three primary home actions on a phone.
  static const double primaryActionHeight = 104;

  // High-contrast palette. Ink on canvas is ~16:1; white on primary ~8.6:1.
  static const Color ink = Color(0xFF101820);
  static const Color inkSoft = Color(0xFF2C3B47);
  static const Color canvas = Color(0xFFFBF7EF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color primary = Color(0xFF0F5132);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color accent = Color(0xFF7A3E00);
  static const Color onAccent = Color(0xFFFFFFFF);
  static const Color danger = Color(0xFF8B1A1A);
  static const Color onDanger = Color(0xFFFFFFFF);
  static const Color border = Color(0xFF1F2A36);
  static const Color muted = Color(0xFF3B4A57);

  // Feedback fills shared by the Play screen and the in-chat activity card, so
  // a tap feels the same in both: pale green (this one is right), pale amber
  // (not quite — warm, never an alarm) and neutral warmth for a reply that is
  // not graded at all.
  static const Color correctFill = Color(0xFFE3EFE6);
  static const Color wrongFill = Color(0xFFF8ECD8);
  static const Color openFill = Color(0xFFF4EFE5);

  // Per-kind identity for the in-chat activity card (trivia / story / memory).
  // No photo assets: a dark ink + a pale tint is enough, and ink on tint stays
  // above 7:1 so the label is readable at 22 px.
  static const Color storyInk = Color(0xFF4A3B76);
  static const Color storyFill = Color(0xFFEDE9F7);
  static const Color triviaFill = Color(0xFFE7F0E9);

  static const ColorScheme _scheme = ColorScheme.light(
    primary: primary,
    onPrimary: onPrimary,
    secondary: accent,
    onSecondary: onAccent,
    tertiary: primary,
    onTertiary: onPrimary,
    surface: surface,
    onSurface: ink,
    surfaceContainerHighest: Color(0xFFF0EAE0),
    onSurfaceVariant: inkSoft,
    error: danger,
    onError: onDanger,
    outline: border,
    shadow: Color(0xFF000000),
  );

  static const TextTheme _textTheme = TextTheme(
    displayLarge: TextStyle(
      fontSize: 44,
      fontWeight: FontWeight.w700,
      color: ink,
      height: 1.2,
    ),
    displayMedium: TextStyle(
      fontSize: 38,
      fontWeight: FontWeight.w700,
      color: ink,
      height: 1.2,
    ),
    headlineLarge: TextStyle(
      fontSize: 34,
      fontWeight: FontWeight.w700,
      color: ink,
      height: 1.25,
    ),
    headlineMedium: TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w700,
      color: ink,
      height: 1.25,
    ),
    titleLarge: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: ink,
      height: 1.3,
    ),
    titleMedium: TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w600,
      color: ink,
      height: 1.3,
    ),
    bodyLarge: TextStyle(
      fontSize: baseTextSize,
      fontWeight: FontWeight.w400,
      color: ink,
      height: 1.45,
    ),
    bodyMedium: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w400,
      color: ink,
      height: 1.45,
    ),
    bodySmall: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w400,
      color: inkSoft,
      height: 1.4,
    ),
    labelLarge: TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w700,
      color: ink,
      height: 1.25,
    ),
    labelMedium: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      color: inkSoft,
      height: 1.25,
    ),
  );

  /// The reading text style used for every sentence the senior must read.
  static const TextStyle reading = TextStyle(
    fontSize: baseTextSize,
    fontWeight: FontWeight.w400,
    color: ink,
    height: 1.45,
  );

  static ThemeData build() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: _scheme,
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      textTheme: _textTheme,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: ink, size: 34),
        titleTextStyle: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        toolbarHeight: 72,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(minTouchTarget, minTouchTarget),
          backgroundColor: primary,
          foregroundColor: onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          textStyle: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: border, width: 1.5),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(minTouchTarget, minTouchTarget),
          foregroundColor: ink,
          backgroundColor: surface,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          textStyle: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
          side: const BorderSide(color: border, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(minTouchTarget, minTouchTarget),
          foregroundColor: primary,
          textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 20,
        ),
        labelStyle: const TextStyle(fontSize: 24, color: inkSoft),
        hintStyle: const TextStyle(fontSize: 24, color: muted),
        errorStyle: const TextStyle(fontSize: 22, color: danger),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 3),
        ),
      ),
      switchTheme: SwitchThemeData(
        materialTapTargetSize: MaterialTapTargetSize.padded,
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? onPrimary : ink,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : surface,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(border),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1.5,
        space: 24,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: TextStyle(fontSize: 24, color: surface),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
      listTileTheme: const ListTileThemeData(
        iconColor: primary,
        textColor: ink,
        minVerticalPadding: 12,
      ),
    );
  }
}
