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
