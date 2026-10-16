import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show ValueListenable, mapEquals;
import 'package:flutter/material.dart';

import '../engine/playback_engine.dart';

/// Resolved, user-configurable subtitle style.
///
/// THE single source of truth for how subtitles LOOK on screen. Parsed from
/// the settings map (`webSettings` / the live sheet values) with safe
/// defaults + clamps so corrupt or missing keys can never break rendering.
///
/// Why a Flutter-side style at all: media_kit is created with the default
/// `PlayerConfiguration(libass: false)` → mpv runs with `sub-visibility=no`,
/// so libmpv renders nothing and the subtitle text is delivered as plain
/// lines on `player.stream.subtitle`. Styling therefore lives entirely in
/// [SubtitleOverlay]; mpv keeps ownership of timing (`sub-delay`) and track
/// selection only. Writing mpv `sub-color`/`sub-font-size`/… would style a
/// renderer that is not visible — the exact bug this class replaces.
class SubtitleStyle {
  const SubtitleStyle({
    this.fontSize = 28,
    this.color = const Color(0xFFFFFFFF),
    this.borderColor = const Color(0xFF000000),
    this.borderSize = 0,
    this.backgroundOpacity = 0.35,
    this.style = 'shadow',
    this.position = 100,
    this.fontFamily = subtitleFontFamily,
  });

  /// Subtitle typeface (user request): bundled Netflix Sans (Light/Regular/
  /// Medium declared in pubspec). Declared once here so the overlay and the
  /// settings-sheet preview can never drift apart (WYSIWYG parity).
  static const String subtitleFontFamily = 'NetflixSans';

  /// Reference pixel size at ≤1080p (scaled down on larger surfaces).
  final int fontSize;
  final Color color;
  final Color borderColor;

  /// Outline thickness 0–8 (mirrors the settings sliders).
  final int borderSize;

  /// Background opacity 0–1 (used by the `box` style).
  final double backgroundOpacity;

  /// `shadow` | `outline` | `box` (legacy `opaque`/`background` → box).
  final String style;

  /// Vertical placement, mpv `sub-pos` semantics: 0 = top, 100 = bottom.
  final int position;

  /// Typeface family used by the visible overlay (and the sheet preview).
  /// Must match a family declared under `fonts:` in pubspec.yaml; unknown
  /// names make Flutter fall back to the default font — never a crash.
  final String fontFamily;

  static const SubtitleStyle fallback = SubtitleStyle();

  static int _int(
    Map<String, Object?> map,
    String key,
    int fallback,
    int min,
    int max,
  ) {
    final value = map[key];
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    if (parsed == null) return fallback;
    return parsed.clamp(min, max);
  }

  static double _double(
    Map<String, Object?> map,
    String key,
    double fallback,
    double min,
    double max,
  ) {
    final value = map[key];
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    if (parsed == null) return fallback;
    return parsed.clamp(min, max);
  }

  static Color _color(Object? raw, Color fallback) {
    if (raw is! String) return fallback;
    final hex = raw.trim().replaceFirst('#', '');
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return fallback;
    return Color(0xFF000000 | (parsed & 0xFFFFFF));
  }

  static String _styleName(Object? raw) => switch (raw) {
        'outline' => 'outline',
        'box' || 'opaque' || 'background' => 'box',
        _ => 'shadow',
      };

  /// Empty/garbage family names fall back to the bundled subtitle font
  /// (permissive on purpose: a future font picker can add families without
  /// touching this parser).
  static String _familyName(Object? raw) {
    if (raw is! String) return subtitleFontFamily;
    final value = raw.trim();
    return value.isEmpty ? subtitleFontFamily : value;
  }

  /// Parses the app settings map (keys: subFontSize, subFontColor, subStyle,
  /// subBorderColor, subBorderSize, subBackgroundOpacity, subPos,
  /// subFontFamily).
  factory SubtitleStyle.fromMap(Map<String, Object?> map) => SubtitleStyle(
        fontSize: _int(map, 'subFontSize', 28, 14, 44),
        color: _color(map['subFontColor'], const Color(0xFFFFFFFF)),
        borderColor: _color(map['subBorderColor'], const Color(0xFF000000)),
        borderSize: _int(map, 'subBorderSize', 0, 0, 8),
        backgroundOpacity: _double(map, 'subBackgroundOpacity', 0.35, 0.0, 1.0),
        style: _styleName(map['subStyle']),
        position: _int(map, 'subPos', 100, 0, 100),
        fontFamily: _familyName(map['subFontFamily']),
      );

  /// The webSettings keys this style (plus the mpv sub-delay) consumes.
  static const Set<String> settingsKeys = {
    'subFontSize',
    'subFontColor',
    'subStyle',
    'subBorderColor',
    'subBorderSize',
    'subBackgroundOpacity',
    'subPos',
    'subFontFamily',
    'subtitleOffsetMs',
  };

  /// Projection of a settings map onto [settingsKeys] (absent keys omitted).
  ///
  /// Used by the player to DIFF incoming AppState notifications: a settings-
  /// page write, a cloud-sync merge, or a backup restore reaches an open
  /// player through this projection — if it differs from the last applied
  /// values, the on-screen subtitles restyle instantly (no restart, no
  /// re-open). Values stay raw so they can round-trip into [fromMap] and be
  /// compared with [mapEquals] across transports.
  static Map<String, Object?> valuesFrom(Map<String, dynamic> settings) =>
      <String, Object?>{
        for (final key in settingsKeys)
          if (settings[key] != null) key: settings[key],
      };

  /// mpv sub-pos → Flutter alignment: 0 → topCenter, 50 → center, 100 →
  /// bottomCenter (position is clamped at parse time).
  Alignment get alignment => Alignment(0, (position / 50.0) - 1.0);

  /// Same scale curve as media_kit's own SubtitleView: sizes are
  /// reference-1080p pixels, shrunk proportionally on larger surfaces.
  static double scaleFactor(Size size) {
    if (size.width <= 0 || size.height <= 0) return 1.0;
    final ratio = (size.width * size.height) / (1920.0 * 1080.0);
    return sqrt(ratio.clamp(0.0, 1.0));
  }

  /// Effective font size at [scale].
  double fontSizeAt(double scale) => fontSize * scale;

  /// Outline stroke width for the `outline` style (matches the settings
  /// sheet preview: borderSize × 1.5, clamped, never invisible).
  double strokeWidthAt(double scale) =>
      ((borderSize * 1.5) * scale).clamp(1.0, 7.0);

  /// Drop shadow for the `shadow` style (matches the settings sheet preview).
  List<Shadow> get shadows => [
        const Shadow(
            color: Color(0xE6000000), blurRadius: 4, offset: Offset(2, 2)),
      ];

  /// Background for the `box` style; null for shadow/outline (mirrors the
  /// preview — background opacity only paints the box style).
  Color? get background => style == 'box'
      ? Color(0xFF000000).withValues(alpha: backgroundOpacity)
      : null;
}

/// Live subtitle renderer on top of the video surface.
///
/// Replaces media_kit's built-in `SubtitleView` (whose TextStyle is a
/// compile-time constant, so no user setting could ever reach the screen).
/// Every visual change flows through the [style] listenable — updates appear
/// on the running video immediately, with no restart, no re-open and no
/// episode exit. Text source: mpv itself (embedded + external tracks alike),
/// already shifted by `sub-delay` for the timing offset.
class SubtitleOverlay extends StatefulWidget {
  const SubtitleOverlay({
    super.key,
    required this.engine,
    required this.style,
  });

  final PlaybackEngine engine;
  final ValueListenable<SubtitleStyle> style;

  @override
  State<SubtitleOverlay> createState() => _SubtitleOverlayState();
}

class _SubtitleOverlayState extends State<SubtitleOverlay> {
  late List<String> _lines = widget.engine.subtitleTextSnapshot;
  StreamSubscription<List<String>>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscribe(widget.engine);
  }

  void _subscribe(PlaybackEngine engine) {
    _subscription = engine.subtitleTexts.listen((lines) {
      if (!mounted) return;
      setState(() => _lines = lines);
    });
  }

  @override
  void didUpdateWidget(covariant SubtitleOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.engine, oldWidget.engine)) {
      // Engine swap (software-decode retry / error retry): the old
      // subscription points at a disposed player, so the subtitle TEXT would
      // freeze forever even though the style notifier kept flowing.
      // Re-seed from the new engine's snapshot and resubscribe.
      unawaited(_subscription?.cancel());
      _subscription = null;
      _lines = widget.engine.subtitleTextSnapshot;
      _subscribe(widget.engine);
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // Never steal gestures from the player chrome beneath.
      child: ValueListenableBuilder<SubtitleStyle>(
        valueListenable: widget.style,
        builder: (context, style, _) {
          final text = [
            for (final line in _lines)
              if (line.trim().isNotEmpty) line.trim(),
          ].join('\n');
          if (text.isEmpty) return const SizedBox.shrink();
          return LayoutBuilder(
            builder: (context, constraints) {
              final scale = SubtitleStyle.scaleFactor(
                Size(constraints.maxWidth, constraints.maxHeight),
              );
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Align(
                  alignment: style.alignment,
                  child: _render(style, text, style.fontSizeAt(scale), scale),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Visual language identical to the settings sheet preview (WYSIWYG):
  /// shadow → drop shadow · outline → stroke under fill · box → background.
  Widget _render(
      SubtitleStyle style, String text, double fontSize, double scale) {
    switch (style.style) {
      case 'box':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          color: style.background,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: fontSize,
              color: style.color,
              fontFamily: style.fontFamily,
            ),
          ),
        );
      case 'outline':
        final stroke = TextStyle(
          fontSize: fontSize,
          fontFamily: style.fontFamily,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = style.strokeWidthAt(scale)
            ..color = style.borderColor,
        );
        return Stack(
          alignment: Alignment.center,
          children: [
            Text(text, textAlign: TextAlign.center, style: stroke),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: fontSize,
                color: style.color,
                fontFamily: style.fontFamily,
              ),
            ),
          ],
        );
      default: // shadow
        return Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: fontSize,
            color: style.color,
            fontFamily: style.fontFamily,
            shadows: style.shadows,
          ),
        );
    }
  }
}
