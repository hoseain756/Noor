import 'package:flutter_test/flutter_test.dart';
import 'package:noor_mobile/core/models/integration_cw.dart';

Map<String, dynamic> _traktMovie({double progress = 42.5, int pausedAt = 1700000000}) =>
    <String, dynamic>{
      'id': 1,
      'progress': progress,
      'paused_at': pausedAt,
      'type': 'movie',
      'movie': <String, dynamic>{
        'title': 'Inception',
        'year': 2010,
        'ids': <String, dynamic>{'trakt': 1, 'imdb': 'tt1375666'},
      },
    };

Map<String, dynamic> _traktEpisode() => <String, dynamic>{
      'id': 2,
      'progress': 66,
      'paused_at': 1700000100,
      'type': 'episode',
      'episode': <String, dynamic>{
        'season': 2,
        'number': 7,
        'title': 'The Episode',
      },
      'show': <String, dynamic>{
        'title': 'Breaking Bad',
        'year': 2008,
        'ids': <String, dynamic>{'trakt': 3, 'imdb': 'tt0903747'},
      },
    };

Map<String, dynamic> _anilistEntry({
  String status = 'CURRENT',
  int progress = 7,
  int? episodes = 12,
  String format = 'TV',
  int updatedAt = 1700000000,
}) =>
    <String, dynamic>{
      'id': 11,
      'status': status,
      'progress': progress,
      'updatedAt': updatedAt, // epoch SECONDS (AniList shape)
      'media': <String, dynamic>{
        'id': 21,
        'idMal': 31,
        'title': <String, dynamic>{
          'romaji': 'Frieren',
          'english': 'Frieren: Beyond Journey\'s End',
        },
        'coverImage': <String, dynamic>{'large': 'https://img/anilist.jpg'},
        'format': format,
        'episodes': episodes,
        'seasonYear': 2023,
      },
    };

Map<String, dynamic> _malRow({
  int watched = 4,
  String mediaType = 'TV',
  String updatedAt = '2024-05-01T12:00:00+09:00',
}) =>
    <String, dynamic>{
      'id': 41,
      'title': 'Spy x Family',
      'main_picture': <String, dynamic>{
        'large': 'https://img/mal.jpg',
      },
      'start_season': <String, dynamic>{'year': 2022},
      'media_type': mediaType,
      'list_status': <String, dynamic>{
        'status': 'watching',
        'num_episodes_watched': watched,
        'updated_at': updatedAt,
      },
    };

void main() {
  group('IntegrationCwEntry.fromTraktPlayback', () {
    test('movie row maps to an imdb item with pause progress', () {
      final entry = IntegrationCwEntry.fromTraktPlayback(_traktMovie());
      expect(entry, isNotNull);
      expect(entry!.source, 'trakt');
      expect(entry.item.id, 'tt1375666');
      expect(entry.item.type, 'movie');
      expect(entry.item.name, 'Inception');
      expect(entry.item.releaseInfo, '2010');
      expect(entry.progress, closeTo(0.425, 0.0001));
      expect(entry.isContinueable, isTrue);
      // paused_at arrives in epoch seconds → normalized to milliseconds.
      expect(entry.watchedAt, 1700000000 * 1000);
    });

    test('episode row maps to the parent show with S/E', () {
      final entry = IntegrationCwEntry.fromTraktPlayback(_traktEpisode());
      expect(entry, isNotNull);
      expect(entry!.item.id, 'tt0903747');
      expect(entry.item.type, 'series');
      expect(entry.season, 2);
      expect(entry.episode, 7);
      expect(entry.progress, closeTo(0.66, 0.0001));
    });

    test('guards: no imdb, unknown type, too little / too much progress', () {
      expect(
        IntegrationCwEntry.fromTraktPlayback(<String, dynamic>{
          'type': 'movie',
          'progress': 50,
          'movie': <String, dynamic>{
            'title': 'X',
            'ids': <String, dynamic>{'trakt': 9},
          },
        }),
        isNull,
      );
      expect(
        IntegrationCwEntry.fromTraktPlayback(<String, dynamic>{
          'type': 'season',
          'progress': 50,
        }),
        isNull,
      );
      expect(
        IntegrationCwEntry.fromTraktPlayback(_traktMovie(progress: 0.4)),
        isNull,
      );
      expect(
        IntegrationCwEntry.fromTraktPlayback(_traktMovie(progress: 97)),
        isNull,
      );
      expect(IntegrationCwEntry.fromTraktPlayback('garbage'), isNull);
      expect(IntegrationCwEntry.fromTraktPlayback(null), isNull);
    });
  });

  group('IntegrationCwEntry.fromAniListRow', () {
    test('CURRENT entry maps with cover art, mal id and episode fraction',
        () {
      final entry = IntegrationCwEntry.fromAniListRow(
        _anilistEntry(),
        statusFilter: 'CURRENT',
      );
      expect(entry, isNotNull);
      expect(entry!.source, 'anilist');
      expect(entry.item.id, 'anilist:21');
      expect(entry.item.name, "Frieren: Beyond Journey's End");
      expect(entry.item.poster, 'https://img/anilist.jpg');
      expect(entry.item.type, 'series');
      expect(entry.item.anilistId, 21);
      expect(entry.item.idMal, 31);
      expect(entry.episodesWatched, 7);
      expect(entry.episodesTotal, 12);
      expect(entry.progress, closeTo(7 / 12, 0.0001));
      expect(entry.nextEpisode, 8);
      // updatedAt arrives in epoch seconds.
      expect(entry.watchedAt, 1700000000 * 1000);
    });

    test('status filter drops non-matching lists', () {
      expect(
        IntegrationCwEntry.fromAniListRow(_anilistEntry(status: 'PLANNING'),
            statusFilter: 'CURRENT'),
        isNull,
      );
      expect(
        IntegrationCwEntry.fromAniListRow(_anilistEntry(status: 'PLANNING'),
            statusFilter: 'PLANNING'),
        isNotNull,
      );
      expect(
        IntegrationCwEntry.fromAniListRow(_anilistEntry(), statusFilter: null),
        isNotNull,
      );
    });

    test('non-episodic formats are skipped', () {
      expect(
        IntegrationCwEntry.fromAniListRow(_anilistEntry(format: 'MUSIC')),
        isNull,
      );
      final movie =
          IntegrationCwEntry.fromAniListRow(_anilistEntry(format: 'MOVIE'));
      expect(movie, isNotNull);
      expect(movie!.item.type, 'movie');
    });

    test('unknown episode total keeps the entry but no progress bar', () {
      final entry =
          IntegrationCwEntry.fromAniListRow(_anilistEntry(episodes: null));
      expect(entry, isNotNull);
      expect(entry!.progress, 0);
      expect(entry.isContinueable, isTrue);
    });
  });

  group('IntegrationCwEntry.fromMalRow', () {
    test('watching row maps with picture, year and ISO timestamp', () {
      final entry = IntegrationCwEntry.fromMalRow(_malRow());
      expect(entry, isNotNull);
      expect(entry!.source, 'mal');
      expect(entry.item.id, 'mal:41');
      expect(entry.item.name, 'Spy x Family');
      expect(entry.item.poster, 'https://img/mal.jpg');
      expect(entry.item.type, 'series');
      expect(entry.item.idMal, 41);
      expect(entry.episodesWatched, 4);
      expect(entry.nextEpisode, 5);
      expect(entry.watchedAt,
          DateTime.parse('2024-05-01T12:00:00+09:00').millisecondsSinceEpoch);
    });

    test('movie media type and zero progress guards', () {
      final movie = IntegrationCwEntry.fromMalRow(_malRow(mediaType: 'movie'));
      expect(movie!.item.type, 'movie');
      final fresh = IntegrationCwEntry.fromMalRow(_malRow(watched: 0));
      expect(fresh!.isContinueable, isFalse);
      expect(
        IntegrationCwEntry.fromMalRow(<String, dynamic>{
          'id': 9,
          'title': '',
        }),
        isNull,
      );
    });
  });

  group('IntegrationCwEntry.merge', () {
    test('newest first, deduped per source+item, capped', () {
      final trakt = [
        IntegrationCwEntry.fromTraktPlayback(_traktMovie(pausedAt: 100))!,
      ];
      final anilist = [
        IntegrationCwEntry.fromAniListRow(_anilistEntry(updatedAt: 300))!,
        // duplicate of the same media → collapsed to the newest instance
        IntegrationCwEntry.fromAniListRow(_anilistEntry(updatedAt: 400))!,
      ];
      final mal = [
        IntegrationCwEntry.fromMalRow(_malRow(updatedAt: '2024-05-01T12:00:00Z'))!,
      ];
      final merged = IntegrationCwEntry.merge([trakt, anilist, mal], limit: 2);
      expect(merged.length, 2);
      // 2024 epoch-ms beats the epoch-seconds entries (400s/300s → ms),
      // which in turn beat the 100s pause point.
      expect(merged.first.source, 'mal');
      expect(merged.last.source, 'anilist');
      // The dedupe keeps exactly ONE anilist entry despite two rows.
      expect(
        IntegrationCwEntry.merge([trakt, anilist, mal])
            .where((entry) => entry.source == 'anilist')
            .length,
        1,
      );
    });

    test('empty groups merge to empty', () {
      expect(IntegrationCwEntry.merge(const []), isEmpty);
    });
  });

  group('IntegrationCwEntry.watchlistItemFromRow', () {
    test('trakt/simkl sync rows map to poster-less items', () {
      final item = IntegrationCwEntry.watchlistItemFromRow(<String, dynamic>{
        'type': 'series',
        'imdb': 'tt0944947',
        'title': 'Game of Thrones',
        'year': 2011,
      });
      expect(item, isNotNull);
      expect(item!.id, 'tt0944947');
      expect(item.type, 'series');
      expect(item.name, 'Game of Thrones');
      expect(item.releaseInfo, '2011');
      expect(item.poster, isNull);
    });

    test('rows without identity are dropped', () {
      expect(
        IntegrationCwEntry.watchlistItemFromRow(<String, dynamic>{
          'type': 'movie',
          'title': 'No id',
        }),
        isNull,
      );
      expect(IntegrationCwEntry.watchlistItemFromRow(null), isNull);
    });
  });
}
