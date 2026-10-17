import 'package:flutter_test/flutter_test.dart';

import 'package:nova_mobile/features/player/segments/playback_segments.dart';

void main() {
  group('PlaybackSegmentsResolver — absence means unknown', () {
    test('no data → every field null and every feature inactive', () {
      final s = PlaybackSegmentsResolver.resolve();
      expect(s.introStartMs, isNull);
      expect(s.introEndMs, isNull);
      expect(s.outroStartMs, isNull);
      expect(s.outroEndMs, isNull);
      expect(s.nextEpisodeAtMs, isNull);
      expect(s.autoAdvanceCountdownMs, isNull);
      expect(s.hasIntro, isFalse);
      expect(s.hasOutro, isFalse);
      expect(
        SegmentWindows.introVisible(
            segments: s, positionMs: 1000, durationMs: 100000),
        isFalse,
      );
    });
  });

  group('PlaybackSegmentsResolver — seconds fields', () {
    test('introStart/introEnd in seconds normalize to ms', () {
      final s = PlaybackSegmentsResolver.resolve(
        stream: const {'introStart': 10, 'introEnd': 90},
      );
      expect(s.introStartMs, 10000);
      expect(s.introEndMs, 90000);
      expect(s.hasIntro, isTrue);
    });

    test('…Ms variants pass through unchanged', () {
      final s = PlaybackSegmentsResolver.resolve(
        video: const {'outroStartMs': 500000, 'outroEndMs': 700000},
      );
      expect(s.outroStartMs, 500000);
      expect(s.outroEndMs, 700000);
      expect(s.hasOutro, isTrue);
    });

    test('creditsStart/creditsEnd feed the outro window', () {
      final s = PlaybackSegmentsResolver.resolve(
        stream: const {'creditsStart': 1200, 'creditsEnd': 1400},
      );
      expect(s.outroStartMs, 1200000);
      expect(s.outroEndMs, 1400000);
    });
  });

  group('PlaybackSegmentsResolver — map & list forms', () {
    test('skipIntro {start, end} map (seconds)', () {
      final s = PlaybackSegmentsResolver.resolve(
        stream: const {
          'skipIntro': {'start': 5, 'end': 45}
        },
      );
      expect(s.introStartMs, 5000);
      expect(s.introEndMs, 45000);
    });

    test('{startMs, endMs} map keeps milliseconds', () {
      final s = PlaybackSegmentsResolver.resolve(
        video: const {
          'intro': {'startMs': 2500, 'endMs': 32500}
        },
      );
      expect(s.introStartMs, 2500);
      expect(s.introEndMs, 32500);
    });

    test('credits [start, end] list form', () {
      final s = PlaybackSegmentsResolver.resolve(
        stream: const {
          'credits': [100, 130]
        },
      );
      expect(s.outroStartMs, 100000);
      expect(s.outroEndMs, 130000);
    });

    test('behaviorHints sub-map is consulted', () {
      final s = PlaybackSegmentsResolver.resolve(
        stream: const {
          'url': 'https://example.com/a.mkv',
          'behaviorHints': {
            'introStart': 8,
            'introEnd': 72,
          },
        },
      );
      expect(s.introStartMs, 8000);
      expect(s.introEndMs, 72000);
    });
  });

  group('PlaybackSegmentsResolver — validation & malformed tolerance', () {
    test('start >= end is rejected', () {
      final s = PlaybackSegmentsResolver.resolve(
        stream: const {'introStart': 90, 'introEnd': 10},
      );
      expect(s.hasIntro, isFalse);
    });

    test('negative and non-numeric values are treated as absent', () {
      final s = PlaybackSegmentsResolver.resolve(
        stream: const {
          'introStart': -5,
          'introEnd': 30,
          'nextEpisodeAt': 'soon',
          'autoAdvanceCountdown': null,
        },
      );
      expect(s.hasIntro, isFalse);
      expect(s.nextEpisodeAtMs, isNull);
      expect(s.autoAdvanceCountdownMs, isNull);
    });

    test('window running past the known media duration is rejected', () {
      final s = PlaybackSegmentsResolver.resolve(
        stream: const {'introStart': 10, 'introEnd': 3600},
        mediaDurationMs: 1200000,
      );
      expect(s.hasIntro, isFalse);
    });

    test('absolute trigger beyond the duration is rejected', () {
      final s = PlaybackSegmentsResolver.resolve(
        video: const {'nextEpisodeAtMs': 5000000},
        mediaDurationMs: 1200000,
      );
      expect(s.nextEpisodeAtMs, isNull);
    });
  });

  group('SegmentWindows', () {
    const segments = PlaybackSegments(
      introStartMs: 10000,
      introEndMs: 90000,
      outroStartMs: 700000,
      outroEndMs: 800000,
    );

    test('intro pill visible strictly inside the window', () {
      expect(
        SegmentWindows.introVisible(
            segments: segments, positionMs: 10000, durationMs: 900000),
        isTrue,
      );
      expect(
        SegmentWindows.introVisible(
            segments: segments, positionMs: 89999, durationMs: 900000),
        isTrue,
      );
      expect(
        SegmentWindows.introVisible(
            segments: segments, positionMs: 90000, durationMs: 900000),
        isFalse,
      );
      expect(
        SegmentWindows.introVisible(
            segments: segments, positionMs: 9999, durationMs: 900000),
        isFalse,
      );
    });

    test('window past the media duration never shows', () {
      expect(
        SegmentWindows.introVisible(
            segments: segments, positionMs: 50000, durationMs: 80000),
        isFalse,
      );
    });

    test('cardAppearAt: data trigger wins when valid', () {
      final s = PlaybackSegmentsResolver.resolve(
        video: const {'nextEpisodeAtMs': 850000},
      );
      expect(
        SegmentWindows.cardAppearAtMs(segments: s, durationMs: 900000),
        850000,
      );
    });

    test('cardAppearAt fallback reproduces the shipped nearEnd rule', () {
      // The original rule was `remaining ≤ 30 s OR ≥95% elapsed` → the card
      // appears at the EARLIER (min) of the two thresholds.
      // 900 s media: 95% (855 s) beats 30s-window (870 s).
      expect(
        SegmentWindows.cardAppearAtMs(
            segments: PlaybackSegments.empty, durationMs: 900000),
        855000,
      );
      // 100 s media: 30s-window (70 s) beats 95% (95 s).
      expect(
        SegmentWindows.cardAppearAtMs(
            segments: PlaybackSegments.empty, durationMs: 100000),
        70000,
      );
      // Unknown duration → never.
      expect(
        SegmentWindows.cardAppearAtMs(
            segments: PlaybackSegments.empty, durationMs: 0),
        -1,
      );
    });

    test('autoAdvanceAtMs: null without a data-provided countdown', () {
      expect(
        SegmentWindows.autoAdvanceAtMs(
            segments: PlaybackSegments.empty, durationMs: 900000),
        isNull,
      );
    });

    test('autoAdvanceAtMs: appear + countdown, clamped to the end', () {
      final s = PlaybackSegmentsResolver.resolve(
        video: const {
          'nextEpisodeAtMs': 850000,
          'autoAdvanceCountdownMs': 20000
        },
      );
      expect(
        SegmentWindows.autoAdvanceAtMs(segments: s, durationMs: 900000),
        870000,
      );
      // Countdown running past the end clamps to the end.
      final s2 = PlaybackSegmentsResolver.resolve(
        video: const {
          'nextEpisodeAtMs': 890000,
          'autoAdvanceCountdownMs': 60000
        },
      );
      expect(
        SegmentWindows.autoAdvanceAtMs(segments: s2, durationMs: 900000),
        900000,
      );
    });
  });
}
