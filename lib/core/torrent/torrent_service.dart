import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'stream_server.dart';
import 'torrent_models.dart';

/// Singleton facade for the on-device torrent streaming engine.
///
/// Talks to the native libtorrent bridge (jlibtorrent) through the
/// `noor/torrent` MethodChannel and receives throttled status updates on the
/// `noor/torrent/events` EventChannel. The engine, its natives and the local
/// streaming server live entirely on the device — there is no server involved.
///
/// Typical player usage:
/// ```dart
/// final torrent = TorrentService.instance;
/// if (await torrent.isSupported) {
///   final meta = await torrent.resolve(magnet);
///   final prepared = await torrent.prepare(
///     infoHash: meta.infoHash,
///     magnet: magnet,
///   );
///   // prepared.url can be handed straight to the video player once
///   // status.ready turns true.
/// }
/// ```
class TorrentService {
  TorrentService._();

  static final TorrentService instance = TorrentService._();

  static const MethodChannel _channel = MethodChannel('noor/torrent');
  static const EventChannel _eventChannel = EventChannel('noor/torrent/events');

  /// Public trackers appended to every generated magnet so DHT-less swarms
  /// still find peers quickly.
  ///
  /// Task 129: the previous list was half-dead (liveness-probed from a real
  /// network — DNS failures, 403s, timeouts on 7 of 16 entries) and ALL FOUR
  /// of its HTTP fallbacks were gone, so on carriers that throttle UDP the
  /// engine had zero trackers and metadata resolution always timed out.
  /// Every entry below was verified alive (BitTorrent UDP connect handshake /
  /// HTTP announce round-trip). Mixes UDP **and** HTTP(S): many mobile
  /// carriers throttle or block UDP announce traffic entirely, so plain-HTTP
  /// trackers are often the only working path on cellular networks.
  static const List<String> _defaultTrackers = <String>[
    // — UDP (verified alive) —
    'udp://tracker.opentrackr.org:1337/announce',
    'udp://open.demonii.com:1337/announce',
    'udp://open.stealth.si:80/announce',
    'udp://exodus.desync.com:6969/announce',
    'udp://tracker.dler.org:6969/announce',
    'udp://explodie.org:6969/announce',
    'udp://tracker.qu.ax:6969/announce',
    'udp://tracker.ducks.party:1984/announce',
    'udp://tracker-udp.gbitt.info:80/announce',
    'udp://tracker.skynetcloud.site:6969/announce',
    'udp://tracker.nyaa.vc:6969/announce',
    'udp://tracker.corpscorp.online:80/announce',
    'udp://tracker.bittor.pw:1337/announce',
    'udp://tracker.farted.net:6969/announce',
    'udp://tracker2.dler.org:80/announce',
    // — HTTP(S) (the lifeline on UDP-restricted networks) —
    'http://tracker.dler.org:6969/announce',
    'http://tracker.dler.com:6969/announce',
    'http://tracker.renfei.net:8080/announce',
  ];

  /// Public HTTP torrent-file cache used as a P2P-free metadata bootstrap
  /// (Task 129): when the swarm is unreachable, the .torrent file itself can
  /// still come from this well-known mirror in ~1-2s. Keyed by UPPER-case
  /// hex info-hash (the mirror's canonical form).
  static const String _torrentCacheUrl = 'https://itorrents.org/torrent/';

  /// Metadata resolved at least once per session, keyed by info-hash.
  final Map<String, TorrentMetadata> _metadataCache =
      <String, TorrentMetadata>{};

  /// Lazily-created broadcast mapping of the native EventChannel.
  Stream<TorrentStatus>? _broadcast;

  /// The one local HTTP server backing the active prepared torrent.
  StreamServer? _server;

  /// Info-hash of the currently active (last prepared) torrent.
  String? _activeHash;

  /// Serialises mutating operations so concurrent prepare/stop/remove calls
  /// can never interleave.
  Future<void> _queue = Future<void>.value();

  // ------------------------------------------------------------------ //
  //  Public API
  // ------------------------------------------------------------------ //

  /// Whether the native torrent engine is available on this platform.
  ///
  /// On non-Android platforms the MethodChannel is not registered, so the
  /// invocation raises [MissingPluginException] — reported as `false`.
  Future<bool> get isSupported async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Pre-boots the native libtorrent session (DHT bootstrap included) so the
  /// first real metadata resolve does not pay the 10–30s cold-start cost
  /// inside its own timeout window (Task 128). Fire-and-forget: every error
  /// is swallowed and the call is a no-op on platforms without the engine.
  Future<void> warmup() async {
    try {
      if (!await isSupported) return;
      await _channel.invokeMethod<void>('warmup');
    } catch (_) {
      // Warm-up is best-effort — resolve() bootstraps the session anyway.
    }
  }

  /// Fetches metadata (name + file list) for [magnet] without downloading.
  ///
  /// The native engine performs a staged retry (22s + 26s — the first attempt
  /// warms DHT, the second rides the warmed session); the Dart-side safety
  /// net caps the await slightly above the native budget and raises
  /// [TorrentException].
  Future<TorrentMetadata> resolve(String magnet) {
    return _serialized(() => _resolve(magnet));
  }

  /// Prepares a torrent for on-device streaming:
  ///
  ///  1. resolves metadata (unless already cached) to locate the target file —
  ///     resolution order (Task 129): HTTP torrent-file cache (itorrents.org,
  ///     no P2P needed), then the swarm itself through the staged magnet
  ///     fetch;
  ///  2. selects the target file — the addon's own [fileIndex] (Torrentio
  ///     `fileIdx`) when playable, else [filename] matching, else the largest
  ///     video file;
  ///  3. starts the native engine with sequential download enabled and
  ///     per-file priorities (target file high, first/last pieces highest);
  ///     the magnet carries the stream's own [trackers] (Torrentio `sources`)
  ///     merged over the verified defaults;
  ///  4. starts a local loopback HTTP server with Range support serving the
  ///     selected file from inside `<documents>/torrents/<infoHash>/`;
  ///  5. returns a [PreparedTorrent] exposing the player URL plus a live
  ///     status stream, and a `stop()` that closes the server and removes the
  ///     torrent from the engine while keeping its files for instant resume.
  Future<PreparedTorrent> prepare({
    required String infoHash,
    String? magnet,
    String? filename,
    int? filesize,
    String? displayName,
    List<String> trackers = const <String>[],
    int? fileIndex,
  }) {
    return _serialized(
      () => _prepare(
        infoHash,
        magnet: magnet,
        filename: filename,
        filesize: filesize,
        displayName: displayName,
        trackers: trackers,
        fileIndex: fileIndex,
      ),
    );
  }

  /// Removes [infoHash] from the engine, optionally deleting its files.
  Future<void> remove(String infoHash, {bool deleteFiles = false}) {
    return _serialized(() => _remove(infoHash, deleteFiles: deleteFiles));
  }

  /// Shuts the whole native engine down (used on app teardown).
  Future<void> shutdown() {
    return _serialized(() async {
      await _server?.close();
      _server = null;
      _activeHash = null;
      try {
        await _channel.invokeMethod<void>('stop');
      } on PlatformException {
        // Engine already gone — nothing left to do.
      } on MissingPluginException {
        // Non-Android platform.
      }
    });
  }

  /// Extracts every `tr=` tracker from a magnet URI (order preserved).
  static List<String> trackersFromMagnet(String magnetUri) {
    final trackers = <String>[];
    for (final match
        in RegExp('(?:^|&)tr(?:\\[\\])?=([^&]+)').allMatches(magnetUri)) {
      final tracker = Uri.decodeComponent(match.group(1) ?? '').trim();
      if (tracker.isNotEmpty && !trackers.contains(tracker)) {
        trackers.add(tracker);
      }
    }
    return trackers;
  }

  /// Builds a magnet URI for [infoHash], merging — in priority order — the
  /// stream's own trackers ([extraTrackers], typically Torrentio `sources`,
  /// fresher than anything static), the [magnetUri]'s existing `tr=` entries
  /// and the verified default list. De-duplicated, defaults last.
  static String magnetFor(
    String infoHash, {
    String? dn,
    List<String> extraTrackers = const <String>[],
    String? magnetUri,
  }) {
    final hash = infoHash.trim().toLowerCase();
    final merged = <String>[
      ...extraTrackers,
      ...trackersFromMagnet(magnetUri ?? ''),
      ..._defaultTrackers,
    ];
    final trackers = <String>[];
    for (final tracker in merged) {
      final clean = tracker.trim();
      if (clean.isNotEmpty && !trackers.contains(clean)) trackers.add(clean);
    }
    var name = dn;
    if ((name == null || name.trim().isEmpty) && magnetUri != null) {
      final dnMatch =
          RegExp('(?:^|&)dn=([^&]+)').firstMatch(magnetUri)?.group(1);
      name = dnMatch == null ? null : Uri.decodeComponent(dnMatch);
    }
    final buffer = StringBuffer('magnet:?xt=urn:btih:$hash');
    if (name != null && name.trim().isNotEmpty) {
      buffer.write('&dn=${Uri.encodeComponent(name.trim())}');
    }
    for (final tracker in trackers) {
      buffer.write('&tr=${Uri.encodeComponent(tracker)}');
    }
    return buffer.toString();
  }

  // ------------------------------------------------------------------ //
  //  Internals
  // ------------------------------------------------------------------ //

  /// Runs [action] after every previously queued action completes, so the
  /// service never runs two mutating flows concurrently.
  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Metadata resolution with the Task 129 fallback chain:
  ///
  ///  1. HTTP torrent-file cache (itorrents.org) — a plain HTTPS GET that
  ///     needs NO peer connectivity; when it hits, metadata arrives in
  ///     ~1-2s and the native side also caches the raw torrent bytes so
  ///     `start` never re-fetches metadata from the swarm;
  ///  2. the staged P2P resolve (22s + 26s) through the engine.
  ///
  /// The HTTP path is best-effort by design: any failure (offline mirror,
  /// unknown hash, slow network) silently falls through to the P2P path.
  Future<TorrentMetadata> _resolveSmart(String hash, String magnetUri) async {
    try {
      final bytes = await _fetchTorrentBytes(hash);
      if (bytes != null) {
        final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
            'resolveTorrentData', <String, Object?>{
          'data': base64Encode(bytes)
        }).timeout(const Duration(seconds: 12));
        if (raw != null) {
          final meta = TorrentMetadata.fromMap(raw);
          if (meta.infoHash.toLowerCase() == hash && meta.files.isNotEmpty) {
            return meta;
          }
          // Hash mismatch or empty file list — untrusted cache, ignore.
        }
      }
    } on PlatformException {
      // resolveTorrentData unsupported (older engine build) — P2P path.
    } on TimeoutException {
      // Native decode round-trip stalled — P2P path.
    } on MissingPluginException {
      // Non-Android platform — P2P path (will report unavailable).
    } catch (_) {
      // Network/dns/decode failure — P2P path.
    }
    return _resolve(magnetUri);
  }

  /// Fetches the raw .torrent bytes for [hash] from the public HTTP cache.
  /// Returns null when the mirror doesn't know the hash or the response
  /// doesn't look like a bencoded torrent file.
  Future<Uint8List?> _fetchTorrentBytes(String hash) async {
    final upper = hash.toUpperCase();
    final uri = Uri.parse('$_torrentCacheUrl$upper.torrent');
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 6);
      final request =
          await client.getUrl(uri).timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36');
      request.followRedirects = true;
      request.maxRedirects = 3;
      final response =
          await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>().catchError((_) {});
        return null;
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      // Bencoded torrents start with 'd' and are never tiny.
      if (bytes.length < 100 || bytes.first != 0x64) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<TorrentMetadata> _resolve(String magnet) async {
    await _ensureAvailable();
    try {
      final raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('resolve', <String, Object?>{
        'magnet': magnet,
      }).timeout(
        // Native staged budget is 22s + 26s = 48s (Task 128); keep the
        // Dart-side safety net above it with headroom for channel hops.
        const Duration(seconds: 55),
        onTimeout: () => throw const TorrentException(
          'timeout',
          'Metadata resolution timed out after 55s',
        ),
      );
      if (raw == null) {
        throw const TorrentException(
          'resolve_failed',
          'Native engine returned no metadata',
        );
      }
      final meta = TorrentMetadata.fromMap(raw);
      _metadataCache[meta.infoHash] = meta;
      return meta;
    } on PlatformException catch (error) {
      throw TorrentException(error.code, error.message ?? 'resolve failed');
    } on MissingPluginException {
      throw const TorrentException(
        'unavailable',
        'Torrent engine unavailable on this platform',
      );
    }
  }

  Future<PreparedTorrent> _prepare(
    String infoHash, {
    String? magnet,
    String? filename,
    int? filesize,
    String? displayName,
    List<String> trackers = const <String>[],
    int? fileIndex,
  }) async {
    await _ensureAvailable();

    // Fail fast on an unusable target (Task 128): an empty/garbled info-hash
    // used to make the full round-trip into the native engine before dying
    // with a raw error. 40-hex (v1) or 32-base32 are the playable shapes;
    // a well-formed magnet carrying its own hash is also accepted.
    final hash = infoHash.trim().toLowerCase();
    final validHash = RegExp(r'^[0-9a-f]{40}$').hasMatch(hash) ||
        RegExp(r'^[a-z2-7]{32}$').hasMatch(hash);
    final magnetOk = magnet != null &&
        magnet.toLowerCase().contains('urn:btih:') &&
        RegExp(r'urn:btih:([a-z0-9]{32,40})(?![a-z0-9])', caseSensitive: false)
                .firstMatch(magnet.toLowerCase()) !=
            null;
    if (!validHash && !magnetOk) {
      throw const TorrentException(
        'invalid_magnet',
        'This stream has no usable torrent identifier',
      );
    }

    // 1. Storage directory: <ApplicationDocuments>/torrents/<infoHash>.
    final saveDir = await _saveDirFor(hash);

    // 2. Metadata → target file. Task 129: the magnet now carries the
    //    stream's own trackers merged over the verified defaults, and
    //    resolution first tries the HTTP torrent-file cache (no P2P needed
    //    — the old path died on networks that throttle peer traffic).
    final magnetUri = magnet ??
        magnetFor(hash, dn: displayName ?? filename, extraTrackers: trackers);
    final TorrentMetadata meta =
        _metadataCache[hash] ?? await _resolveSmart(hash, magnetUri);
    _metadataCache[hash] = meta;

    final target = selectTorrentFile(meta, filename, fileIndex);
    if (target == null) {
      throw const TorrentException('no_files', 'Torrent contains no files');
    }

    // Stop the previous active torrent (keeping files for resume) unless the
    // engine should keep downloading the very same torrent.
    final previousHash = _activeHash;
    await _deactivate(
      removeTorrent: previousHash != null && previousHash != hash,
    );

    // 3. Native start: sequential download + smart per-file priorities.
    final started = await _invokeMap('start', <String, Object?>{
      'magnet': magnetUri,
      'fileIndex': target.index,
      'saveDir': saveDir,
      'sequential': true,
    });
    final torrentId =
        (started['torrentId'] as String?)?.trim().isNotEmpty == true
            ? started['torrentId'] as String
            : infoHash;

    // 4. Local range-capable HTTP server for the selected file.
    final absoluteFilePath = _join(saveDir, target.name);
    await _server?.close();
    final server = StreamServer(
      filePath: absoluteFilePath,
      declaredSize: filesize ?? target.size,
    );
    await server.start();
    final url = server.url;
    if (url == null) {
      throw const TorrentException(
          'server_failed', 'Local stream server failed to start');
    }

    // 5. Status stream filtered to the active torrent.
    _server = server;
    _activeHash = torrentId;

    return PreparedTorrent(
      infoHash: torrentId,
      url: url,
      statusStream:
          _broadcastStream.where((status) => status.infoHash == torrentId),
      onStop: () => _stopPrepared(torrentId, server),
    );
  }

  Future<void> _stopPrepared(String torrentId, StreamServer server) async {
    if (identical(_server, server)) {
      _server = null;
      if (_activeHash == torrentId) _activeHash = null;
    }
    await server.close();
    // Keep files on disk so a later prepare() of the same torrent resumes
    // instantly from the pieces already downloaded.
    try {
      await _channel.invokeMethod<void>('remove', <String, Object?>{
        'infoHash': torrentId,
        'deleteFiles': false,
      });
    } on PlatformException {
      // Engine already gone — ignore.
    } on MissingPluginException {
      // Non-Android platform — ignore.
    }
  }

  Future<void> _remove(String infoHash, {required bool deleteFiles}) async {
    await _ensureAvailable();
    if (_activeHash == infoHash) {
      await _server?.close();
      _server = null;
      _activeHash = null;
    }
    try {
      await _channel.invokeMethod<void>('remove', <String, Object?>{
        'infoHash': infoHash,
        'deleteFiles': deleteFiles,
      });
    } on PlatformException catch (error) {
      throw TorrentException(error.code, error.message ?? 'remove failed');
    } on MissingPluginException {
      throw const TorrentException(
        'unavailable',
        'Torrent engine unavailable on this platform',
      );
    }
    _metadataCache.remove(infoHash);
  }

  /// Closes the local server of the previous prepared torrent and optionally
  /// removes it from the native engine (files are always kept on disk).
  Future<void> _deactivate({required bool removeTorrent}) async {
    final server = _server;
    _server = null;
    final hash = _activeHash;
    _activeHash = null;
    await server?.close();
    if (removeTorrent && hash != null) {
      try {
        await _channel.invokeMethod<void>('remove', <String, Object?>{
          'infoHash': hash,
          'deleteFiles': false,
        });
      } on PlatformException {
        // Ignore — best effort cleanup.
      } on MissingPluginException {
        // Ignore.
      }
    }
  }

  Future<Map<Object?, Object?>> _invokeMap(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      final result =
          await _channel.invokeMethod<Map<Object?, Object?>>(method, arguments);
      if (result == null) {
        throw TorrentException(
            '${method}_failed', 'Native engine returned null');
      }
      return result;
    } on PlatformException catch (error) {
      throw TorrentException(error.code, error.message ?? '$method failed');
    } on MissingPluginException {
      throw const TorrentException(
        'unavailable',
        'Torrent engine unavailable on this platform',
      );
    }
  }

  Future<void> _ensureAvailable() async {
    if (!await isSupported) {
      throw const TorrentException(
        'unavailable',
        'Torrent engine unavailable on this platform',
      );
    }
  }

  /// `<ApplicationDocumentsDirectory>/torrents/<infoHash>`, created on demand.
  Future<String> _saveDirFor(String infoHash) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/torrents/$infoHash');
    await dir.create(recursive: true);
    return dir.path;
  }

  /// Broadcast stream of native status events, created once and reused.
  Stream<TorrentStatus> get _broadcastStream {
    var stream = _broadcast;
    if (stream == null) {
      stream = _eventChannel.receiveBroadcastStream().map<TorrentStatus>(
            (dynamic event) => TorrentStatus.fromMap(
              event is Map ? Map<Object?, Object?>.from(event) : const {},
            ),
          );
      _broadcast = stream;
    }
    return stream;
  }

  /// POSIX-safe join (Android/iOS only — the torrent engine is not desktop).
  static String _join(String base, String relative) {
    final clean = relative.replaceAll('\\', '/');
    final slash = base.endsWith('/');
    return slash ? '$base$clean' : '$base/$clean';
  }
}
