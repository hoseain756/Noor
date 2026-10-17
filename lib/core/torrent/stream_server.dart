import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

/// A parsed single HTTP byte range (`bytes=start-end`).
class _ByteRange {
  const _ByteRange(this.start, this.end);

  final int start;
  final int end;
}

/// Local HTTP server that streams exactly one file with full HTTP Range
/// support, so a media player can seek into a file while the torrent engine
/// is still downloading it.
///
/// Key behaviours:
///  - `Content-Length` always reflects the REAL file size. The torrent engine
///    preallocates the file, and an authoritative [declaredSize] (from the
///    torrent metadata) takes precedence over a partial on-disk stat.
///  - When a requested range reaches a piece that is not complete yet, the
///    server waits instead of streaming preallocated zero bytes to the player.
///  - Supports GET and HEAD, answers 206 with `Content-Range` for single
///    ranges, 416 for unsatisfiable ranges and 404 when the file is missing.
class StreamServer {
  StreamServer({
    required this.filePath,
    this.declaredSize,
    this.availableBytes,
  });

  /// Absolute path of the file being served.
  final String filePath;

  /// Authoritative file size taken from the torrent metadata. When null the
  /// size on disk is used instead.
  final int? declaredSize;

  /// Returns the consecutive byte count currently backed by completed
  /// torrent pieces, starting at the file-relative [offset].
  final Future<int> Function(int offset, int maxBytes)? availableBytes;

  // Check piece availability often enough that the player does not sit idle
  // after libtorrent has completed the next piece on disk.
  static const Duration _pollInterval = Duration(milliseconds: 100);

  /// Maximum time a streaming response may stay idle (no new bytes written)
  /// before it is closed; the player will retry the range if needed.
  static const Duration _stallTimeout = Duration(minutes: 2);

  // Larger reads reduce Dart↔Android channel round trips while still keeping
  // response writes small enough for low-memory phones.
  static const int _chunkSize = 512 * 1024;

  HttpServer? _server;
  bool _closing = false;
  final Set<Future<void>> _pendingRequests = {};

  /// Bound port, or `null` before [start] / after [close].
  int? get port => _server?.port;

  /// Full URL to stream the file from, e.g. `http://127.0.0.1:43210/stream`.
  String? get url =>
      _server == null ? null : 'http://127.0.0.1:${_server!.port}/stream';

  bool get isRunning => _server != null;

  /// Binds the server on an ephemeral loopback port and starts serving.
  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    _closing = false;
    server.listen(
      (HttpRequest request) {
        // Each request is handled independently; errors never kill the server.
        final pending = _handleRequest(request);
        _pendingRequests.add(pending);
        unawaited(pending.whenComplete(() => _pendingRequests.remove(pending)));
      },
      onError: (Object _) {
        // A broken client socket surfaces here; the server keeps running.
      },
    );
    _server = server;
  }

  /// Stops accepting connections and closes the listener. Safe to call twice.
  Future<void> close() async {
    final server = _server;
    _server = null;
    _closing = true;
    if (server != null) {
      try {
        await server.close(force: true);
      } catch (_) {
        // Listener may already be dead.
      }
    }
    if (_pendingRequests.isNotEmpty) {
      await Future.wait(List<Future<void>>.of(_pendingRequests));
    }
  }

  // ------------------------------------------------------------------ //
  //  Request handling
  // ------------------------------------------------------------------ //

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
      }

      final size = _currentFileSize();
      if (size == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      final range =
          _parseRange(request.headers.value(HttpHeaders.rangeHeader), size);
      if (range == _unsatisfiableSentinel) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes */$size',
        );
        await request.response.close();
        return;
      }

      final selected = range as _ByteRange?;
      if (selected == null) {
        await _serve(request, 0, size - 1, size, partial: false);
      } else {
        await _serve(request, selected.start, selected.end, size,
            partial: true);
      }
    } catch (_) {
      try {
        await request.response.close();
      } catch (_) {
        // Response already dead — nothing to do.
      }
    }
  }

  /// Size used for responses: metadata size when available, otherwise the
  /// current on-disk size (the engine preallocates, so this is authoritative).
  int? _currentFileSize() {
    final declared = declaredSize;
    if (declared != null && declared > 0) {
      return declared;
    }
    final stat = FileStat.statSync(filePath);
    if (stat.type == FileSystemEntityType.notFound) return null;
    return stat.size;
  }

  /// Parses the `Range` header. Returns:
  ///  - `null` when absent/multi-range/not bytes → serve a full 200 response;
  ///  - [_unsatisfiableSentinel] → answer 416;
  ///  - a [_ByteRange] with an inclusive [start]/[end] → answer 206.
  ///
  /// A String sentinel is used (instead of `null`) because `null` already
  /// means "no range header, serve everything".
  static const String _unsatisfiableSentinel = '416';

  Object? _parseRange(String? header, int size) {
    if (header == null) return null; // no range → 200 full
    final value = header.trim().toLowerCase();
    if (!value.startsWith('bytes=')) return null; // unknown unit → ignore
    if (value.contains(',')) return null; // multi-range → serve 200 full

    final spec = value.substring('bytes='.length).trim();
    final dash = spec.indexOf('-');
    if (dash < 0) return _unsatisfiableSentinel;

    final startText = spec.substring(0, dash).trim();
    final endText = spec.substring(dash + 1).trim();

    if (startText.isEmpty) {
      // Suffix range: last N bytes.
      final n = int.tryParse(endText);
      if (n == null || n <= 0) return _unsatisfiableSentinel;
      if (size == 0) return _unsatisfiableSentinel;
      return _ByteRange(math.max(0, size - n), size - 1);
    }

    final start = int.tryParse(startText);
    if (start == null || start < 0) return _unsatisfiableSentinel;
    if (start >= size) return _unsatisfiableSentinel;

    var end = size - 1;
    if (endText.isNotEmpty) {
      final parsedEnd = int.tryParse(endText);
      if (parsedEnd == null || parsedEnd < start) return _unsatisfiableSentinel;
      end = math.min(parsedEnd, size - 1);
    }
    return _ByteRange(start, end);
  }

  Future<void> _serve(
    HttpRequest request,
    int start,
    int end,
    int size, {
    required bool partial,
  }) async {
    final response = request.response;
    final length = end - start + 1;

    response.statusCode = partial ? HttpStatus.partialContent : HttpStatus.ok;
    response.headers
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.contentTypeHeader, _contentTypeFor(filePath));
    if (partial) {
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$size',
      );
    }
    // Always advertise the real byte count for this response.
    response.headers.set(HttpHeaders.contentLengthHeader, '$length');

    if (request.method == 'HEAD') {
      await response.close();
      return;
    }

    RandomAccessFile? raf;
    try {
      // Commit the status and headers while the engine is still downloading
      // the requested piece. Players otherwise time out while waiting for the
      // first body bytes and report the loopback URL as unopenable.
      await response.flush();
      raf = await _openWhenExists();
      if (start > 0) await raf.setPosition(start);

      var remaining = length;
      var stallDeadline = DateTime.now().add(_stallTimeout);
      while (remaining > 0 && !_closing) {
        final offset = start + (length - remaining);
        final maxBytes = math.min(_chunkSize, remaining);
        var readableLength = maxBytes;
        final isReadable = availableBytes;
        if (isReadable != null) {
          readableLength = math.min(
            maxBytes,
            await isReadable(offset, maxBytes),
          );
          if (readableLength <= 0) {
            if (DateTime.now().isAfter(stallDeadline)) break;
            await Future<void>.delayed(_pollInterval);
            continue;
          }
        }
        final bytes = await raf.read(readableLength);
        if (bytes.isEmpty) {
          // The file may not have been materialised yet, or the engine may
          // still be writing the completed piece to storage.
          if (DateTime.now().isAfter(stallDeadline)) break;
          await Future<void>.delayed(_pollInterval);
          continue;
        }
        response.add(bytes);
        await response.flush();
        remaining -= bytes.length;
        stallDeadline = DateTime.now().add(_stallTimeout);
      }
      await response.close();
    } catch (_) {
      // Client disconnected or engine file vanished — best-effort cleanup.
      try {
        await response.close();
      } catch (_) {
        // Already closed.
      }
    } finally {
      try {
        await raf?.close();
      } catch (_) {
        // Handle may already be closed.
      }
    }
  }

  /// Opens the target file, WAITING for the torrent engine to create it
  /// when it does not exist yet. libtorrent materialises the selected file
  /// when its first piece lands; on a cold swarm (zero peers — the exact
  /// report: "Failed to open http://127.0.0.1:…/stream" at P:0 S:0 0.0%)
  /// the player's very first request arrived before that moment, the open()
  /// threw and the response closed EMPTY, which mpv reports as "Failed to
  /// open". The response now stays open and starts streaming the moment the
  /// file appears — the same patience the server already applies to file
  /// GROWTH. The deadline bounds the wait to the stall timeout, so a truly
  /// dead swarm still fails loudly instead of hanging forever.
  Future<RandomAccessFile> _openWhenExists() async {
    final deadline = DateTime.now().add(_stallTimeout);
    while (true) {
      if (_closing) throw StateError('Stream server is closing.');
      try {
        return await File(filePath).open();
      } on FileSystemException {
        if (DateTime.now().isAfter(deadline)) rethrow;
        await Future<void>.delayed(_pollInterval);
      }
    }
  }

  /// Best-effort `Content-Type` for video containers; defaults to mp4, which
  /// every Android player accepts.
  static String _contentTypeFor(String path) {
    final name = path.toLowerCase();
    final dot = name.lastIndexOf('.');
    final ext = dot == -1 ? '' : name.substring(dot + 1);
    switch (ext) {
      case 'mp4':
      case 'm4v':
      case 'm4a':
        return 'video/mp4';
      case 'mkv':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';
      case 'avi':
        return 'video/x-msvideo';
      case 'mov':
        return 'video/quicktime';
      case 'flv':
        return 'video/x-flv';
      case 'ts':
      case 'm2ts':
      case 'mts':
        return 'video/mp2t';
      case 'wmv':
        return 'video/x-ms-wmv';
      case 'rm':
      case 'rmvb':
        return 'application/vnd.rn-realmedia-vbr';
      case 'ogg':
      case 'ogv':
        return 'video/ogg';
      case 'mp3':
        return 'audio/mpeg';
      case 'flac':
        return 'audio/flac';
      case 'srt':
        return 'application/x-subrip';
      default:
        return 'video/mp4';
    }
  }
}
