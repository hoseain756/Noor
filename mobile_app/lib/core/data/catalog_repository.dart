import 'dart:async';

import '../api/horse_api.dart';
import 'content_classifier.dart';
import '../models/addon.dart';
import '../models/anime_airing.dart';
import '../models/featured_artwork.dart';
import '../models/media_item.dart';

class CatalogRepository {
  CatalogRepository(this.api);

  final HorseApi api;
  static const _cinemeta = 'https://v3-cinemeta.strem.io';
  static const _animeQuery = r'''
query ($page: Int, $perPage: Int, $sort: [MediaSort], $isAdult: Boolean) {
  Page(page: $page, perPage: $perPage) {
    media(sort: $sort, type: ANIME, isAdult: $isAdult) {
      id
      title { romaji english native }
      coverImage { extraLarge large }
      description(asHtml: false)
      format
      averageScore
      seasonYear
      genres
    }
  }
}
''';
  static const _animeAiringWeekQuery = r'''
query ($weekStart: Int!, $weekEnd: Int!) {
  Page(page: 1, perPage: 100) {
    airingSchedules(
      airingAt_greater: $weekStart,
      airingAt_lesser: $weekEnd,
      sort: TIME
    ) {
      airingAt
      episode
      media {
        id
        title { romaji english native }
        coverImage { extraLarge large }
        description(asHtml: false)
        format
        averageScore
        seasonYear
        genres
        isAdult
      }
    }
  }
}
''';
  final Map<String, FeaturedArtwork> _featuredArtworkCache = {};
  final Map<String, Future<FeaturedArtwork?>> _featuredArtworkRequests = {};

  Future<List<MediaItem>> catalog(
    String type,
    String id, {
    Map<String, dynamic> extras = const {},
    Addon? addon,
  }) async {
    final base = addon?.baseUrl ?? _cinemeta;
    final url = _resourceUrl(base, 'catalog', type, id, extras);
    final data = await api.proxyGet(url);
    final rows = (data['metas'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => MediaItem.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.id.isNotEmpty)
        .toList();
    return _unique(rows);
  }

  Future<MediaItem?> detail(String type, String id, List<Addon> addons) async {
    for (final addon in addons.where(
      (a) => a.enabled && a.supports('meta', type, id),
    )) {
      try {
        final url = _resourceUrl(addon.baseUrl, 'meta', type, id, const {});
        final data = await api.proxyGet(url);
        final value = data['meta'];
        if (value is Map) {
          return MediaItem.fromJson(Map<String, dynamic>.from(value));
        }
      } catch (_) {
        // Try the next metadata provider before falling back to Cinemeta.
      }
    }
    try {
      final data = await api.proxyGet(
        _resourceUrl(_cinemeta, 'meta', type, id, const {}),
      );
      final value = data['meta'];
      return value is Map
          ? MediaItem.fromJson(Map<String, dynamic>.from(value))
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<MediaItem>> homeTopTen() async {
    // This mirrors the web Home ranking: alternate current Cinemeta movie and
    // series trends, deduplicating IDs. If those trend catalogs are empty,
    // retry with the live top catalogs rather than rendering a blank section.
    final trending = await Future.wait([
      _capture(catalog('movie', 'trailer')),
      _capture(catalog('series', 'trailer')),
    ]);
    final ranked = rankTopTen(trending.map((result) => result.$1).toList());
    if (ranked.isNotEmpty) return ranked;

    final popular = await Future.wait([
      _capture(catalog('movie', 'top')),
      _capture(catalog('series', 'top')),
    ]);
    final fallback = rankTopTen(popular.map((result) => result.$1).toList());
    if (fallback.isNotEmpty) return fallback;

    final everyRequestFailed =
        [...trending, ...popular].every((result) => result.$2 != null);
    if (everyRequestFailed) {
      throw const CatalogLoadException('Could not load the Top 10 catalog.');
    }
    return const [];
  }

  /// Enriches the home hero with the same localized transparent logo and
  /// textless artwork that the Harbor web hero requests from TMDB.
  Future<FeaturedArtwork> featuredArtwork(
    MediaItem item, {
    String language = 'en-US',
    String region = 'US',
    String uiLanguage = 'en',
  }) async {
    final fallback = FeaturedArtwork(
      logo: item.logo,
      portrait: item.poster,
      landscape: item.background,
      genre: item.genres.firstOrNull,
      overview: item.description,
    );
    final imdbId = RegExp(r'tt\d+').firstMatch(item.id)?.group(0);
    if (imdbId == null || imdbId.isEmpty) return fallback;

    final locale = uiLanguage.split(RegExp('[-_]')).first.toLowerCase();
    final key = '${item.type}:$imdbId:$language:$region:$locale';
    final cached = _featuredArtworkCache[key];
    if (cached != null) return cached;

    final request = _featuredArtworkRequests.putIfAbsent(
      key,
      () => _loadFeaturedArtwork(
        item,
        imdbId: imdbId,
        language: language,
        region: region,
        uiLanguage: locale,
      ),
    );
    try {
      final artwork = await request;
      if (artwork == null) return fallback;
      _featuredArtworkCache[key] = artwork;
      return artwork;
    } finally {
      _featuredArtworkRequests.remove(key);
    }
  }

  Future<FeaturedArtwork?> _loadFeaturedArtwork(
    MediaItem item, {
    required String imdbId,
    required String language,
    required String region,
    required String uiLanguage,
  }) async {
    try {
      final kind = item.type.toLowerCase() == 'series' ? 'tv' : 'movie';
      final lookup = await api.tmdbGet(
        '/find/${Uri.encodeComponent(imdbId)}',
        query: const {'external_source': 'imdb_id'},
        language: language,
        region: region,
      );
      final resultKey = kind == 'tv' ? 'tv_results' : 'movie_results';
      final matches = (lookup[resultKey] as List? ?? const [])
          .whereType<Map>()
          .toList(growable: false);
      final tmdbId = matches.isEmpty ? null : matches.first['id'];
      if (tmdbId is! num && tmdbId is! String) return null;

      final imageLanguages =
          uiLanguage == 'en' ? 'en,null' : '$uiLanguage,en,null';
      final details = await api.tmdbGet(
        '/$kind/${Uri.encodeComponent(tmdbId.toString())}',
        query: {
          'append_to_response': 'images',
          'include_image_language': imageLanguages,
        },
        language: language,
        region: region,
      );
      final images = details['images'] is Map
          ? Map<String, dynamic>.from(details['images'] as Map)
          : const <String, dynamic>{};
      final logoPath = _localizedLogoPath(
        images['logos'],
        language: uiLanguage,
      );
      final textlessPoster = _bestTextlessImagePath(images['posters']);
      final textlessBackdrop = _bestTextlessImagePath(images['backdrops']);
      final genres = (details['genres'] as List? ?? const [])
          .whereType<Map>()
          .toList(growable: false);
      final genre = genres.isEmpty ? null : genres.first['name']?.toString();
      final overview = details['overview']?.toString().trim();

      return FeaturedArtwork(
        logo: item.logo ?? _tmdbImage(logoPath, 'w500'),
        portrait: _tmdbImage(textlessPoster, 'w780') ??
            _tmdbImage(textlessBackdrop, 'w780') ??
            item.poster,
        landscape: _tmdbImage(textlessBackdrop, 'w1280') ?? item.background,
        genre: genre?.isNotEmpty == true ? genre : item.genres.firstOrNull,
        overview: overview?.isNotEmpty == true ? overview : item.description,
      );
    } catch (_) {
      // The catalog hero must still render when TMDB is unavailable.
      return null;
    }
  }

  static String? _localizedLogoPath(
    dynamic value, {
    required String language,
  }) {
    final logos =
        (value as List? ?? const []).whereType<Map>().toList(growable: false);
    if (logos.isEmpty) return null;

    final sorted = [...logos]..sort((a, b) =>
        ((b['width'] as num?)?.toInt() ?? 0)
            .compareTo((a['width'] as num?)?.toInt() ?? 0));
    final preferred =
        sorted.where((logo) => logo['iso_639_1'] == language).firstOrNull;
    final english =
        sorted.where((logo) => logo['iso_639_1'] == 'en').firstOrNull;
    final any = sorted.where((logo) => logo['file_path'] is String).firstOrNull;
    final path = (preferred ?? english ?? any)?['file_path'];
    return path is String && path.isNotEmpty ? path : null;
  }

  static String? _bestTextlessImagePath(dynamic value) {
    final images = (value as List? ?? const [])
        .whereType<Map>()
        .where((image) => image['iso_639_1'] == null)
        .toList(growable: false)
      ..sort((a, b) {
        double score(Map image) =>
            ((image['vote_average'] as num?)?.toDouble() ?? 0) *
            ((image['vote_count'] as num?)?.toDouble() ?? 0);
        return score(b).compareTo(score(a));
      });
    final path = images.firstOrNull?['file_path'];
    return path is String && path.isNotEmpty ? path : null;
  }

  static String? _tmdbImage(String? path, String size) =>
      path == null ? null : 'https://image.tmdb.org/t/p/$size$path';

  /// Resolves TMDB recommendations back to Cinemeta IDs so each result opens
  /// in the native detail and stream-picker flow. TMDB metadata alone is not
  /// treated as playable content.
  Future<List<MediaItem>> tmdbRecommendations(
    MediaItem seed, {
    String language = 'en-US',
    String region = 'US',
  }) async {
    final imdbId = RegExp(r'tt\d+').firstMatch(seed.id)?.group(0);
    if (imdbId == null || imdbId.isEmpty) return const [];
    try {
      final lookup = await api.tmdbGet(
        '/find/${Uri.encodeComponent(imdbId)}',
        query: const {'external_source': 'imdb_id'},
        language: language,
        region: region,
      );
      final tmdbType = seed.type == 'series' ? 'tv' : 'movie';
      final sourceKey = tmdbType == 'tv' ? 'tv_results' : 'movie_results';
      final found =
          (lookup[sourceKey] as List? ?? const []).whereType<Map>().firstOrNull;
      final tmdbId = found?['id'];
      if (tmdbId is! num && tmdbId is! String) return const [];

      final recommendations = await api.tmdbGet(
        '/$tmdbType/${Uri.encodeComponent(tmdbId.toString())}/recommendations',
        query: const {'page': 1},
        language: language,
        region: region,
      );
      final candidates = (recommendations['results'] as List? ?? const [])
          .whereType<Map>()
          .take(12)
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final resolved = await Future.wait(candidates.map((row) async {
        final title = (row['title'] ?? row['name'] ?? '').toString().trim();
        if (title.isEmpty) return null;
        final matches = await _softList(
          catalog(seed.type, 'top', extras: {'search': title}),
        );
        MediaItem? best;
        var bestScore = 0;
        for (final item in matches) {
          final score = _titleMatchScore(item.name, title);
          if (score > bestScore) {
            best = item;
            bestScore = score;
          }
        }
        return bestScore >= 70 ? best : null;
      }));
      return _unique(resolved
          .whereType<MediaItem>()
          .where((item) => item.id != seed.id)
          .toList());
    } catch (_) {
      // Recommendations are an optional enhancement; catalog browsing and
      // playback continue when the TMDB key or upstream service is unavailable.
      return const [];
    }
  }

  static List<MediaItem> rankTopTen(List<List<MediaItem>> groups) {
    final merged = <MediaItem>[];
    final seen = <String>{};
    final longest = groups.fold<int>(
        0, (max, rows) => rows.length > max ? rows.length : max);
    for (var index = 0; index < longest && merged.length < 10; index++) {
      for (final rows in groups) {
        if (index >= rows.length) continue;
        final item = rows[index];
        if (seen.add(item.id)) merged.add(item);
        if (merged.length == 10) break;
      }
    }
    return merged;
  }

  Future<(List<MediaItem>, Object?)> _capture(
    Future<List<MediaItem>> future,
  ) async {
    try {
      return (await future, null);
    } catch (error) {
      return (<MediaItem>[], error);
    }
  }

  Future<List<MediaItem>> anime() async {
    final response = await api.postJson('/api/anilist', {
      'query': _animeQuery,
      'variables': {
        'page': 1,
        'perPage': 40,
        'sort': ['TRENDING_DESC', 'POPULARITY_DESC'],
        'isAdult': false,
      },
    });
    return parseAnimeResponse(response);
  }

  Future<List<AnimeAiring>> animeAiringWeek(
    DateTime weekStart,
    DateTime weekEnd,
  ) async {
    final response = await api.postJson('/api/anilist', {
      'query': _animeAiringWeekQuery,
      'variables': {
        'weekStart': weekStart.toUtc().millisecondsSinceEpoch ~/ 1000,
        'weekEnd': weekEnd.toUtc().millisecondsSinceEpoch ~/ 1000,
      },
    });
    return parseAnimeAiringResponse(response);
  }

  static List<AnimeAiring> parseAnimeAiringResponse(
    Map<String, dynamic> response,
  ) {
    final page =
        response['data'] is Map ? (response['data'] as Map)['Page'] : null;
    final schedules = page is Map ? page['airingSchedules'] : null;
    if (schedules is! List) return const [];

    final entries = <AnimeAiring>[];
    final seen = <String>{};
    for (final row in schedules.whereType<Map>()) {
      final schedule = Map<String, dynamic>.from(row);
      final airingAt = schedule['airingAt'];
      final episode = schedule['episode'];
      final media = schedule['media'];
      if (airingAt is! num || episode is! num || media is! Map) continue;
      if (media['isAdult'] == true) continue;
      final parsedMedia = parseAnimeResponse({
        'data': {
          'Page': {
            'media': [Map<String, dynamic>.from(media)],
          },
        },
      });
      if (parsedMedia.isEmpty || !seen.add(parsedMedia.first.id)) continue;
      entries.add(AnimeAiring(
        airingAt: DateTime.fromMillisecondsSinceEpoch(
          airingAt.toInt() * 1000,
          isUtc: true,
        ).toLocal(),
        episode: episode.toInt(),
        media: parsedMedia.first,
      ));
    }
    entries.sort((a, b) => a.airingAt.compareTo(b.airingAt));
    return entries;
  }

  /// Converts the web app's AniList response into the shared poster-card model.
  /// AniList supplies anime-only records; the format guard excludes music and
  /// other non-episodic formats so this page contains movies and series only.
  static List<MediaItem> parseAnimeResponse(Map<String, dynamic> response) {
    final page =
        response['data'] is Map ? (response['data'] as Map)['Page'] : null;
    final rows = page is Map ? page['media'] : null;
    if (rows is! List) return const [];
    const seriesFormats = {'TV', 'TV_SHORT', 'OVA', 'ONA', 'SPECIAL'};
    return rows
        .whereType<Map>()
        .map((row) {
          final value = Map<String, dynamic>.from(row);
          final format = value['format']?.toString().toUpperCase() ?? '';
          final type = format == 'MOVIE'
              ? 'movie'
              : seriesFormats.contains(format)
                  ? 'series'
                  : null;
          if (type == null) return null;
          final title = value['title'] is Map
              ? Map<String, dynamic>.from(value['title'] as Map)
              : const <String, dynamic>{};
          final cover = value['coverImage'] is Map
              ? Map<String, dynamic>.from(value['coverImage'] as Map)
              : const <String, dynamic>{};
          final score = (value['averageScore'] as num?)?.toDouble();
          final genres = (value['genres'] as List? ?? const [])
              .map((genre) => genre.toString())
              .toList();
          if (!genres.any((genre) => genre.toLowerCase() == 'anime')) {
            genres.insert(0, 'Anime');
          }
          final description = value['description']?.toString();
          return MediaItem(
            id: 'anilist:${value['id'] ?? ''}',
            type: type,
            name: (title['english'] ??
                    title['romaji'] ??
                    title['native'] ??
                    'AniList #${value['id'] ?? ''}')
                .toString(),
            poster: (cover['extraLarge'] ?? cover['large'])?.toString(),
            description: description == null ? null : _plainText(description),
            releaseInfo: value['seasonYear']?.toString(),
            rating: score == null || score <= 0
                ? null
                : (score / 10).toStringAsFixed(1),
            genres: genres,
          );
        })
        .whereType<MediaItem>()
        .where((item) => item.id != 'anilist:')
        .toList();
  }

  Future<MediaItem?> resolveAnime(MediaItem anime) async {
    final title = anime.name.trim();
    if (title.isEmpty) return null;
    final results = await Future.wait([
      _softList(catalog('movie', 'top', extras: {'search': title})),
      _softList(catalog('series', 'top', extras: {'search': title})),
    ]);
    final candidates = [...results[0], ...results[1]];
    MediaItem? best;
    var bestScore = 0;
    for (final candidate in candidates) {
      final score = _titleMatchScore(candidate.name, title);
      final adjusted = candidate.type == anime.type ? score + 1 : score;
      if (adjusted > bestScore) {
        best = candidate;
        bestScore = adjusted;
      }
    }
    return bestScore >= 40 ? best : null;
  }

  Future<List<MediaItem>> kids({bool series = false}) async {
    final type = series ? 'series' : 'movie';
    final results = await Future.wait([
      _capture(catalog(type, 'top', extras: {'genre': 'Family'})),
      _capture(catalog(type, 'top', extras: {'genre': 'Kids'})),
    ]);
    if (results.every((result) => result.$2 != null)) {
      throw const CatalogLoadException('Could not load Kids catalogs.');
    }
    final safeItems = _merge(results.map((result) => result.$1).toList())
        .where(ContentClassifier.isKidSuitable)
        .toList();
    assert(safeItems.every(ContentClassifier.isKidSuitable));
    assert(safeItems.every((item) => !ContentClassifier.isAnime(item)));
    return safeItems;
  }

  Future<List<MediaItem>> addonCatalogs(
    List<Addon> addons, {
    bool showAll = false,
  }) async {
    final jobs = <Future<List<MediaItem>>>[];
    for (final addon in addons.where((a) => a.enabled)) {
      for (final definition in addon.catalogs
          .where((c) => c.type == 'movie' || c.type == 'series')
          .take(showAll ? 50 : 2)) {
        jobs.add(catalog(definition.type, definition.id, addon: addon));
      }
      if (jobs.length >= (showAll ? 100 : 8)) break;
    }
    return _merge(await Future.wait(jobs.map(_softList)));
  }

  Future<List<Map<String, dynamic>>> streams(
    String type,
    String id,
    List<Addon> addons,
  ) async {
    final supported = addons
        .where((a) => a.enabled && a.supports('stream', type, id))
        .toList();
    final results = await Future.wait(
      supported.map((addon) async {
        try {
          final data = await api.proxyGet(
            _resourceUrl(addon.baseUrl, 'stream', type, id, const {}),
          );
          return (data['streams'] as List? ?? const [])
              .whereType<Map>()
              .map(
                (e) => <String, dynamic>{
                  ...Map<String, dynamic>.from(e),
                  'addonName': addon.name,
                },
              )
              .toList();
        } catch (_) {
          return <Map<String, dynamic>>[];
        }
      }),
    );
    final merged = results.expand((e) => e).toList();
    final keys = <String>{};
    return merged.where((stream) {
      final key = (stream['url'] ?? stream['infoHash'] ?? stream['title'] ?? '')
          .toString();
      return key.isNotEmpty && keys.add(key);
    }).toList();
  }

  Future<List<Map<String, dynamic>>> subtitles(
    String type,
    String id,
    List<Addon> addons,
  ) async {
    final supported = addons.where(
        (addon) => addon.enabled && addon.supports('subtitles', type, id));
    final result = await Future.wait(supported.map((addon) async {
      try {
        final response = await api.proxyGet(
          _resourceUrl(addon.baseUrl, 'subtitles', type, id, const {}),
        );
        return (response['subtitles'] as List? ?? const [])
            .whereType<Map>()
            .map((row) => <String, dynamic>{
                  ...Map<String, dynamic>.from(row),
                  'addonName': addon.name,
                })
            .where((row) =>
                row['url'] is String && (row['url'] as String).isNotEmpty)
            .toList();
      } catch (_) {
        return <Map<String, dynamic>>[];
      }
    }));
    return result.expand((rows) => rows).toList();
  }

  Future<Map<String, dynamic>> manifest(String rawUrl) async {
    var url = rawUrl.trim().replaceFirst(
          RegExp(r'^stremio://', caseSensitive: false),
          'https://',
        );
    url = url
        .replaceFirst(RegExp(r'/configure/?$'), '')
        .replaceFirst(RegExp(r'/+$'), '');
    if (!url.endsWith('manifest.json')) url = '$url/manifest.json';
    final data = await api.proxyGet(url);
    if (data['id'] is! String || data['name'] is! String) {
      throw const FormatException('رابط الإضافة لا يحتوي على manifest صالح.');
    }
    return data;
  }

  Future<List<MediaItem>> _softList(Future<List<MediaItem>> job) async {
    try {
      return await job;
    } catch (_) {
      return [];
    }
  }

  List<MediaItem> _merge(List<List<MediaItem>> groups) =>
      _unique(groups.expand((e) => e).toList());

  List<MediaItem> _unique(List<MediaItem> items) {
    final seen = <String>{};
    return items.where((e) => e.id.isNotEmpty && seen.add(e.id)).toList();
  }

  String _resourceUrl(
    String base,
    String resource,
    String type,
    String id,
    Map<String, dynamic> extras,
  ) {
    var path = '$base/$resource/$type/${Uri.encodeComponent(id)}';
    if (extras.isNotEmpty) {
      final encoded = extras.entries
          .where(
            (entry) => entry.value != null && entry.value.toString().isNotEmpty,
          )
          .map(
            (entry) =>
                '${entry.key}=${Uri.encodeComponent(entry.value.toString())}',
          )
          .join('&');
      if (encoded.isNotEmpty) path += '/$encoded';
    }
    return '$path.json';
  }

  static int _titleMatchScore(String candidate, String title) {
    String normalize(String value) => value
        .toLowerCase()
        // Cinemeta and TMDB may return Arabic titles when the selected
        // language is Arabic; retain those letters while dropping punctuation.
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff]'), '');
    final a = normalize(candidate);
    final b = normalize(title);
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 100;
    if (a.startsWith(b) || b.startsWith(a)) return 70;
    return a.contains(b) || b.contains(a) ? 40 : 0;
  }

  static String _plainText(String value) => value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();
}

class CatalogLoadException implements Exception {
  const CatalogLoadException(this.message);
  final String message;
  @override
  String toString() => message;
}
