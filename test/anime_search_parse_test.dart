import 'package:flutter_test/flutter_test.dart';

import 'package:nova_mobile/core/data/catalog_repository.dart';

/// `parseAnimeResponse` routing for both providers' search rows: AniList
/// GraphQL rows and the MAL-normalized rows (`source: 'mal'`) must keep
/// their identities straight — a MAL id must never land in `anilistId`,
/// or tracker pushes would hit the wrong media on AniList.
void main() {
  Map<String, dynamic> page(List<dynamic> media) => <String, dynamic>{
        'data': <String, dynamic>{
          'Page': <String, dynamic>{'media': media},
        },
      };

  test('AniList rows parse with anilistId + idMal and an anilist: id', () {
    final items = CatalogRepository.parseAnimeResponse(page([
      <String, dynamic>{
        'id': 21,
        'idMal': 1,
        'format': 'TV',
        'title': {'english': 'One Piece', 'romaji': 'One Piece'},
        'coverImage': {'large': 'https://img/one-piece.jpg'},
        'seasonYear': 1999,
        'averageScore': 88,
      },
    ]));
    expect(items, hasLength(1));
    final item = items.single;
    expect(item.id, 'anilist:21');
    expect(item.anilistId, 21);
    expect(item.idMal, 1);
    expect(item.name, 'One Piece');
    expect(item.type, 'series');
    expect(item.rating, '8.8');
  });

  test('MAL-sourced rows keep anilistId null and build mal: ids', () {
    final items = CatalogRepository.parseAnimeResponse(page([
      <String, dynamic>{
        'id': 9253,
        'idMal': 9253,
        'source': 'mal',
        'format': 'TV',
        'title': {'english': 'Steins;Gate'},
        'coverImage': {'large': 'https://img/sg.jpg'},
        'seasonYear': 2011,
        'averageScore': 91,
      },
    ]));
    expect(items, hasLength(1));
    final item = items.single;
    expect(item.id, 'mal:9253');
    expect(item.anilistId, isNull);
    expect(item.idMal, 9253);
    expect(item.name, 'Steins;Gate');
    expect(item.hasAnimeIds, isTrue);
  });

  test('MAL movie rows type as movies; MAL id survives the copy', () {
    final items = CatalogRepository.parseAnimeResponse(page([
      <String, dynamic>{
        'id': 5114,
        'idMal': 5114,
        'source': 'mal',
        'format': 'MOVIE',
        'title': {'english': 'Fate/stay night: Heaven\u2019s Feel'},
        'seasonYear': 2017,
      },
    ]));
    final item = items.single;
    expect(item.type, 'movie');
    expect(item.anilistId, isNull);
    expect(item.idMal, 5114);
    expect(item.rating, isNull); // no averageScore -> no rating
  });

  test('Rows without a usable id are dropped for both providers', () {
    final items = CatalogRepository.parseAnimeResponse(page([
      <String, dynamic>{
        'id': null,
        'format': 'TV',
        'title': {'english': 'Ghost'},
      },
      <String, dynamic>{
        'id': null,
        'source': 'mal',
        'format': 'TV',
        'title': {'english': 'Ghost (MAL)'},
      },
    ]));
    expect(items, isEmpty);
  });

  test('Non-listable formats (music, unknown) are filtered out', () {
    final items = CatalogRepository.parseAnimeResponse(page([
      <String, dynamic>{
        'id': 1,
        'format': 'MUSIC',
        'title': {'english': 'Some OP'},
      },
      <String, dynamic>{
        'id': 2,
        'source': 'mal',
        'format': null,
        'title': {'english': 'Unknown MAL shape'},
      },
    ]));
    expect(items, isEmpty);
  });
}
