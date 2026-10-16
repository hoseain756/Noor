import 'dart:math' as math;

/// Timing segments for the skip-intro / skip-outro / next-episode features.
///
/// EVERY field is nullable and absence means "unknown" — never a guessed
/// default. A segment that is absent, malformed, or fails validation simply
/// keeps its feature inactive (spec B1/B3: no invented timings, nothing
/// shows without real data).
class PlaybackSegments {
  const PlaybackSegments({
    this.introStartMs,
    this.introEndMs,
    this.outroStartMs,
    this.outroEndMs,
    this.nextEpisodeAtMs,
    this.autoAdvanceCountdownMs,
  });

  /// Intro window (absolute positions on the timeline, ms).
  final int? introStartMs;
  final int? introEndMs;

  /// Outro / credits window (absolute positions, ms).
  final int? outroStartMs;
  final int? outroEndMs;

  /// When the next-episode card should appear (absolute position, ms).
  final int? nextEpisodeAtMs;

  /// Length of the next-episode auto-advance countdown (a DURATION, ms).
  final int? autoAdvanceCountdownMs;

  bool get hasIntro =>
      introStartMs != null && introEndMs != null && introStartMs! < introEndMs!;

  bool get hasOutro =>
      outroStartMs != null && outroEndMs != null && outroStartMs! < outroEndMs!;

  static const PlaybackSegments empty = PlaybackSegments();
}

/// Timing-window math used by the player UI — pure so it is unit-testable.
class SegmentWindows {
  SegmentWindows._();

  /// The skip-intro pill is visible while the playhead is inside the intro
  /// window. A window wider than the media (duration known) never shows.
  static bool introVisible({
    required PlaybackSegments segments,
    required int positionMs,
    required int durationMs,
  }) =>
      _inWindow(
        startMs: segments.introStartMs,
        endMs: segments.introEndMs,
        positionMs: positionMs,
        durationMs: durationMs,
      );

  /// The skip-outro pill — same rule on the outro window.
  static bool outroVisible({
    required PlaybackSegments segments,
    required int positionMs,
    required int durationMs,
  }) =>
      _inWindow(
        startMs: segments.outroStartMs,
        endMs: segments.outroEndMs,
        positionMs: positionMs,
        durationMs: durationMs,
      );

  static bool _inWindow({
    required int? startMs,
    required int? endMs,
    required int positionMs,
    required int durationMs,
  }) {
    if (startMs == null || endMs == null || startMs >= endMs) return false;
    if (positionMs < startMs || positionMs >= endMs) return false;
    // Duration-known media: a window running past the end is corrupt data.
    if (durationMs > 0 && endMs > durationMs) return false;
    return true;
  }

  /// When the next-episode card appears. Data trigger wins when valid;
  /// otherwise the card keeps its SHIPPED trigger (the pre-existing nearEnd
  /// window: ≤30 s left or ≥95% elapsed — inherited behavior, not a new
  /// default). Returns -1 while the duration is unknown.
  static int cardAppearAtMs({
    required PlaybackSegments segments,
    required int durationMs,
  }) {
    final fromData = segments.nextEpisodeAtMs;
    if (durationMs <= 0) return -1;
    if (fromData != null && fromData > 0 && fromData < durationMs) {
      return fromData;
    }
    return math.max(
        0, math.min(durationMs - 30000, (durationMs * .95).round()));
  }

  /// Absolute time the next-episode auto-advance fires (card appear time +
  /// data-provided countdown, clamped to the end). Null when the countdown
  /// duration was not provided by data — the card then stays manual, exactly
  /// as it behaves today.
  static int? autoAdvanceAtMs({
    required PlaybackSegments segments,
    required int durationMs,
  }) {
    final countdown = segments.autoAdvanceCountdownMs;
    if (countdown == null || countdown <= 0 || durationMs <= 0) return null;
    final appear = cardAppearAtMs(segments: segments, durationMs: durationMs);
    if (appear < 0) return null;
    return math.min(appear + countdown, durationMs);
  }
}

/// Central, source-agnostic resolver: maps whatever timing fields an add-on
/// or episode row carries into [PlaybackSegments], with unit normalization,
/// validation and total tolerance for malformed data.
///
/// Supported source formats (documented contract — anything else is ignored):
///
///  · stream row, its `behaviorHints` sub-map, or the episode `videos[]` row:
///      - `introStart` / `introEnd`      (+ `…Ms` variants)  → seconds / ms
///      - `outroStart` / `outroEnd`, `creditsStart` / `creditsEnd` (+ `…Ms`)
///      - `intro` / `skipIntro` as `{start, end}` or `[start, end]` (seconds,
///        or `{startMs, endMs}` for ms)
///      - `outro` / `credits` in the same map/list forms
///      - `nextEpisodeAt` (+ `…Ms`)       → absolute position, s / ms
///      - `autoAdvanceCountdown` (+ `…Ms`) → duration, s / ms
///
/// Numbers only: strings, nulls and negative values are treated as absent.
/// Pairs validate start < end and end ≤ media duration (when known).
class PlaybackSegmentsResolver {
  PlaybackSegmentsResolver._();

  static PlaybackSegments resolve({
    Map<String, dynamic>? video,
    Map<String, dynamic>? stream,
    int? mediaDurationMs,
  }) {
    final behaviorHints = stream == null
        ? null
        : (stream['behaviorHints'] as Map<String, dynamic>?);
    final sources = <Map<String, dynamic>?>[stream, behaviorHints, video];

    final intro = _resolvePair(
      sources,
      const [('introStart', 'introEnd'), ('introStartMs', 'introEndMs')],
      mapKeys: const ['intro', 'skipIntro'],
      durationMs: mediaDurationMs,
    );
    final outro = _resolvePair(
      sources,
      const [
        ('outroStart', 'outroEnd'),
        ('creditsStart', 'creditsEnd'),
        ('outroStartMs', 'outroEndMs'),
        ('creditsStartMs', 'creditsEndMs'),
      ],
      mapKeys: const ['outro', 'credits'],
      durationMs: mediaDurationMs,
    );
    final nextAt =
        _firstMs(sources, const ['nextEpisodeAtMs', 'nextEpisodeAt']);
    final countdown = _firstMs(
      sources,
      const ['autoAdvanceCountdownMs', 'autoAdvanceCountdown'],
    );

    int? validAbsolute(int? ms) {
      if (ms == null || ms <= 0) return null;
      if (mediaDurationMs != null && ms > mediaDurationMs) return null;
      return ms;
    }

    return PlaybackSegments(
      introStartMs: intro?.$1,
      introEndMs: intro?.$2,
      outroStartMs: outro?.$1,
      outroEndMs: outro?.$2,
      nextEpisodeAtMs: validAbsolute(nextAt),
      autoAdvanceCountdownMs:
          countdown != null && countdown > 0 ? countdown : null,
    );
  }

  /// First valid (start, end) pair found across the documented key forms,
  /// then the {start, end} / [start, end] map forms.
  static (int, int)? _resolvePair(
    List<Map<String, dynamic>?> sources,
    List<(String, String)> keyPairs, {
    required List<String> mapKeys,
    required int? durationMs,
  }) {
    for (final source in sources) {
      if (source == null) continue;
      for (final (startKey, endKey) in keyPairs) {
        final start = _msOf(source[startKey], msUnits: startKey.endsWith('Ms'));
        final end = _msOf(source[endKey], msUnits: endKey.endsWith('Ms'));
        final pair = _validate(start, end, durationMs);
        if (pair != null) return pair;
      }
    }
    for (final source in sources) {
      if (source == null) continue;
      for (final key in mapKeys) {
        final raw = source[key];
        (int, int)? pair;
        if (raw is Map) {
          final start = _msOf(raw['startMs'] ?? raw['start'],
              msUnits: raw['startMs'] != null);
          final end =
              _msOf(raw['endMs'] ?? raw['end'], msUnits: raw['endMs'] != null);
          pair = _validate(start, end, durationMs);
        } else if (raw is List && raw.length >= 2) {
          final start = _msOf(raw[0], msUnits: false);
          final end = _msOf(raw[1], msUnits: false);
          pair = _validate(start, end, durationMs);
        }
        if (pair != null) return pair;
      }
    }
    return null;
  }

  static (int, int)? _validate(int? startMs, int? endMs, int? durationMs) {
    if (startMs == null || endMs == null) return null;
    if (startMs < 0 || endMs <= startMs) return null;
    if (durationMs != null && endMs > durationMs) return null;
    return (startMs, endMs);
  }

  static int? _firstMs(
    List<Map<String, dynamic>?> sources,
    List<String> keys,
  ) {
    for (final source in sources) {
      if (source == null) continue;
      for (final key in keys) {
        final ms = _msOf(source[key], msUnits: key.endsWith('Ms'));
        if (ms != null) return ms;
      }
    }
    return null;
  }

  /// Numbers only — anything else is malformed and treated as absent.
  /// Seconds convert to ms; keys ending in `Ms` (or ms-form map keys) pass
  /// through unchanged.
  static int? _msOf(Object? raw, {required bool msUnits}) {
    if (raw is! num) return null;
    final value = raw.toDouble();
    if (value.isNaN || value.isInfinite || value < 0) return null;
    return (msUnits ? value : value * 1000).round();
  }
}
