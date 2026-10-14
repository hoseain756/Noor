// Regression lock for the edge-to-edge system-bar contract (Tasks 115/117):
// the status bar (clock/battery/signal) and the Android gesture bar must be
// FULLY transparent with icons that stay readable over the canvas, in both
// theme brightnesses. main.dart and MainShell's AnnotatedRegion both derive
// their SystemUiOverlayStyle from noorSystemBarOverlayStyle — if a future
// edit reintroduces a solid bar color or mismatches icon brightness, these
// expectations fail.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noor_mobile/core/theme/system_bars.dart';

void main() {
  group('noorSystemBarOverlayStyle — edge-to-edge contract', () {
    test('dark canvas (HorseTheme.dark): transparent bars + light icons', () {
      final style = noorSystemBarOverlayStyle(Brightness.dark);

      // No solid strip anywhere — the canvas shows through on every edge.
      expect(style.statusBarColor, Colors.transparent);
      expect(style.systemNavigationBarColor, Colors.transparent);
      expect(style.systemNavigationBarDividerColor, Colors.transparent);

      // Readable icons: light system icons on the dark canvas (Android +
      // iOS brightness hint), light gesture-bar icons.
      expect(style.statusBarIconBrightness, Brightness.light);
      expect(style.statusBarBrightness, Brightness.dark);
      expect(style.systemNavigationBarIconBrightness, Brightness.light);

      // API 29+ OEM contrast scrim stays off over the transparent bar.
      expect(style.systemNavigationBarContrastEnforced, isFalse);
    });

    test('light theme flips icon brightness, keeps every bar transparent', () {
      final style = noorSystemBarOverlayStyle(Brightness.light);

      expect(style.statusBarColor, Colors.transparent);
      expect(style.systemNavigationBarColor, Colors.transparent);
      expect(style.systemNavigationBarDividerColor, Colors.transparent);

      expect(style.statusBarIconBrightness, Brightness.dark);
      expect(style.statusBarBrightness, Brightness.light);
      expect(style.systemNavigationBarIconBrightness, Brightness.dark);
      expect(style.systemNavigationBarContrastEnforced, isFalse);
    });
  });
}
