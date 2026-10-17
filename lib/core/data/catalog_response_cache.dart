import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Bounded device-local stale-while-revalidate cache for addon catalogs/metadata.
/// Never used for stream URLs, OAuth, personalized libraries or credential calls.
class CatalogResponseCache extends ChangeNotifier {
  CatalogResponseCache._();
  static final instance = CatalogResponseCache._();
  final _memory = <String, (DateTime, dynamic)>{};
  final _pending = <String, Future<dynamic>>{};
  Future<Directory?>? _root;
  int revision = 0;
  Future<Directory?> _directory() => _root ??= () async {
        try {
          final root = await getTemporaryDirectory();
          return await Directory('${root.path}/nova_catalog_v1')
              .create(recursive: true);
        } catch (_) {
          return null;
        }
      }();
  Future<dynamic> get(String key, Future<dynamic> Function() loader) async {
    final digest = sha256.convert(utf8.encode(key)).toString();
    var cached = _memory[digest];
    if (cached == null) {
      try {
        final directory = await _directory();
        if (directory != null) {
          final file = File('${directory.path}/$digest.json');
          if (await file.exists()) {
            final record = await compute(_decode, await file.readAsString());
            cached = (
              DateTime.fromMillisecondsSinceEpoch(record['time'] as int),
              record['data']
            );
            if (DateTime.now().difference(cached.$1).inDays < 7)
              _remember(digest, cached);
            else
              cached = null;
          }
        }
      } catch (_) {
        cached = null;
      }
    }
    if (cached != null) {
      if (DateTime.now().difference(cached.$1) > const Duration(minutes: 10)) {
        unawaited(_refresh(digest, loader, announce: true)
            .then<void>((_) {}, onError: (_) {}));
      }
      return cached.$2;
    }
    return _refresh(digest, loader);
  }

  void _remember(String key, (DateTime, dynamic) entry) {
    _memory.remove(key);
    _memory[key] = entry;
    while (_memory.length > 80) {
      _memory.remove(_memory.keys.first);
    }
  }

  Future<dynamic> _refresh(String key, Future<dynamic> Function() loader,
      {bool announce = false}) {
    return _pending.putIfAbsent(key, () async {
      try {
        final value = await loader();
        final time = DateTime.now();
        _remember(key, (time, value));
        unawaited(_persist(key, time, value));
        if (announce) {
          revision++;
          notifyListeners();
        }
        return value;
      } finally {
        _pending.remove(key);
      }
    });
  }

  Future<void> _persist(String key, DateTime time, dynamic value) async {
    try {
      final root = await _directory();
      if (root == null) return;
      final text = await compute(
          _encode, {'time': time.millisecondsSinceEpoch, 'data': value});
      if (text.length > 2 * 1024 * 1024) return;
      await File('${root.path}/$key.json').writeAsString(text);
      final files =
          await root.list().where((e) => e is File).cast<File>().toList();
      if (files.length > 80) {
        final dated = await Future.wait(
            files.map((file) async => (file, await file.lastModified())));
        dated.sort((a, b) => a.$2.compareTo(b.$2));
        for (final entry in dated.take(dated.length - 80)) {
          await entry.$1.delete();
        }
      }
    } catch (_) {/* Cache failure never prevents browsing. */}
  }

  Future<void> clear() async {
    _memory.clear();
    final root = await _directory();
    if (root != null && await root.exists()) {
      await for (final file in root.list()) {
        if (file is File) await file.delete();
      }
    }
  }
}

Map<String, dynamic> _decode(String text) =>
    jsonDecode(text) as Map<String, dynamic>;
String _encode(Map<String, dynamic> value) => jsonEncode(value);
