import 'package:flutter/material.dart' show Alignment, Color, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:noor_mobile/features/player/widgets/subtitle_overlay.dart';

void main() {
  group('SubtitleStyle.fromMap — defaults', () {
    test('empty map yields the documented defaults', () {
      final s = SubtitleStyle.fromMap({});
      expect(s.fontSize, 28);
      expect(s.color, const Color(0xFFFFFFFF));
      expect(s.borderColor, const Color(0xFF000000));
      expect(s.borderSize, 0);
      expect(s.backgroundOpacity, 0.35);
      expect(s.style, 'shadow');
      expect(s.position, 100);
      expect(s.fontFamily, 'NetflixSans');
    });
  });

  group('SubtitleStyle.fontFamily (user-requested subtitle typeface)', () {
    test('defaults to the bundled Netflix Sans family', () {
      expect(SubtitleStyle.subtitleFontFamily, 'NetflixSans');
      expect(SubtitleStyle.fallback.fontFamily, 'NetflixSans');
    });

    test('explicit subFontFamily override is respected', () {
      final s = SubtitleStyle.fromMap({'subFontFamily': 'Tajawal'});
      expect(s.fontFamily, 'Tajawal');
    });

    test('empty or whitespace family falls back to the bundled font', () {
      expect(
        SubtitleStyle.fromMap({'subFontFamily': ''}).fontFamily,
        'NetflixSans',
      );
      expect(
        SubtitleStyle.fromMap({'subFontFamily': '   '}).fontFamily,
        'NetflixSans',
      );
    });

    test('non-string family values fall back instead of crashing', () {
      expect(
        SubtitleStyle.fromMap({'subFontFamily': 42}).fontFamily,
        'NetflixSans',
      );
    });
  });

  group('SubtitleStyle.fromMap — parsing', () {
    test('parses a full valid map', () {
      final s = SubtitleStyle.fromMap({
        'subFontSize': 36,
        'subFontColor': '#FF0000',
        'subStyle': 'outline',
        'subBorderColor': '#00FF00',
        'subBorderSize': 3,
        'subBackgroundOpacity': 0.6,
        'subPos': 25,
      });
      expect(s.fontSize, 36);
      expect(s.color, const Color(0xFFFF0000));
      expect(s.style, 'outline');
      expect(s.borderColor, const Color(0xFF00FF00));
      expect(s.borderSize, 3);
      expect(s.backgroundOpacity, 0.6);
      expect(s.position, 25);
    });

    test('tolerates numeric strings (cloud-sync payloads)', () {
      final s = SubtitleStyle.fromMap({
        'subFontSize': '30',
        'subBorderSize': '2',
        'subPos': '75',
        'subBackgroundOpacity': '0.5',
      });
      expect(s.fontSize, 30);
      expect(s.borderSize, 2);
      expect(s.position, 75);
      expect(s.backgroundOpacity, 0.5);
    });

    test('parses hex colors without the # prefix', () {
      final s = SubtitleStyle.fromMap({'subFontColor': '00FF00'});
      expect(s.color, const Color(0xFF00FF00));
    });

    test('invalid color falls back instead of crashing', () {
      final s = SubtitleStyle.fromMap({
        'subFontColor': 'not-a-color',
        'subBorderColor': 42,
      });
      expect(s.color, const Color(0xFFFFFFFF));
      expect(s.borderColor, const Color(0xFF000000));
    });

    test('style vocabulary: legacy opaque/background map to box', () {
      expect(SubtitleStyle.fromMap({'subStyle': 'box'}).style, 'box');
      expect(SubtitleStyle.fromMap({'subStyle': 'opaque'}).style, 'box');
      expect(SubtitleStyle.fromMap({'subStyle': 'background'}).style, 'box');
      expect(SubtitleStyle.fromMap({'subStyle': 'outline'}).style, 'outline');
      expect(SubtitleStyle.fromMap({'subStyle': 'shadow'}).style, 'shadow');
      expect(SubtitleStyle.fromMap({'subStyle': 'junk'}).style, 'shadow');
      expect(SubtitleStyle.fromMap({'subStyle': null}).style, 'shadow');
    });
  });

  group('SubtitleStyle.fromMap — clamping', () {
    test('fontSize stays inside the settings slider range (14..44)', () {
      expect(SubtitleStyle.fromMap({'subFontSize': 99}).fontSize, 44);
      expect(SubtitleStyle.fromMap({'subFontSize': 1}).fontSize, 14);
    });

    test('position clamps to 0..100', () {
      expect(SubtitleStyle.fromMap({'subPos': -5}).position, 0);
      expect(SubtitleStyle.fromMap({'subPos': 150}).position, 100);
    });

    test('borderSize clamps to 0..8', () {
      expect(SubtitleStyle.fromMap({'subBorderSize': 20}).borderSize, 8);
    });

    test('background opacity clamps to 0..1', () {
      expect(
        SubtitleStyle.fromMap({'subBackgroundOpacity': 1.5}).backgroundOpacity,
        1.0,
      );
      expect(
        SubtitleStyle.fromMap({'subBackgroundOpacity': -0.2}).backgroundOpacity,
        0.0,
      );
    });
  });

  group('SubtitleStyle mapping', () {
    test(
        'position maps onto mpv sub-pos semantics (0 top / 50 mid / 100 bottom)',
        () {
      expect(SubtitleStyle.fromMap({'subPos': 0}).alignment,
          const Alignment(0, -1));
      expect(SubtitleStyle.fromMap({'subPos': 50}).alignment, Alignment.center);
      expect(SubtitleStyle.fromMap({'subPos': 100}).alignment,
          const Alignment(0, 1));
    });

    test('scaleFactor mirrors the 1080p reference curve', () {
      expect(SubtitleStyle.scaleFactor(const Size(1920, 1080)), 1.0);
      expect(SubtitleStyle.scaleFactor(const Size(960, 540)), 0.5);
      // Larger surfaces never scale the font UP.
      expect(SubtitleStyle.scaleFactor(const Size(3840, 2160)), 1.0);
      // Degenerate constraints stay safe.
      expect(SubtitleStyle.scaleFactor(Size.zero), 1.0);
    });

    test('fontSizeAt scales with the surface factor', () {
      expect(SubtitleStyle.fromMap({'subFontSize': 28}).fontSizeAt(0.5), 14.0);
    });

    test('strokeWidthAt matches the sheet preview formula', () {
      // borderSize 0 still draws a hairline (never an invisible stroke).
      expect(SubtitleStyle.fallback.strokeWidthAt(1.0), 1.0);
      expect(
        SubtitleStyle.fromMap({'subBorderSize': 2}).strokeWidthAt(1.0),
        3.0,
      );
      // Clamped ceiling.
      expect(
        SubtitleStyle.fromMap({'subBorderSize': 8}).strokeWidthAt(1.0),
        7.0,
      );
    });

    test('background paints only for the box style', () {
      final box = SubtitleStyle.fromMap(
          {'subStyle': 'box', 'subBackgroundOpacity': 0.5});
      expect(box.background, isNotNull);
      expect((box.background!.a * 255.0).round(), closeTo(128, 1));

      expect(SubtitleStyle.fromMap({'subStyle': 'shadow'}).background, isNull);
      expect(SubtitleStyle.fromMap({'subStyle': 'outline'}).background, isNull);
    });

    test('shadow style always carries at least one shadow', () {
      expect(
        SubtitleStyle.fromMap({'subStyle': 'shadow'}).shadows,
        isNotEmpty,
      );
    });
  });
}
