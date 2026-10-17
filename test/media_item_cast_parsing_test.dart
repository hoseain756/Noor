import 'package:flutter_test/flutter_test.dart';

import 'package:nova_mobile/core/models/media_item.dart';

void main() {
  test('parses cast/director/runtime from a Cinemeta-shaped payload', () {
    final item = MediaItem.fromJson({
      'id': 'tt0903747',
      'type': 'series',
      'name': 'Breaking Bad',
      'runtime': '49 min',
      'cast': [
        'Bryan Cranston',
        'Aaron Paul',
        'Anna Gunn',
        'Dean Norris',
        'Betsy Brandt',
        'Bob Odenkirk',
        'Giancarlo Esposito',
        'Jonathan Banks',
        'Jesse Plemons',
        'RJ Mitte',
        'Matt Jones',
      ],
      'director': ['Vince Gilligan', 'Michelle MacLaren', 'Rian Johnson'],
    });

    expect(item.runtime, '49 min');
    expect(item.cast, hasLength(10)); // capped at 10
    expect(item.cast.first, 'Bryan Cranston');
    expect(item.cast.last, 'RJ Mitte');
    expect(item.director, hasLength(3));
    expect(item.director.first, 'Vince Gilligan');
  });

  test('defensively parses the comma-separated string form', () {
    final item = MediaItem.fromJson({
      'id': 'tt0111161',
      'type': 'movie',
      'name': 'The Shawshank Redemption',
      'cast': ' Tim Robbins , Morgan Freeman ,, Bob Gunton ',
      'director': 'Frank Darabont',
      'runtime': '2h 22m',
    });

    expect(item.cast, ['Tim Robbins', 'Morgan Freeman', 'Bob Gunton']);
    expect(item.director, ['Frank Darabont']);
    expect(item.runtime, '2h 22m');
  });

  test('caps the director list at 5 and skips empty entries', () {
    final item = MediaItem.fromJson({
      'id': 'tt1520211',
      'type': 'movie',
      'name': 'The Walking Dead',
      'cast': ['', '   ', 'Andrew Lincoln'],
      'director': ['A', 'B', 'C', 'D', 'E', 'F', 'G'],
    });

    expect(item.cast, ['Andrew Lincoln']);
    expect(item.director, hasLength(5));
    expect(item.director, ['A', 'B', 'C', 'D', 'E']);
  });

  test('missing / malformed people fields fall back to empty lists', () {
    final item = MediaItem.fromJson({
      'id': 'tt1375666',
      'type': 'movie',
      'name': 'Inception',
      'cast': 42,
      'director': {'unexpected': true},
    });

    expect(item.cast, isEmpty);
    expect(item.director, isEmpty);
    expect(item.runtime, isNull);
  });

  test('accepts {name} map entries inside the cast list', () {
    final item = MediaItem.fromJson({
      'id': 'tt0898266',
      'type': 'series',
      'name': 'The Big Bang Theory',
      'cast': [
        {'name': 'Jim Parsons'},
        {'name': 'Johnny Galecki'},
      ],
    });

    expect(item.cast, ['Jim Parsons', 'Johnny Galecki']);
  });

  test('cast/director/runtime survive toJson + withAnimeIds round-trips', () {
    final item = MediaItem.fromJson({
      'id': 'tt5491994',
      'type': 'series',
      'name': 'Planet Earth II',
      'runtime': '50 min',
      'cast': ['David Attenborough'],
      'director': ['Tom Hugh-Jones'],
    });

    final roundTripped = MediaItem.fromJson(item.toJson());
    expect(roundTripped.runtime, '50 min');
    expect(roundTripped.cast, ['David Attenborough']);
    expect(roundTripped.director, ['Tom Hugh-Jones']);

    final withIds = item.withAnimeIds(anilistId: 1, idMal: 2);
    expect(withIds.runtime, '50 min');
    expect(withIds.cast, item.cast);
    expect(withIds.director, item.director);

    final withArt = item.withArtwork(poster: 'https://example.com/p.jpg');
    expect(withArt.runtime, '50 min');
    expect(withArt.cast, item.cast);
    expect(withArt.director, item.director);
  });

  test('existing behavior is untouched (defaults + fields)', () {
    final item = MediaItem.fromJson({
      'id': 'anilist:16498',
      'type': 'series',
      'name': 'Attack on Titan',
      'poster': 'https://example.com/poster.jpg',
      'genres': ['Action', 'Drama'],
      'anilistId': 16498,
    });

    expect(item.id, 'anilist:16498');
    expect(item.releaseInfo, isNull);
    expect(item.genres, ['Action', 'Drama']);
    expect(item.anilistId, 16498);
    expect(item.hasAnimeIds, isTrue);
    expect(item.cast, isEmpty);
    expect(item.director, isEmpty);
    expect(item.runtime, isNull);
  });
}
