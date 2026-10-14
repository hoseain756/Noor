import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/noor_api.dart';
import '../data/catalog_repository.dart';
import '../models/addon.dart';
import '../models/custom_list.dart';
import '../models/media_item.dart';
import '../oauth/oauth_redirect.dart';
import '../sync/noor_sync.dart';
import '../track/track_link.dart';

class AppState extends ChangeNotifier {
  AppState(this.api, this.catalogs);

  static const settingsStorageKey = 'harbor-web.settings';

  /// Shared keys and defaults follow the web app's Harbor settings schema.
  /// Mobile-only keys extend it where native playback has additional controls.
  static final Map<String, dynamic> defaultSettings = {
    'profileId': 'default', 'region': 'US',
    'preferredLanguages': <String>['English'], 'uiLanguage': 'ar',
    'homeMode': 'harbor', 'homeShowAllAddonRows': false,
    'hideWatchedInCatalogs': false, 'tmdbKey': '',
    'opensubtitlesEnabled': true, 'tmdbEnabled': true,
    'tmdbLanguage': 'en-US', 'tmdbImageQuality': 'medium',
    'tmdbUserKey': '', 'ratingsProviders': <String>[],
    'ratingsEnabled': true, 'showImdbBadge': true, 'showMalBadge': true,
    'showQualityBadge': true, 'showCardBadges': true, 'cardBadgeLimit': 3,
    'posterScale': 1.0, 'posterRadius': 12, 'hidePosterTitles': false,
    'posterEffect': 'off', 'episodesView': 'auto',
    'blurEpisodeThumbnails': false, 'instantPlay': true,
    'autoPlayNextEpisode': true, 'resumePlayback': true,
    'resumePrompt': false, 'playerConfirmLeave': true,
    'seekBackStepSec': 10, 'seekForwardStepSec': 10, 'subFontSize': 28,
    'subFontColor': '#FFFFFF', 'subBorderColor': '#000000',
    'subBorderSize': 0, 'subBackgroundOpacity': 0.35,
    'subStyle': 'shadow', 'preferredSubLangs': <String>['English'],
    'subtitlesOffByDefault': false,
    'customPlaybackSpeeds': <double>[], 'showQualityInfo': false,
    'videoFill': 'fit', 'playerTheme': 'auto',
    'pickerLayout': 'stremio', 'streamSort': 'addon',
    'p2pEnabled': true, 'browserEngineEnabled': false,
    'proxyMode': 'auto', 'transcodeMode': 'ask', 'playableOnly': true,
    'preferH264': true, 'kidsCardSize': 'medium',
    'librarySort': 'recent', 'libraryBookmarkedOnly': true,
    'hideContent': <String, dynamic>{
      'anime': false,
      'liveTv': false,
      'adult': true
    },
    'kidsMode': false, 'appearance': 'dark', 'contrastLevel': 'standard',
    'theme': <String, dynamic>{},
    'navOrder': <String>[], 'navHidden': <String>[],
    'navRenamed': <String, dynamic>{}, 'hubOrder': <String>[],
    'hubHidden': <String>[], 'dockAutoHide': true, 'railAutoHide': true,
    'iptvPlaylists': <dynamic>[], 'aiEnabled': true, 'aiStyle': 'concise',
    'soundTheme': 'none', 'wrappedButton': true, 'cloudSyncEnabled': true,
    // Native extensions: audio language and subtitle track preference are
    // applied by the native player; the web schema has no equivalents.
    'defaultAudioLanguage': 'source',
    'subtitleTranslationLanguage': 'off',
    'subtitleOffsetMs': 0,
    'preferredQuality': 'auto',
  };

  final NoorApi api;
  final CatalogRepository catalogs;
  final NoorSyncService sync = NoorSyncService.instance;
  SharedPreferences? _preferences;
  bool initialized = false;
  bool english = false;

  /// Accountless identity: UUID v4 generated once, persisted in secure
  /// storage, and used as the sync key (there is no user account).
  String? deviceId;

  Map<String, dynamic> webSettings = Map<String, dynamic>.from(defaultSettings);
  Map<String, Map<String, dynamic>> linkedServices = {};
  Map<String, dynamic>? debridUser;
  List<Addon> addons = [];
  List<CustomMediaList> customLists = [];
  List<MediaItem> watchlist = [];
  List<WatchHistoryEntry> history = [];
  final Map<String, Map<String, dynamic>> _continueWatching = {};

  /// Buckets queued for the next debounced cloud push.
  final Set<String> _dirtyBuckets = {};
  Timer? _pushTimer;
  bool _pushInFlight = false;

  bool contains(MediaItem item) =>
      watchlist.any((entry) => entry.id == item.id);
  int get watchedCount => history.length;
  List<WatchHistoryEntry> get continueWatching => history
      .where(
        (entry) =>
            entry.durationMs > 0 &&
            entry.positionMs > 0 &&
            entry.positionMs < entry.durationMs - 120000,
      )
      .take(12)
      .toList();
  double get watchedHours =>
      history.fold<double>(0, (sum, entry) => sum + entry.positionMs) / 3600000;

  Future<void> initialize() async {
    await api.initialize();
    _preferences = await SharedPreferences.getInstance();
    final savedEnglish = _preferences!.getBool('horse.mobile.english');
    english = savedEnglish ?? false;
    final savedSettings = _preferences!.getString(settingsStorageKey);
    if (savedSettings != null) {
      try {
        final decoded = jsonDecode(savedSettings);
        if (decoded is Map) {
          webSettings = {
            ...defaultSettings,
            ...Map<String, dynamic>.from(decoded),
          };
        }
      } catch (_) {
        webSettings = Map<String, dynamic>.from(defaultSettings);
      }
    }
    final legacyPlaylists = _playlistRows(webSettings['iptvPlaylists']);
    final storedPlaylists = await api.loadIptvPlaylists();
    if (legacyPlaylists.isNotEmpty && storedPlaylists.isEmpty) {
      // First boot on the accountless build: carry local playlists over.
      await api.saveIptvPlaylists(legacyPlaylists);
    }
    webSettings = {
      ...webSettings,
      'iptvPlaylists': legacyPlaylists.isNotEmpty && storedPlaylists.isEmpty
          ? legacyPlaylists
          : storedPlaylists,
    };
    // TMDB credentials live in device-local secure storage. Old versions kept
    // these fields in the preferences JSON, so blank them before any settings
    // write or sync push can serialize them again.
    webSettings = {...webSettings, 'tmdbKey': '', 'tmdbUserKey': ''};
    await _persistSettings();
    if (savedEnglish == null) english = webSettings['uiLanguage'] == 'en';
    webSettings['uiLanguage'] = english ? 'en' : 'ar';
    linkedServices = _decodeMap(
      _preferences!.getString('horse.mobile.linked-services'),
    );
    final savedDebridUser = _preferences!.getString('horse.mobile.debrid.user');
    if (savedDebridUser != null && api.debridService != null) {
      try {
        debridUser =
            Map<String, dynamic>.from(jsonDecode(savedDebridUser) as Map);
      } catch (_) {
        debridUser = null;
      }
    }
    deviceId = await sync.deviceId();
    unawaited(sync.heartbeat());
    addons = _decodeList(
      _preferences!.getString('horse.mobile.addons'),
      Addon.fromJson,
    );
    customLists = _decodeList(
      _preferences!.getString('horse.mobile.lists'),
      CustomMediaList.fromJson,
    );
    watchlist = _decodeList(
      _preferences!.getString('horse.mobile.watchlist'),
      MediaItem.fromJson,
    );
    history = _decodeList(
      _preferences!.getString('horse.mobile.history'),
      WatchHistoryEntry.fromJson,
    );
    _continueWatching.addAll(
      _decodeMap(_preferences!.getString('horse.mobile.cw')),
    );
    initialized = true;
    notifyListeners();

    // Linked services are resolved straight from the API (no account needed).
    await _refreshLinkedServices();

    // Accountless cloud sync: pull every bucket whose cloud revision is newer
    // than the last revision this device has seen, then persist the merge.
    if (webSettings['cloudSyncEnabled'] != false) {
      await _pullBuckets();
    }
    await _persist();
    notifyListeners();

    // Resume a Trakt browser handshake that was interrupted by a cold start:
    // the relay entry (15 min TTL) may still be waiting for us.
    if (await api.hasPendingTraktLink()) {
      beginTraktRelayWatch();
    }
  }

  Future<void> setLanguage(bool useEnglish) async {
    english = useEnglish;
    webSettings['uiLanguage'] = useEnglish ? 'en' : 'ar';
    await _preferences?.setBool('horse.mobile.english', useEnglish);
    await _persistSettings();
    notifyListeners();
    _schedulePush(NoorSyncService.bucketSettings);
  }

  Future<void> setSetting(String key, dynamic value) async {
    if (key == 'iptvPlaylists') {
      final playlists = _playlistRows(value);
      await api.saveIptvPlaylists(playlists);
      webSettings = {...webSettings, key: playlists};
    } else {
      webSettings = {
        ...webSettings,
        key: key == 'tmdbKey' || key == 'tmdbUserKey' ? '' : value,
      };
    }
    await _persistSettings();
    notifyListeners();
    _schedulePush(NoorSyncService.bucketSettings);
  }

  Future<void> _persistSettings() async {
    await _preferences?.setString(
      settingsStorageKey,
      _encode(_settingsWithoutSecrets()),
    );
  }

  Future<String> exportLocalData() async {
    final exportedSettings = _settingsWithoutSecrets();
    return jsonEncode({
      'format': 'horse-mobile-backup',
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'settings': exportedSettings,
      'addons': addons.map((entry) => entry.toJson()).toList(),
      'watchlist': watchlist.map((entry) => entry.toJson()).toList(),
      'history': history.map((entry) => entry.toJson()).toList(),
      'lists': customLists.map((list) => list.toJson()).toList(),
    });
  }

  Future<void> restoreLocalData(String raw) async {
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        decoded['format'] != 'horse-mobile-backup' ||
        decoded['settings'] is! Map ||
        decoded['addons'] is! List ||
        decoded['watchlist'] is! List ||
        decoded['history'] is! List) {
      throw const FormatException('النسخة الاحتياطية غير صالحة.');
    }
    final data = Map<String, dynamic>.from(decoded);
    final settings = Map<String, dynamic>.from(data['settings'] as Map);
    webSettings = {
      ...defaultSettings,
      ...settings,
      // Provider credentials remain in secure storage, even for old backups.
      'tmdbKey': '',
      'tmdbUserKey': '',
      'iptvPlaylists': webSettings['iptvPlaylists'],
      'cloudSyncEnabled': webSettings['cloudSyncEnabled'],
    };
    english = webSettings['uiLanguage'] == 'en';
    addons = _decodeList(
      jsonEncode(data['addons']),
      Addon.fromJson,
    );
    customLists = _decodeList(
      jsonEncode(data['lists'] ?? const []),
      CustomMediaList.fromJson,
    );
    watchlist = _decodeList(
      jsonEncode(data['watchlist']),
      MediaItem.fromJson,
    );
    history = _decodeList(
      jsonEncode(data['history']),
      WatchHistoryEntry.fromJson,
    );
    _continueWatching
      ..clear()
      ..addEntries(history
          .where((entry) => entry.videoId != null)
          .map((entry) => MapEntry(entry.item.id, {
                ...entry.item.toJson(),
                'positionMs': entry.positionMs,
                'durationMs': entry.durationMs,
                't': entry.watchedAt,
                'videoId': entry.videoId,
                if (entry.season != null) 'season': entry.season,
                if (entry.episode != null) 'episode': entry.episode,
              })));
    await _preferences?.setBool('horse.mobile.english', english);
    await _persistSettings();
    await _persistAndSync();
  }

  Future<void> saveLinkedService(
    String service,
    Map<String, dynamic> account,
  ) async {
    linkedServices = {
      ...linkedServices,
      service: Map<String, dynamic>.from(account),
    };
    await _preferences?.setString(
      'horse.mobile.linked-services',
      _encode(linkedServices),
    );
    notifyListeners();
  }

  Future<void> unlinkService(String service) async {
    try {
      await api.unlinkService(service);
    } catch (_) {
      // Clear the local link even if the provider has already removed it.
    }
    linkedServices = {...linkedServices}..remove(service);
    await _preferences?.setString(
      'horse.mobile.linked-services',
      _encode(linkedServices),
    );
    notifyListeners();
  }

  Future<(int, int)> syncLinkedService(String service) async {
    if (linkedServices[service] == null) return (0, 0);
    int imported = 0;
    int historyImported = 0;
    try {
      final watchlistItems = await api.syncLinkedService(service, 'watchlist');
      final historyItems = await api.syncLinkedService(service, 'history');
      final importedWatchlist = watchlistItems
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .map(
            (entry) => MediaItem.fromJson({
              'id': (entry['imdb'] ?? entry['id'] ?? '').toString(),
              'type': entry['type'],
              'name': (entry['title'] ?? entry['name'] ?? '').toString(),
              if (entry['year'] != null) 'releaseInfo': entry['year'].toString(),
              if (entry['anilist'] != null) 'anilistId': entry['anilist'],
              if (entry['mal'] != null) 'idMal': entry['mal'],
            }),
          )
          .where((item) => item.id.isNotEmpty)
          .toList();
      final importedHistory = historyItems
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .map((entry) {
            final item = MediaItem.fromJson({
              'id': (entry['imdb'] ?? entry['id'] ?? '').toString(),
              'type': entry['type'],
              'name': (entry['title'] ?? entry['name'] ?? '').toString(),
              if (entry['year'] != null) 'releaseInfo': entry['year'].toString(),
              if (entry['anilist'] != null) 'anilistId': entry['anilist'],
              if (entry['mal'] != null) 'idMal': entry['mal'],
            });
            final watchedAt = entry['watchedAt'];
            return WatchHistoryEntry(
              item: item,
              watchedAt: watchedAt is int
                  ? watchedAt
                  : int.tryParse('$watchedAt') ?? 0,
            );
          })
          .where((row) => row.item.id.isNotEmpty)
          .toList();
      // Merge into watchlist without duplicates.
      final watchlistIds = watchlist.map((m) => m.id).toSet();
      final freshWatchlist = importedWatchlist
          .where((item) => !watchlistIds.contains(item.id))
          .toList();
      watchlist = [...watchlist, ...freshWatchlist];
      historyImported = importedHistory.length;
      if (importedHistory.isNotEmpty) {
        final historyIds = history.map((row) => row.item.id).toSet();
        final freshHistory = importedHistory
            .where((row) => !historyIds.contains(row.item.id))
            .toList();
        history = [...freshHistory, ...history];
      }
      imported = freshWatchlist.length;
      await _persist();
      _schedulePush('history');
    } catch (_) {
      return (0, 0);
    }
    return (imported, historyImported);
  }

  Future<void> configureDebrid(String service, String apiKey) async {
    final user = await api.verifyDebridKey(
      service: service,
      apiKey: apiKey.trim(),
    );
    if (user == null) {
      throw Exception('invalid-debrid-key');
    }
    await api.saveDebridKey(service: service, apiKey: apiKey.trim());
    debridUser = user;
    await _preferences?.setString(
      'horse.mobile.debrid.user',
      _encode(debridUser),
    );
    notifyListeners();
  }

  Future<void> disconnectDebrid() async {
    await api.clearDebridKey();
    debridUser = null;
    await _preferences?.remove('horse.mobile.debrid.user');
    notifyListeners();
  }

  Future<void> installAddon(String url) async {
    final manifest = await catalogs.manifest(url);
    final normalizedUrl = _normalizeManifestUrl(url);
    final next = addons.where((addon) => addon.id != manifest['id']).toList()
      ..add(
        Addon(
          id: manifest['id'].toString(),
          name: manifest['name'].toString(),
          transportUrl: normalizedUrl,
          manifest: manifest,
          order: addons.length,
        ),
      );
    addons = next;
    await _saveAddons();
  }

  Future<void> removeAddon(String id) async {
    addons = addons.where((addon) => addon.id != id).toList();
    await _saveAddons();
  }

  Future<void> setAddonEnabled(String id, bool enabled) async {
    addons = addons
        .map(
          (addon) => addon.id == id ? addon.copyWith(enabled: enabled) : addon,
        )
        .toList();
    await _saveAddons();
  }

  Future<void> toggleWatchlist(MediaItem item) async {
    final adding = !contains(item);
    watchlist = adding
        ? [item, ...watchlist]
        : watchlist.where((entry) => entry.id != item.id).toList();
    await _persistAndSync(const {NoorSyncService.bucketWatchlist});
    // Mirror the change to the linked Trakt account (documented
    // POST /sync/watchlist[//remove]). Best-effort push: only imdb-id items
    // map to Trakt, and a failure never disturbs the local library.
    if (linkedServices['trakt']?['linked'] == true &&
        item.id.startsWith('tt')) {
      unawaited(
        api.pushTraktWatchlist(type: item.type, imdb: item.id, add: adding),
      );
    }
    // Independent anime-tracker mirrors: AniList PLANNING / MAL plan_to_watch
    // for anything carrying a provider id. Each integration pushes on its
    // own; removal only ever deletes pure planning rows provider-side.
    final anilistId = item.anilistId;
    if (anilistId != null && linkedServices['anilist']?['linked'] == true) {
      unawaited(
        api.pushAniListWatchlist(mediaId: anilistId, add: adding),
      );
    }
    final malId = item.idMal;
    if (malId != null && linkedServices['mal']?['linked'] == true) {
      unawaited(api.pushMalWatchlist(malId: malId, add: adding));
    }
  }

  Future<void> createCustomList(String name, {String? description}) async {
    final trimmedName = name.trim();
    final cleanName =
        trimmedName.length > 80 ? trimmedName.substring(0, 80) : trimmedName;
    if (cleanName.isEmpty) {
      throw const FormatException('أدخل اسم القائمة.');
    }
    if (customLists.length >= 40) {
      throw const FormatException('وصلت إلى الحد الأقصى للقوائم.');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final list = CustomMediaList(
      id: _newCustomListId(),
      name: cleanName,
      description: _cleanDescription(description),
      items: const [],
      createdAt: now,
      updatedAt: now,
    );
    customLists = [list, ...customLists];
    await _persistAndSync(const {NoorSyncService.bucketLists});
  }

  Future<void> renameCustomList(
    String id, {
    required String name,
    String? description,
  }) async {
    final trimmedName = name.trim();
    final cleanName =
        trimmedName.length > 80 ? trimmedName.substring(0, 80) : trimmedName;
    if (cleanName.isEmpty) {
      throw const FormatException('أدخل اسم القائمة.');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    customLists = customLists
        .map((list) => list.id == id
            ? CustomMediaList(
                id: list.id,
                name: cleanName,
                description: _cleanDescription(description),
                items: list.items,
                createdAt: list.createdAt,
                updatedAt: now,
              )
            : list)
        .toList();
    await _persistAndSync(const {NoorSyncService.bucketLists});
  }

  Future<void> deleteCustomList(String id) async {
    customLists = customLists.where((list) => list.id != id).toList();
    await _persistAndSync(const {NoorSyncService.bucketLists});
  }

  Future<bool> addToCustomList(String listId, MediaItem item) async {
    final index = customLists.indexWhere((list) => list.id == listId);
    if (index < 0) return false;
    final list = customLists[index];
    if (list.items.any((entry) => entry.id == item.id) ||
        list.items.length >= 300) {
      return false;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final listItem = CustomListItem(
      id: item.id,
      type: item.type,
      name: item.name,
      poster: item.poster,
      releaseInfo: item.releaseInfo,
      rating: item.rating,
      addedAt: now,
    );
    customLists = [...customLists];
    customLists[index] = CustomMediaList(
      id: list.id,
      name: list.name,
      description: list.description,
      items: [listItem, ...list.items],
      createdAt: list.createdAt,
      updatedAt: now,
    );
    await _persistAndSync(const {NoorSyncService.bucketLists});
    return true;
  }

  Future<void> removeFromCustomList(String listId, String itemId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    customLists = customLists
        .map((list) => list.id == listId
            ? CustomMediaList(
                id: list.id,
                name: list.name,
                description: list.description,
                items: list.items.where((item) => item.id != itemId).toList(),
                createdAt: list.createdAt,
                updatedAt: now,
              )
            : list)
        .toList();
    await _persistAndSync(const {NoorSyncService.bucketLists});
  }

  Future<void> importCustomList({
    required String name,
    String? description,
    required List<CustomListItem> items,
  }) async {
    final trimmedName = name.trim();
    final cleanName =
        trimmedName.length > 80 ? trimmedName.substring(0, 80) : trimmedName;
    if (cleanName.isEmpty) {
      throw const FormatException('أدخل اسم القائمة.');
    }
    if (customLists.length >= 40) {
      throw const FormatException('وصلت إلى الحد الأقصى للقوائم.');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    customLists = [
      CustomMediaList(
        id: _newCustomListId(),
        name: cleanName,
        description: _cleanDescription(description),
        items: items.take(300).toList(),
        createdAt: now,
        updatedAt: now,
      ),
      ...customLists,
    ];
    await _persistAndSync(const {NoorSyncService.bucketLists});
  }

  Future<void> recordPlayback(
    MediaItem item, {
    required int positionMs,
    required int durationMs,
    String? videoId,
    int? season,
    int? episode,
  }) async {
    final entry = WatchHistoryEntry(
      item: item,
      watchedAt: DateTime.now().millisecondsSinceEpoch,
      positionMs: positionMs,
      durationMs: durationMs,
      videoId: videoId,
      season: season,
      episode: episode,
    );
    history = [
      entry,
      ...history.where((h) => h.item.id != item.id),
    ].take(200).toList();
    if (durationMs > 0 && positionMs < durationMs - 120000) {
      _continueWatching[item.id] = {
        'id': item.id,
        'type': item.type,
        'name': item.name,
        if (item.poster != null) 'poster': item.poster,
        if (item.background != null) 'background': item.background,
        'positionMs': positionMs,
        'durationMs': durationMs,
        't': entry.watchedAt,
        if (videoId != null) 'videoId': videoId,
        if (season != null) 'season': season,
        if (episode != null) 'episode': episode,
      };
    } else {
      _continueWatching.remove(item.id);
    }
    await _persistAndSync(const {
      NoorSyncService.bucketHistory,
      NoorSyncService.bucketLibrary,
    });
    _mirrorAnimeProgress(item, positionMs, durationMs, episode);
  }

  /// Mirrors anime watch progress to the linked trackers: an episode number
  /// becomes AniList progress / MAL num_watched_episodes; a finished anime
  /// MOVIE becomes COMPLETED. Best-effort and independent per service.
  void _mirrorAnimeProgress(
    MediaItem item,
    int positionMs,
    int durationMs,
    int? episode,
  ) {
    if (item.anilistId == null && item.idMal == null) return;
    final finished = durationMs > 0 && positionMs >= durationMs - 120000;
    final isMovie = item.type == 'movie';
    if (!isMovie && episode == null) return;
    if (isMovie && !finished) return;
    final anilistId = item.anilistId;
    if (anilistId != null && linkedServices['anilist']?['linked'] == true) {
      unawaited(
        api.pushAniListProgress(
          mediaId: anilistId,
          progress: isMovie ? 1 : episode!,
          completed: isMovie && finished,
        ),
      );
    }
    final malId = item.idMal;
    if (malId != null && linkedServices['mal']?['linked'] == true) {
      unawaited(
        api.pushMalProgress(
          malId: malId,
          episodes: isMovie ? 1 : episode!,
          completed: isMovie && finished,
        ),
      );
    }
  }

  Future<void> clearHistory() async {
    history = [];
    _continueWatching.clear();
    await _persistAndSync(const {
      NoorSyncService.bucketHistory,
      NoorSyncService.bucketLibrary,
    });
  }

  Future<void> clearLibraryData() async {
    watchlist = [];
    history = [];
    _continueWatching.clear();
    await _persistAndSync(const {
      NoorSyncService.bucketWatchlist,
      NoorSyncService.bucketHistory,
      NoorSyncService.bucketLibrary,
    });
  }

  /// Manual "sync now": pull every bucket, then push the full local state.
  /// Returns whether the round trip fully succeeded.
  Future<bool> syncNow() async {
    if (webSettings['cloudSyncEnabled'] == false) return false;
    await _pullBuckets();
    await _persist();
    var ok = true;
    for (final bucket in NoorSyncService.buckets) {
      final payload = _bucketPayload(bucket);
      if (payload == null) continue;
      if (!await sync.pushBucket(bucket, payload)) {
        ok = false;
        continue;
      }
      _dirtyBuckets.remove(bucket);
      await _storeLocalRev(bucket);
    }
    unawaited(sync.heartbeat());
    notifyListeners();
    return ok;
  }

  Future<void> _saveAddons() async {
    await _persist();
    _schedulePush(NoorSyncService.bucketAddons);
    notifyListeners();
  }

  Future<void> _persistAndSync([
    Set<String> buckets = const {
      NoorSyncService.bucketSettings,
      NoorSyncService.bucketAddons,
      NoorSyncService.bucketLists,
      NoorSyncService.bucketWatchlist,
      NoorSyncService.bucketHistory,
      NoorSyncService.bucketLibrary,
    },
  ]) async {
    await _persist();
    for (final bucket in buckets) {
      _schedulePush(bucket);
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    await _preferences?.setString(
      'horse.mobile.addons',
      _encode(addons.map((e) => e.toJson()).toList()),
    );
    await _preferences?.setString(
      'horse.mobile.lists',
      _encode(customLists.map((list) => list.toJson()).toList()),
    );
    await _preferences?.setString(
      'horse.mobile.watchlist',
      _encode(watchlist.map((e) => e.toJson()).toList()),
    );
    await _preferences?.setString(
      'horse.mobile.history',
      _encode(history.map((e) => e.toJson()).toList()),
    );
    await _preferences?.setString(
      'horse.mobile.cw',
      _encode(_continueWatching),
    );
  }

  // ---------------------------------------------------------------------------
  // Accountless cloud sync (NoorSyncService over direct Postgres).
  // ---------------------------------------------------------------------------

  /// Debounced push: queues [bucket] and (re)starts the 4s timer so bursts of
  /// changes collapse into a single write per bucket.
  void _schedulePush(String bucket) {
    if (webSettings['cloudSyncEnabled'] == false) {
      _dirtyBuckets.clear();
      return;
    }
    _dirtyBuckets.add(bucket);
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(seconds: 4), _flushPush);
  }

  Future<void> _flushPush() async {
    if (_dirtyBuckets.isEmpty) return;
    if (webSettings['cloudSyncEnabled'] == false) {
      _dirtyBuckets.clear();
      return;
    }
    if (_pushInFlight) {
      _pushTimer?.cancel();
      _pushTimer = Timer(const Duration(seconds: 4), _flushPush);
      return;
    }
    _pushInFlight = true;
    try {
      for (final bucket in _dirtyBuckets.toList()) {
        final payload = _bucketPayload(bucket);
        if (payload == null) {
          _dirtyBuckets.remove(bucket);
          continue;
        }
        if (!await sync.pushBucket(bucket, payload)) break;
        _dirtyBuckets.remove(bucket);
        await _storeLocalRev(bucket);
        if (_dirtyBuckets.isEmpty) break;
      }
    } finally {
      _pushInFlight = false;
    }
    if (_dirtyBuckets.isNotEmpty) {
      // Failed buckets stay dirty; retry after a short backoff so an offline
      // device does not hammer the database on every keystroke.
      _pushTimer?.cancel();
      _pushTimer = Timer(const Duration(seconds: 30), _flushPush);
    }
  }

  /// Persists the revision the cloud row now carries for [bucket], so a later
  /// boot only applies buckets that were written after this device's last
  /// known revision.
  Future<void> _storeLocalRev(String bucket) async {
    final current = _preferences?.getInt('noor.sync.rev.$bucket') ?? 0;
    final rev = sync.lastKnownRev(bucket) ?? current + 1;
    await _preferences?.setInt('noor.sync.rev.$bucket', rev);
  }

  /// Boot-time pull: whole-bucket replace whenever the cloud revision is
  /// newer than the last revision recorded locally.
  Future<void> _pullBuckets() async {
    for (final bucket in NoorSyncService.buckets) {
      final remote = await sync.pullBucket(bucket);
      if (remote == null) {
        // The bucket has never been written: seed the cloud from local data.
        if (_hasLocalBucketData(bucket)) _schedulePush(bucket);
        continue;
      }
      final remoteRev = (remote['rev'] as num?)?.toInt() ?? 0;
      final localRev = _preferences?.getInt('noor.sync.rev.$bucket') ?? 0;
      if (remoteRev > localRev) {
        await _applyBucket(bucket, remote['data']);
        await _preferences?.setInt('noor.sync.rev.$bucket', remoteRev);
      }
    }
    notifyListeners();
  }

  bool _hasLocalBucketData(String bucket) {
    switch (bucket) {
      case NoorSyncService.bucketAddons:
        return addons.isNotEmpty;
      case NoorSyncService.bucketLists:
        return customLists.isNotEmpty;
      case NoorSyncService.bucketWatchlist:
        return watchlist.isNotEmpty;
      case NoorSyncService.bucketHistory:
        return history.isNotEmpty;
      case NoorSyncService.bucketLibrary:
        return _continueWatching.isNotEmpty;
      default:
        return false;
    }
  }

  Map<String, dynamic>? _bucketPayload(String bucket) {
    switch (bucket) {
      case NoorSyncService.bucketSettings:
        return {
          'settings': {
            ..._settingsWithoutSecrets(),
            'uiLanguage': english ? 'en' : 'ar',
          },
        };
      case NoorSyncService.bucketAddons:
        return {'addons': addons.map((e) => e.toJson()).toList()};
      case NoorSyncService.bucketLists:
        return {'lists': customLists.map((list) => list.toJson()).toList()};
      case NoorSyncService.bucketWatchlist:
        return {'watchlist': watchlist.map((e) => e.toJson()).toList()};
      case NoorSyncService.bucketHistory:
        return {'history': history.map((e) => e.toJson()).toList()};
      case NoorSyncService.bucketLibrary:
        return {'cw': _continueWatching};
      default:
        return null;
    }
  }

  Future<void> _applyBucket(String bucket, dynamic payload) async {
    if (payload is! Map) return;
    final data = Map<String, dynamic>.from(payload);
    switch (bucket) {
      case NoorSyncService.bucketSettings:
        if (data['settings'] is! Map) return;
        webSettings = {
          ...webSettings,
          ...Map<String, dynamic>.from(data['settings'] as Map),
          'tmdbKey': '',
          'tmdbUserKey': '',
          // Playlist URLs can include provider credentials; keep them local.
          'iptvPlaylists': webSettings['iptvPlaylists'],
          // Sync on/off is a per-device choice, never inherited from the cloud.
          'cloudSyncEnabled': webSettings['cloudSyncEnabled'],
        };
        english = webSettings['uiLanguage'] == 'en';
        await _preferences?.setBool('horse.mobile.english', english);
        await _persistSettings();
      case NoorSyncService.bucketAddons:
        addons = (data['addons'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Addon.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.id.isNotEmpty)
            .toList();
      case NoorSyncService.bucketLists:
        customLists = (data['lists'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => CustomMediaList.fromJson(Map<String, dynamic>.from(e)))
            .where((list) => list.id.isNotEmpty && list.name.isNotEmpty)
            .toList();
      case NoorSyncService.bucketWatchlist:
        watchlist = (data['watchlist'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => MediaItem.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.id.isNotEmpty)
            .toList();
      case NoorSyncService.bucketHistory:
        history = (data['history'] as List? ?? const [])
            .whereType<Map>()
            .map(
                (e) => WatchHistoryEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      case NoorSyncService.bucketLibrary:
        if (data['cw'] is! Map) return;
        _continueWatching
          ..clear()
          ..addAll(
            Map<String, dynamic>.from(data['cw'] as Map).map(
              (key, value) =>
                  MapEntry(key, Map<String, dynamic>.from(value as Map)),
            ),
          );
    }
  }

  /// Linked services are checked directly against the API — no pairing codes,
  /// no account. The cached map keeps `linkId`s for offline scrobble calls.
  Future<void> _refreshLinkedServices() async {
    var next = _decodeMap(
      _preferences?.getString('horse.mobile.linked-services'),
    );
    for (final service in const ['trakt', 'simkl']) {
      try {
        // isLinked is synchronous (token presence) — no await needed.
        final dynamic linked = api.isLinked(service);
        if (linked == true) {
          if (!next.containsKey(service)) {
            next = {
              ...next,
              service: const <String, dynamic>{'linked': true},
            };
          }
        } else if (linked is Map && linked.isNotEmpty) {
          next = {...next, service: Map<String, dynamic>.from(linked)};
        } else {
          next = {...next}..remove(service);
        }
      } catch (_) {
        // Keep the cached entry when the status check is unavailable.
      }
    }
    linkedServices = next;
    await _preferences?.setString(
      'horse.mobile.linked-services',
      _encode(linkedServices),
    );
    notifyListeners();
  }


  String? _cleanDescription(String? value) {
    final clean = value?.trim();
    if (clean == null || clean.isEmpty) return null;
    return clean.length > 200 ? clean.substring(0, 200) : clean;
  }

  Map<String, dynamic> _settingsWithoutSecrets() => {
        ...webSettings,
        'tmdbKey': '',
        'tmdbUserKey': '',
        // M3U and EPG URLs often carry account tokens in their query string.
        'iptvPlaylists': <dynamic>[],
      };

  List<Map<String, dynamic>> _playlistRows(dynamic value) =>
      (value as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .where((row) => row['url'] is String)
          .toList();

  String _newCustomListId() {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    String nextId() => List.generate(
          13,
          (_) => alphabet[random.nextInt(alphabet.length)],
        ).join();
    var id = nextId();
    while (customLists.any((list) => list.id == id)) {
      id = nextId();
    }
    return id;
  }

  List<T> _decodeList<T>(String? raw, T Function(Map<String, dynamic>) decode) {
    if (raw == null) return [];
    try {
      return (List<dynamic>.from(_decode(raw) as List))
          .whereType<Map>()
          .map((e) => decode(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Map<String, Map<String, dynamic>> _decodeMap(String? raw) {
    if (raw == null) return {};
    try {
      return Map<String, dynamic>.from(_decode(raw) as Map).map(
        (key, value) => MapEntry(key, Map<String, dynamic>.from(value as Map)),
      );
    } catch (_) {
      return {};
    }
  }

  dynamic _decode(String raw) {
    // SharedPreferences JSON is decoded here to keep serialization in one place.
    return jsonDecode(raw);
  }

  String _encode(Object? value) => jsonEncode(value);

  String _normalizeManifestUrl(String raw) {
    var url = raw.trim().replaceFirst(
          RegExp(r'^stremio://', caseSensitive: false),
          'https://',
        );
    url = url
        .replaceFirst(RegExp(r'/configure/?$'), '')
        .replaceFirst(RegExp(r'/+$'), '');
    return url.endsWith('manifest.json') ? url : '$url/manifest.json';
  }

  @override
  void dispose() {
    _pushTimer?.cancel();
    _traktRelayTimer?.cancel();
    sync.close();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // Trakt browser-PKCE relay watcher (web companion callback bridge)
  // --------------------------------------------------------------------------

  Timer? _traktRelayTimer;
  DateTime? _traktRelayDeadline;
  Map<String, dynamic>? _traktLinkEvent;

  /// Timestamp of the last Trakt link event already surfaced as a toast by
  /// the link listener (guards against double-toasting one event).
  int seenTraktLinkEventAt = 0;

  /// Last finished Trakt link round (`{at, ok, reason?}`) — surfaced as a
  /// toast by [IncomingLinkListener] wherever the user happens to be.
  Map<String, dynamic>? get traktLinkEvent => _traktLinkEvent;

  /// Watches the web companion relay while a browser Trakt handshake is in
  /// flight: when the user approves on trakt.tv the browser lands on the
  /// companion (the registered HTTPS redirect URI), which stores
  /// code+state at /api/trakt/relay; we fetch it here and finish the
  /// PKCE exchange. Runs app-wide so closing the linking sheet never loses
  /// the callback.
  void beginTraktRelayWatch() {
    _traktRelayDeadline = DateTime.now().add(const Duration(minutes: 12));
    _traktRelayTimer?.cancel();
    _traktRelayTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_traktRelayTick()),
    );
  }

  /// Manual completion of a pending Trakt flow with an authorization code
  /// the user pasted from the browser. Mirrors the relay-watch success
  /// handling so app state updates identically regardless of which leg
  /// (deep link, relay poll, or this paste) delivered the code. Returns the
  /// NoorApi result map for caller-side toasts.
  Future<Map<String, dynamic>> completeTraktWithCode(String code) async {
    final result = await api.submitTraktCode(code);
    if (result['status']?.toString() == 'success') {
      await saveLinkedService('trakt', <String, dynamic>{
        'linked': true,
        'linkedAt': DateTime.now().millisecondsSinceEpoch,
        if (result['username'] != null) 'username': result['username'],
      });
    }
    return result;
  }

  void _stopTraktRelayWatch() {
    _traktRelayTimer?.cancel();
    _traktRelayTimer = null;
    _traktRelayDeadline = null;
  }

  Future<void> _traktRelayTick() async {
    final deadline = _traktRelayDeadline;
    if (deadline == null) return;
    if (DateTime.now().isAfter(deadline) ||
        linkedServices['trakt']?['linked'] == true) {
      _stopTraktRelayWatch();
      return;
    }
    final Map<String, dynamic> result;
    try {
      result = await api.pollTraktLink();
    } catch (_) {
      return;
    }
    final status = result['status']?.toString();
    if (status == 'pending') return;
    if (status == 'idle') {
      // The pending flow was consumed, cancelled or never started — stop
      // polling quietly (no user-facing event).
      _stopTraktRelayWatch();
      return;
    }
    _stopTraktRelayWatch();
    if (status == 'success') {
      await saveLinkedService('trakt', <String, dynamic>{
        'linked': true,
        'linkedAt': DateTime.now().millisecondsSinceEpoch,
        if (result['username'] != null) 'username': result['username'],
      });
      _traktLinkEvent = <String, dynamic>{
        'at': DateTime.now().millisecondsSinceEpoch,
        'ok': true,
      };
    } else {
      _traktLinkEvent = <String, dynamic>{
        'at': DateTime.now().millisecondsSinceEpoch,
        'ok': false,
        'reason': result['reason']?.toString(),
      };
    }
    notifyListeners();
  }

  // --------------------------------------------------------------------------
  // Generic OAuth return leg (AniList / MyAnimeList trackers)
  // --------------------------------------------------------------------------

  Map<String, dynamic>? _oauthCallback;
  Map<String, dynamic>? _oauthLinkEvent;

  /// Timestamp of the last tracker link event already surfaced as a toast
  /// (guards against double-toasting one event).
  int seenOAuthLinkEventAt = 0;

  /// Last OAuth return received over the app-identifier scheme
  /// (`app.noor.mobile://callback?…`): `{at, code, state, error?}`.
  /// In-memory only: authorization codes live minutes.
  Map<String, dynamic>? get oauthCallback => _oauthCallback;

  /// Last finished tracker link round
  /// (`{at, ok, service, reason?}`) — surfaced as a toast by the link
  /// listener wherever the user happens to be.
  Map<String, dynamic>? get oauthLinkEvent => _oauthLinkEvent;

  /// Stores a freshly parsed OAuth return and dispatches it to whichever
  /// tracker handshake is pending (AniList presence-match or MyAnimeList
  /// state-match). Completion updates [linkedServices] and emits
  /// [oauthLinkEvent] for the toast.
  void announceOAuthCallback(OAuthCallback callback) {
    _oauthCallback = <String, dynamic>{
      'at': DateTime.now().millisecondsSinceEpoch,
      'code': callback.code,
      'state': callback.state,
      if (callback.isDenied) 'error': callback.error,
    };
    notifyListeners();
    if (callback.isDenied) {
      _oauthLinkEvent = <String, dynamic>{
        'at': DateTime.now().millisecondsSinceEpoch,
        'ok': false,
        'service': null,
        'reason': callback.error,
      };
      notifyListeners();
      return;
    }
    unawaited(_dispatchOAuthCallback(callback));
  }

  Future<void> _dispatchOAuthCallback(OAuthCallback callback) async {
    String? service;
    Map<String, dynamic> result;
    try {
      service = await api.pendingOAuthService(state: callback.state);
      switch (service) {
        case 'anilist':
          result = await api.completeAniListLink(callback.code);
        case 'mal':
          result = await api.completeMalLink(
            callback.code,
            state: callback.state,
          );
        default:
          // No pending flow (stale/duplicate callback) — stay silent unless
          // the service never linked.
          return;
      }
    } catch (_) {
      result = <String, dynamic>{'status': 'error', 'reason': 'exchange_failed'};
    }
    final ok = result['status']?.toString() == 'success';
    if (ok && service != null) {
      await saveLinkedService(service, <String, dynamic>{
        'linked': true,
        'linkedAt': DateTime.now().millisecondsSinceEpoch,
        if (result['username'] != null) 'username': result['username'],
      });
    }
    _oauthLinkEvent = <String, dynamic>{
      'at': DateTime.now().millisecondsSinceEpoch,
      'ok': ok,
      'service': service,
      'reason': ok ? null : result['reason']?.toString(),
    };
    notifyListeners();
  }

  /// Refreshes the linked tracker's profile (username, avatar, anime
  /// stats) into [linkedServices] so the integrations card shows live data.
  Future<void> refreshTrackerProfile(String service) async {
    if (linkedServices[service]?['linked'] != true) return;
    try {
      if (service == 'anilist') {
        final viewer = await api.aniListViewer();
        if (viewer == null) return;
        final stats = _asMapMap(viewer['statistics'])?['anime'];
        final current = Map<String, dynamic>.from(linkedServices['anilist'] ?? {});
        current['username'] = viewer['name']?.toString() ?? current['username'];
        final avatar = _asMapMap(viewer['avatar']);
        if (avatar?['large'] != null) {
          current['avatar'] = avatar!['large']?.toString();
        }
        if (stats != null) {
          current['animeCount'] = stats['count'];
          current['episodesWatched'] = stats['episodesWatched'];
          current['meanScore'] = stats['meanScore'];
        }
        linkedServices = {...linkedServices, 'anilist': current};
        await _preferences?.setString(
          'horse.mobile.linked-services',
          _encode(linkedServices),
        );
        notifyListeners();
      } else if (service == 'mal') {
        final profile = await api.malProfile();
        if (profile == null) return;
        final current = Map<String, dynamic>.from(linkedServices['mal'] ?? {});
        current['username'] = profile['name']?.toString() ?? current['username'];
        if (profile['picture'] != null) {
          current['avatar'] = profile['picture']?.toString();
        }
        final stats = _asMapMap(profile['anime_statistics']);
        if (stats != null) {
          current['animeCount'] = stats['num_list_items'];
          current['episodesWatched'] = stats['num_episodes'];
          current['meanScore'] = stats['mean_score'];
        }
        linkedServices = {...linkedServices, 'mal': current};
        await _preferences?.setString(
          'horse.mobile.linked-services',
          _encode(linkedServices),
        );
        notifyListeners();
      }
    } catch (_) {
      // Profile enrichment is cosmetic — never disturb the link state.
    }
  }

  static Map<String, dynamic>? _asMapMap(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  /// Manual completion from the integrations card's paste field.
  Future<Map<String, dynamic>> completeAniListWithCode(String code) async {
    final result = await api.submitAniListCode(code);
    if (result['status']?.toString() == 'success') {
      await saveLinkedService('anilist', <String, dynamic>{
        'linked': true,
        'linkedAt': DateTime.now().millisecondsSinceEpoch,
        if (result['username'] != null) 'username': result['username'],
      });
    }
    return result;
  }

  Future<Map<String, dynamic>> completeMalWithCode(String code) async {
    final result = await api.submitMalCode(code);
    if (result['status']?.toString() == 'success') {
      await saveLinkedService('mal', <String, dynamic>{
        'linked': true,
        'linkedAt': DateTime.now().millisecondsSinceEpoch,
        if (result['username'] != null) 'username': result['username'],
      });
    }
    return result;
  }

  /// Saves the tracker-sheet form (status / progress / score) to EVERY
  /// linked tracker the item can reach. Returns per-service outcomes for
  /// the sheet's confirmation toasts.
  Future<Map<String, bool>> saveAnimeEntry({
    required MediaItem item,
    AnimeTrackStatus? status,
    int? progress,
    double? score10,
  }) async {
    final outcomes = <String, bool>{};
    // Everything null = the tracker sheet's explicit "Remove" — genuinely
    // delete the entries on each reachable provider (never a fake success).
    final isRemove =
        status == null && progress == null && score10 == null;
    final anilistId = item.anilistId;
    if (anilistId != null && linkedServices['anilist']?['linked'] == true) {
      var ok = true;
      if (isRemove) {
        ok = await api.removeAniListEntry(anilistId);
      } else if (status != null) {
        ok = await api.pushAniListEntryStatus(
          mediaId: anilistId,
          status: status,
          progress: progress,
        );
      } else if (progress != null) {
        ok = await api.pushAniListProgress(
          mediaId: anilistId,
          progress: progress,
        );
      }
      if (!isRemove && ok && score10 != null) {
        ok = await api.pushAniListScore(
          mediaId: anilistId,
          score10: score10,
        );
      }
      outcomes['anilist'] = ok;
    }
    final malId = item.idMal;
    if (malId != null && linkedServices['mal']?['linked'] == true) {
      var ok = true;
      if (isRemove) {
        ok = await api.removeMalEntry(malId);
      } else if (status != null) {
        ok = await api.pushMalEntryStatus(
          malId: malId,
          status: status,
          progress: progress,
        );
      } else if (progress != null) {
        ok = await api.pushMalProgress(malId: malId, episodes: progress);
      }
      if (!isRemove && ok && score10 != null) {
        ok = await api.pushMalScore(malId: malId, score10: score10);
      }
      outcomes['mal'] = ok;
    }
    return outcomes;
  }
}
