import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Website-free API layer for Noor.
///
/// Every provider is contacted DIRECTLY from the device — there is no proxy
/// server in the middle anymore. The operator keys ship embedded as static
/// defaults below; users can override the TMDB credential and the Trakt
/// client secret from Settings. Plain (non-secret) state lives in
/// [SharedPreferences], secrets live in [FlutterSecureStorage].
///
/// Storage map:
///  - secure 'noor.tmdb.user-token'      → TMDB credential override (v4 JWT
///    starting with 'eyJ' → Bearer header, otherwise treated as a v3 api_key)
///  - secure 'noor.trakt.client-secret'  → user-provided Trakt OAuth secret
///    (NONE is embedded; written by Settings, picked up live at poll time)
///  - secure `noor.<service>.token`     → linked-service access tokens
///  - prefs  'noor.debrid.service'       → active debrid service name
///  - secure `noor.debrid.<service>`     → debrid API key
///  - secure 'noor.iptv.playlists'       → IPTV playlist JSON
class NoorApi {
  NoorApi({SharedPreferences? preferences}) : _preferences = preferences;

  // --------------------------------------------------------------------------
  // Embedded operator keys (user-overridable where noted)
  // --------------------------------------------------------------------------

  /// TMDB v4 read-access JWT used with `Authorization: Bearer`.
  static const String defaultTmdbToken =
      'eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiJmNTdjMGUzNTVmMmE5NDBhYWUxZTUzNDA4NmI5YWRiNyIsIm5iZiI6MTc4NTQ5MTE1Mi41MzIsInN1YiI6IjZhNmM2ZWQwZGM4ZTU2MGY2MTY1ZTUwNyIsInNjb3BlcyI6WyJhcGlfcmVhZCJdLCJ2ZXJzaW9uIjoxfQ.1bcfeeYR-LuBHJrSsFHHbGMfRL_9DWelu79SWgyOn2U';

  static const String defaultOmdbKey = 'b978cd59';

  static const String defaultMdbListKey = 'ben6ji6z3db5x1pps3wv5okwd';

  static const String defaultTraktClientId =
      'pk0CCmQaUuZt3VqpWu0lphpro_i52wX9QnkbGbf_fUY';

  static const String defaultSimklClientId =
      '77b9125e4f1148d09b4fec74474171a02daefe24272cc1aa8b2efcb4da367bee';

  static const String defaultSimklClientSecret =
      'simkl_cs_bFZ4x7Sgrkc2hhslQDD38LVnkM7D1bI0Ym';

  // NOTE: TRAKT_CLIENT_SECRET is intentionally absent — Trakt device linking
  // requires a user/operator-provided secret stored in secure storage under
  // [_traktSecretKey]. Without it [pollLinkedService] answers
  // `{'error': 'secret_required'}`.

  // --------------------------------------------------------------------------
  // Endpoints & timings
  // --------------------------------------------------------------------------

  static const String tmdbBaseUrl = 'https://api.themoviedb.org/3';
  static const String traktBaseUrl = 'https://api.trakt.tv';
  static const String simklBaseUrl = 'https://api.simkl.com';
  static const String anilistUrl = 'https://graphql.anilist.co';

  static const Duration _connectTimeout = Duration(seconds: 15);
  static const Duration _receiveTimeout = Duration(seconds: 25);
  static const Duration _sendTimeout = Duration(seconds: 20);
  static const Duration _debridTimeout = Duration(seconds: 25);
  static const Duration _ratingsTtl = Duration(hours: 6);

  // --------------------------------------------------------------------------
  // Storage keys
  // --------------------------------------------------------------------------

  static const String _tmdbUserTokenKey = 'noor.tmdb.user-token';
  static const String _legacyTmdbUserTokenKey = 'horse.mobile.tmdb.user-key';
  static const String _traktSecretKey = 'noor.trakt.client-secret';
  static const String _debridServiceKey = 'noor.debrid.service';
  static const String _debridSecretPrefix = 'noor.debrid.';
  static const String _iptvPlaylistsKey = 'noor.iptv.playlists';
  static const String _legacyIptvPlaylistsKey = 'horse.mobile.iptv.playlists';

  String _serviceTokenKey(String service) => 'noor.$service.token';

  // --------------------------------------------------------------------------
  // State
  // --------------------------------------------------------------------------

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  SharedPreferences? _preferences;
  Dio? _dio;

  /// TMDB credential override: v4 JWT ('eyJ…') or 32-hex v3 key.
  String? _tmdbUserToken;

  /// User-provided Trakt OAuth client secret (none is embedded).
  String? _traktClientSecret;

  final Map<String, String> _serviceTokens = <String, String>{};

  String? _debridService;
  String? _debridApiKey;

  final Map<String, _RatingsCacheEntry> _ratingsCache =
      <String, _RatingsCacheEntry>{};
  final Map<String, Future<Map<String, dynamic>>> _ratingsInflight =
      <String, Future<Map<String, dynamic>>>{};

  // --------------------------------------------------------------------------
  // Lifecycle
  // --------------------------------------------------------------------------

  Future<void> initialize() async {
    _preferences ??= await SharedPreferences.getInstance();

    // TMDB override — falls back to the website-proxied build's key so
    // existing users keep working after the migration.
    _tmdbUserToken = await _secure.read(key: _tmdbUserTokenKey);
    if (_tmdbUserToken == null || _tmdbUserToken!.isEmpty) {
      _tmdbUserToken = await _secure.read(key: _legacyTmdbUserTokenKey);
    }

    _traktClientSecret = await _secure.read(key: _traktSecretKey);

    for (final service in const <String>['trakt', 'simkl']) {
      final token = await _secure.read(key: _serviceTokenKey(service));
      if (token != null && token.isNotEmpty) {
        _serviceTokens[service] = token;
      }
    }

    _debridService = _preferences!.getString(_debridServiceKey);
    if (_debridService != null) {
      _debridApiKey = await _secure.read(
        key: '$_debridSecretPrefix$_debridService',
      );
      if (_debridApiKey == null || _debridApiKey!.isEmpty) {
        _debridService = null;
      }
    }
  }

  void dispose() {
    _ratingsCache.clear();
    _ratingsInflight.clear();
    try {
      _dio?.close();
    } catch (_) {
      // Ignore transport teardown issues.
    }
    _dio = null;
  }

  Dio get _client {
    return _dio ??= Dio(
      BaseOptions(
        connectTimeout: _connectTimeout,
        receiveTimeout: _receiveTimeout,
        sendTimeout: _sendTimeout,
        headers: <String, dynamic>{'Accept': 'application/json'},
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Generic passthrough (replaces the website /api/proxy + /api/proxy/raw)
  // --------------------------------------------------------------------------

  /// GETs [url] directly and returns the decoded JSON body (or plain text
  /// when the payload is not JSON).
  Future<dynamic> proxyGet(String url, {Map<String, String>? headers}) async {
    final response = await _client.get<dynamic>(
      url,
      options: Options(headers: headers),
    );
    return response.data;
  }

  /// GETs [url] directly and returns the raw body as text (M3U / XML sources).
  Future<String> proxyText(String url, {Map<String, String>? headers}) async {
    final response = await _client.get<String>(
      url,
      options: Options(headers: headers, responseType: ResponseType.plain),
    );
    final text = response.data;
    if (text == null || text.isEmpty) {
      throw const FormatException('Empty response body.');
    }
    return text;
  }

  // --------------------------------------------------------------------------
  // TMDB (direct — https://api.themoviedb.org/3)
  // --------------------------------------------------------------------------

  bool get hasUserTmdbKey {
    final key = _tmdbUserToken;
    return key != null && key.isNotEmpty;
  }

  bool _isJwt(String value) => value.startsWith('eyJ');

  /// Resolves the credential actually used: the user override when present,
  /// otherwise the embedded operator token.
  String get _tmdbCredential {
    final key = _tmdbUserToken;
    return (key != null && key.isNotEmpty) ? key : defaultTmdbToken;
  }

  String _normalizeTmdbPath(String path) =>
      path.startsWith('/') ? path : '/$path';

  /// GETs a TMDB path. v4-token credentials go into the Authorization header,
  /// v3 keys into the `api_key` query parameter.
  Future<dynamic> tmdbGet(
    String path, {
    Map<String, String>? query,
    String? language,
  }) async {
    final credential = _tmdbCredential;
    final parsed = Uri.parse(
      path.startsWith('http')
          ? path
          : '$tmdbBaseUrl${_normalizeTmdbPath(path)}',
    );
    final params = <String, String>{
      ...parsed.queryParameters,
      ...?query,
      if (language != null && language.isNotEmpty) 'language': language,
      if (!_isJwt(credential)) 'api_key': credential,
    };
    final uri = parsed.replace(queryParameters: params);
    final response = await _client.get<dynamic>(
      uri.toString(),
      options: Options(
        headers: <String, String>{
          if (_isJwt(credential)) 'Authorization': 'Bearer $credential',
        },
      ),
    );
    return response.data;
  }

  /// Live-checks a TMDB credential against /configuration.
  Future<bool> validateTmdbUserKey(String value) async {
    final credential = value.trim();
    if (credential.isEmpty) return false;
    try {
      final uri = Uri.parse('$tmdbBaseUrl/configuration').replace(
        queryParameters: <String, String>{
          if (!_isJwt(credential)) 'api_key': credential,
        },
      );
      final response = await _client.get<dynamic>(
        uri.toString(),
        options: Options(
          headers: <String, String>{
            if (_isJwt(credential)) 'Authorization': 'Bearer $credential',
          },
        ),
      );
      final data = response.data;
      return data is Map && data['images'] != null;
    } catch (_) {
      return false;
    }
  }

  /// Validates then persists the TMDB credential in secure storage.
  Future<void> saveTmdbUserKey(String value) async {
    final credential = value.trim();
    if (credential.isEmpty) {
      throw const FormatException('Enter a TMDB key first.');
    }
    if (!await validateTmdbUserKey(credential)) {
      throw const FormatException('TMDB key validation failed.');
    }
    await _secure.write(key: _tmdbUserTokenKey, value: credential);
    _tmdbUserToken = credential;
  }

  Future<void> clearTmdbUserKey() async {
    await _secure.delete(key: _tmdbUserTokenKey);
    _tmdbUserToken = null;
  }

  // --------------------------------------------------------------------------
  // Ratings (direct — replaces the website /api/ratings aggregate)
  // --------------------------------------------------------------------------

  /// Aggregated provider ratings for a title. Never throws; every provider
  /// key is always present and is null when that provider had nothing:
  /// `{imdb, rottenTomatoes, metacritic, tmdb, trakt, mdblist}` →
  /// `{rating, votes} | null`.
  Future<dynamic> ratingsGet({
    required String type,
    required String title,
    String? year,
    String? imdb,
    bool anime = false,
  }) async {
    final key = <String>[
      type.toLowerCase(),
      title.trim().toLowerCase(),
      year ?? '',
      imdb ?? '',
      anime ? 'anime' : 'live',
    ].join('|');

    final cached = _ratingsCache[key];
    if (cached != null) {
      if (cached.expiry.isAfter(DateTime.now())) return cached.data;
      _ratingsCache.remove(key);
    }

    final inflight = _ratingsInflight[key];
    if (inflight != null) return inflight;

    final future = _fetchRatings(
      type: type,
      title: title,
      year: year,
      imdb: imdb,
      anime: anime,
    );
    _ratingsInflight[key] = future;
    Map<String, dynamic> data;
    try {
      data = await future;
    } finally {
      _ratingsInflight.remove(key);
    }
    _ratingsCache[key] = _RatingsCacheEntry(
      data,
      DateTime.now().add(_ratingsTtl),
    );
    return data;
  }

  Future<Map<String, dynamic>> _fetchRatings({
    required String type,
    required String title,
    required String? year,
    required String? imdb,
    required bool anime,
  }) async {
    final result = <String, dynamic>{
      'imdb': null,
      'rottenTomatoes': null,
      'metacritic': null,
      'tmdb': null,
      'trakt': null,
      'mdblist': null,
    };
    try {
      final kind = type.toLowerCase() == 'series' ? 'series' : 'movie';

      // OMDb answers IMDb + Rotten Tomatoes + Metacritic in one call; TMDB
      // and Trakt run concurrently with it.
      final omdbFuture = _ratingsFromOmdb(kind: kind, title: title, year: year);
      final traktFuture = _ratingsFromTrakt(kind: kind, title: title);
      final tmdbFuture = _ratingsFromTmdb(
        kind: kind,
        title: title,
        year: year,
        imdb: imdb,
        anime: anime,
      );

      final omdb = await omdbFuture;
      result['imdb'] = omdb?['imdb'];
      result['rottenTomatoes'] = omdb?['rottenTomatoes'];
      result['metacritic'] = omdb?['metacritic'];

      final trakt = await traktFuture;
      result['trakt'] = trakt;

      // TMDB also yields the id MDBList needs; skipped when absent.
      final tmdb = await tmdbFuture;
      if (tmdb != null) {
        result['tmdb'] = <String, dynamic>{
          'rating': _asDouble(tmdb['vote_average']),
          'votes': _asInt(tmdb['vote_count']),
        };
        final tmdbId = tmdb['id'];
        if (tmdbId is num || tmdbId is String) {
          result['mdblist'] = await _ratingsFromMdbList(
            kind: kind,
            tmdbId: tmdbId.toString(),
          );
        }
      }
      return result;
    } catch (_) {
      return result; // Partial data beats a crash — never rethrow.
    }
  }

  Future<Map<String, dynamic>?> _ratingsFromOmdb({
    required String kind,
    required String title,
    required String? year,
  }) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        'https://www.omdbapi.com/',
        queryParameters: <String, String>{
          'apikey': defaultOmdbKey,
          't': title,
          'type': kind, // OMDb expects movie|series
          if (year != null && year.isNotEmpty) 'y': year,
        },
      );
      final data = response.data;
      if (data == null || data['Response'] != 'True') return null;
      final rating = _asDouble(data['imdbRating']);
      final votes = _asInt(data['imdbVotes']);
      num? tomatoes;
      num? metacritic;
      for (final entry
          in (data['Ratings'] as List? ?? const <dynamic>[])) {
        if (entry is! Map) continue;
        final source = entry['Source']?.toString();
        if (source == 'Rotten Tomatoes') {
          tomatoes = _asPercent(entry['Value']);
        } else if (source == 'Metacritic') {
          metacritic = _asPercent(entry['Value']);
        }
      }
      metacritic ??= _asPercent(data['Metascore']);
      return <String, dynamic>{
        'imdb': (rating == null && votes == null)
            ? null
            : <String, dynamic>{'rating': rating, 'votes': votes},
        'rottenTomatoes': tomatoes == null
            ? null
            : <String, dynamic>{'rating': tomatoes, 'votes': null},
        'metacritic': metacritic == null
            ? null
            : <String, dynamic>{'rating': metacritic, 'votes': null},
      };
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _ratingsFromTmdb({
    required String kind,
    required String title,
    required String? year,
    required String? imdb,
    required bool anime,
  }) async {
    try {
      Map<String, dynamic>? match;
      if (imdb != null && imdb.isNotEmpty) {
        final found = await tmdbGet(
          '/find/${Uri.encodeComponent(imdb)}',
          query: const <String, String>{'external_source': 'imdb_id'},
        );
        final results = found is Map
            ? (found[kind == 'series' ? 'tv_results' : 'movie_results']
                    as List? ??
                const <dynamic>[])
            : const <dynamic>[];
        if (results.isNotEmpty && results.first is Map) {
          match = Map<String, dynamic>.from(results.first as Map);
        }
      }
      match ??= await _tmdbSearchMatch(kind, title, year, anime);
      if (match == null) return null;
      // /find payloads are sparse — fetch the details object for scores.
      if (match['vote_average'] == null && match['id'] != null) {
        final details = await tmdbGet(
          '/${kind == 'series' ? 'tv' : 'movie'}/${match['id']}',
        );
        if (details is Map) match = Map<String, dynamic>.from(details);
      }
      return match;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _tmdbSearchMatch(
    String kind,
    String title,
    String? year,
    bool anime,
  ) async {
    try {
      final params = <String, String>{'query': title};
      // Anime release years frequently mismatch catalog metadata, so the
      // year filter is only applied to non-anime lookups.
      if (year != null && year.isNotEmpty && !anime) {
        params[kind == 'series' ? 'first_air_date_year' : 'year'] = year;
      }
      final data = await tmdbGet(
        kind == 'series' ? '/search/tv' : '/search/movie',
        query: params,
      );
      final results = data is Map
          ? (data['results'] as List? ?? const <dynamic>[])
          : const <dynamic>[];
      if (results.isEmpty || results.first is! Map) return null;
      return Map<String, dynamic>.from(results.first as Map);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _ratingsFromTrakt({
    required String kind,
    required String title,
  }) async {
    try {
      final slug = _traktSlug(title);
      if (slug.isEmpty) return null;
      final response = await _client.get<dynamic>(
        '$traktBaseUrl/${kind == 'series' ? 'shows' : 'movies'}/$slug/ratings',
        options: Options(
          headers: <String, String>{
            'trakt-api-version': '2',
            'trakt-api-key': defaultTraktClientId,
          },
        ),
      );
      final data = response.data;
      if (data is! Map) return null;
      final rating = _asDouble(data['rating']);
      final votes = _asInt(data['votes']);
      if (rating == null && votes == null) return null;
      return <String, dynamic>{'rating': rating, 'votes': votes};
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _ratingsFromMdbList({
    required String kind,
    required String tmdbId,
  }) async {
    try {
      final response = await _client.get<dynamic>(
        'https://api.mdblist.com/tmdb/${kind == 'series' ? 'show' : 'movie'}'
        '/$tmdbId',
        queryParameters: <String, String>{'apikey': defaultMdbListKey},
      );
      final data = response.data;
      if (data is! Map) return null;
      var score = _asDouble(data['score_average']) ??
          _asDouble(data['score']) ??
          _asDouble(data['rating']);
      if (score == null && data['scores'] is Map) {
        final scores = Map<String, dynamic>.from(data['scores'] as Map);
        score = _asDouble(scores['score_average']) ??
            _asDouble(scores['average']);
      }
      if (score == null) return null;
      return <String, dynamic>{'rating': score, 'votes': null};
    } catch (_) {
      return null;
    }
  }

  // --------------------------------------------------------------------------
  // AniList (direct GraphQL)
  // --------------------------------------------------------------------------

  /// POSTs a GraphQL document to https://graphql.anilist.co and returns the
  /// decoded response.
  Future<dynamic> anilistPost({
    required String query,
    Map<String, dynamic>? variables,
  }) async {
    final response = await _client.post<dynamic>(
      anilistUrl,
      data: <String, dynamic>{
        'query': query,
        'variables': variables ?? const <String, dynamic>{},
      },
      options: Options(
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
    return response.data;
  }

  // --------------------------------------------------------------------------
  // Debrid (direct — Real-Debrid / AllDebrid / TorBox)
  // --------------------------------------------------------------------------

  /// Verifies a debrid API key and returns `{name, expires?}`, or null when
  /// the key is invalid / the service is unknown.
  Future<Map<String, dynamic>?> verifyDebridKey({
    required String service,
    required String apiKey,
  }) async {
    try {
      switch (service) {
        case 'realdebrid':
          {
            final response = await _client.get<dynamic>(
              'https://api.real-debrid.com/rest/1.0/user',
              options: _debridGetOptions(<String, String>{
                'Authorization': 'Bearer $apiKey',
              }),
            );
            final user = _asMap(response.data);
            final name = user?['username']?.toString();
            if (name == null || name.isEmpty) return null;
            return <String, dynamic>{
              'name': name,
              'expires': _expiryString(user),
            };
          }
        case 'alldebrid':
          {
            final response = await _client.get<dynamic>(
              'https://api.alldebrid.com/v4/user',
              queryParameters: <String, String>{
                'agent': 'noor',
                'apikey': apiKey,
              },
            );
            final user =
                _asMap(_asMap(_asMap(response.data)?['data'])?['user']);
            final name = user?['username']?.toString();
            if (name == null || name.isEmpty) return null;
            return <String, dynamic>{
              'name': name,
              'expires': _expiryString(user),
            };
          }
        case 'torbox':
          {
            final response = await _client.get<dynamic>(
              'https://torbox.app/api/users/me',
              options: _debridGetOptions(<String, String>{
                'Authorization': 'Bearer $apiKey',
              }),
            );
            final user = _asMap(_asMap(response.data)?['data']);
            final name = user?['email']?.toString();
            if (name == null || name.isEmpty) return null;
            return <String, dynamic>{
              'name': name,
              'expires': _expiryString(user),
            };
          }
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDebridKey({
    required String service,
    required String apiKey,
  }) async {
    final prefs = _preferences ??= await SharedPreferences.getInstance();
    final previous = _debridService;
    if (previous != null && previous != service) {
      await _secure.delete(key: '$_debridSecretPrefix$previous');
    }
    await _secure.write(key: '$_debridSecretPrefix$service', value: apiKey);
    await prefs.setString(_debridServiceKey, service);
    _debridService = service;
    _debridApiKey = apiKey;
  }

  Future<void> clearDebridKey() async {
    final service = _debridService;
    if (service != null) {
      await _secure.delete(key: '$_debridSecretPrefix$service');
    }
    await _preferences?.remove(_debridServiceKey);
    _debridService = null;
    _debridApiKey = null;
  }

  String? get debridService => _debridService;

  String? get debridApiKey => _debridApiKey;

  /// Resolves a torrent to a DIRECT playable URL using the linked debrid
  /// service. Returns null when no service is linked or anything goes wrong.
  Future<String?> resolveDebridTorrent({
    required String infoHash,
    String? filename,
    int? filesize,
  }) async {
    final service = _debridService;
    final apiKey = _debridApiKey;
    if (service == null || apiKey == null || apiKey.isEmpty) return null;
    final hash = infoHash.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9]{32,64}$').hasMatch(hash)) return null;
    final magnet = 'magnet:?xt=urn:btih:$hash'
        '${(filename == null || filename.isEmpty) ? '' : '&dn=${Uri.encodeComponent(filename)}'}';
    try {
      switch (service) {
        case 'realdebrid':
          return await _resolveRealDebrid(
            magnet: magnet,
            apiKey: apiKey,
            filename: filename,
            filesize: filesize,
          );
        case 'alldebrid':
          return await _resolveAllDebrid(
            magnet: magnet,
            apiKey: apiKey,
            filename: filename,
            filesize: filesize,
          );
        case 'torbox':
          return await _resolveTorbox(
            magnet: magnet,
            apiKey: apiKey,
            infoHash: hash,
            filename: filename,
            filesize: filesize,
          );
        default:
          return null;
      }
    } catch (_) {
      return null; // Playback must degrade gracefully, never crash.
    }
  }

  Future<String?> _resolveRealDebrid({
    required String magnet,
    required String apiKey,
    required String? filename,
    required int? filesize,
  }) async {
    final auth = <String, String>{'Authorization': 'Bearer $apiKey'};

    // 1. Only continue when the torrent is instantly available (cached).
    final availability = await _client.post<dynamic>(
      'https://api.real-debrid.com/rest/1.0/torrents/instantAvailable',
      data: <String>[magnet],
      options: _debridJsonOptions(auth),
    );
    final available = availability.data;
    if (available is! List || available.isEmpty || available.first != true) {
      return null;
    }

    // 2. Add the magnet (RD expects a form-encoded `magnet` field).
    final added = await _client.post<dynamic>(
      'https://api.real-debrid.com/rest/1.0/torrents/addTorrent',
      data: 'magnet=${Uri.encodeComponent(magnet)}',
      options: _debridFormOptions(auth),
    );
    final torrentId = _asMap(added.data)?['id']?.toString();
    if (torrentId == null || torrentId.isEmpty) return null;

    // 3. Read the torrent info and choose the file to play.
    final info = await _client.get<dynamic>(
      'https://api.real-debrid.com/rest/1.0/torrents/info/$torrentId',
      options: _debridGetOptions(auth),
    );
    final torrent = _asMap(info.data);
    final links = torrent?['links'] as List? ?? const <dynamic>[];
    if (links.isEmpty) return null;
    final files = (torrent?['files'] as List? ?? const <dynamic>[])
        .whereType<Map>()
        .map(_asMap)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final link = _pickRealDebridLink(
      files: files,
      links: links,
      filename: filename,
      filesize: filesize,
    );
    if (link == null || link.isEmpty) return null;

    // 4. Unlock the hoster link into a direct download URL.
    final unlocked = await _client.post<dynamic>(
      'https://api.real-debrid.com/rest/1.0/links/unlock',
      data: <String, String>{'link': link},
      options: _debridJsonOptions(auth),
    );
    final download = _asMap(unlocked.data)?['download']?.toString();
    return (download == null || download.isEmpty) ? null : download;
  }

  Future<String?> _resolveAllDebrid({
    required String magnet,
    required String apiKey,
    required String? filename,
    required int? filesize,
  }) async {
    final base = <String, String>{'agent': 'noor', 'apikey': apiKey};

    // 1. Upload the magnet.
    final uploaded = await _client.post<dynamic>(
      'https://api.alldebrid.com/v4/magnet/upload',
      queryParameters: base,
      data: 'magnets[]=${Uri.encodeComponent(magnet)}',
      options: _debridFormOptions(const <String, String>{}),
    );
    final magnets =
        _asMap(_asMap(uploaded.data)?['data'])?['magnets'] as List?;
    if (magnets == null || magnets.isEmpty) return null;
    final magnetId = _asMap(magnets.first)?['id']?.toString();
    if (magnetId == null || magnetId.isEmpty) return null;

    // 2. Poll the magnet status until it is ready (~20 s budget).
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    Map<String, dynamic>? magnetInfo;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      final response = await _client.get<dynamic>(
        'https://api.alldebrid.com/v4/magnet/status',
        queryParameters: <String, String>{...base, 'id': magnetId},
      );
      final rows =
          _asMap(_asMap(response.data)?['data'])?['magnets'] as List?;
      if (rows == null || rows.isEmpty) return null;
      magnetInfo = _asMap(rows.first);
      final code = (magnetInfo?['statusCode'] as num?)?.toInt() ?? -1;
      if (code >= 5) return null; // Dead / unsupported / error states.
      final links = magnetInfo?['links'] as List?;
      if (code >= 4 && links != null && links.isNotEmpty) break;
      magnetInfo = null;
    }

    // 3. Unlock the link matching the requested file.
    final links = magnetInfo?['links'] as List? ?? const <dynamic>[];
    if (links.isEmpty) return null;
    final link = _pickAllDebridLink(links, filename, filesize);
    if (link == null || link.isEmpty) return null;
    final unlocked = await _client.post<dynamic>(
      'https://api.alldebrid.com/v4/link/unlock',
      queryParameters: base,
      data: <String, String>{'link': link},
      options: _debridJsonOptions(const <String, String>{}),
    );
    final direct = _asMap(_asMap(unlocked.data)?['data'])?['link']?.toString();
    return (direct == null || direct.isEmpty) ? null : direct;
  }

  Future<String?> _resolveTorbox({
    required String magnet,
    required String apiKey,
    required String infoHash,
    required String? filename,
    required int? filesize,
  }) async {
    final auth = <String, String>{'Authorization': 'Bearer $apiKey'};

    // 1. Create the torrent (seed 3 keeps the TorBox tracker happy).
    final created = await _client.post<dynamic>(
      'https://torbox.app/api/torrents/createtorrent',
      data: <String, dynamic>{'magnet': magnet, 'seed': 3},
      options: _debridJsonOptions(auth),
    );
    final createdMap = _asMap(created.data);
    if (createdMap == null || createdMap['success'] == false) return null;
    final torrentId = _asMap(createdMap['data'])?['torrent_id']?.toString();
    if (torrentId == null || torrentId.isEmpty || torrentId == 'null') {
      return null;
    }

    // 2. Look the torrent up by hash and find the file to play. The file
    //    list appears once metadata is ready, hence the short retry loop.
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    Map<String, dynamic>? torrent;
    var files = const <Map<String, dynamic>>[];
    while (true) {
      final mylist = await _client.get<dynamic>(
        'https://torbox.app/api/torrents/mylist',
        queryParameters: <String, String>{
          'search': infoHash,
          'bypass_cache': 'true',
        },
        options: _debridGetOptions(auth),
      );
      final rows = _asMap(mylist.data)?['data'] as List?;
      if (rows != null) {
        for (final row in rows) {
          final rowMap = _asMap(row);
          final hash = rowMap?['hash']?.toString().toLowerCase();
          if (hash == infoHash) {
            torrent = rowMap;
            break;
          }
        }
        torrent ??= rows.isNotEmpty ? _asMap(rows.first) : null;
      }
      files = (torrent?['files'] as List? ?? const <dynamic>[])
          .whereType<Map>()
          .map(_asMap)
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
      if (files.isNotEmpty || !DateTime.now().isBefore(deadline)) break;
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    if (files.isEmpty) return null;

    final fileIndex = _matchFileIndex(files, filename, filesize);
    final file =
        fileIndex >= 0 ? files[fileIndex] : files[_largestFileIndex(files)];
    final fileId = (file['file_id'] ?? file['id'])?.toString();
    if (fileId == null || fileId.isEmpty || fileId == 'null') return null;

    // 3. Request the direct download URL for the chosen file.
    final request = await _client.get<dynamic>(
      'https://torbox.app/api/torrents/requestdl',
      queryParameters: <String, String>{
        'token': apiKey,
        'torrent_id': torrentId,
        'file_id': fileId,
      },
      options: _debridGetOptions(auth),
    );
    final requestMap = _asMap(request.data);
    if (requestMap == null || requestMap['success'] == false) return null;
    final url = requestMap['data']?.toString() ?? '';
    return url.startsWith('http') ? url : null;
  }

  String? _pickRealDebridLink({
    required List<Map<String, dynamic>> files,
    required List<dynamic> links,
    required String? filename,
    required int? filesize,
  }) {
    if (links.isEmpty) return null;
    if (links.length == 1 || files.isEmpty) return links.first?.toString();
    // RD aligns links[] with the *selected* files, in order.
    final selected = files
        .where((file) => file['selected'] == 1 || file['selected'] == true)
        .toList(growable: false);
    final ordered = selected.isNotEmpty ? selected : files;
    var index = _matchFileIndex(ordered, filename, filesize);
    if (index < 0) {
      // Fall back to the biggest file (RD's default magnet selection).
      index = _largestFileIndex(ordered);
    }
    if (index < 0 || index >= links.length) return links.first?.toString();
    return links[index]?.toString();
  }

  String? _pickAllDebridLink(
    List<dynamic> links,
    String? filename,
    int? filesize,
  ) {
    final entries = links
        .whereType<Map>()
        .map(_asMap)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    if (entries.isEmpty) return null;
    if (entries.length == 1) return entries.first['link']?.toString();
    final wanted = filename?.trim().toLowerCase() ?? '';
    if (wanted.isNotEmpty) {
      for (final entry in entries) {
        final name = entry['name']?.toString().toLowerCase() ?? '';
        if (name.contains(wanted)) return entry['link']?.toString();
      }
    }
    if (filesize != null && filesize > 0) {
      for (final entry in entries) {
        if (_fileBytes(entry) == filesize) return entry['link']?.toString();
      }
    }
    return entries[_largestFileIndex(entries)]['link']?.toString();
  }

  int _matchFileIndex(
    List<Map<String, dynamic>> files,
    String? filename,
    int? filesize,
  ) {
    final wanted = filename?.trim().toLowerCase() ?? '';
    if (wanted.isNotEmpty) {
      for (var i = 0; i < files.length; i++) {
        final path = files[i]['path']?.toString() ??
            files[i]['name']?.toString() ??
            '';
        final base = path.split('/').last.toLowerCase();
        if (base.contains(wanted)) return i;
      }
    }
    if (filesize != null && filesize > 0) {
      for (var i = 0; i < files.length; i++) {
        if (_fileBytes(files[i]) == filesize) return i;
      }
    }
    return -1;
  }

  int _largestFileIndex(List<Map<String, dynamic>> files) {
    if (files.isEmpty) return -1;
    var best = 0;
    for (var i = 1; i < files.length; i++) {
      if (_fileBytes(files[i]) > _fileBytes(files[best])) best = i;
    }
    return best;
  }

  int _fileBytes(Map<String, dynamic> file) {
    final value = file['bytes'] ?? file['size'] ?? file['filesize'];
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  Options _debridGetOptions(Map<String, String> headers) => Options(
        sendTimeout: _debridTimeout,
        receiveTimeout: _debridTimeout,
        headers: headers,
      );

  Options _debridJsonOptions(Map<String, String> headers) => Options(
        sendTimeout: _debridTimeout,
        receiveTimeout: _debridTimeout,
        headers: <String, dynamic>{
          ...headers,
          'Content-Type': 'application/json',
        },
      );

  Options _debridFormOptions(Map<String, String> headers) => Options(
        sendTimeout: _debridTimeout,
        receiveTimeout: _debridTimeout,
        headers: <String, dynamic>{
          ...headers,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
      );

  /// Normalizes the various premium-expiry field names providers use.
  String? _expiryString(Map<String, dynamic>? user) {
    if (user == null) return null;
    for (final key in const <String>[
      'expiration',
      'expires',
      'expiresAt',
      'premium_expires',
      'premium_expiration',
    ]) {
      final value = user[key];
      if (value == null) continue;
      final text = value.toString();
      // TorBox answers with Go's zero time when there is no premium.
      if (text.isEmpty || text.startsWith('0001-')) continue;
      return text;
    }
    final until = user['premiumUntil'];
    if (until is num && until > 0) {
      return DateTime.fromMillisecondsSinceEpoch(until.toInt() * 1000)
          .toIso8601String();
    }
    return null;
  }

  // --------------------------------------------------------------------------
  // Linked services (direct device flow — Trakt / Simkl)
  // --------------------------------------------------------------------------

  bool isLinked(String service) => _serviceTokens[service]?.isNotEmpty ?? false;

  /// Starts the device-link flow: Trakt → POST /oauth/device/code, Simkl →
  /// POST /oauth/device. Returns the provider payload (device_code, user_code,
  /// verification_url, expires_in, interval) or null on failure.
  Future<Map<String, dynamic>?> startLinkedService(String service) async {
    try {
      switch (service) {
        case 'trakt':
          {
            final response = await _client.post<dynamic>(
              '$traktBaseUrl/oauth/device/code',
              data: <String, String>{'client_id': defaultTraktClientId},
              options: Options(
                headers: <String, String>{
                  'Content-Type': 'application/json',
                  'trakt-api-version': '2',
                  'trakt-api-key': defaultTraktClientId,
                },
              ),
            );
            return _asMap(response.data);
          }
        case 'simkl':
          {
            final response = await _client.post<dynamic>(
              '$simklBaseUrl/oauth/device',
              queryParameters: <String, String>{
                'client_id': defaultSimklClientId,
              },
              data: const <String, dynamic>{},
              options: Options(
                headers: <String, String>{
                  'Content-Type': 'application/json',
                  'simkl-api-key': defaultSimklClientId,
                },
              ),
            );
            return _asMap(response.data);
          }
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  /// Polls the device-link token endpoint once. Success stores the access
  /// token in secure storage and returns `{'status': 'success'}`; pending
  /// answers return `{'status': 'pending'}`; failures return
  /// `{'status': 'error'}`. Trakt without a configured client secret returns
  /// `{'error': 'secret_required'}`.
  Future<Map<String, dynamic>?> pollLinkedService(
    String service,
    Map<String, dynamic> start,
  ) async {
    try {
      switch (service) {
        case 'trakt':
          {
            var secret = _traktClientSecret;
            if (secret == null || secret.isEmpty) {
              // Settings may write this key directly — re-read so no app
              // restart is needed.
              secret = await _secure.read(key: _traktSecretKey);
              _traktClientSecret = secret;
            }
            if (secret == null || secret.isEmpty) {
              return <String, dynamic>{'error': 'secret_required'};
            }
            final response = await _client.post<dynamic>(
              '$traktBaseUrl/oauth/device/token',
              data: <String, String>{
                'code': start['device_code']?.toString() ?? '',
                'client_id': defaultTraktClientId,
                'client_secret': secret,
              },
              options: Options(
                headers: <String, String>{
                  'Content-Type': 'application/json',
                  'trakt-api-version': '2',
                  'trakt-api-key': defaultTraktClientId,
                },
              ),
            );
            final token = _asMap(response.data)?['access_token']?.toString();
            if (token == null || token.isEmpty) {
              return <String, dynamic>{'status': 'error'};
            }
            await _storeServiceToken('trakt', token);
            return <String, dynamic>{'status': 'success'};
          }
        case 'simkl':
          {
            final response = await _client.post<dynamic>(
              '$simklBaseUrl/oauth/token',
              data: <String, String>{
                'client_id': defaultSimklClientId,
                'client_secret': defaultSimklClientSecret,
                'device_code': start['device_code']?.toString() ?? '',
                'grant_type': 'device',
              },
              options: Options(
                headers: <String, String>{
                  'Content-Type': 'application/json',
                  'simkl-api-key': defaultSimklClientId,
                },
              ),
            );
            final token = _asMap(response.data)?['access_token']?.toString();
            if (token != null && token.isNotEmpty) {
              await _storeServiceToken('simkl', token);
              return <String, dynamic>{'status': 'success'};
            }
            return <String, dynamic>{'status': 'error'};
          }
        default:
          return null;
      }
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      // Trakt: 400 = authorization_pending, 429 = slow_down.
      if (service == 'trakt' && (status == 400 || status == 429)) {
        return <String, dynamic>{'status': 'pending'};
      }
      // Simkl signals pending via a 400 body.
      if (service == 'simkl' && status == 400) {
        final body = _asMap(error.response?.data);
        final detail = body?['error']?.toString() ?? '';
        if (detail.contains('pending') || detail.contains('slow_down')) {
          return <String, dynamic>{'status': 'pending'};
        }
      }
      return <String, dynamic>{'status': 'error'};
    } catch (_) {
      return null;
    }
  }

  Future<void> _storeServiceToken(String service, String token) async {
    _serviceTokens[service] = token;
    await _secure.write(key: _serviceTokenKey(service), value: token);
  }

  Future<void> unlinkService(String service) async {
    _serviceTokens.remove(service);
    await _secure.delete(key: _serviceTokenKey(service));
  }

  /// Fetches the watchlist or history of a linked service, normalized to
  /// `{type: 'movie'|'series', imdb, title, year}` maps (history entries also
  /// carry `watchedAt` epoch milliseconds when the provider exposes it).
  Future<List<dynamic>> syncLinkedService(String service, String kind) async {
    final token = _serviceTokens[service];
    if (token == null || token.isEmpty) return const <dynamic>[];
    try {
      switch (service) {
        case 'trakt':
          return await _syncTrakt(token: token, kind: kind);
        case 'simkl':
          return await _syncSimkl(token: token, kind: kind);
        default:
          return const <dynamic>[];
      }
    } catch (_) {
      return const <dynamic>[];
    }
  }

  Future<List<dynamic>> _syncTrakt({
    required String token,
    required String kind,
  }) async {
    final Uri uri = kind == 'history'
        ? Uri.parse('$traktBaseUrl/users/me/history')
            .replace(queryParameters: <String, String>{'limit': '50'})
        : Uri.parse('$traktBaseUrl/users/me/watchlist');
    final response = await _client.get<dynamic>(
      uri.toString(),
      options: Options(
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'trakt-api-version': '2',
          'trakt-api-key': defaultTraktClientId,
        },
      ),
    );
    final items = response.data is List
        ? response.data as List
        : const <dynamic>[];
    return items
        .map(_mapTraktItem)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  Map<String, dynamic>? _mapTraktItem(Object? raw) {
    final entry = _asMap(raw);
    if (entry == null) return null;
    final watchedAt = _epochMillis(entry['watched_at']);
    if (entry['type'] == 'movie') {
      final movie = _asMap(entry['movie']);
      final title = movie?['title']?.toString();
      if (title == null || title.isEmpty) return null;
      return <String, dynamic>{
        'type': 'movie',
        'imdb': _asMap(movie?['ids'])?['imdb']?.toString(),
        'title': title,
        'year': movie?['year'],
        if (watchedAt != null) 'watchedAt': watchedAt,
      };
    }
    // show / season / episode entries all resolve to the parent show.
    final show = _asMap(entry['show']);
    final title = show?['title']?.toString();
    if (title == null || title.isEmpty) return null;
    return <String, dynamic>{
      'type': 'series',
      'imdb': _asMap(show?['ids'])?['imdb']?.toString(),
      'title': title,
      'year': show?['year'],
      if (watchedAt != null) 'watchedAt': watchedAt,
    };
  }

  Future<List<dynamic>> _syncSimkl({
    required String token,
    required String kind,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'simkl-api-key': defaultSimklClientId,
    };
    // History: try /sync/history first, fall back to the full event log.
    final urls = <String>[
      kind == 'history'
          ? '$simklBaseUrl/sync/history'
          : '$simklBaseUrl/sync/watchlist',
      if (kind == 'history') '$simklBaseUrl/sync/all-events/',
    ];
    Map<String, dynamic>? data;
    for (final url in urls) {
      try {
        final response = await _client.get<dynamic>(
          url,
          options: Options(headers: headers),
        );
        data = _asMap(response.data);
        if (data != null) break;
      } on DioException catch (error) {
        if (error.response?.statusCode == 404 && url != urls.last) continue;
        rethrow;
      }
    }
    if (data == null) return const <dynamic>[];

    final sections = <String, String>{
      'movies': 'movie',
      'shows': 'series',
      'anime': 'series',
      'episodes': 'series',
    };
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final section in sections.entries) {
      final rows = data[section.key];
      if (rows is! List) continue;
      for (final row in rows) {
        final entry = _asMap(row);
        if (entry == null) continue;
        final meta = _asMap(entry['movie']) ?? _asMap(entry['show']);
        final title = meta?['title']?.toString();
        if (title == null || title.isEmpty) continue;
        final imdb = _asMap(meta?['ids'])?['imdb']?.toString();
        final dedupeKey = '${section.value}|${imdb ?? title.toLowerCase()}';
        if (!seen.add(dedupeKey)) continue;
        final watchedAt = _epochMillis(
          entry['watched_at'] ??
              entry['last_watched_at'] ??
              entry['added_at'],
        );
        result.add(<String, dynamic>{
          'type': section.value,
          'imdb': imdb,
          'title': title,
          'year': meta?['year'],
          if (watchedAt != null) 'watchedAt': watchedAt,
        });
      }
    }
    return result;
  }

  /// Fire-and-forget scrobble. Never throws; silently no-ops when the
  /// service is not linked.
  Future<void> scrobbleLinkedService(
    String service, {
    required String action,
    required String type,
    required String title,
    String? year,
    String? imdb,
    required double progress,
  }) async {
    try {
      final token = _serviceTokens[service];
      if (token == null || token.isEmpty) return;
      final percent = progress.clamp(0.0, 100.0).toDouble();
      final normalizedAction =
          const <String>{'start', 'pause', 'stop'}.contains(action)
              ? action
              : 'start';
      if (service == 'trakt') {
        final ids = <String, dynamic>{
          if (imdb != null && imdb.isNotEmpty) 'imdb': imdb,
        };
        await _client.post<dynamic>(
          '$traktBaseUrl/scrobble/$normalizedAction',
          data: <String, dynamic>{
            if (type.toLowerCase() == 'movie')
              'movie': <String, dynamic>{'ids': ids}
            else
              'show': <String, dynamic>{'ids': ids},
            'progress': percent,
          },
          options: Options(
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
              'trakt-api-version': '2',
              'trakt-api-key': defaultTraktClientId,
            },
          ),
        );
      } else if (service == 'simkl') {
        await _client.post<dynamic>(
          '$simklBaseUrl/scrobble',
          data: <String, dynamic>{
            'progress': percent,
            'action': normalizedAction, // start|pause|stop map 1:1
            'type': type.toLowerCase() == 'movie' ? 'movies' : 'episodes',
            'title': title,
            if (year != null && year.isNotEmpty)
              'year': int.tryParse(year) ?? year,
            if (imdb != null && imdb.isNotEmpty) 'imdb': imdb,
          },
          options: Options(
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
              'simkl-api-key': defaultSimklClientId,
            },
          ),
        );
      }
    } catch (_) {
      // Provider hiccups must never interrupt playback.
    }
  }

  // --------------------------------------------------------------------------
  // IPTV playlists (secure storage — same behaviour as the old API)
  // --------------------------------------------------------------------------

  Future<List<dynamic>> loadIptvPlaylists() async {
    for (final key in const <String>[
      _iptvPlaylistsKey,
      _legacyIptvPlaylistsKey,
    ]) {
      final raw = await _secure.read(key: key);
      if (raw == null || raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded;
      } catch (_) {
        // Corrupt payload — try the next key.
      }
    }
    return const <dynamic>[];
  }

  Future<void> saveIptvPlaylists(List<dynamic> list) async {
    if (list.isEmpty) {
      await _secure.delete(key: _iptvPlaylistsKey);
      return;
    }
    await _secure.write(key: _iptvPlaylistsKey, value: jsonEncode(list));
  }

  // --------------------------------------------------------------------------
  // Small helpers
  // --------------------------------------------------------------------------

  Map<String, dynamic>? _asMap(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  num? _asDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value;
    return num.tryParse(value.toString().trim());
  }

  num? _asInt(Object? value) {
    if (value == null) return null;
    if (value is num) return value;
    final digits = value.toString().replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? null : int.tryParse(digits);
  }

  /// Parses OMDb-style values: "90%", "66/100" or plain "66".
  num? _asPercent(Object? value) {
    if (value == null) return null;
    final match = RegExp(r'(\d{1,3})').firstMatch(value.toString().trim());
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  int? _epochMillis(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    final parsed = DateTime.tryParse(value.toString());
    return parsed?.toUtc().millisecondsSinceEpoch;
  }

  String _traktSlug(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9]+"), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }
}

/// Six-hour TTL entry for the in-memory ratings cache.
class _RatingsCacheEntry {
  const _RatingsCacheEntry(this.data, this.expiry);

  final Map<String, dynamic> data;
  final DateTime expiry;
}

/// Compat alias so un-migrated imports of the old website-proxied API layer
/// keep compiling while call sites move over to [NoorApi].
typedef HorseApi = NoorApi;
