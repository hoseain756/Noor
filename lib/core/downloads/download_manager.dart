import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class NovaDownload {
  NovaDownload(
      {required this.id,
      required this.title,
      required this.path,
      this.status = 'queued',
      this.received = 0,
      this.total = 0,
      this.error});
  final String id, title, path;
  String status;
  int received, total;

  /// Stable diagnostic code; never contains a provider URL or credential.
  String? error;
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'path': path,
        'status': status,
        'received': received,
        'total': total,
        if (error != null) 'error': error
      };
  factory NovaDownload.fromJson(Map<String, dynamic> json) => NovaDownload(
      id: json['id'] as String,
      title: json['title'] as String,
      path: json['path'] as String,
      status: json['status'] as String? ?? 'failed',
      received: (json['received'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      error: json['error'] as String?);
}

/// Standalone video downloads. Sources stay in secure storage; metadata is local.
/// Mutations and persistence are serialized independently of the network worker.
/// Cancellation settles the active writer before Retry or Remove can proceed.
class DownloadManager extends ChangeNotifier {
  DownloadManager._()
      : this._withDependencies(
          downloadDirectory: () async {
            final root = await getApplicationDocumentsDirectory();
            return Directory(
                '${root.path}${Platform.pathSeparator}nova_downloads');
          },
          readMetadata: () async =>
              (await SharedPreferences.getInstance()).getString(_metadataKey),
          writeMetadata: (value) async {
            if (!await (await SharedPreferences.getInstance())
                .setString(_metadataKey, value)) {
              throw const FileSystemException(
                  'Download metadata could not be saved');
            }
          },
          readSecret: (key) => _secure.read(key: key),
          writeSecret: (key, value) => _secure.write(key: key, value: value),
          deleteSecret: (key) => _secure.delete(key: key),
        );

  @visibleForTesting
  DownloadManager.forTesting({
    required Future<Directory> Function() downloadDirectory,
    required Future<String?> Function() readMetadata,
    required Future<void> Function(String) writeMetadata,
    required Future<String?> Function(String) readSecret,
    required Future<void> Function(String, String) writeSecret,
    required Future<void> Function(String) deleteSecret,
    required Dio dio,
  }) : this._withDependencies(
            downloadDirectory: downloadDirectory,
            readMetadata: readMetadata,
            writeMetadata: writeMetadata,
            readSecret: readSecret,
            writeSecret: writeSecret,
            deleteSecret: deleteSecret,
            dio: dio);

  DownloadManager._withDependencies({
    required Future<Directory> Function() downloadDirectory,
    required Future<String?> Function() readMetadata,
    required Future<void> Function(String) writeMetadata,
    required Future<String?> Function(String) readSecret,
    required Future<void> Function(String, String) writeSecret,
    required Future<void> Function(String) deleteSecret,
    Dio? dio,
  })  : _downloadDirectory = downloadDirectory,
        _readMetadata = readMetadata,
        _writeMetadata = writeMetadata,
        _readSecret = readSecret,
        _writeSecret = writeSecret,
        _deleteSecret = deleteSecret,
        _dio = dio ??
            Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 45)));

  static final instance = DownloadManager._();
  static const _secure = FlutterSecureStorage();
  static const _metadataKey = 'nova.downloads.v1';
  static final _idPattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false);
  static final _filePattern =
      RegExp(r'\.(mp4|mkv|webm|avi|mov|m4v)$', caseSensitive: false);
  final Future<Directory> Function() _downloadDirectory;
  final Future<String?> Function() _readMetadata;
  final Future<void> Function(String) _writeMetadata;
  final Future<String?> Function(String) _readSecret;
  final Future<void> Function(String, String) _writeSecret;
  final Future<void> Function(String) _deleteSecret;
  final Dio _dio;
  final _jobs = <NovaDownload>[];
  Future<void>? _initializing, _pumpFuture;
  Future<void> _operations = Future<void>.value();
  Future<void> _persistence = Future<void>.value();
  Directory? _root;
  CancelToken? _token;
  String? _activeId;
  Completer<void>? _activeDone;
  bool _disposed = false;
  bool initialized = false;

  /// Exposed so startup/storage errors are not mistaken for an empty library.
  String? initializationError;
  String? storageError;
  List<NovaDownload> get jobs => List.unmodifiable(_jobs);

  Future<void> initialize() {
    if (initialized) return Future<void>.value();
    return _initializing ??= _load().whenComplete(() {
      if (!initialized) _initializing = null;
    });
  }

  Future<void> _load() async {
    initializationError = null;
    try {
      final requested = await _downloadDirectory();
      final existingType =
          await FileSystemEntity.type(requested.path, followLinks: false);
      if (existingType != FileSystemEntityType.notFound &&
          existingType != FileSystemEntityType.directory) {
        throw const FileSystemException(
            'Download root is not a private directory');
      }
      await requested.create(recursive: true);
      final resolved = await requested.resolveSymbolicLinks();
      final parent = await requested.parent.resolveSymbolicLinks();
      final name =
          requested.uri.pathSegments.where((part) => part.isNotEmpty).last;
      if (_normalized(resolved) !=
              _normalized('$parent${Platform.pathSeparator}$name') ||
          await FileSystemEntity.type(requested.path, followLinks: false) !=
              FileSystemEntityType.directory) {
        throw const FileSystemException(
            'Download root cannot be a symbolic link');
      }
      _root = Directory(resolved);
      final raw = await _readMetadata();
      final loaded = <NovaDownload>[];
      var repaired = false;
      if (raw != null) {
        List<dynamic> rows;
        try {
          rows = jsonDecode(raw) as List<dynamic>;
        } catch (_) {
          rows = [];
          repaired = true;
        }
        final seen = <String>{};
        for (final row in rows) {
          try {
            if (row is! Map) {
              repaired = true;
              continue;
            }
            final job = NovaDownload.fromJson(Map<String, dynamic>.from(row));
            if (!seen.add(job.id) || !await _managedPath(job)) {
              repaired = true;
              continue;
            }
            if (job.received < 0 || job.total < 0) {
              repaired = true;
              continue;
            }
            if (!{'queued', 'downloading', 'failed', 'cancelled', 'complete'}
                .contains(job.status)) {
              job.status = 'failed';
              job.error = 'metadata';
              repaired = true;
            }
            if (job.status == 'queued' || job.status == 'downloading') {
              job.status = 'failed';
              job.error = 'interrupted';
              repaired = true;
            }
            if (job.status == 'complete' &&
                !await _isVideoFile(File(job.path))) {
              job.status = 'failed';
              job.error = 'missingFile';
              repaired = true;
            }
            loaded.add(job);
          } catch (_) {
            repaired = true;
          }
        }
      }
      _jobs
        ..clear()
        ..addAll(loaded);
      initialized = true;
      if (repaired) await _persistSafely();
    } catch (_) {
      initializationError = 'storage';
      initialized = false;
    }
    _notify();
  }

  Future<void> _serial(Future<void> Function() action) {
    final result = _operations.then((_) async {
      if (_disposed) throw StateError('Download manager is closed');
      await initialize();
      if (!initialized) {
        throw const FileSystemException('Download storage is unavailable');
      }
      await action();
    });
    _operations =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> enqueue(
          {required String url,
          required String title,
          Map<String, String> headers = const {}}) =>
      _serial(() async {
        final uri = _validateSource(url, headers);
        final id = const Uuid().v4();
        final extension =
            _filePattern.firstMatch(uri.path)?.group(1)?.toLowerCase() ?? 'mp4';
        final job = NovaDownload(
            id: id,
            title: title,
            path: '${_root!.path}${Platform.pathSeparator}$id.$extension');
        if (!await _managedPath(job)) {
          throw const FileSystemException('Unsafe download destination');
        }
        final key = 'nova.download.$id';
        await _writeSecret(key, jsonEncode({'url': url, 'headers': headers}));
        _jobs.insert(0, job);
        try {
          await _persist();
        } catch (_) {
          _jobs.remove(job);
          try {
            await _deleteSecret(key);
          } catch (_) {/* Orphan secret has no public metadata. */}
          rethrow;
        }
        _notify();
        _startPump();
      });

  Future<void> retry(NovaDownload job) => _serial(() async {
        if (!_jobs.contains(job) ||
            job.status == 'complete' ||
            job.status == 'downloading' ||
            job.status == 'queued') {
          return;
        }
        await _settleActive(job);
        if (!await _managedPath(job)) {
          throw const FileSystemException('Unsafe download destination');
        }
        job.status = 'queued';
        job.error = null;
        job.received = 0;
        job.total = 0;
        try {
          await _persist();
        } catch (_) {
          job.status = 'failed';
          job.error = 'storage';
          _notify();
          rethrow;
        }
        _notify();
        _startPump();
      });

  Future<void> cancel(NovaDownload job) => _serial(() async {
        if (!_jobs.contains(job) || job.status == 'complete') return;
        job.status = 'cancelled';
        job.error = null;
        _notify();
        await _settleActive(job);
        await _persist();
        _notify();
      });

  Future<void> remove(NovaDownload job) => _serial(() async {
        if (!_jobs.contains(job)) return;
        final previous = job.status;
        if (previous != 'complete') job.status = 'cancelled';
        await _settleActive(job);
        // Validate the actual parent and reject links before every disk mutation.
        if (!await _managedPath(job)) {
          throw const FileSystemException('Unsafe download destination');
        }
        try {
          await _deleteManagedFile(job, partial: true);
          await _deleteManagedFile(job);
          await _deleteSecret('nova.download.${job.id}');
        } catch (_) {
          if (!await File(job.path).exists()) job.status = 'failed';
          job.error = 'storage';
          await _persistSafely();
          _notify();
          rethrow;
        }
        _jobs.remove(job);
        try {
          await _persist();
        } catch (_) {
          // Keep an honest visible failure if metadata removal could not be committed.
          job.status = 'failed';
          job.error = 'storage';
          _jobs.insert(0, job);
          _notify();
          rethrow;
        }
        _notify();
      });

  Future<void> _settleActive(NovaDownload job) async {
    if (_activeId != job.id) return;
    final done = _activeDone;
    _token?.cancel();
    if (done != null) await done.future;
  }

  void _startPump() {
    if (_disposed || _pumpFuture != null) return;
    _pumpFuture = _pump().whenComplete(() {
      _pumpFuture = null;
      if (!_disposed && _jobs.any((job) => job.status == 'queued')) {
        _startPump();
      }
    });
  }

  Future<void> _pump() async {
    while (!_disposed && _jobs.any((job) => job.status == 'queued')) {
      final job = _jobs.lastWhere((job) => job.status == 'queued');
      final token = CancelToken();
      final done = Completer<void>();
      _activeId = job.id;
      _token = token;
      _activeDone = done;
      job.status = 'downloading';
      job.error = null;
      _notify();
      var lastPaint = DateTime.now();
      try {
        if (!await _managedPath(job)) {
          throw const FileSystemException('Unsafe download destination');
        }
        final raw = await _readSecret('nova.download.${job.id}');
        if (raw == null) throw const FormatException('Missing download source');
        final source = jsonDecode(raw) as Map;
        final headers =
            Map<String, String>.from(source['headers'] as Map? ?? const {});
        final url = source['url'] as String;
        _validateSource(url, headers);
        if (token.isCancelled) continue;
        final partial = File('${job.path}.part');
        if (!await _managedPath(job, partial: true)) {
          throw const FileSystemException('Unsafe partial destination');
        }
        final response = await _dio.download(url, partial.path,
            options: Options(headers: headers),
            cancelToken: token,
            deleteOnError: false, onReceiveProgress: (received, total) {
          if (token.isCancelled || !_jobs.contains(job)) return;
          job.received = received;
          job.total = total > 0 ? total : 0;
          if (DateTime.now().difference(lastPaint).inMilliseconds >= 200) {
            lastPaint = DateTime.now();
            _notify();
          }
        });
        if (token.isCancelled ||
            job.status == 'cancelled' ||
            !_jobs.contains(job)) {
          continue;
        }
        final contentType =
            (response.headers.value('content-type') ?? '').toLowerCase();
        if (contentType.contains('text/') ||
            contentType.contains('json') ||
            contentType.contains('mpegurl') ||
            contentType.contains('dash+xml') ||
            !await _isVideoFile(partial)) {
          throw const FormatException(
              'Response is not a standalone video file');
        }
        final bytes = await partial.length();
        final expected =
            int.tryParse(response.headers.value('content-length') ?? '');
        // Compressed HTTP bodies may have a different transport length.
        if (expected != null &&
            response.headers.value('content-encoding') == null &&
            bytes != expected) {
          throw const FormatException('Incomplete download');
        }
        if (!await _managedPath(job) ||
            !await _managedPath(job, partial: true)) {
          throw const FileSystemException('Unsafe download destination');
        }
        await partial.rename(job.path);
        job.received = bytes;
        job.total = bytes;
        job.status = 'complete';
      } catch (error) {
        if (job.status != 'cancelled' && _jobs.contains(job)) {
          job.status = 'failed';
          job.error = error is FileSystemException
              ? 'storage'
              : error is FormatException
                  ? 'invalidSource'
                  : 'network';
        }
      } finally {
        try {
          await _deleteManagedFile(job, partial: true);
        } catch (_) {
          if (job.status != 'complete') job.error = 'storage';
        }
        await _persistSafely();
        _activeId = null;
        _token = null;
        _activeDone = null;
        _notify();
        done.complete();
      }
    }
  }

  Uri _validateSource(String url, Map<String, String> headers) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        RegExp(r'\.(m3u8|mpd)$', caseSensitive: false).hasMatch(uri.path) ||
        headers.entries.any((entry) =>
            RegExp(r'[\r\n]').hasMatch('${entry.key}${entry.value}'))) {
      throw const FormatException('A direct video file is required');
    }
    return uri;
  }

  String _normalized(String path) {
    final value = File(path).absolute.uri.normalizePath().toString();
    return Platform.isWindows ? value.toLowerCase() : value;
  }

  Future<bool> _managedPath(NovaDownload job, {bool partial = false}) async {
    final root = _root;
    if (root == null || !_idPattern.hasMatch(job.id)) return false;
    final extension =
        _filePattern.firstMatch(job.path)?.group(1)?.toLowerCase();
    if (extension == null) return false;
    final expected =
        '${root.path}${Platform.pathSeparator}${job.id}.$extension';
    if (_normalized(job.path) != _normalized(expected)) return false;
    if (_normalized(await root.resolveSymbolicLinks()) !=
        _normalized(root.path)) {
      return false;
    }
    final path = partial ? '${job.path}.part' : job.path;
    final type = await FileSystemEntity.type(path, followLinks: false);
    return type == FileSystemEntityType.notFound ||
        type == FileSystemEntityType.file;
  }

  Future<void> _deleteManagedFile(NovaDownload job,
      {bool partial = false}) async {
    if (!await _managedPath(job, partial: partial)) {
      throw const FileSystemException('Unsafe download destination');
    }
    final file = File(partial ? '${job.path}.part' : job.path);
    if (await file.exists()) await file.delete();
  }

  Future<bool> _isVideoFile(File file) async {
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.length() < 16) {
      return false;
    }
    final handle = await file.open();
    try {
      final bytes = await handle.read(64);
      bool asciiAt(int offset, String value) =>
          bytes.length >= offset + value.length &&
          List.generate(
                  value.length, (i) => bytes[offset + i] == value.codeUnitAt(i))
              .every((same) => same);
      return asciiAt(4, 'ftyp') || // ISO BMFF: MP4/M4V/QuickTime.
          (bytes[0] == 0x1a &&
              bytes[1] == 0x45 &&
              bytes[2] == 0xdf &&
              bytes[3] == 0xa3) || // Matroska/WebM.
          (asciiAt(0, 'RIFF') && (asciiAt(8, 'AVI ') || asciiAt(8, 'AVIX'))) ||
          asciiAt(4, 'moov') ||
          asciiAt(4, 'mdat'); // Older QuickTime containers.
    } finally {
      await handle.close();
    }
  }

  Future<void> _persist() {
    final value = jsonEncode(_jobs.map((job) => job.toJson()).toList());
    final result = _persistence.then((_) => _writeMetadata(value));
    _persistence = result.then<void>((_) {
      storageError = null;
    }, onError: (Object _, StackTrace __) {
      storageError = 'storage';
    });
    return result;
  }

  Future<void> _persistSafely() async {
    try {
      await _persist();
    } catch (_) {
      storageError = 'storage';
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @visibleForTesting
  Future<void> waitForIdle() async {
    await _operations;
    while (_pumpFuture != null) {
      await _pumpFuture;
    }
    await _persistence;
  }

  @override
  void dispose() {
    _disposed = true;
    _token?.cancel();
    super.dispose();
  }
}
