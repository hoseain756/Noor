import 'dart:async';
import 'dart:io';

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
  static const List<String> _defaultTrackers = <String>[
    'udp://tracker.opentrackr.org:1337/announce',
    'udp://open.demonii.com:1337/announce',
    'udp://open.stealth.si:80/announce',
    'udp://tracker.torrent.eu.org:451/announce',
    'udp://exodus.desync.com:6969/announce',
    'udp://tracker.tiny-vps.com:6969/announce',
    'udp://tracker.dler.org:6969/announce',
    'udp://opentracker.i2p.rocks:6969/announce',
  ];

  /// Extensions recognised as streamable video content.
  static const List<String> _videoExtensions = <String>[
    '.mp4',
    '.mkv',
    '.avi',
    '.webm',
    '.mov',
    '.flv',
    '.ts',
    '.rmvb',
  ];

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

  /// Fetches metadata (name + file list) for [magnet] without downloading.
  ///
  /// The native engine enforces a 30 second timeout; a Dart-side safety net
  /// caps the await slightly above it and raises [TorrentException].
  Future<TorrentMetadata> resolve(String magnet) {
    return _serialized(() => _resolve(magnet));
  }

  /// Prepares a torrent for on-device streaming:
  ///
  ///  1. resolves metadata (unless already cached) to locate the target file —
  ///     the largest video file when [filename] is not given;
  ///  2. starts the native engine with sequential download enabled and
  ///     per-file priorities (target file high, first/last pieces highest);
  ///  3. starts a local loopback HTTP server with Range support serving the
  ///     selected file from inside `<documents>/torrents/<infoHash>/`;
  ///  4. returns a [PreparedTorrent] exposing the player URL plus a live
  ///     status stream, and a `stop()` that closes the server and removes the
  ///     torrent from the engine while keeping its files for instant resume.
  Future<PreparedTorrent> prepare({
    required String infoHash,
    String? magnet,
    String? filename,
    int? filesize,
    String? displayName,
  }) {
    return _serialized(
      () => _prepare(
        infoHash,
        magnet: magnet,
        filename: filename,
        filesize: filesize,
        displayName: displayName,
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

  /// Builds a magnet URI for [infoHash] with an optional display name and the
  /// default public tracker list appended.
  static String magnetFor(String infoHash, {String? dn}) {
    final hash = infoHash.trim().toLowerCase();
    final buffer = StringBuffer('magnet:?xt=urn:btih:$hash');
    if (dn != null && dn.trim().isNotEmpty) {
      buffer.write('&dn=${Uri.encodeComponent(dn.trim())}');
    }
    for (final tracker in _defaultTrackers) {
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

  Future<TorrentMetadata> _resolve(String magnet) async {
    await _ensureAvailable();
    try {
      final raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('resolve', <String, Object?>{
        'magnet': magnet,
      }).timeout(
        const Duration(seconds: 35),
        onTimeout: () => throw const TorrentException(
          'timeout',
          'Metadata resolution timed out after 35s',
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
  }) async {
    await _ensureAvailable();

    // 1. Storage directory: <ApplicationDocuments>/torrents/<infoHash>.
    final saveDir = await _saveDirFor(infoHash);

    // 2. Metadata → target file. Reuse cached metadata when possible.
    final TorrentMetadata meta = _metadataCache[infoHash] ??
        await _resolve(magnet ?? magnetFor(infoHash, dn: displayName ?? filename));
    _metadataCache[infoHash] = meta;

    final TorrentFileInfo target;
    if (filename != null && filename.trim().isNotEmpty) {
      target = meta.files.firstWhere(
        (file) => _matchesName(file.name, filename),
        orElse: () => _pickLargestVideo(meta),
      );
    } else {
      target = _pickLargestVideo(meta);
    }

    // Stop the previous active torrent (keeping files for resume) unless the
    // engine should keep downloading the very same torrent.
    final previousHash = _activeHash;
    await _deactivate(
      removeTorrent: previousHash != null && previousHash != infoHash,
    );

    // 3. Native start: sequential download + smart per-file priorities.
    final started = await _invokeMap('start', <String, Object?>{
      'magnet': magnet ?? magnetFor(infoHash, dn: displayName ?? target.name),
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
      throw const TorrentException('server_failed', 'Local stream server failed to start');
    }

    // 5. Status stream filtered to the active torrent.
    _server = server;
    _activeHash = torrentId;

    return PreparedTorrent(
      infoHash: torrentId,
      url: url,
      statusStream: _broadcastStream.where((status) => status.infoHash == torrentId),
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
        throw TorrentException('${method}_failed', 'Native engine returned null');
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
      stream = _eventChannel
          .receiveBroadcastStream()
          .map<TorrentStatus>(
            (dynamic event) => TorrentStatus.fromMap(
              event is Map ? Map<Object?, Object?>.from(event) : const {},
            ),
          );
      _broadcast = stream;
    }
    return stream;
  }

  /// Picks the largest playable video file, falling back to the largest file
  /// of the torrent when nothing looks like video.
  TorrentFileInfo _pickLargestVideo(TorrentMetadata meta) {
    final videos = meta.files
        .where(
          (file) =>
              file.size > 0 &&
              _videoExtensions.any(
                (extension) => file.name.toLowerCase().endsWith(extension),
              ),
        )
        .toList()
      ..sort((a, b) => b.size.compareTo(a.size));
    if (videos.isNotEmpty) return videos.first;

    final all = meta.files.where((file) => file.size > 0).toList()
      ..sort((a, b) => b.size.compareTo(a.size));
    if (all.isEmpty) {
      throw const TorrentException('no_files', 'Torrent contains no files');
    }
    return all.first;
  }

  /// Lenient name match: exact, suffix or basename equality (case-insensitive).
  bool _matchesName(String torrentName, String wanted) {
    final a = _normalize(torrentName);
    final b = _normalize(wanted);
    return a == b || a.endsWith(b) || b.endsWith(a) || _basename(a) == b;
  }

  static String _normalize(String path) => path.trim().toLowerCase().replaceAll('\\', '/');

  static String _basename(String path) {
    final clean = _normalize(path);
    final index = clean.lastIndexOf('/');
    return index == -1 ? clean : clean.substring(index + 1);
  }

  /// POSIX-safe join (Android/iOS only — the torrent engine is not desktop).
  static String _join(String base, String relative) {
    final clean = relative.replaceAll('\\', '/');
    final slash = base.endsWith('/');
    return slash ? '$base$clean' : '$base/$clean';
  }
}
