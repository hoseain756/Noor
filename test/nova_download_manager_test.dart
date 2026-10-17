import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noor_mobile/core/downloads/download_manager.dart';

final _video = <int>[
  0,
  0,
  0,
  24,
  ...ascii.encode('ftypisom'),
  ...List.filled(52, 0)
];
ResponseBody _response(List<int> bytes,
        {int status = 200, String type = 'video/mp4', int? length}) =>
    ResponseBody.fromBytes(bytes, status, headers: {
      Headers.contentTypeHeader: [type],
      Headers.contentLengthHeader: ['${length ?? bytes.length}'],
    });

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions, Future<void>?) respond;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    requests.add(options);
    return respond(options, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

class _Store {
  _Store(this.root);
  final Directory root;
  String? metadata;
  final secrets = <String, String>{};
  int reads = 0;
  bool failRead = false, failWrite = false, failSecretDelete = false;
  DownloadManager manager(_Adapter adapter) => DownloadManager.forTesting(
        downloadDirectory: () async => root,
        readMetadata: () async {
          reads++;
          if (failRead) throw const FileSystemException('Read denied');
          return metadata;
        },
        writeMetadata: (value) async {
          if (failWrite) throw const FileSystemException('Write denied');
          metadata = value;
        },
        readSecret: (key) async => secrets[key],
        writeSecret: (key, value) async {
          secrets[key] = value;
        },
        deleteSecret: (key) async {
          if (failSecretDelete)
            throw const FileSystemException('Secret deletion denied');
          secrets.remove(key);
        },
        dio: Dio()..httpClientAdapter = adapter,
      );
}

void main() {
  late Directory sandbox;
  late _Store store;
  final managers = <DownloadManager>[];
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('nova-download-test-');
    store = _Store(
        Directory('${sandbox.path}${Platform.pathSeparator}nova_downloads'));
  });
  tearDown(() async {
    for (final manager in managers) {
      manager.dispose();
      await manager.waitForIdle().timeout(const Duration(seconds: 5));
    }
    managers.clear();
    // The fixture creates only these two directories. No recursive deletion.
    for (final directory in [
      store.root,
      Directory('${sandbox.path}${Platform.pathSeparator}outside'),
      sandbox
    ]) {
      if (await FileSystemEntity.type(directory.path, followLinks: false) ==
          FileSystemEntityType.link) {
        await Link(directory.path).delete();
        continue;
      }
      if (await directory.exists()) {
        await for (final entry in directory.list(followLinks: false)) {
          if (entry is File) await entry.delete();
          if (entry is Link) await entry.delete();
        }
        await directory.delete();
      }
    }
  });
  DownloadManager make(_Adapter adapter) {
    final manager = store.manager(adapter);
    managers.add(manager);
    return manager;
  }

  test(
      'concurrent enqueues initialize once and keep every job and private source',
      () async {
    final adapter = _Adapter((_, __) async => _response(_video));
    final manager = make(adapter);
    await Future.wait([
      manager.enqueue(
          url: 'https://video.example/a.mp4?token=private-a',
          title: 'A',
          headers: {'Authorization': 'Bearer private-header'}),
      manager.enqueue(
          url: 'https://video.example/b.mp4?token=private-b', title: 'B'),
    ]);
    await manager.waitForIdle();
    expect(store.reads, 1);
    expect(manager.jobs.length, 2);
    expect(manager.jobs.every((job) => job.status == 'complete'), isTrue);
    expect((jsonDecode(store.metadata!) as List).length, 2);
    expect(store.metadata, isNot(contains('private-')));
    expect(store.secrets.length, 2);
    expect(adapter.requests.length, 2);
    for (final job in manager.jobs) {
      expect(await File(job.path).readAsBytes(), _video);
    }
  });

  test('Cancel followed immediately by Retry waits for the old writer',
      () async {
    final started = Completer<void>();
    var count = 0;
    final adapter = _Adapter((options, cancelled) async {
      count++;
      if (count > 1) return _response(_video);
      final stream = StreamController<Uint8List>();
      stream.onListen = () {
        stream.add(Uint8List.fromList(_video.take(16).toList()));
        started.complete();
      };
      cancelled?.then((_) {
        if (!stream.isClosed) {
          stream.addError(DioException.requestCancelled(
              requestOptions: options, reason: 'test cancellation'));
          unawaited(stream.close());
        }
      });
      return ResponseBody(stream.stream, 200, headers: {
        Headers.contentTypeHeader: ['video/mp4'],
        Headers.contentLengthHeader: ['${_video.length}']
      });
    });
    final manager = make(adapter);
    await manager.enqueue(
        url: 'https://video.example/movie.mp4', title: 'Movie');
    await started.future.timeout(const Duration(seconds: 5));
    final job = manager.jobs.single;
    final cancel = manager.cancel(job);
    final retry = manager.retry(job);
    await Future.wait([cancel, retry]).timeout(const Duration(seconds: 5));
    await manager.waitForIdle().timeout(const Duration(seconds: 5));
    expect(count, 2);
    expect(job.status, 'complete');
    expect(await File(job.path).readAsBytes(), _video);
    expect(await File('${job.path}.part').exists(), isFalse);
  });

  test(
      'failed metadata commit rolls back enqueue and does not start network work',
      () async {
    store.failWrite = true;
    final adapter = _Adapter((_, __) async => _response(_video));
    final manager = make(adapter);
    await expectLater(
        manager.enqueue(url: 'https://video.example/a.mp4', title: 'A'),
        throwsA(isA<FileSystemException>()));
    await manager.waitForIdle();
    expect(manager.jobs, isEmpty);
    expect(store.secrets, isEmpty);
    expect(adapter.requests, isEmpty);
    expect(manager.storageError, 'storage');
  });

  test('reload retries from secure source and preserves request headers',
      () async {
    final first = make(_Adapter((_, __) async => _response([], status: 503)));
    await first.enqueue(
        url: 'https://video.example/movie.mp4?token=private',
        title: 'Movie',
        headers: {'Authorization': 'Bearer saved'});
    await first.waitForIdle();
    expect(first.jobs.single.status, 'failed');
    final adapter = _Adapter((_, __) async => _response(_video));
    final restored = make(adapter);
    await restored.initialize();
    await restored.retry(restored.jobs.single);
    await restored.waitForIdle();
    expect(restored.jobs.single.status, 'complete');
    expect(adapter.requests.single.uri.query, 'token=private');
    expect(adapter.requests.single.headers['Authorization'], 'Bearer saved');
  });

  for (final payload in <List<int>>[
    [],
    utf8.encode('<html>This is an error document, not a movie.</html>')
  ]) {
    test('HTTP success with empty or disguised text is not reported as a video',
        () async {
      final manager = make(_Adapter((_, __) async =>
          _response(payload, type: 'application/octet-stream')));
      await manager.enqueue(
          url: 'https://video.example/movie.mp4', title: 'Movie');
      await manager.waitForIdle();
      final job = manager.jobs.single;
      expect(job.status, 'failed');
      expect(job.error, 'invalidSource');
      expect(await File(job.path).exists(), isFalse);
      expect(await File('${job.path}.part').exists(), isFalse);
    });
  }

  test('truncated success response is rejected and partial file removed',
      () async {
    final manager = make(_Adapter(
        (_, __) async => _response(_video, length: _video.length + 100)));
    await manager.enqueue(
        url: 'https://video.example/movie.mp4', title: 'Movie');
    await manager.waitForIdle();
    expect(manager.jobs.single.status, 'failed');
    expect(await File(manager.jobs.single.path).exists(), isFalse);
    expect(await File('${manager.jobs.single.path}.part').exists(), isFalse);
  });

  test(
      'playlist URLs, foreign schemes and newline headers never start requests',
      () async {
    final adapter = _Adapter((_, __) async => _response(_video));
    final manager = make(adapter);
    for (final url in [
      'file:///private/movie.mp4',
      'https://video.example/movie.M3U8?token=x',
      'https://video.example/movie.mpd'
    ]) {
      await expectLater(
          manager.enqueue(url: url, title: 'Bad'), throwsFormatException);
    }
    await expectLater(
        manager.enqueue(
            url: 'https://video.example/movie.mp4',
            title: 'Bad',
            headers: {'X-Test': 'one\r\nOther: two'}),
        throwsFormatException);
    expect(adapter.requests, isEmpty);
    expect(manager.jobs, isEmpty);
  });

  test(
      'tampered metadata cannot read/delete outside the private root and does not hide valid rows',
      () async {
    await store.root.create(recursive: true);
    const id = 'c9ebc339-fffd-4d24-b5b0-a33254c881f2';
    const goodId = 'bdf22432-d1e6-4305-aee8-7eec6e66fcad';
    final external = File('${sandbox.path}${Platform.pathSeparator}$id.mp4');
    await external.writeAsBytes(_video);
    final good = File('${store.root.path}${Platform.pathSeparator}$goodId.mp4');
    await good.writeAsBytes(_video);
    store.metadata = jsonEncode([
      NovaDownload(
              id: id,
              title: 'External',
              path: external.path,
              status: 'complete')
          .toJson(),
      {'invalid': 'row'},
      NovaDownload(
              id: goodId, title: 'Safe', path: good.path, status: 'complete')
          .toJson(),
    ]);
    final manager = make(_Adapter((_, __) async => _response(_video)));
    await manager.initialize();
    expect(manager.jobs.map((job) => job.title), ['Safe']);
    await manager
        .remove(NovaDownload(id: id, title: 'Injected', path: external.path));
    await manager.remove(manager.jobs.single);
    expect(await external.readAsBytes(), _video);
    expect(await good.exists(), isFalse);
    expect(manager.jobs, isEmpty);
  });

  test('missing completed file and interrupted jobs reload as failures',
      () async {
    await store.root.create(recursive: true);
    final ids = [
      'c9ebc339-fffd-4d24-b5b0-a33254c881f2',
      'bdf22432-d1e6-4305-aee8-7eec6e66fcad'
    ];
    store.metadata = jsonEncode([
      for (var i = 0; i < ids.length; i++)
        NovaDownload(
                id: ids[i],
                title: 'Movie $i',
                path:
                    '${store.root.path}${Platform.pathSeparator}${ids[i]}.mp4',
                status: i == 0 ? 'complete' : 'downloading')
            .toJson(),
    ]);
    final manager = make(_Adapter((_, __) async => _response(_video)));
    await manager.initialize();
    expect(manager.jobs.map((job) => job.status), ['failed', 'failed']);
    expect(
        manager.jobs.map((job) => job.error), ['missingFile', 'interrupted']);
  });

  test('metadata read failure is visible, blocks enqueue and can be retried',
      () async {
    store.failRead = true;
    final manager = make(_Adapter((_, __) async => _response(_video)));
    await manager.initialize();
    expect(manager.initialized, isFalse);
    expect(manager.initializationError, 'storage');
    await expectLater(
        manager.enqueue(url: 'https://video.example/a.mp4', title: 'A'),
        throwsA(isA<FileSystemException>()));
    store.failRead = false;
    await manager.initialize();
    expect(manager.initialized, isTrue);
    expect(manager.initializationError, isNull);
  });

  test('a symbolic-link download root is rejected before touching its target',
      () async {
    final outside =
        await Directory('${sandbox.path}${Platform.pathSeparator}outside')
            .create();
    final sentinel =
        await File('${outside.path}${Platform.pathSeparator}sentinel.mp4')
            .writeAsBytes(_video);
    try {
      await Link(store.root.path).create(outside.path);
    } on FileSystemException {
      markTestSkipped(
          'This host does not permit creating directory symbolic links.');
      return;
    }
    final manager = make(_Adapter((_, __) async => _response(_video)));
    await manager.initialize();
    expect(manager.initialized, isFalse);
    expect(manager.initializationError, 'storage');
    await expectLater(
        manager.enqueue(url: 'https://video.example/a.mp4', title: 'A'),
        throwsA(isA<FileSystemException>()));
    expect(await sentinel.readAsBytes(), _video);
  });

  test('partial removal failure never leaves a missing file marked complete',
      () async {
    final manager = make(_Adapter((_, __) async => _response(_video)));
    await manager.enqueue(url: 'https://video.example/a.mp4', title: 'A');
    await manager.waitForIdle();
    final job = manager.jobs.single;
    expect(job.status, 'complete');
    store.failSecretDelete = true;
    await expectLater(manager.remove(job), throwsA(isA<FileSystemException>()));
    expect(job.status, 'failed');
    expect(job.error, 'storage');
    expect(await File(job.path).exists(), isFalse);
    expect(manager.jobs, contains(job));
    store.failSecretDelete = false;
    await manager.remove(job);
    expect(manager.jobs, isEmpty);
  });
}
