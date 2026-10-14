import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The Noor system-bar contract (edge-to-edge mandate, Tasks 115/117):
///
/// The app draws behind a FULLY TRANSPARENT status bar (clock, battery,
/// signal — no solid strip, ever) and a fully transparent Android
/// gesture/navigation bar, so the canvas shows through on every edge.
///
/// The system icons stay readable by following the active theme brightness:
///  - dark canvas (`HorseTheme.dark`, the shipped theme) → light icons;
///  - a future light theme flips to dark icons automatically, because
///    MainShell derives this style from `Theme.of(context).brightness`.
///
/// `systemNavigationBarContrastEnforced: false` guards the API 29+ contrast
/// scrim OEMs apply to transparent gesture bars.
SystemUiOverlayStyle noorSystemBarOverlayStyle(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
      .copyWith(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness:
        dark ? Brightness.light : Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );
}
