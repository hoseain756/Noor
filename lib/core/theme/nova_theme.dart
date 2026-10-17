import 'package:flutter/material.dart';

/// Only colours supplied in the NOVA identity, including its companion palette.
abstract final class NovaColors {
  static const red = Color(0xFFD13B47);
  static const redDeep = Color(0xFF9E2A34);
  static const redSoft = Color(0xFFE8858D);
  static const blush = Color(0xFFF9E4E6);
  static const ink = Color(0xFF141417);
  static const graphite = Color(0xFF232329);
  static const surfaceHigh = Color(0xFF2E2E35);
  static const divider = Color(0xFF3A3A42);
  static const white = Color(0xFFFFFFFF);
  static const mist = Color(0xFFA4A4AC);
  static const textDisabled = Color(0xFF6E6E78);
  static const success = Color(0xFF3FB27F);
  static const warning = Color(0xFFE8A93B);
  static const info = Color(0xFF4C8DE0);
  static const error = Color(0xFFE5484D);
  static const rating = Color(0xFFF5C451);
  static const lightBackground = Color(0xFFF6F6F7);
  static const lightSurface = white;
  static const lightText = ink;
  static const lightTextSecondary = Color(0xFF585862);
  static const lightAccent = Color(0xFFB82C39);
  static const lightDivider = Color(0xFFDCDCE0);
  static const scrim = Color(0x99000000);
}

abstract final class NovaSpace {
  static const xs = 4.0, sm = 8.0, md = 16.0, lg = 24.0, xl = 32.0, xxl = 48.0;
  static double gutter(double width) => width >= 840
      ? 32
      : width >= 600
          ? 24
          : 16;
}

abstract final class NovaMotion {
  static const press = Duration(milliseconds: 120);
  static const state = Duration(milliseconds: 180);
  static const route = Duration(milliseconds: 240);
  static const curve = Curves.easeOutCubic;
  static Duration duration(BuildContext context, Duration value) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : value;
}

/// Context-bound roles update in every screen when appearance changes.
class NovaPalette {
  const NovaPalette(this.theme);
  final ThemeData theme;
  bool get dark => theme.brightness == Brightness.dark;
  Color get canvas => theme.scaffoldBackgroundColor;
  Color get surface => theme.colorScheme.surface;
  Color get raised => theme.colorScheme.surfaceContainerHigh;
  Color get line => theme.colorScheme.outlineVariant;
  Color get gold => theme.colorScheme.secondary;
  Color get ink => theme.colorScheme.onSurface;
  Color get muted => theme.colorScheme.onSurfaceVariant;
}

abstract final class NovaTheme {
  static NovaPalette of(BuildContext context) => NovaPalette(Theme.of(context));
  static final dark = build(Brightness.dark);
  static final light = build(Brightness.light);

  static ThemeData build(Brightness brightness, {bool arabic = false}) {
    final dark = brightness == Brightness.dark;
    final text = dark ? NovaColors.white : NovaColors.ink;
    final muted = dark ? NovaColors.mist : NovaColors.lightTextSecondary;
    final accent = dark ? NovaColors.redSoft : NovaColors.lightAccent;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: NovaColors.red,
      onPrimary: NovaColors.white,
      primaryContainer: dark ? NovaColors.redDeep : NovaColors.blush,
      onPrimaryContainer: dark ? NovaColors.white : NovaColors.redDeep,
      secondary: accent,
      onSecondary: dark ? NovaColors.ink : NovaColors.white,
      secondaryContainer: dark ? NovaColors.surfaceHigh : NovaColors.blush,
      onSecondaryContainer: text,
      tertiary: accent,
      onTertiary: dark ? NovaColors.ink : NovaColors.white,
      error: dark ? NovaColors.redSoft : NovaColors.redDeep,
      onError: dark ? NovaColors.ink : NovaColors.white,
      errorContainer: dark ? NovaColors.redDeep : NovaColors.blush,
      onErrorContainer: dark ? NovaColors.white : NovaColors.redDeep,
      surface: dark ? NovaColors.graphite : NovaColors.white,
      onSurface: text,
      surfaceContainerLowest: dark ? NovaColors.ink : NovaColors.white,
      surfaceContainerLow:
          dark ? NovaColors.graphite : NovaColors.lightBackground,
      surfaceContainer: dark ? NovaColors.graphite : NovaColors.lightBackground,
      surfaceContainerHigh:
          dark ? NovaColors.surfaceHigh : NovaColors.lightBackground,
      surfaceContainerHighest:
          dark ? NovaColors.divider : NovaColors.lightDivider,
      onSurfaceVariant: muted,
      outline: muted,
      outlineVariant: dark ? NovaColors.divider : NovaColors.lightDivider,
      shadow: NovaColors.ink,
      scrim: NovaColors.ink,
      inverseSurface: dark ? NovaColors.white : NovaColors.graphite,
      onInverseSurface: dark ? NovaColors.ink : NovaColors.white,
      inversePrimary: dark ? NovaColors.lightAccent : NovaColors.redSoft,
      surfaceTint: Colors.transparent,
    );
    final family = arabic ? 'IBMPlexSansArabic' : 'Poppins';
    TextStyle type(double size, FontWeight weight,
            {Color? color, double height = 1.5}) =>
        TextStyle(
            fontFamily: family,
            fontFamilyFallback: const ['IBMPlexSansArabic', 'Poppins'],
            fontSize: size,
            fontWeight: weight,
            height: arabic ? height + .1 : height,
            color: color ?? text);
    final textTheme = TextTheme(
      displayLarge: type(48, FontWeight.w700, height: 1.15),
      displayMedium: type(40, FontWeight.w700, height: 1.15),
      displaySmall: type(32, FontWeight.w700, height: 1.2),
      headlineLarge: type(32, FontWeight.w700, height: 1.2),
      headlineMedium: type(28, FontWeight.w700, height: 1.25),
      headlineSmall: type(24, FontWeight.w600, height: 1.3),
      titleLarge: type(20, FontWeight.w600, height: 1.3),
      titleMedium: type(16, FontWeight.w600),
      titleSmall: type(14, FontWeight.w600),
      bodyLarge: type(16, FontWeight.w400),
      bodyMedium: type(14, FontWeight.w400),
      bodySmall: type(12, FontWeight.w400, color: muted),
      labelLarge: type(14, FontWeight.w600, height: 1.3),
      labelMedium: type(12, FontWeight.w500, height: 1.3),
      labelSmall: type(11, FontWeight.w500, height: 1.3),
    );
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    final button = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
      shape: WidgetStatePropertyAll(shape),
      textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
      overlayColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.pressed)
              ? NovaColors.redDeep.withValues(alpha: .18)
              : states.contains(WidgetState.focused)
                  ? accent.withValues(alpha: .18)
                  : null),
    );
    final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outline));
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: family,
      fontFamilyFallback: const ['IBMPlexSansArabic', 'Poppins'],
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      scaffoldBackgroundColor:
          dark ? NovaColors.ink : NovaColors.lightBackground,
      canvasColor: scheme.surface,
      cardColor: scheme.surface,
      dividerColor: scheme.outlineVariant,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      splashFactory: InkRipple.splashFactory,
      iconTheme: IconThemeData(color: text, size: 22),
      appBarTheme: AppBarTheme(
          backgroundColor: dark ? NovaColors.ink : NovaColors.lightBackground,
          foregroundColor: text,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: textTheme.titleLarge),
      cardTheme:
          CardThemeData(elevation: 0, margin: EdgeInsets.zero, shape: shape),
      filledButtonTheme: FilledButtonThemeData(
          style: button.copyWith(
              backgroundColor: WidgetStateProperty.resolveWith(
                  (s) => s.contains(WidgetState.disabled)
                      ? scheme.surfaceContainerHighest
                      : s.contains(WidgetState.pressed)
                          ? NovaColors.redDeep
                          : NovaColors.red),
              foregroundColor: WidgetStateProperty.resolveWith((s) =>
                  s.contains(WidgetState.disabled)
                      ? muted
                      : NovaColors.white))),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: button.copyWith(
              elevation: const WidgetStatePropertyAll(0),
              backgroundColor: const WidgetStatePropertyAll(NovaColors.red),
              foregroundColor: const WidgetStatePropertyAll(NovaColors.white))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: button.copyWith(
              side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
              foregroundColor: WidgetStatePropertyAll(text))),
      textButtonTheme: TextButtonThemeData(
          style:
              button.copyWith(foregroundColor: WidgetStatePropertyAll(accent))),
      iconButtonTheme: IconButtonThemeData(
          style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
              foregroundColor: WidgetStatePropertyAll(text))),
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: scheme.surfaceContainerHigh,
          contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16),
          labelStyle: textTheme.bodyMedium?.copyWith(color: muted),
          hintStyle: textTheme.bodyMedium?.copyWith(color: muted),
          border: border,
          enabledBorder: border,
          focusedBorder:
              border.copyWith(borderSide: BorderSide(color: accent, width: 2)),
          errorBorder:
              border.copyWith(borderSide: BorderSide(color: scheme.error)),
          errorMaxLines: 3),
      chipTheme: ChipThemeData(
          shape: const StadiumBorder(),
          backgroundColor: scheme.surfaceContainerHigh,
          selectedColor: scheme.primaryContainer,
          side: BorderSide(color: scheme.outlineVariant),
          labelStyle: textTheme.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
      tabBarTheme: TabBarThemeData(
          labelColor: accent,
          unselectedLabelColor: muted,
          labelStyle: textTheme.labelLarge,
          indicatorColor: accent,
          dividerColor: scheme.outlineVariant),
      switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? NovaColors.white : muted),
          trackColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected)
                  ? NovaColors.red
                  : scheme.surfaceContainerHighest)),
      checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? NovaColors.red : null),
          checkColor: const WidgetStatePropertyAll(NovaColors.white),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
      sliderTheme: SliderThemeData(
          activeTrackColor: accent,
          thumbColor: accent,
          inactiveTrackColor: scheme.outlineVariant,
          trackHeight: 4,
          overlayColor: accent.withValues(alpha: .12)),
      progressIndicatorTheme: ProgressIndicatorThemeData(
          color: accent, linearTrackColor: scheme.surfaceContainerHighest),
      dialogTheme: DialogThemeData(
          backgroundColor: scheme.surface,
          surfaceTintColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          titleTextStyle: textTheme.titleLarge,
          contentTextStyle: textTheme.bodyMedium),
      bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: scheme.surface,
          modalBackgroundColor: scheme.surface,
          surfaceTintColor: Colors.transparent,
          showDragHandle: true,
          elevation: 0,
          modalBarrierColor: NovaColors.ink.withValues(alpha: .72),
          shape: const RoundedRectangleBorder(
              borderRadius:
                  BorderRadiusDirectional.vertical(top: Radius.circular(24)))),
      listTileTheme: ListTileThemeData(
          contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
          minVerticalPadding: 12,
          iconColor: muted,
          textColor: text,
          selectedColor: accent,
          titleTextStyle: textTheme.titleMedium,
          subtitleTextStyle: textTheme.bodySmall),
      navigationRailTheme: NavigationRailThemeData(
          backgroundColor: scheme.surface,
          indicatorColor: scheme.primaryContainer,
          selectedIconTheme: IconThemeData(color: accent),
          unselectedIconTheme: IconThemeData(color: muted),
          selectedLabelTextStyle:
              textTheme.labelMedium?.copyWith(color: accent)),
      snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: scheme.inverseSurface,
          contentTextStyle:
              textTheme.bodyMedium?.copyWith(color: scheme.onInverseSurface),
          shape: shape),
      tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
              color: scheme.inverseSurface,
              borderRadius: BorderRadius.circular(8)),
          textStyle:
              textTheme.bodySmall?.copyWith(color: scheme.onInverseSurface)),
    );
  }
}
