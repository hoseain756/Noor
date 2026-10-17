import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/data/catalog_repository.dart';
import 'package:nova_mobile/core/models/addon.dart';

Addon _addon(
  String id, {
  bool enabled = true,
  List<Map<String, dynamic>> catalogs = const [],
}) =>
    Addon(
      id: id,
      name: 'Addon $id',
      transportUrl: 'https://$id.example/manifest.json',
      manifest: <String, dynamic>{'catalogs': catalogs},
      enabled: enabled,
    );

Map<String, dynamic> _catalog(
  String id,
  String type,
  String name, {
  bool requiresSearch = false,
}) =>
    <String, dynamic>{
      'id': id,
      'type': type,
      'name': name,
      if (requiresSearch)
        'extra': <Map<String, dynamic>>[
          <String, dynamic>{'name': 'search', 'isRequired': true},
        ],
    };

void main() {
  group('CatalogRepository.selectAddonCatalogRows', () {
    test('one rail per catalog, first add-on wins on name collisions', () {
      final rows = CatalogRepository.selectAddonCatalogRows([
        _addon('a', catalogs: [
          _catalog('top', 'movie', 'Popular'),
        ]),
        _addon('b', catalogs: [
          _catalog('top2', 'movie', 'POPULAR '), // same name, different case
          _catalog('other', 'series', 'Other'),
        ]),
      ]);
      expect(rows.map((row) => row.key).toList(),
          ['a:movie:top', 'b:series:other']);
      expect(rows.first.title, 'Popular');
      expect(rows.first.subtitle, 'Addon a');
    });

    test('anchor keys, disabled add-ons and non-movie/series types are skipped',
        () {
      final rows = CatalogRepository.selectAddonCatalogRows([
        _addon('a', catalogs: [
          _catalog('trailer', 'movie', 'Trending'), // anchor pair movie:trailer
          _catalog('channels', 'tv', 'Live'), // unsupported type
          _catalog('other', 'movie', 'Other'),
        ]),
        _addon('b', enabled: false, catalogs: [
          _catalog('x', 'movie', 'Hidden'),
        ]),
      ], anchorKeys: const {
        'movie:trailer'
      });
      expect(rows.map((row) => row.key).toList(), ['a:movie:other']);
    });

    test('catalogs that REQUIRE a search term never get a row', () {
      final rows = CatalogRepository.selectAddonCatalogRows([
        _addon('a', catalogs: [
          _catalog('search-only', 'movie', 'Searchable', requiresSearch: true),
          _catalog('plain', 'movie', 'Plain'),
        ]),
      ]);
      expect(rows.map((row) => row.catalog.id).toList(), ['plain']);
    });

    test('limit caps the result across add-ons', () {
      final rows = CatalogRepository.selectAddonCatalogRows(
        [
          _addon('a', catalogs: [
            _catalog('1', 'movie', 'One'),
            _catalog('2', 'movie', 'Two'),
          ]),
          _addon('b', catalogs: [
            _catalog('3', 'series', 'Three'),
            _catalog('4', 'series', 'Four'),
          ]),
        ],
        limit: 3,
      );
      expect(rows.length, 3);
    });

    test('empty input yields no rows', () {
      expect(CatalogRepository.selectAddonCatalogRows(const []), isEmpty);
    });
  });
}
