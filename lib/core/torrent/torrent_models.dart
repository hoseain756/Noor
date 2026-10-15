/// Data models for the on-device torrent streaming engine.
///
/// These types are shared between the native platform channel bridge
/// (`noor/torrent`), the [TorrentService] singleton and the player UI.
library;

/// A single file inside a torrent.
class TorrentFileInfo {
  const TorrentFileInfo({
    required this.index,
    required this.name,
    required this.size,
  });

  /// Position of the file within the torrent (used for native priority setup).
  final int index;

  /// Path of the file inside the torrent, e.g. `Movie/Movie.2023.mkv`.
  final String name;

  /// Size of the file in bytes.
  final int size;

  factory TorrentFileInfo.fromMap(Map<Object?, Object?> map) => TorrentFileInfo(
        index: (map['index'] as num?)?.toInt() ?? 0,
        name: (map['name'] as String?) ?? '',
        size: (map['size'] as num?)?.toInt() ?? 0,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'index': index,
        'name': name,
        'size': size,
      };

  @override
  bool operator ==(Object other) =>
      other is TorrentFileInfo &&
      other.index == index &&
      other.name == name &&
      other.size == size;

  @override
  int get hashCode => Object.hash(index, name, size);

  @override
  String toString() => 'TorrentFileInfo(#$index, $name, $size B)';
}

/// Metadata of a torrent (everything the swarm exposes before downloading).
class TorrentMetadata {
  const TorrentMetadata({
    required this.name,
    required this.infoHash,
    required this.files,
  });

  /// Display name of the torrent (usually the root folder or file name).
  final String name;

  /// Lowercase hex info-hash, the torrent's unique identifier.
  final String infoHash;

  /// All files contained in the torrent, ordered by index.
  final List<TorrentFileInfo> files;

  factory TorrentMetadata.fromMap(Map<Object?, Object?> map) {
    final rawFiles = (map['files'] as List<Object?>?) ?? const <Object?>[];
    final files = rawFiles
        .whereType<Map<Object?, Object?>>()
        .map(TorrentFileInfo.fromMap)
        .toList(growable: false);
    return TorrentMetadata(
      name: (map['name'] as String?) ?? '',
      infoHash: (map['infoHash'] as String?) ?? '',
      files: files,
    );
  }

  /// The torrent file with [index], or `null` when out of range.
  TorrentFileInfo? fileAt(int index) {
    for (final file in files) {
      if (file.index == index) return file;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is TorrentMetadata &&
      other.name == name &&
      other.infoHash == infoHash &&
      const ListEquality<TorrentFileInfo>().equals(other.files, files);

  @override
  int get hashCode => Object.hash(name, infoHash, Object.hashAll(files));

  @override
  String toString() =>
      'TorrentMetadata($infoHash, "$name", ${files.length} files)';
}

/// Live engine status for one torrent, broadcast over the EventChannel.
class TorrentStatus {
  const TorrentStatus({
    required this.infoHash,
    required this.progress,
    required this.downloadRate,
    required this.uploadRate,
    required this.numPeers,
    required this.numSeeds,
    required this.state,
    required this.filePath,
    required this.fileSize,
    required this.ready,
  });

  factory TorrentStatus.fromMap(Map<Object?, Object?> map) => TorrentStatus(
        infoHash: (map['infoHash'] as String?) ?? '',
        progress: (map['progress'] as num?)?.toDouble() ?? 0,
        downloadRate: (map['downloadRate'] as num?)?.toInt() ?? 0,
        uploadRate: (map['uploadRate'] as num?)?.toInt() ?? 0,
        numPeers: (map['numPeers'] as num?)?.toInt() ?? 0,
        numSeeds: (map['numSeeds'] as num?)?.toInt() ?? 0,
        state: (map['state'] as String?) ?? 'checking',
        filePath: map['filePath'] as String?,
        fileSize: (map['fileSize'] as num?)?.toInt() ?? 0,
        ready: (map['ready'] as bool?) ?? false,
      );

  /// Lowercase hex info-hash of the torrent this status belongs to.
  final String infoHash;

  /// Download progress of the wanted data, `0..1`.
  final double progress;

  /// Current download speed in bytes/second.
  final int downloadRate;

  /// Current upload speed in bytes/second.
  final int uploadRate;

  /// Number of connected peers (leechers).
  final int numPeers;

  /// Number of connected seeds.
  final int numSeeds;

  /// Engine state: `checking`, `downloading`, `finished`, `seeding` or `paused`.
  final String state;

  /// Absolute on-device path of the file selected for streaming.
  final String? filePath;

  /// Real size of the selected file in bytes (preallocated by the engine).
  final int fileSize;

  /// `true` once the first pieces of the selected file are downloaded, meaning
  /// playback can safely start.
  final bool ready;

  @override
  bool operator ==(Object other) =>
      other is TorrentStatus &&
      other.infoHash == infoHash &&
      other.progress == progress &&
      other.downloadRate == downloadRate &&
      other.uploadRate == uploadRate &&
      other.numPeers == numPeers &&
      other.numSeeds == numSeeds &&
      other.state == state &&
      other.filePath == filePath &&
      other.fileSize == fileSize &&
      other.ready == ready;

  @override
  int get hashCode => Object.hash(infoHash, progress, state, ready);

  @override
  String toString() =>
      'TorrentStatus($infoHash, ${(progress * 100).toStringAsFixed(1)}%, '
      '$state, ready=$ready, ${downloadRate ~/ 1024} KB/s)';
}

/// A torrent that has been prepared for streaming: the engine is downloading
/// it and a local HTTP server is exposing the selected file to the player.
class PreparedTorrent {
  PreparedTorrent({
    required this.infoHash,
    required this.url,
    required this.statusStream,
    required Future<void> Function() onStop,
  }) : _onStop = onStop;

  /// Lowercase hex info-hash of the streaming torrent.
  final String infoHash;

  /// Local HTTP URL for the player, e.g. `http://127.0.0.1:4321/stream`.
  final String url;

  /// Live status updates, already filtered to this torrent.
  final Stream<TorrentStatus> statusStream;

  final Future<void> Function() _onStop;

  /// Stops the local HTTP server and removes the torrent from the engine
  /// while keeping downloaded files on disk for a later instant resume.
  Future<void> stop() => _onStop();

  @override
  bool operator ==(Object other) =>
      other is PreparedTorrent &&
      other.infoHash == infoHash &&
      other.url == url;

  @override
  int get hashCode => Object.hash(infoHash, url);

  @override
  String toString() => 'PreparedTorrent($infoHash @ $url)';
}

/// Error raised by the torrent engine, mirroring the native error codes.
class TorrentException implements Exception {
  const TorrentException(this.code, this.message);

  /// Stable machine-readable code, e.g. `metadata_timeout`, `unavailable`.
  final String code;

  /// Human-readable explanation.
  final String message;

  @override
  String toString() => 'TorrentException($code): $message';
}

/// Maps any playback-resolution failure onto a bilingual, actionable message
/// (Task 128): raw exception toasts like `TorrentException(metadata_timeout):
/// Timed out fetching torrent metadata after 30s` gave the user nothing to
/// act on. Recognised codes get specific advice; everything else falls back
/// to a generic try-another-source line.
String torrentFriendlyMessage(Object error, {required bool english}) {
  final code = error is TorrentException ? error.code : '';
  switch (code) {
    case 'metadata_timeout':
    case 'timeout':
      return english
          ? 'Could not find torrent peers in time — your network may block P2P or the swarm is thin. Try again, or pick a direct source.'
          : 'تعذّر العثور على مشاركي التورنت في الوقت المناسب — قد تحجب شبكتك اتصالات P2P أو تكون البذور قليلة. أعد المحاولة أو اختر مصدرًا مباشرًا.';
    case 'invalid_magnet':
      return english
          ? 'This stream has no usable torrent identifier — pick another source.'
          : 'لا يحتوي هذا المصدر على معرّف تورنت صالح — اختر مصدرًا آخر.';
    case 'unavailable':
      return english
          ? 'Torrent streaming needs a device with the built-in engine or a connected Debrid service.'
          : 'البث عبر التورنت يحتاج جهازًا يدعم المحرك المدمج أو خدمة Debrid متصلة.';
    case 'server_failed':
      return english
          ? 'The local stream server could not start — try again or pick another source.'
          : 'تعذّر تشغيل خادم البث المحلي — أعد المحاولة أو اختر مصدرًا آخر.';
    case 'no_files':
      return english
          ? 'This torrent contains no playable files — pick another source.'
          : 'لا يحتوي هذا التورنت على ملفات قابلة للتشغيل — اختر مصدرًا آخر.';
    default:
      return english
          ? 'Could not start this stream — try another source or check your connection.'
          : 'تعذّر بدء هذا البث — جرّب مصدرًا آخر أو تحقق من اتصالك.';
  }
}

/// Minimal structural list equality helper (keeps the models dependency-free).
class ListEquality<T> {
  const ListEquality();

  bool equals(List<T>? a, List<T>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// --------------------------------------------------------------------------- //
//  Torrent source helpers (Task 129 — Torrentio reliability package)
// --------------------------------------------------------------------------- //

/// Extensions recognised as streamable video content. Shared by the torrent
/// service and the file-selection helper so every layer agrees on what
/// "playable" means.
const List<String> kTorrentVideoExtensions = <String>[
  '.mp4',
  '.mkv',
  '.avi',
  '.webm',
  '.mov',
  '.flv',
  '.ts',
  '.rmvb',
];

/// Whether [name] ends with a known playable video extension.
bool isVideoFileName(String name) {
  final lower = name.toLowerCase();
  return kTorrentVideoExtensions.any(lower.endsWith);
}

/// Normalizes a Stremio stream `sources` array (Task 129) into plain tracker
/// announce URLs. Addons ship entries shaped like `tracker:<url>`,
/// `dht:<infohash>` or a bare `udp://`/`http(s)://` announce. Non-tracker
/// shapes (DHT is native to the engine, WSS unsupported) are dropped and the
/// result is de-duplicated while preserving order.
List<String> normalizeTrackerSources(Object? raw) {
  if (raw is! List) return const <String>[];
  final out = <String>[];
  for (final entry in raw) {
    if (entry is! String) continue;
    var value = entry.trim();
    if (value.isEmpty) continue;
    final colon = value.indexOf(':');
    final scheme = colon == -1 ? '' : value.substring(0, colon).toLowerCase();
    switch (scheme) {
      case 'tracker':
        value = value.substring(colon + 1).trim();
        break;
      case 'udp':
      case 'http':
      case 'https':
        break; // bare announce URL — keep as-is
      default:
        continue; // dht:, wss:, garbage
    }
    if (value.isEmpty || !value.contains('://')) continue;
    if (!out.contains(value)) out.add(value);
  }
  return out;
}

/// Case-insensitive, suffix/basename-lenient torrent file-name matcher
/// (moved from [TorrentService] so selection and the service share it).
bool torrentFileMatches(String torrentName, String wanted) {
  final a = _normalizeTorrentName(torrentName);
  final b = _normalizeTorrentName(wanted);
  return a == b || a.endsWith(b) || b.endsWith(a) || _torrentBasename(a) == b;
}

String _normalizeTorrentName(String path) =>
    path.trim().toLowerCase().replaceAll('\\', '/');

String _torrentBasename(String path) {
  final clean = _normalizeTorrentName(path);
  final index = clean.lastIndexOf('/');
  return index == -1 ? clean : clean.substring(index + 1);
}

/// Picks the torrent file to stream (Task 129), in priority order:
///
///  1. the addon's own [fileIndex] (Torrentio `fileIdx`) when it points at a
///     playable video — the authoritative choice for multi-episode packs;
///  2. the [filename] hint (Stremio `behaviorHints.filename`) via lenient
///     matching;
///  3. the file at [fileIndex] even when it lacks a recognised video
///     extension — the addon computed that exact file for this title, and
///     unusual containers (.divx, extension-less) are still playable;
///  4. the largest video file in the torrent;
///  5. the largest file of any kind. Returns null only for an empty torrent.
TorrentFileInfo? selectTorrentFile(
  TorrentMetadata meta,
  String? filename,
  int? fileIndex,
) {
  final files = meta.files;

  TorrentFileInfo? at(int? index) {
    if (index == null || index < 0 || index >= files.length) return null;
    final file = files[index];
    return file.size > 0 ? file : null;
  }

  final indexed = at(fileIndex);
  if (indexed != null && isVideoFileName(indexed.name)) return indexed;

  final wanted = filename?.trim() ?? '';
  if (wanted.isNotEmpty) {
    for (final file in files) {
      if (file.size > 0 && torrentFileMatches(file.name, wanted)) return file;
    }
  }

  if (indexed != null) return indexed;

  final videos = files
      .where((file) => file.size > 0 && isVideoFileName(file.name))
      .toList()
    ..sort((a, b) => b.size.compareTo(a.size));
  if (videos.isNotEmpty) return videos.first;

  final all = files.where((file) => file.size > 0).toList()
    ..sort((a, b) => b.size.compareTo(a.size));
  return all.isEmpty ? null : all.first;
}
