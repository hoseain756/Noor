import 'package:flutter/material.dart';

abstract final class HorseTheme {
  // Pure black app background (user spec: #000000).
  static const canvas = Color(0xFF000000);
  static const surface = Color(0xFF131617);
  static const raised = Color(0xFF1A1E1F);
  static const line = Color(0xFF292E2F);
  static const gold = Color(0xFFC99C62);
  static const ink = Color(0xFFF3F1ED);
  static const muted = Color(0xFFA4A5A2);

  /// Built once per isolate (Task 122-b, F3): `dark` used to be a getter
  /// that constructed the full ThemeData on EVERY access — including inside
  /// the per-notification app builder. Repo-wide check found only reads
  /// (no reassignment/mutation), so a lazy static final is safe and produces
  /// the byte-identical theme via [_buildDark].
  static final ThemeData dark = _buildDark();

  static ThemeData _buildDark() {
    final scheme = const ColorScheme.dark(
      primary: gold,
      onPrimary: Color(0xFF1A1209),
      secondary: Color(0xFFE3BD86),
      surface: surface,
      onSurface: ink,
      error: Color(0xFFFF8178),
      onError: Color(0xFF2A0907),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      // One family for Arabic + Latin (user request): bundled Tajawal (OFL).
      fontFamily: 'Tajawal',
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      dividerColor: line,
      splashColor: gold.withValues(alpha: 0.08),
      highlightColor: Colors.transparent,
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF101314),
        indicatorColor: gold.withValues(alpha: 0.16),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? gold : muted,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: const Color(0xFF111415),
        indicatorColor: gold.withValues(alpha: 0.16),
        selectedIconTheme: const IconThemeData(color: gold),
        unselectedIconTheme: const IconThemeData(color: muted),
        selectedLabelTextStyle: const TextStyle(
          color: gold,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: const TextStyle(color: muted),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: raised,
        hintStyle: const TextStyle(color: muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: gold, width: 1.4),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: raised,
        contentTextStyle: const TextStyle(color: ink),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: ink,
          fontSize: 34,
          fontWeight: FontWeight.w800,
          height: 1.12,
        ),
        headlineMedium: TextStyle(
          color: ink,
          fontSize: 27,
          fontWeight: FontWeight.w700,
          height: 1.15,
        ),
        headlineSmall: TextStyle(
          color: ink,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
        titleLarge: TextStyle(
          color: ink,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: ink,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(color: ink, fontSize: 15, height: 1.5),
        bodyMedium: TextStyle(color: ink, fontSize: 13, height: 1.45),
        bodySmall: TextStyle(color: muted, fontSize: 11, height: 1.4),
      ),
    );
  }

  // --- Task 121 shared tokens (additive) ---

  /// Semantic colors reused across features (evidence: audit 121-a2 §1.2 —
  /// recurring file-local literals promoted to shared tokens). `danger`
  /// aliases colorScheme.error; the scrims/hairline/badge hues were
  /// duplicated as raw hexes in 5–7 files each.
  static const Color hairline = Color(0x14FFFFFF); // white .08 borders
  static const Color scrimPoster = Color(0xB8000000); // black .72 poster scrims
  static const Color scrimStrong = Color(0x8C000000); // black .55 strong scrims
  static const Color danger = Color(0xFFFF8178); // == scheme.error
  static const Color success = Color(0xFF22C55E); // watched/positive
  static const Color progressRed = Color(0xFFDC2626); // resume progress bars
  static const Color imdbYellow = Color(0xFFF5C518); // IMDb badge amber

  /// Shared corner radii (circular(999) alone appears ×29 across features).
  static const double radiusPill = 999;
  static const double radiusCard = 16;
  static const double radiusInput = 14;
  static const double radiusChip = 12;

  /// Motion tokens — `emphasized` was defined 3× independently (detail_hero
  /// `_cubicEmphasized`, episode_views inline, glass_dock `kDockEase`);
  /// durations cluster at 150/220/350ms across features.
  static const Cubic emphasized = Cubic(0.2, 0, 0, 1);
  static const Duration durFast = Duration(milliseconds: 150);
  static const Duration durMed = Duration(milliseconds: 220);
  static const Duration durSlow = Duration(milliseconds: 350);

  /// Page gutter used by media rails + detail skeleton geometry, and the
  /// read-only breakpoint references (700/600/840) repeated at ~20 sites.
  static double gutter({required bool wide}) => wide ? 34 : 20;
  static const double bpWide = 700;
  static const double bpHero = 600;
  static const double bpTablet = 840;
}
