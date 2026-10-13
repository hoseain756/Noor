import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HorseApi {
  HorseApi({SharedPreferences? preferences}) : _preferences = preferences;

  static const defaultServer = String.fromEnvironment(
    'HORSE_API_BASE_URL',
    defaultValue: 'https://horse-silk.vercel.app',
  );
  static const _serverKey = 'horse.mobile.server';
  static const _stremioKey = 'horse.mobile.stremio.auth';
  static const _tmdbUserKey = 'horse.mobile.tmdb.user-key';
  static const _legacyTmdbKey = 'horse.mobile.tmdb.legacy-key';
  static const _iptvPlaylistsKey = 'horse.mobile.iptv.playlists';
  static const _debridServiceKey = 'horse.mobile.debrid.service';
  static const _debridSecretPrefix = 'horse.mobile.debrid.';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  SharedPreferences? _preferences;
  late Dio _dio;
  String _baseUrl = defaultServer;
  String? stremioAuthKey;
  String? debridService;
  String? debridApiKey;
  String? tmdbUserKey;

  String get baseUrl => _baseUrl;
  Dio get dio => _dio;

  Future<void> initialize() async {
    _preferences ??= await SharedPreferences.getInstance();
    _baseUrl = _normalizeServer(
      _preferences!.getString(_serverKey) ?? defaultServer,
    );
    stremioAuthKey = await _secure.read(key: _stremioKey);
    tmdbUserKey = await _secure.read(key: _tmdbUserKey);
    debridService = _preferences!.getString(_debridServiceKey);
    if (debridService != null) {
      debridApiKey = await _secure.read(
        key: '$_debridSecretPrefix$debridService',
      );
      if (debridApiKey == null) debridService = null;
    }
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 25),
        sendTimeout: const Duration(seconds: 20),
        headers: {'Accept': 'application/json'},
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final cookie = await _secure.read(key: _sessionStorageKey);
          if (cookie != null && cookie.isNotEmpty) {
            options.headers['Cookie'] = cookie;
          }
          handler.next(options);
        },
        onResponse: (response, handler) async {
          final cookies =
              response.headers.map['set-cookie'] ?? const <String>[];
          for (final cookie in cookies) {
            if (!cookie.startsWith('horse_session=')) continue;
            final pair = cookie.split(';').first;
            if (cookie.toLowerCase().contains('max-age=0')) {
              await _secure.delete(key: _sessionStorageKey);
            } else {
              await _secure.write(key: _sessionStorageKey, value: pair);
            }
          }
          handler.next(response);
        },
      ),
    );
  }

  String get _sessionStorageKey =>
      'horse.mobile.session.${Uri.parse(_baseUrl).host}';

  Future<void> setServerUrl(String raw) async {
    final normalized = _normalizeServer(raw);
    await _preferences?.setString(_serverKey, normalized);
    _baseUrl = normalized;
    _dio.options.baseUrl = normalized;
  }

  String _normalizeServer(String raw) {
    final value = raw.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        !{'https', 'http'}.contains(uri.scheme)) {
      throw const FormatException('أدخل عنوان خادم صحيحًا يبدأ بـ https://');
    }
    return value;
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final response = await _dio.get<dynamic>(path, queryParameters: query);
    if (response.data is Map) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    throw const FormatException('استجابة غير صالحة من الخادم');
  }

  Future<Map<String, dynamic>> serverHealth() => getJson('/api/health');

  Future<Map<String, dynamic>> integrationStatus() =>
      getJson('/api/integrations/status');

  Future<Map<String, dynamic>> mediaCapabilities() =>
      getJson('/api/media/capabilities');

  Future<Map<String, dynamic>> tmdbGet(
    String path, {
    Map<String, dynamic> query = const {},
    String language = 'en-US',
    String region = 'US',
  }) async {
    final response = await _dio.get<dynamic>(
      '/api/tmdb',
      queryParameters: {'path': path, ...query},
      options: Options(
        headers: {
          if (tmdbUserKey case final String key when key.isNotEmpty)
            'x-tmdb-user-key': key,
          if (language.isNotEmpty) 'x-tmdb-lang': language,
          if (region.isNotEmpty) 'x-tmdb-region': region,
        },
      ),
    );
    if (response.data is Map) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    throw const FormatException('استجابة TMDB غير صالحة');
  }

  Future<Map<String, dynamic>> validateTmdbUserKey(String key) =>
      postJson('/api/tmdb/validate', {'key': key.trim()});

  Future<Map<String, dynamic>> saveTmdbUserKey(String raw) async {
    final key = raw.trim();
    if (key.isEmpty) throw const FormatException('أدخل مفتاح TMDB أولًا.');
    final result = await validateTmdbUserKey(key);
    if (result['ok'] != true) {
      throw FormatException(
        result['error']?.toString() ?? 'تعذر التحقق من مفتاح TMDB.',
      );
    }
    await _secure.write(key: _tmdbUserKey, value: key);
    tmdbUserKey = key;
    return result;
  }

  Future<void> migrateLegacyTmdbKeys({String? userKey, String? apiKey}) async {
    final key = userKey?.trim() ?? '';
    if ((tmdbUserKey == null || tmdbUserKey!.isEmpty) && key.isNotEmpty) {
      await _secure.write(key: _tmdbUserKey, value: key);
      tmdbUserKey = key;
    }
    final legacyKey = apiKey?.trim() ?? '';
    if (legacyKey.isNotEmpty &&
        await _secure.read(key: _legacyTmdbKey) == null) {
      await _secure.write(key: _legacyTmdbKey, value: legacyKey);
    }
  }

  Future<void> clearTmdbUserKey() async {
    await _secure.delete(key: _tmdbUserKey);
    await _secure.delete(key: _legacyTmdbKey);
    tmdbUserKey = null;
  }

  Future<List<Map<String, dynamic>>> loadIptvPlaylists() async {
    final raw = await _secure.read(key: _iptvPlaylistsKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .where((row) => row['url'] is String)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveIptvPlaylists(
    List<Map<String, dynamic>> playlists,
  ) async {
    if (playlists.isEmpty) {
      await _secure.delete(key: _iptvPlaylistsKey);
      return;
    }
    await _secure.write(key: _iptvPlaylistsKey, value: jsonEncode(playlists));
  }

  Future<void> migrateLegacyIptvPlaylists(
    List<Map<String, dynamic>> legacy,
  ) async {
    if (legacy.isEmpty || await _secure.read(key: _iptvPlaylistsKey) != null) {
      return;
    }
    await saveIptvPlaylists(legacy);
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _dio.post<dynamic>(path, data: body);
    if (response.data is Map) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    throw const FormatException('استجابة غير صالحة من الخادم');
  }

  Future<Map<String, dynamic>> deleteJson(String path) async {
    final response = await _dio.delete<dynamic>(path);
    if (response.data is Map) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    return const {};
  }

  Future<Map<String, dynamic>> proxyGet(String url) =>
      getJson('/api/proxy', query: {'url': url});

  Future<String> proxyText(String url) async {
    final response = await _dio.get<String>(
      '/api/proxy/raw',
      queryParameters: {'url': url},
      options: Options(responseType: ResponseType.plain),
    );
    final text = response.data;
    if (text == null || text.isEmpty) {
      throw const FormatException('استجابة الترجمة فارغة.');
    }
    return text;
  }

  Future<Map<String, dynamic>> loginHorse(String email, String password) =>
      postJson('/api/auth/login', {
        'email': email,
        'password': password,
        'remember': true,
      });

  Future<Map<String, dynamic>> registerHorse(
    String email,
    String password,
    String displayName,
  ) =>
      postJson('/api/auth/register', {
        'email': email,
        'password': password,
        'displayName': displayName,
        'lang': 'ar',
      });

  Future<Map<String, dynamic>> horseMe() => getJson('/api/auth/me');

  Future<List<Map<String, dynamic>>> horseSessions() async {
    final data = await getJson('/api/auth/sessions');
    return (data['devices'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<void> revokeHorseSession(String id) async {
    await deleteJson('/api/auth/sessions/${Uri.encodeComponent(id)}');
  }

  Future<void> logoutHorseAllDevices() async {
    await postJson('/api/auth/logout-all', const {});
    await _secure.delete(key: _sessionStorageKey);
  }

  Future<void> changeHorsePassword(
    String currentPassword,
    String newPassword,
  ) async {
    await postJson('/api/auth/change-password', {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    });
  }

  Future<void> forgotHorsePassword(String email,
      {required String language}) async {
    await postJson('/api/auth/forgot-password', {
      'email': email,
      'lang': language,
    });
  }

  Future<void> deleteHorseAccount() async {
    await deleteJson('/api/auth/account');
    await _secure.delete(key: _sessionStorageKey);
  }

  Future<Map<String, dynamic>> exportHorseAccount() =>
      getJson('/api/account/export');

  Future<void> logoutHorse() async {
    await postJson('/api/auth/logout', const {});
    await _secure.delete(key: _sessionStorageKey);
  }

  Future<Map<String, dynamic>> loginStremio(
    String email,
    String password,
  ) async {
    final result = await postJson('/api/stremio/login', {
      'email': email,
      'password': password,
    });
    final key = result['authKey'];
    if (key is! String || key.isEmpty) {
      throw const FormatException('لم يرجع Stremio مفتاح الدخول');
    }
    stremioAuthKey = key;
    await _secure.write(key: _stremioKey, value: key);
    return Map<String, dynamic>.from(result['user'] as Map? ?? const {});
  }

  Future<void> logoutStremio() async {
    stremioAuthKey = null;
    await _secure.delete(key: _stremioKey);
  }

  Future<List<dynamic>> loadStremioAddons() async {
    final key = stremioAuthKey;
    if (key == null) return [];
    final data = await postJson('/api/stremio/addons', {
      'authKey': key,
      'action': 'get',
    });
    return data['addons'] as List? ?? [];
  }

  Future<void> saveStremioAddons(List<Map<String, dynamic>> addons) async {
    final key = stremioAuthKey;
    if (key == null) return;
    await postJson('/api/stremio/addons', {
      'authKey': key,
      'action': 'set',
      'addons': addons,
    });
  }

  Future<Map<String, dynamic>> startLinkedService(String service) =>
      postJson('/api/$service/link/start', const {});

  Future<Map<String, dynamic>> pollLinkedService(
    String service,
    String pollId,
  ) =>
      postJson('/api/$service/link/poll', {'pollId': pollId});

  Future<void> unlinkService(String service, String linkId) async {
    await postJson('/api/$service/link/unlink', {'linkId': linkId});
  }

  Future<Map<String, dynamic>> createPairingCode(String service) =>
      postJson('/api/pairing/create', {'service': service});

  Future<Map<String, dynamic>> pairingStatus(String code) =>
      getJson('/api/pairing/status', query: {'code': code});

  Future<void> cancelPairingCode(String code) async {
    await postJson('/api/pairing/cancel', {'code': code});
  }

  Future<Map<String, dynamic>> claimPairingCode({
    required String code,
    required String service,
    required String apiKey,
  }) =>
      postJson('/api/pairing/claim', {
        'code': code.trim(),
        'service': service,
        'apiKey': apiKey,
      });

  Future<(List<dynamic>, List<dynamic>)> syncLinkedService(
    String service,
    String linkId,
  ) async {
    final body = {'linkId': linkId};
    final results = await Future.wait([
      postJson('/api/$service/watchlist', body),
      postJson('/api/$service/history', body),
    ]);
    return (
      results[0]['items'] as List? ?? const <dynamic>[],
      results[1]['items'] as List? ?? const <dynamic>[],
    );
  }

  Future<Map<String, dynamic>> verifyDebridKey(
    String service,
    String apiKey,
  ) =>
      postJson('/api/debrid/user', {'service': service, 'apiKey': apiKey});

  Future<Map<String, dynamic>> saveDebridKey(
    String service,
    String apiKey,
  ) async {
    final user = await verifyDebridKey(service, apiKey);
    final previous = debridService;
    if (previous != null && previous != service) {
      await _secure.delete(key: '$_debridSecretPrefix$previous');
    }
    await _secure.write(key: '$_debridSecretPrefix$service', value: apiKey);
    await _preferences?.setString(_debridServiceKey, service);
    debridService = service;
    debridApiKey = apiKey;
    return user;
  }

  Future<void> clearDebridKey() async {
    final service = debridService;
    if (service != null) {
      await _secure.delete(key: '$_debridSecretPrefix$service');
    }
    await _preferences?.remove(_debridServiceKey);
    debridService = null;
    debridApiKey = null;
  }

  Future<String> resolveDebridTorrent(Map<String, dynamic> stream) async {
    final service = debridService;
    final apiKey = debridApiKey;
    if (service == null || apiKey == null) {
      throw const FormatException('اربط خدمة Debrid من الإعدادات أولًا.');
    }
    final infoHash = (stream['infoHash'] ?? '').toString().toLowerCase();
    final hints = (stream['behaviorHints'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final filename = (hints['filename'] ?? stream['title'] ?? '').toString();
    final result = await postJson('/api/debrid/resolve', {
      'service': service,
      'apiKey': apiKey,
      'infoHash': infoHash,
      if (filename.isNotEmpty) 'filename': filename,
      if (stream['fileSize'] is num) 'filesize': stream['fileSize'],
    });
    final url = result['url'] as String?;
    if (url == null || url.isEmpty) {
      throw const FormatException('لم تُرجع خدمة Debrid رابط تشغيل.');
    }
    return signMediaUrl(
      url,
      filename: result['filename'] as String? ?? filename,
    );
  }

  Future<void> scrobbleLinkedService({
    required String service,
    required String linkId,
    required String action,
    required double progress,
    required String imdbId,
    required String type,
    int? season,
    int? episode,
  }) async {
    try {
      await postJson('/api/$service/scrobble', {
        'linkId': linkId,
        'action': action,
        'progress': progress.clamp(0.0, 100.0).toDouble(),
        'imdbId': imdbId,
        'type': type,
        if (season != null) 'season': season,
        if (episode != null) 'episode': episode,
      });
    } catch (_) {
      // Provider outages must never interrupt playback.
    }
  }

  Future<Map<String, dynamic>> loadSnapshot(String deviceId) =>
      getJson('/api/sync', query: {'device': deviceId});

  Future<void> saveSnapshot(
    String deviceId,
    Map<String, dynamic> snapshot,
  ) async {
    await postJson('/api/sync', {'device': deviceId, 'snapshot': snapshot});
  }

  Future<String> signMediaUrl(
    String url, {
    Map<String, dynamic>? proxyHeaders,
    String? filename,
  }) async {
    final data = await postJson('/api/media/sign', {
      'url': url,
      if (proxyHeaders != null) 'proxyHeaders': proxyHeaders,
      if (filename != null) 'filename': filename,
    });
    final signed = data['proxiedUrl'] as String?;
    if (signed == null || signed.isEmpty) {
      throw const FormatException('تعذر تجهيز رابط التشغيل');
    }
    return Uri.parse(_baseUrl).resolve(signed).toString();
  }

  Future<String> prepareTorrent(Map<String, dynamic> stream) async {
    final infoHash = (stream['infoHash'] ?? '').toString().toLowerCase();
    if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(infoHash)) {
      throw const FormatException('رابط التورنت لا يحتوي على بصمة صالحة.');
    }
    final capabilities = await getJson('/api/media/capabilities');
    final mode = capabilities['torrent']?.toString() ?? 'none';
    if (mode == 'none') {
      throw const FormatException(
        'لا يوجد محرك تورنت مربوط بالخادم. أضف إضافة توفّر رابط بث مباشر أو اربط محركًا بالخادم.',
      );
    }
    final hints = (stream['behaviorHints'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final filename = (hints['filename'] ?? stream['title'] ?? '').toString();
    final fileIdx = (stream['fileIdx'] as num?)?.toInt();
    final prepared = await postJson('/api/engine/prepare', {
      'infoHash': infoHash,
      if (fileIdx != null) 'fileIdx': fileIdx,
      if (filename.isNotEmpty) 'filename': filename,
    });
    var status = prepared;
    final started = DateTime.now();
    while (status['pending'] == true &&
        DateTime.now().difference(started) < const Duration(seconds: 100)) {
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      status = await getJson('/api/engine/status/$infoHash');
      if (status['error'] is String && status['error'] != 'not ready') {
        throw FormatException(status['error'] as String);
      }
      if (status['ready'] == true) break;
    }
    if (status['pending'] == true && status['ready'] != true) {
      throw const FormatException('لم يتم العثور على أقران لهذا التورنت.');
    }
    final index = (prepared['fileIdx'] as num?)?.toInt() ?? fileIdx ?? 0;
    final ext = filename.split('.').last.toLowerCase();
    final useRemux = const {
      'mkv',
      'avi',
      'ts',
      'wmv',
      'flv',
      'mpg',
      'mpeg',
    }.contains(ext);
    final path =
        useRemux ? 'remux/$infoHash/$index' : 'stream/$infoHash/$index';
    if (mode == 'external') {
      final engine = capabilities['enginePublicUrl'] as String?;
      if (engine == null || engine.isEmpty) {
        throw const FormatException('خادم التورنت غير متاح.');
      }
      final tokenResponse = await getJson('/api/engine/token');
      final token = tokenResponse['available'] == true
          ? tokenResponse['token']?.toString()
          : null;
      final uri = Uri.parse(
        '$engine/$path',
      ).replace(queryParameters: {if (token != null) 'k': token});
      return uri.toString();
    }
    if (mode == 'builtin') {
      return Uri.parse(
        _baseUrl,
      ).resolve('/$path?XTransformPort=3031').toString();
    }
    throw const FormatException('محرك التورنت غير متاح.');
  }
}

String compactJson(Object? value) => jsonEncode(value);
