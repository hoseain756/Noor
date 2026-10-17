import 'package:flutter_test/flutter_test.dart';

import 'package:nova_mobile/core/models/media_item.dart';
import 'package:nova_mobile/features/media/episode_data.dart';

MediaItem _item(String id) => MediaItem(id: id, type: 'series', name: id);

WatchHistoryEntry _entry({
  required String itemId,
  required int watchedAt,
  String? videoId,
  int? season,
  int? episode,
  int positionMs = 0,
  int durationMs = 0,
}) =>
    WatchHistoryEntry(
      item: _item(itemId),
      watchedAt: watchedAt,
      videoId: videoId,
      season: season,
      episode: episode,
      positionMs: positionMs,
      durationMs: durationMs,
    );

Map<String, dynamic> _video(int season, int episode, {String? id}) =>
    {'id': id ?? 'tt1:$season:$episode', 'season': season, 'episode': episode};

void main() {
  group('sortEpisodes', () {
    test('orders by (season, episode) without mutating the input', () {
      final input = [
        _video(2, 1),
        _video(1, 10),
        _video(0, 1), // specials
        _video(1, 2),
        _video(2, 12),
      ];
      final snapshot = List.of(input);
      final sorted = sortEpisodes(input);

      expect(
        sorted.map((v) => '${v['season']}:${v['episode']}').toList(),
        ['0:1', '1:2', '1:10', '2:1', '2:12'],
      );
      expect(input, snapshot); // never mutated
    });

    test('treats missing season/episode as zero', () {
      final sorted = sortEpisodes([
        {'id': 'b', 'episode': 1},
        {'id': 'a'},
      ]);
      expect(sorted.first['id'], 'a');
    });
  });

  group('episodeProgressMap', () {
    test('keys by BOTH videoId and the composite {itemId}:{s}:{e} form', () {
      final map = episodeProgressMap(
        entries: [
          _entry(
            itemId: 'tt1',
            watchedAt: 100,
            videoId: 'addon-ep-303',
            season: 2,
            episode: 3,
            positionMs: 300000,
            durationMs: 1800000,
          ),
        ],
        itemId: 'tt1',
      );

      expect(map.containsKey('addon-ep-303'), isTrue); // direct videoId key
      expect(map.containsKey('tt1:2:3'), isTrue); // composite key
      expect(map['addon-ep-303']!.progress, closeTo(300000 / 1800000, 1e-9));
    });

    test('newest entry wins for the same key', () {
      final map = episodeProgressMap(
        entries: [
          _entry(
            itemId: 'tt1',
            watchedAt: 500,
            videoId: 'ep5',
            season: 1,
            episode: 5,
            positionMs: 900000,
            durationMs: 1800000,
          ),
          _entry(
            itemId: 'tt1',
            watchedAt: 900,
            videoId: 'ep5',
            season: 1,
            episode: 5,
            positionMs: 1000,
            durationMs: 1800000,
          ),
        ],
        itemId: 'tt1',
      );

      expect(map['ep5']!.positionMs, 1000);
      // composite key mirrors the same newest-wins value
      expect(map['tt1:1:5']!.positionMs, 1000);
    });

    test('entries without season/episode only key by videoId', () {
      final map = episodeProgressMap(
        entries: [
          _entry(
            itemId: 'tt1',
            watchedAt: 10,
            videoId: 'movie-id',
            positionMs: 10,
            durationMs: 100,
          ),
        ],
        itemId: 'tt1',
      );

      expect(map.containsKey('movie-id'), isTrue);
      expect(map.containsKey('tt1:null:null'), isFalse);
    });
  });

  group('watched threshold (0.85)', () {
    test('0.84 progress is NOT watched, 0.85 is', () {
      final below = _video(1, 1, id: 'e1');
      final at = _video(1, 2, id: 'e2');
      final map = episodeProgressMap(
        entries: [
          _entry(
            itemId: 'tt1',
            watchedAt: 1,
            videoId: 'e1',
            season: 1,
            episode: 1,
            positionMs: 84,
            durationMs: 100,
          ),
          _entry(
            itemId: 'tt1',
            watchedAt: 2,
            videoId: 'e2',
            season: 1,
            episode: 2,
            positionMs: 85,
            durationMs: 100,
          ),
        ],
        itemId: 'tt1',
      );

      expect(isEpisodeWatched(map, below, 'tt1'), isFalse);
      expect(isEpisodeWatched(map, at, 'tt1'), isTrue);
    });

    test('the composite key alone can mark an episode watched', () {
      final video = _video(3, 4, id: 'different-addon-id');
      final map = episodeProgressMap(
        entries: [
          _entry(
            itemId: 'tt1',
            watchedAt: 1,
            videoId: 'old-video-id',
            season: 3,
            episode: 4,
            positionMs: 95,
            durationMs: 100,
          ),
        ],
        itemId: 'tt1',
      );

      expect(isEpisodeWatched(map, video, 'tt1'), isTrue);
    });

    test('zero-duration entries never count as watched', () {
      final video = _video(1, 1, id: 'e1');
      final map = episodeProgressMap(
        entries: [
          _entry(
            itemId: 'tt1',
            watchedAt: 1,
            videoId: 'e1',
            season: 1,
            episode: 1,
            positionMs: 5000,
            durationMs: 0,
          ),
        ],
        itemId: 'tt1',
      );

      expect(map['e1']!.progress, 0.0);
      expect(isEpisodeWatched(map, video, 'tt1'), isFalse);
    });
  });

  group('isUpcomingEpisode', () {
    final now = DateTime(2026, 10, 15, 12);

    test('future air date → upcoming', () {
      expect(
        isUpcomingEpisode({
          'id': 'e1',
          'released': '2026-10-20T00:00:00.000Z',
        }, now),
        isTrue,
      );
    });

    test('past air date / unparsable / missing → not upcoming', () {
      expect(
        isUpcomingEpisode({
          'id': 'e1',
          'released': '2020-01-01T00:00:00.000Z',
        }, now),
        isFalse,
      );
      expect(
        isUpcomingEpisode({'id': 'e1', 'released': 'not-a-date'}, now),
        isFalse,
      );
      expect(isUpcomingEpisode({'id': 'e1'}, now), isFalse);
      expect(
        isUpcomingEpisode({'id': 'e1', 'released': ''}, now),
        isFalse,
      );
    });
  });

  group('defaultSeason', () {
    final videos = [
      for (var e = 1; e <= 4; e++) _video(1, e, id: 's1e$e'),
      for (var e = 1; e <= 4; e++) _video(2, e, id: 's2e$e'),
      _video(0, 1, id: 'special1'),
      _video(0, 2, id: 'special2'),
    ];

    test('continue-watching season wins while still in progress', () {
      final season = defaultSeason(
        videos: videos,
        history: [
          _entry(
            itemId: 'tt1',
            watchedAt: 100,
            videoId: 's2e2',
            season: 2,
            episode: 2,
            positionMs: 500000,
            durationMs: 1800000, // ~0.28 → in progress
          ),
        ],
        itemId: 'tt1',
      );
      expect(season, 2);
    });

    test('a finished (≥ 0.85) latest entry falls through to first unwatched',
        () {
      final season = defaultSeason(
        videos: videos,
        history: [
          _entry(
            itemId: 'tt1',
            watchedAt: 100,
            videoId: 's2e2',
            season: 2,
            episode: 2,
            positionMs: 1800000,
            durationMs: 1800000, // finished
          ),
        ],
        itemId: 'tt1',
      );
      // S1 is untouched → the scanner lands there, not on the finished S2.
      expect(season, 1);
    });

    test('fresh user (no history) lands on Season 1, NOT specials', () {
      final season = defaultSeason(videos: videos, itemId: 'tt1');
      expect(season, 1);
    });

    test('specials are scanned LAST (S1 watched → S2 before specials)', () {
      final watched = [
        for (var e = 1; e <= 4; e++)
          _entry(
            itemId: 'tt1',
            watchedAt: e,
            videoId: 's1e$e',
            season: 1,
            episode: e,
            positionMs: 1800000,
            durationMs: 1800000,
          ),
      ];
      final season = defaultSeason(
        videos: videos,
        history: watched,
        itemId: 'tt1',
      );
      expect(season, 2);
    });

    test('all watched → first regular season (specials ignored)', () {
      final watched = [
        for (final v in videos)
          _entry(
            itemId: 'tt1',
            watchedAt: 1,
            videoId: v['id'] as String,
            season: (v['season'] as num).toInt(),
            episode: (v['episode'] as num).toInt(),
            positionMs: 1800000,
            durationMs: 1800000,
          ),
      ];
      final season = defaultSeason(
        videos: videos,
        history: watched,
        itemId: 'tt1',
      );
      expect(season, 1);
    });

    test('only specials → returns 0', () {
      final season = defaultSeason(
        videos: [_video(0, 1, id: 'sp1'), _video(0, 2, id: 'sp2')],
        itemId: 'tt1',
      );
      expect(season, 0);
    });

    test('empty videos → null', () {
      expect(defaultSeason(videos: const [], itemId: 'tt1'), isNull);
    });
  });

  group('parseRuntimeMinutes', () {
    test('addon runtime strings', () {
      expect(parseRuntimeMinutes('23min'), 23);
      expect(parseRuntimeMinutes('58 min'), 58);
      expect(parseRuntimeMinutes('1h 52m'), 112);
      expect(parseRuntimeMinutes('2 hours'), 120);
      expect(parseRuntimeMinutes('90'), 90);
    });

    test('garbage → null', () {
      expect(parseRuntimeMinutes(null), isNull);
      expect(parseRuntimeMinutes(''), isNull);
      expect(parseRuntimeMinutes('abc'), isNull);
      expect(parseRuntimeMinutes('0'), isNull);
    });
  });

  group('formatEpisodeDate', () {
    test('d MMM yyyy with latin digits', () {
      expect(formatEpisodeDate('2024-03-02T00:00:00.000Z'), '2 Mar 2024');
      expect(formatEpisodeDate('2015-12-31'), '31 Dec 2015');
    });

    test('unparsable → empty string', () {
      expect(formatEpisodeDate(null), '');
      expect(formatEpisodeDate(''), '');
      expect(formatEpisodeDate('nope'), '');
    });
  });
}
