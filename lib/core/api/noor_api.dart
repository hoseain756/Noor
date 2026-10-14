import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../trakt/trakt_pkce.dart';
import '../trakt/trakt_tokens.dart';

/// Website-free API layer for Noor.
///
/// Every provider is contacted DIRECTLY from the device — there is no proxy
/// server in the middle anymore. The operator keys ship embedded as static
/// defaults below; users can override the TMDB credential from Settings.
/// Plain (non-secret) state lives in [SharedPreferences], secrets live in
/// [FlutterSecureStorage].
///
/// Trakt linking uses RFC 7636 PKCE over the system browser (the user's
/// Trakt app is PKCE-only — the current official docs deprecate
/// client_secret for user sign-in altogether): we open
/// auth.trakt.tv/oauth/authorize with an S256 code challenge and the
/// registered HTTPS redirect_uri (App Links return). The browser lands on
/// the Noor web companion which relays `code`+`state` to /api/trakt/relay;
/// the app polls it via [pollTraktLink] — or receives the link directly
/// once Android App Links verification is in place. The legacy
/// `noor://callback` custom scheme stays wired as a fallback
/// ([completeTraktLink] accepts both), but the docs discourage custom
/// schemes so nothing depends on it.
///
/// Access tokens live 7 days (docs) — [_validTraktAccessToken] transparently
/// refreshes them single-flight before every authenticated call, and
/// [unlinkService] revokes the session server-side (no secret needed).
///
/// Storage map:
///  - secure 'noor.tmdb.user-token'      → TMDB credential override (v4 JWT
///    starting with 'eyJ' → Bearer header, otherwise treated as a v3 api_key)
///  - secure 'noor.trakt.pkce.verifier'  → in-flight PKCE code verifier
///  - secure 'noor.trakt.pkce.state'     → in-flight PKCE state (CSRF guard)
///  - secure 'noor.trakt.pkce.redirect'  → redirect_uri used by this flow
///  - secure 'noor.trakt.pkce.created'   → pending-flow creation (TTL)
///  - secure 'noor.trakt.refresh'        → Trakt refresh token (single-use)
///  - secure 'noor.trakt.expires'        → access-token expiry (epoch ms)
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

  // Trakt OAuth — current documented endpoints (developer.trakt.tv, 2026):
  // authorize + token + revoke live on the auth host; data endpoints stay
  // on api.trakt.tv. PKCE never sends a client_secret (deprecated for user
  // sign-in; the user's app is PKCE-only and has none to send).
  static const String traktAuthorizeUrl = 'https://auth.trakt.tv/oauth/authorize';
  static const String traktTokenUrl = 'https://auth.trakt.tv/oauth/token';
  static const String traktRevokeUrl = 'https://auth.trakt.tv/oauth/revoke';

  /// Primary return leg (documented): HTTPS on the Noor web companion — the
  /// redirect_uri already registered on the user's Trakt app. The browser
  /// lands there and the companion relays the code to the app; Android App
  /// Links (assetlinks.json is served from the same domain) deliver the
  /// link straight into the app once the signing-cert SHA-256 is published.
  static const String traktHttpsRedirectBase =
      'https://preview-chat-607a5306-ab5d-4ec1-9d61-23b1874d8c08.space-z.ai';

  /// Companion endpoint that bridges the browser callback to the app.
  static const String traktRelayPath = '/api/trakt/relay';

  /// RFC 8252 fallback return — only active if the user registers it on
  /// trakt.tv/oauth/applications. Never required: the docs discourage
  /// custom schemes, so the HTTPS return above is the primary path.
  static const String traktLegacySchemeRedirectUri = 'noor://callback';

  /// redirect_uri used in BOTH the authorize request and the token exchange
  /// — must byte-match the dashboard registration (case-sensitive per docs).
  static const String traktRedirectUri = '$traktHttpsRedirectBase/';

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

  /// A pending browser handshake dies after this window; the relay drops
  /// its entry on the same schedule.
  static const Duration _traktFlowTtl = Duration(minutes: 15);

  /// Proactively refresh when the access token has less than an hour left
  /// (tokens live 7 days per the docs) so long playback sessions never hit
  /// a mid-scrobble 401.
  static const Duration _traktRefreshMargin = Duration(hours: 1);

  // --------------------------------------------------------------------------
  // Storage keys
  // --------------------------------------------------------------------------

  static const String _tmdbUserTokenKey = 'noor.tmdb.user-token';
  static const String _legacyTmdbUserTokenKey = 'horse.mobile.tmdb.user-key';
  static const String _traktPkceVerifierKey = 'noor.trakt.pkce.verifier';
  static const String _traktPkceStateKey = 'noor.trakt.pkce.state';
  static const String _traktPkceRedirectKey = 'noor.trakt.pkce.redirect';
  static const String _traktPkceCreatedAtKey = 'noor.trakt.pkce.created';
  static const String _traktLinkMethodKey = 'noor.trakt.link.method';
  static const String _traktRefreshKey = 'noor.trakt.refresh';
  static const String _traktExpiryKey = 'noor.trakt.expires';
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

  final Map<String, String> _serviceTokens = <String, String>{};

  /// Access-token expiry for Trakt (null = legacy token stored before
  /// expiry tracking existed — used as-is until it 401s).
  DateTime? _traktExpiresAt;

  TraktTokenRefresher? _traktRefresherInstance;

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

    for (final service in const <String>['trakt', 'simkl']) {
      final token = await _secure.read(key: _serviceTokenKey(service));
      if (token != null && token.isNotEmpty) {
        _serviceTokens[service] = token;
      }
    }

    final traktExpiry = int.tryParse(
      await _secure.read(key: _traktExpiryKey) ?? '',
    );
    _traktExpiresAt = traktExpiry == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(traktExpiry);

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
              'https://api.torbox.app/v1/api/user/me',
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
      'https://api.torbox.app/v1/api/torrents/createtorrent',
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
        'https://api.torbox.app/v1/api/torrents/mylist',
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
      'https://api.torbox.app/v1/api/torrents/requestdl',
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

  /// Starts the Simkl device-link flow (POST /oauth2/device). Trakt linking
  /// lives in [startTraktLink] instead — browser PKCE, no client secret
  /// anywhere. Returns the provider payload (device_code, user_code,
  /// verification_url, expires_in, interval) or null on failure.
  Future<Map<String, dynamic>?> startLinkedService(String service) async {
    try {
      switch (service) {
        case 'simkl':
          {
            // Simkl registers this client as an OAuth 2.0 app: the legacy
            // /oauth/device endpoint answers 404 url_failed — the device
            // flow lives at /oauth2/device (verified live against the API).
            final response = await _client.post<dynamic>(
              '$simklBaseUrl/oauth2/device',
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

  /// Polls the Simkl device-link token endpoint once. Success stores the
  /// access token in secure storage and returns `{'status': 'success'}`;
  /// pending answers return `{'status': 'pending'}`; failures return
  /// `{'status': 'error'}`.
  Future<Map<String, dynamic>?> pollLinkedService(
    String service,
    Map<String, dynamic> start,
  ) async {
    try {
      switch (service) {
        case 'simkl':
          {
            // OAuth 2.0 apps poll /oauth2/token with the RFC 8628 device
            // grant; the legacy /oauth/token answers unauthorized_client.
            final response = await _client.post<dynamic>(
              '$simklBaseUrl/oauth2/token',
              data: <String, String>{
                'client_id': defaultSimklClientId,
                'client_secret': defaultSimklClientSecret,
                'device_code': start['device_code']?.toString() ?? '',
                'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
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
      final body = _asMap(error.response?.data);
      final detail = body?['error']?.toString() ??
          (error.response?.data is String
              ? (error.response!.data as String)
              : '');
      // Simkl signals pending via a 400/429 body (authorization_pending /
      // slow_down); expired_token means the device code timed out.
      if (status == 400 || status == 429) {
        if (detail.contains('pending') || detail.contains('slow_down')) {
          return <String, dynamic>{'status': 'pending'};
        }
      }
      return <String, dynamic>{'status': 'error'};
    } catch (_) {
      return null;
    }
  }

  // --------------------------------------------------------------------------
  // Trakt browser PKCE (RFC 7636) — the user's Trakt registration is
  // PKCE-only: the current official docs deprecate client_secret for user
  // sign-in (and Trakt's device grant rejects secret-less exchanges, verified
  // live), so Trakt links through the external browser: authorize on
  // auth.trakt.tv with an S256 challenge and the registered HTTPS redirect
  // URI. The browser lands on the Noor web companion, which relays
  // code+state to /api/trakt/relay; [pollTraktLink] fetches it — or a
  // verified Android App Link hands the URL straight to
  // [completeTraktLink]. The verifier never leaves the device and no secret
  // is ever sent (none exists).
  // --------------------------------------------------------------------------

  /// Generates the PKCE pair + state, persists them for the completion leg
  /// and returns the authorize URL to open in the external browser:
  /// `{'authorizeUrl': ..., 'state': ...}` or null on failure.
  ///
  /// The return leg follows the user's chosen link method ([traktLinkMethod]):
  ///  - `direct` (default): `noor://callback` — the OS bounces straight back
  ///    into Noor the moment Trakt approves; no website involved. Requires
  ///    `noor://callback` registered once on trakt.tv/oauth/applications.
  ///  - `relay`: the registered HTTPS companion URL — the browser lands on
  ///    the Noor web companion which relays code+state to /api/trakt/relay
  ///    and [pollTraktLink] fetches it.
  /// Either way the flow pins its redirect byte-for-byte for the exchange.
  Future<Map<String, dynamic>?> startTraktLink() async {
    try {
      final method = await traktLinkMethod();
      final redirect = method == 'relay'
          ? traktRedirectUri
          : traktLegacySchemeRedirectUri;
      final verifier = TraktPkce.generateVerifier();
      final state = TraktPkce.generateState();
      final challenge = TraktPkce.challengeS256(verifier);
      await _secure.write(key: _traktPkceVerifierKey, value: verifier);
      await _secure.write(key: _traktPkceStateKey, value: state);
      // The exchange must repeat the redirect_uri byte-for-byte, so the
      // flow pins whatever it authorized with.
      await _secure.write(key: _traktPkceRedirectKey, value: redirect);
      await _secure.write(
        key: _traktPkceCreatedAtKey,
        value: DateTime.now().millisecondsSinceEpoch.toString(),
      );
      final url = Uri.parse(traktAuthorizeUrl).replace(
        queryParameters: <String, String>{
          'response_type': 'code',
          'client_id': defaultTraktClientId,
          'redirect_uri': redirect,
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
          'state': state,
        },
      );
      return <String, dynamic>{'authorizeUrl': url.toString(), 'state': state};
    } catch (_) {
      return null;
    }
  }

  /// Forgets a pending PKCE handshake (user cancelled the linking sheet).
  Future<void> cancelTraktLink() => _clearTraktPkce();

  /// Selected return leg for new Trakt flows: `direct` (noor://callback —
  /// back into the app immediately, no website) or `relay` (the registered
  /// HTTPS companion). Defaults to direct.
  Future<String> traktLinkMethod() async {
    final value = await _secure.read(key: _traktLinkMethodKey);
    return value == 'relay' ? 'relay' : 'direct';
  }

  /// Persists the return-leg choice; changing it drops any pending flow so
  /// a stale verifier can never complete against the wrong redirect.
  Future<void> setTraktLinkMethod(String method) async {
    await cancelTraktLink();
    await _secure.write(
      key: _traktLinkMethodKey,
      value: method == 'relay' ? 'relay' : 'direct',
    );
  }

  /// Manual completion leg: the user pastes an authorization code they can
  /// see in the browser (companion card, address bar, or any visible
  /// surface). The pending flow's state + verifier are already on this
  /// device, so the pasted code alone is enough — no relay round-trip.
  Future<Map<String, dynamic>> submitTraktCode(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty) {
      return <String, dynamic>{'status': 'error', 'reason': 'missing_code'};
    }
    final savedState = await _secure.read(key: _traktPkceStateKey);
    if (savedState == null || savedState.isEmpty) {
      return <String, dynamic>{'status': 'error', 'reason': 'no_pending_flow'};
    }
    return _finishTraktLink(code, savedState);
  }

  /// True while a browser handshake is pending — used to resume the relay
  /// watcher after a cold start interrupted the flow.
  Future<bool> hasPendingTraktLink() async {
    final state = await _secure.read(key: _traktPkceStateKey);
    return state != null && state.isNotEmpty;
  }

  /// True when [link] is an HTTPS return belonging to the registered
  /// redirect host (used by the native link router to forward App Links).
  static bool isTraktHttpsReturn(String link) {
    final uri = Uri.tryParse(link.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'https') return false;
    final registeredHost = Uri.tryParse(traktHttpsRedirectBase)?.host ?? '';
    return registeredHost.isNotEmpty &&
        uri.host.toLowerCase() == registeredHost.toLowerCase();
  }

  /// Completes the browser round-trip for a URL that reached the app
  /// directly (legacy `noor://callback` deep link or a verified App Link):
  /// parses it, validates state, swaps the authorization code + PKCE
  /// verifier for tokens at /oauth/token and stores them. Returns
  /// `{'status': 'success', 'username': ...}` or
  /// `{'status': 'error', 'reason': ...}`.
  Future<Map<String, dynamic>> completeTraktLink(String link) async {
    final registeredHost = Uri.tryParse(traktRedirectUri)?.host ?? '';
    final callback = TraktCallback.fromUri(
      link,
      allowedHttpsHost: registeredHost,
    );
    if (callback == null) {
      return <String, dynamic>{'status': 'error', 'reason': 'invalid_link'};
    }
    if (callback.isDenied) {
      await _clearTraktPkce();
      return <String, dynamic>{
        'status': 'error',
        'reason': callback.error ?? 'access_denied',
      };
    }
    return _finishTraktLink(callback.code, callback.state);
  }

  /// One relay poll cycle for the pending browser flow. The web companion
  /// stores `code`+`state` at [traktRelayPath] when Trakt redirects the
  /// browser; we fetch the entry keyed by OUR state (only the holder of the
  /// random state can retrieve the code — and the code alone is useless
  /// without the verifier, which never leaves this device).
  ///
  /// Returns `{'status': 'idle'}` (no pending flow), `{'status': 'pending'}`
  /// (keep polling), or the [completeTraktLink] result map.
  Future<Map<String, dynamic>> pollTraktLink() async {
    final state = await _secure.read(key: _traktPkceStateKey);
    if (state == null || state.isEmpty) {
      return <String, dynamic>{'status': 'idle'};
    }
    final createdAtMs = int.tryParse(
      await _secure.read(key: _traktPkceCreatedAtKey) ?? '',
    );
    if (createdAtMs != null &&
        DateTime.now().difference(
              DateTime.fromMillisecondsSinceEpoch(createdAtMs),
            ) >
            _traktFlowTtl) {
      await _clearTraktPkce();
      return <String, dynamic>{'status': 'error', 'reason': 'flow_expired'};
    }
    // Direct-return flows (noor://callback) complete via the deep link or a
    // manual paste — there is nothing to poll for on the relay.
    final pinnedRedirect =
        await _secure.read(key: _traktPkceRedirectKey) ?? traktRedirectUri;
    if (!pinnedRedirect.toLowerCase().startsWith('https://')) {
      return <String, dynamic>{'status': 'idle'};
    }
    try {
      final relayUrl = Uri.parse('$traktHttpsRedirectBase$traktRelayPath')
          .replace(queryParameters: <String, String>{'state': state});
      final response = await _client.get<dynamic>(
        relayUrl.toString(),
        options: Options(
          headers: <String, String>{'Accept': 'application/json'},
        ),
      );
      final payload = _asMap(response.data);
      final code = payload?['code']?.toString() ?? '';
      if (code.isEmpty) {
        return <String, dynamic>{'status': 'pending'};
      }
      final relayState = payload?['state']?.toString() ?? '';
      if (relayState.isNotEmpty && relayState != state) {
        // Foreign entry — ignore this cycle.
        return <String, dynamic>{'status': 'pending'};
      }
      return await _finishTraktLink(code, state);
    } catch (_) {
      // Relay unreachable (dev server restart, flaky network) — keep polling.
      return <String, dynamic>{'status': 'pending'};
    }
  }

  /// Shared completion leg: validates the pending flow (state equality +
  /// TTL), validates the token response shape, stores the pair atomically
  /// and clears the handshake.
  Future<Map<String, dynamic>> _finishTraktLink(
    String code,
    String state,
  ) async {
    if (code.isEmpty) {
      return <String, dynamic>{'status': 'error', 'reason': 'missing_code'};
    }
    final savedState = await _secure.read(key: _traktPkceStateKey);
    final verifier = await _secure.read(key: _traktPkceVerifierKey);
    final redirect =
        await _secure.read(key: _traktPkceRedirectKey) ?? traktRedirectUri;
    final createdAtMs = int.tryParse(
      await _secure.read(key: _traktPkceCreatedAtKey) ?? '',
    );
    if (savedState == null ||
        savedState.isEmpty ||
        verifier == null ||
        verifier.isEmpty) {
      // Consumed already or never started — races between duplicate link
      // events are not user-facing failures.
      return <String, dynamic>{'status': 'error', 'reason': 'no_pending_flow'};
    }
    if (state != savedState) {
      await _clearTraktPkce();
      return <String, dynamic>{'status': 'error', 'reason': 'state_mismatch'};
    }
    if (createdAtMs == null ||
        DateTime.now().difference(
              DateTime.fromMillisecondsSinceEpoch(createdAtMs),
            ) >
            _traktFlowTtl) {
      await _clearTraktPkce();
      return <String, dynamic>{'status': 'error', 'reason': 'flow_expired'};
    }
    try {
      final response = await _client.post<dynamic>(
        traktTokenUrl,
        data: <String, String>{
          'code': code,
          'client_id': defaultTraktClientId,
          'redirect_uri': redirect,
          'grant_type': 'authorization_code',
          'code_verifier': verifier,
        },
        options: Options(
          headers: <String, String>{
            'Content-Type': 'application/json',
            'trakt-api-version': '2',
            'trakt-api-key': defaultTraktClientId,
          },
        ),
      );
      final TraktTokenSet tokens;
      try {
        tokens = TraktTokenSet.fromResponse(_asMap(response.data) ?? const {});
      } on FormatException {
        await _clearTraktPkce();
        return <String, dynamic>{'status': 'error', 'reason': 'exchange_failed'};
      }
      await _storeTraktTokens(tokens);
      await _clearTraktPkce();
      return <String, dynamic>{
        'status': 'success',
        'username': await traktUsername(tokens.accessToken),
      };
    } on DioException catch (error) {
      await _clearTraktPkce();
      return <String, dynamic>{
        'status': 'error',
        'reason': error.response?.statusCode == 400
            ? 'exchange_failed'
            : 'network_error',
      };
    } catch (_) {
      await _clearTraktPkce();
      return <String, dynamic>{'status': 'error', 'reason': 'exchange_failed'};
    }
  }

  /// Persists a fresh Trakt token pair. Write order matters: refresh token
  /// first (the old access token stays valid for a while, so a crash after
  /// this write still leaves a usable session), then the access token, then
  /// the expiry.
  Future<void> _storeTraktTokens(TraktTokenSet tokens) async {
    final refresh = tokens.refreshToken;
    if (refresh != null && refresh.isNotEmpty) {
      await _secure.write(key: _traktRefreshKey, value: refresh);
    }
    await _storeServiceToken('trakt', tokens.accessToken);
    _traktExpiresAt = tokens.expiresAt;
    await _secure.write(
      key: _traktExpiryKey,
      value: tokens.expiresAt.millisecondsSinceEpoch.toString(),
    );
  }

  /// Best-effort display name for the freshly linked account (null on any
  /// hiccup — the UI falls back to the service title).
  Future<String?> traktUsername([String? token]) async {
    final access = token ?? await _validTraktAccessToken();
    if (access == null || access.isEmpty) return null;
    try {
      final response = await _client.get<dynamic>(
        '$traktBaseUrl/users/me',
        options: Options(
          headers: <String, String>{
            'trakt-api-version': '2',
            'trakt-api-key': defaultTraktClientId,
            'Authorization': 'Bearer $access',
          },
        ),
      );
      final user = _asMap(response.data)?['user'];
      final name = user is Map ? user['username']?.toString() : null;
      return (name == null || name.isEmpty) ? null : name;
    } on DioException catch (error) {
      // Revoked/expired session that the proactive refresh could not see —
      // drop the stored pair so the UI falls back to the disconnected card.
      if (error.response?.statusCode == 401) await _clearTraktTokens();
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Returns a Trakt access token that is still valid, transparently
  /// refreshing it (single-flight) when it is expired or inside the
  /// refresh margin. Null means "no usable session" — the caller skips the
  /// request; a dead grant also clears the stored tokens so the UI shows
  /// the disconnected state.
  Future<String?> _validTraktAccessToken() async {
    final token = _serviceTokens['trakt'];
    if (token == null || token.isEmpty) return null;
    final expiresAt = _traktExpiresAt;
    if (expiresAt == null) return token; // legacy token without expiry info
    if (DateTime.now().isBefore(expiresAt.subtract(_traktRefreshMargin))) {
      return token;
    }
    final result = await _traktRefresher.refresh(
      await _secure.read(key: _traktRefreshKey) ?? '',
    );
    if (result.outcome == TraktRefreshOutcome.refreshed) {
      return result.tokens!.accessToken;
    }
    if (result.outcome == TraktRefreshOutcome.grantDead) {
      // Single-use refresh token consumed, revoked or expired — the session
      // is unrecoverable; require a fresh user authorization.
      await _clearTraktTokens();
    }
    return null;
  }

  TraktTokenRefresher get _traktRefresher =>
      _traktRefresherInstance ??= TraktTokenRefresher(
        clientId: defaultTraktClientId,
        exchange: _traktRefreshExchange,
        persist: _storeTraktTokens,
      );

  /// HTTP leg of the refresh grant. HTTP 400/401 → null (dead grant per the
  /// docs' status-code table); everything else rethrows so the refresher
  /// treats it as transient and the stored session stays put.
  Future<Map<String, dynamic>?> _traktRefreshExchange(
    Map<String, String> body,
  ) async {
    try {
      final response = await _client.post<dynamic>(
        traktTokenUrl,
        data: body,
        options: Options(
          headers: <String, String>{
            'Content-Type': 'application/json',
            'trakt-api-version': '2',
            'trakt-api-key': defaultTraktClientId,
          },
        ),
      );
      final payload = _asMap(response.data);
      if (payload == null || !payload.containsKey('access_token')) {
        return null;
      }
      return payload;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? 0;
      if (status == 400 || status == 401) return null;
      rethrow;
    }
  }

  /// Wipes every stored Trakt credential (access, refresh, expiry).
  Future<void> _clearTraktTokens() async {
    _serviceTokens.remove('trakt');
    _traktExpiresAt = null;
    await _secure.delete(key: _serviceTokenKey('trakt'));
    await _secure.delete(key: _traktRefreshKey);
    await _secure.delete(key: _traktExpiryKey);
  }

  Future<void> _clearTraktPkce() async {
    await _secure.delete(key: _traktPkceVerifierKey);
    await _secure.delete(key: _traktPkceStateKey);
    await _secure.delete(key: _traktPkceRedirectKey);
    await _secure.delete(key: _traktPkceCreatedAtKey);
  }

  Future<void> _storeServiceToken(String service, String token) async {
    _serviceTokens[service] = token;
    await _secure.write(key: _serviceTokenKey(service), value: token);
  }

  Future<void> unlinkService(String service) async {
    if (service == 'trakt') {
      // Documented remote revocation before dropping the local session —
      // works with just the token + client_id for PKCE apps (verified live:
      // HTTP 200, no secret involved). RFC 7009 semantics also kill the
      // associated refresh token.
      final token = _serviceTokens['trakt'];
      if (token != null && token.isNotEmpty) {
        try {
          await _client.post<dynamic>(
            traktRevokeUrl,
            data: <String, String>{
              'token': token,
              'client_id': defaultTraktClientId,
            },
            options: Options(
              headers: <String, String>{
                'Content-Type': 'application/json',
              },
            ),
          );
        } catch (_) {
          // Revocation is best-effort; the local session is cleared below
          // either way and an unrevoked token simply expires unused.
        }
      }
      await _clearTraktTokens();
      await _clearTraktPkce();
      return;
    }
    _serviceTokens.remove(service);
    await _secure.delete(key: _serviceTokenKey(service));
  }

  /// Mirrors a local watchlist change to the linked Trakt account via the
  /// documented `POST /sync/watchlist` (add) and `POST /sync/watchlist/remove`
  /// endpoints. Best-effort: false on any hiccup, never disturbs the local
  /// library state.
  Future<bool> pushTraktWatchlist({
    required String type,
    required String imdb,
    required bool add,
  }) async {
    if (imdb.isEmpty) return false;
    final token = await _validTraktAccessToken();
    if (token == null) return false;
    try {
      final entry = <String, dynamic>{
        'ids': <String, dynamic>{'imdb': imdb},
      };
      final body = type.toLowerCase() == 'series'
          ? <String, dynamic>{'shows': <dynamic>[entry]}
          : <String, dynamic>{'movies': <dynamic>[entry]};
      await _client.post<dynamic>(
        '$traktBaseUrl/sync/watchlist${add ? '' : '/remove'}',
        data: body,
        options: Options(
          headers: <String, String>{
            'Content-Type': 'application/json',
            'trakt-api-version': '2',
            'trakt-api-key': defaultTraktClientId,
            'Authorization': 'Bearer $token',
          },
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Fetches the watchlist or history of a linked service, normalized to
  /// `{type: 'movie'|'series', imdb, title, year}` maps (history entries also
  /// carry `watchedAt` epoch milliseconds when the provider exposes it).
  Future<List<dynamic>> syncLinkedService(String service, String kind) async {
    if (service != 'trakt' && (_serviceTokens[service]?.isEmpty ?? true)) {
      return const <dynamic>[];
    }
    try {
      switch (service) {
        case 'trakt':
          return await _syncTrakt(kind: kind);
        case 'simkl':
          final token = _serviceTokens[service];
          if (token == null || token.isEmpty) return const <dynamic>[];
          return await _syncSimkl(token: token, kind: kind);
        default:
          return const <dynamic>[];
      }
    } catch (_) {
      return const <dynamic>[];
    }
  }

  Future<List<dynamic>> _syncTrakt({required String kind}) async {
    // Transparently refreshes an expiring token before the request.
    final token = await _validTraktAccessToken();
    if (token == null) return const <dynamic>[];
    final Uri uri = kind == 'history'
        ? Uri.parse('$traktBaseUrl/users/me/history')
            .replace(queryParameters: <String, String>{'limit': '50'})
        : Uri.parse('$traktBaseUrl/users/me/watchlist');
    try {
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
    } on DioException catch (error) {
      // Token revoked server-side (or hard-expired without expiry metadata):
      // drop the session so the integrations card returns to "connect".
      if (error.response?.statusCode == 401) await _clearTraktTokens();
      return const <dynamic>[];
    }
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
      final percent = progress.clamp(0.0, 100.0).toDouble();
      final normalizedAction =
          const <String>{'start', 'pause', 'stop'}.contains(action)
              ? action
              : 'start';
      if (service == 'trakt') {
        // Fresh token (auto-refresh) — scrobble must never run on a stale
        // session mid-playback.
        final token = await _validTraktAccessToken();
        if (token == null) return;
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
        final token = _serviceTokens[service];
        if (token == null || token.isEmpty) return;
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
