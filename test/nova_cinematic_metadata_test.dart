import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/models/media_item.dart';

void main() {
  test('provider people and production survive serialization and copies', () {
    final item = MediaItem.fromJson({
      'id': 'tt123',
      'type': 'series',
      'name': 'A story',
      'originalTitle': 'The original',
      'language': 'ar',
      'status': 'Returning Series',
      'seasonCount': 2,
      'episodeCount': 18,
      'castMembers': [
        {
          'name': 'A Person',
          'character': 'A Role',
          'profile_path': '/person.jpg'
        }
      ],
      'crewMembers': [
        {'name': 'A Creator', 'job': 'Creator'}
      ],
      'production_companies': [
        {'name': 'A Studio', 'logo_path': '/studio.png'}
      ],
    });
    final restored = MediaItem.fromJson(item
        .withArtwork(poster: 'poster')
        .withAnimeIds(anilistId: 12)
        .toJson());
    expect(restored.castMembers.single.photo,
        'https://image.tmdb.org/t/p/w185/person.jpg');
    expect(restored.castMembers.single.role, 'A Role');
    expect(restored.crewMembers.single.role, 'Creator');
    expect(restored.productionCompanies.single.logo,
        'https://image.tmdb.org/t/p/w300/studio.png');
    expect(restored.originalTitle, 'The original');
    expect(restored.seasonCount, 2);
    expect(restored.episodeCount, 18);
    expect(restored.anilistId, 12);
  });

  test('missing provider portraits and logos are never fabricated', () {
    final item = MediaItem.fromJson({
      'id': 'tt1',
      'name': 'Story',
      'castMembers': [
        {'name': 'Actor'}
      ],
      'productionCompanies': [
        {'name': 'Studio'}
      ]
    });
    expect(item.castMembers.single.photo, isNull);
    expect(item.productionCompanies.single.logo, isNull);
    expect(item.releaseDate, isNull);
  });
}
