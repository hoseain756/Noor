import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/noor_api.dart';
import 'content_classifier.dart';
import '../models/addon.dart';
import '../models/anime_airing.dart';
import '../models/featured_artwork.dart';
import '../models/media_item.dart';

/// One home "catalog rail": an enabled add-on plus one of its catalog
/// entries that deserves its own row (same shape as the Harbor web home
/// `AddonRail`).
class AddonCatalogRow {
  const AddonCatalogRow({required this.addon, required this.catalog});

  final Addon addon;
  final AddonCatalog catalog;

  String get key => '${addon.id}:${catalog.type}:${catalog.id}';
  String get title => catalog.name;
  String get subtitle => addon.name;
}

class CatalogRepository {
  CatalogRepository(this.api);

  final NoorApi api;
  static const _cinemeta = 'https://v3-cinemeta.strem.io';
  static const _animeQuery = r'''
query ($page: Int, $perPage: Int, $sort: [MediaSort], $isAdult: Boolean) {
  Page(page: $page, perPage: $perPage) {
    media(sort: $sort, type: ANIME, isAdult: $isAdult) {
      id
      idMal
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
        idMal
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
  final Map<String, Map<String, dynamic>> _detailEnrichmentCache = {};
  final Map<String, Future<FeaturedArtwork?>> _featuredArtworkRequests = {};

  Future<List<MediaItem>> catalog(
    String type,
    String id, {
    Map<String, dynamic> extras = const {},
    Addon? addon,
  }) async {
    final base = addon?.baseUrl ?? _cinemeta;
    // Task 122-d: strictly-gated content language. Only a user-installed
    // add-on whose manifest entry for THIS catalog declares `language`
    // support gets the extra appended; every other path — above all the
    // Cinemeta built-in fallback (addon == null) — is requested unchanged,
    // because Cinemeta ignores language extras entirely (live-verified in
    // audit 122-a2) and its manifest declares no language support.
    var requestExtras = extras;
    if (addon != null && !extras.containsKey('language')) {
      final definition =
          addon.catalogs.where((c) => c.type == type && c.id == id).firstOrNull;
      if (definition != null &&
          _declaresLanguageExtra(addon, catalog: definition)) {
        requestExtras = {...extras, 'language': await _contentLanguage()};
      }
    }
    final url = _resourceUrl(base, 'catalog', type, id, requestExtras);
    final data = await api.proxyGet(url);
    final rows = (data['metas'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => MediaItem.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.id.isNotEmpty)
        .toList();
    return _unique(rows);
  }

  Future<MediaItem?> detail(String type, String id, List<Addon> addons) async {
    String? languageExtra;
    for (final addon in addons.where(
      (a) => a.enabled && a.supports('meta', type, id),
    )) {
      // Task 122-d: the `language` extra rides along ONLY when the add-on's
      // manifest declares support (a catalog entry's extras or the legacy
      // manifest-level extraSupported). Every provider stays in the query
      // loop — non-declaring add-ons are requested exactly as before — and
      // the Cinemeta fallback below NEVER gets the extra (English-only,
      // live-verified).
      try {
        final extras = _declaresLanguageExtra(addon)
            ? <String, dynamic>{
                'language': languageExtra ??= await _contentLanguage(),
              }
            : const <String, dynamic>{};
        final url = _resourceUrl(addon.baseUrl, 'meta', type, id, extras);
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
  ///
  /// Task 122-d: callers pass the CONTENT-language basis — [language] is the
  /// full TMDB locale (AppState.contentTmdbLocale) driving text/genre/
  /// overview, and [uiLanguage] feeds the artwork-language picks: this method
  /// normalizes it to its primary subtag for the cache key, the
  /// include_image_language list (`<subtag>`,en,null — the en/null fallback
  /// chain is unchanged) and the localized logo preference.
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
      );
      _detailEnrichmentCache['${item.type}:${item.id}:$language'] = details;
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

  /// Reuses the artwork response for genuine people, production and metadata.
  /// The detail page renders its warm item before this optional enrichment.
  Future<MediaItem> detailEnrichment(MediaItem item,
      {String language = 'en-US', String region = 'US'}) async {
    final key = '${item.type}:${item.id}:$language';
    if (!_detailEnrichmentCache.containsKey(key)) {
      await featuredArtwork(item,
          language: language, region: region, uiLanguage: language);
    }
    final details = _detailEnrichmentCache[key];
    if (details == null) return item;
    // Credits are loaded only for an opened detail page. Home artwork must
    // not pay for the much larger cast payload for every carousel slide.
    Map credits = details['credits'] as Map? ?? const {};
    if (credits.isEmpty && details['id'] != null) {
      try {
        credits = await api.tmdbGet(
            '/${item.type == 'series' ? 'tv' : 'movie'}/${details['id']}/credits',
            language: language);
        details['credits'] = credits;
      } catch (_) {/* Existing addon names remain useful offline. */}
    }
    final crew = (credits['crew'] as List? ?? const [])
        .whereType<Map>()
        .where((person) => const {
              'Director',
              'Writer',
              'Screenplay',
              'Creator',
              'Executive Producer'
            }.contains(person['job']))
        .take(12)
        .toList();
    final creators = (details['created_by'] as List? ?? const [])
        .whereType<Map>()
        .map((person) => {...person, 'job': 'Creator'})
        .toList();
    final directors = crew
        .where((person) => person['job'] == 'Director')
        .map((person) => person['name'])
        .whereType<String>()
        .toList();
    final json = item.toJson();
    void add(String key, Object? value) {
      if (value != null && value.toString().trim().isNotEmpty)
        json[key] = value;
    }

    add('originalTitle', details['original_title'] ?? details['original_name']);
    add('status', details['status']);
    add('language', details['original_language']);
    add('releaseDate', details['release_date'] ?? details['first_air_date']);
    if (item.type == 'series') {
      add('seasonCount', details['number_of_seasons']);
      add('episodeCount', details['number_of_episodes']);
    }
    if ((credits['cast'] as List?)?.isNotEmpty == true)
      json['castMembers'] = credits['cast'];
    if (crew.isNotEmpty || creators.isNotEmpty)
      json['crewMembers'] = [...creators, ...crew];
    if ((details['production_companies'] as List?)?.isNotEmpty == true)
      json['productionCompanies'] = details['production_companies'];
    if (item.director.isEmpty && directors.isNotEmpty)
      json['director'] = directors;
    if (item.originCountry == null)
      json['countries'] = details['production_countries'];
    return MediaItem.fromJson(json);
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
      );
      final tmdbType = seed.type == 'series' ? 'tv' : 'movie';
      final sourceKey = tmdbType == 'tv' ? 'tv_results' : 'movie_results';
      final found =
          (lookup[sourceKey] as List? ?? const []).whereType<Map>().firstOrNull;
      final tmdbId = found?['id'];
      if (tmdbId is! num && tmdbId is! String) return const [];

      final recommendations = await api.tmdbGet(
        '/$tmdbType/${Uri.encodeComponent(tmdbId.toString())}/recommendations',
        query: const {'page': '1'},
        language: language,
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
    final response = await api.anilistPost(
      query: _animeQuery,
      variables: {
        'page': 1,
        'perPage': 40,
        'sort': ['TRENDING_DESC', 'POPULARITY_DESC'],
        'isAdult': false,
      },
    );
    // Task 122-d: a Japanese content language flips the AniList title pick
    // to native-first; every other language keeps the existing order.
    return parseAnimeResponse(
      response,
      preferNativeTitles: await prefersNativeAnimeTitles(),
    );
  }

  Future<List<AnimeAiring>> animeAiringWeek(
    DateTime weekStart,
    DateTime weekEnd,
  ) async {
    final response = await api.anilistPost(
      query: _animeAiringWeekQuery,
      variables: {
        'weekStart': weekStart.toUtc().millisecondsSinceEpoch ~/ 1000,
        'weekEnd': weekEnd.toUtc().millisecondsSinceEpoch ~/ 1000,
      },
    );
    // Task 122-d: same native-title preference as [anime].
    return parseAnimeAiringResponse(
      response,
      preferNativeTitles: await prefersNativeAnimeTitles(),
    );
  }

  static List<AnimeAiring> parseAnimeAiringResponse(
    Map<String, dynamic> response, {
    bool preferNativeTitles = false,
  }) {
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
      final parsedMedia = parseAnimeResponse(
        {
          'data': {
            'Page': {
              'media': [Map<String, dynamic>.from(media)],
            },
          },
        },
        preferNativeTitles: preferNativeTitles,
      );
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
  ///
  /// [preferNativeTitles] (Task 122-d): when the effective content language
  /// is Japanese, callers pass true so the native title wins
  /// (native→english→romaji); the default keeps the historical
  /// english→romaji→native order — AniList exposes no other localized title
  /// fields, so every other content language maps to the default order.
  static List<MediaItem> parseAnimeResponse(
    Map<String, dynamic> response, {
    bool preferNativeTitles = false,
  }) {
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
          // MAL-sourced rows (from malSearch) carry their provider id in
          // both `id` and `idMal` — never misread the MAL id as an AniList
          // media id, or tracker pushes would hit the wrong media.
          final malSourced = value['source']?.toString() == 'mal';
          final idNum = (value['id'] as num?)?.toInt();
          final idMalNum = (value['idMal'] as num?)?.toInt();
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
            id: malSourced ? 'mal:${idNum ?? ''}' : 'anilist:${idNum ?? ''}',
            type: type,
            name: (_animeTitle(title, preferNative: preferNativeTitles) ??
                    '${malSourced ? 'MyAnimeList' : 'AniList'} #${idNum ?? ''}')
                .toString(),
            poster: (cover['extraLarge'] ?? cover['large'])?.toString(),
            description: description == null ? null : _plainText(description),
            releaseInfo: value['seasonYear']?.toString(),
            rating: score == null || score <= 0
                ? null
                : (score / 10).toStringAsFixed(1),
            genres: genres,
            anilistId: malSourced ? null : idNum,
            idMal: malSourced ? (idMalNum ?? idNum) : idMalNum,
          );
        })
        .whereType<MediaItem>()
        .where((item) => item.id != 'anilist:' && item.id != 'mal:')
        .toList();
  }

  /// AniList title-field pick (Task 122-d): english→romaji→native by
  /// default, native→english→romaji when the content language is Japanese
  /// (ja is the one content language AniList has a dedicated field for).
  static Object? _animeTitle(
    Map<String, dynamic> title, {
    required bool preferNative,
  }) =>
      preferNative
          ? (title['native'] ?? title['english'] ?? title['romaji'])
          : (title['english'] ?? title['romaji'] ?? title['native']);

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

  /// Pure selection of add-on catalogs that deserve their own home row —
  /// ported from the Harbor web home `addonRows` memo: enabled add-ons only,
  /// movie/series catalogs only, catalogs that REQUIRE a search term are
  /// skipped, one row per normalized catalog name (first add-on wins), and
  /// `type:id` pairs already rendered as anchor rails are skipped.
  static List<AddonCatalogRow> selectAddonCatalogRows(
    List<Addon> addons, {
    Set<String> anchorKeys = const {},
    int limit = 8,
  }) {
    final seenNames = <String>{};
    final rows = <AddonCatalogRow>[];
    for (final addon in addons) {
      if (rows.length >= limit) break;
      if (!addon.enabled) continue;
      for (final catalog in addon.catalogs) {
        if (rows.length >= limit) break;
        if (catalog.type != 'movie' && catalog.type != 'series') continue;
        if (anchorKeys.contains('${catalog.type}:${catalog.id}')) continue;
        final requiresSearch = catalog.extra.any(
          (entry) => entry['name'] == 'search' && entry['isRequired'] == true,
        );
        if (requiresSearch) continue;
        final name = catalog.name.toLowerCase().trim();
        if (!seenNames.add(name)) continue;
        rows.add(AddonCatalogRow(addon: addon, catalog: catalog));
      }
    }
    return rows;
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
                  // Task 123: add-on identity for the sources page rows
                  // (icon square + per-add-on filter).
                  if (addon.iconUrl != null) 'addonIcon': addon.iconUrl,
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
    // Task 122-d: NO `language` extra here. The add-on model carries extra
    // declarations on catalog entries (plus the legacy manifest-level
    // extraSupported) only — neither is a statement about the subtitles
    // resource, so appending would be blind. The 122-plan contract forbids
    // blind appends; subtitle add-ons keep receiving the unmodified request.
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

  // --------------------------------------------------------------------------
  // Content-language access (Task 122-d)
  // --------------------------------------------------------------------------

  /// Mirrors AppState.settingsStorageKey. This repository is constructed
  /// BEFORE AppState (main.dart) and holds no AppState handle, and its
  /// callers sit outside wave 122-d's ownership — so the persisted settings
  /// blob that AppState._persistSettings maintains is read back here. The
  /// blob IS the webSettings map, making 'contentLanguage' a top-level
  /// entry. An absent/unreadable blob resolves to 'ar' — exactly the seeded
  /// default — and AppState.initialize() re-persists the merged map on every
  /// boot before any request can run.
  static const _settingsStorageKey = 'harbor-web.settings';

  /// The effective content language (seeded default 'ar'), read through the
  /// persisted-settings accessor above. Never throws.
  static Future<String> _contentLanguage() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_settingsStorageKey);
      if (raw == null || raw.isEmpty) return 'ar';
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return 'ar';
      return decoded['contentLanguage']?.toString() ?? 'ar';
    } catch (_) {
      return 'ar';
    }
  }

  /// Japanese is the only content language with a dedicated AniList title
  /// field, so native titles are preferred for ja alone.
  static Future<bool> prefersNativeAnimeTitles() async =>
      await _contentLanguage() == 'ja';

  /// STRICT gate for the addon `language` extra (122-plan contract): true
  /// only when the add-on's manifest itself declares language support —
  /// either the modern per-catalog `extra` entries (optionally narrowed to
  /// the exact [catalog] being fetched) or the legacy manifest-level
  /// `extraSupported` list. Cinemeta declares neither (its extras are
  /// search/genre/skip/...), so the built-in paths can never qualify, and an
  /// ambiguous signal for any other add-on resolves to "no extra".
  static bool _declaresLanguageExtra(Addon addon, {AddonCatalog? catalog}) {
    final candidates = catalog == null ? addon.catalogs : [catalog];
    if (candidates.any(
      (candidate) => candidate.extra
          .any((entry) => entry['name']?.toString() == 'language'),
    )) {
      return true;
    }
    final legacy = addon.manifest['extraSupported'];
    return legacy is List &&
        legacy.any((entry) => entry?.toString() == 'language');
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
        // Cinemeta and TMDB may return localized titles for the selected
        // content language; retain those scripts while dropping punctuation.
        // Arabic shipped first (Task 114); Cyrillic/Devanagari/kana/CJK/
        // Hangul joined with the 11-language content switch (Task 122-d) —
        // without them every localized title normalized to '' and scored 0,
        // dead-ending resolveAnime and the TMDB recommendation lookup.
        .replaceAll(
            RegExp(r'[^a-z0-9\u0400-\u04ff\u0600-\u06ff\u0900-\u097f'
                r'\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]'),
            '');
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
