import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:nova_mobile/core/torrent/stream_server.dart';

void main() {
  // Regression test for the reported failure: "Failed to open
  // http://127.0.0.1:38115/stream" with the torrent HUD at P:0 S:0 0.0%.
  //
  // The player's FIRST request used to arrive before libtorrent had created
  // the target file (cold swarm, zero peers → zero bytes downloaded). The
  // server's File.open() threw and the response closed EMPTY → mpv reported
  // "Failed to open". The server must instead HOLD the response open until
  // the file appears, then stream it — the same patience it already applies
  // to file growth.
  //
  // flutter_test installs global HttpOverrides in some bindings; the local
  // loopback server here needs the plain dart:io stack (Task 132 lesson).
  setUpAll(() {
    HttpOverrides.global = null;
  });

  test('initial request stays open until the engine creates the file',
      () async {
    final dir = await Directory.systemTemp.createTemp('noor-stream');
    final path = '${dir.path}/movie.mkv';
    final server = StreamServer(filePath: path, declaredSize: 32);
    await server.start();
    final client = HttpClient();
    try {
      // The file does NOT exist yet (zero peers — nothing downloaded).
      expect(File(path).existsSync(), isFalse);

      final request = await client.getUrl(Uri.parse(server.url!));
      // Deliberately NOT awaited yet: dart:io completes request.close() when
      // the response HEADERS arrive, and the server sends headers only when
      // the first body byte is ready. The engine creates the file on its own
      // thread while the request waits — model that with a concurrent step.
      final responseFuture = request.close();

      // The engine "downloads" its first pieces while the request waits.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final payload = Uint8List.fromList(List.generate(32, (i) => i + 1));
      await File(path).writeAsBytes(payload, flush: true);

      final response = await responseFuture;

      // The request must complete with REAL data — not an empty body.
      final body = BytesBuilder(copy: false);
      await for (final chunk in response) {
        body.add(chunk);
      }
      expect(response.statusCode, HttpStatus.ok);
      expect(body.takeBytes(), payload);
    } finally {
      client.close(force: true);
      await server.close();
      await dir.delete(recursive: true);
    }
  });

  test('a missing file without a declared size still answers 404', () async {
    final dir = await Directory.systemTemp.createTemp('noor-stream');
    final server = StreamServer(
      filePath: '${dir.path}/ghost.mkv',
    ); // no declaredSize → size unknowable
    await server.start();
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(server.url!));
      final response = await request.close();
      expect(response.statusCode, HttpStatus.notFound);
    } finally {
      client.close(force: true);
      await server.close();
      await dir.delete(recursive: true);
    }
  });
}
