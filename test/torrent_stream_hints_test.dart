import 'package:flutter_test/flutter_test.dart';

import 'package:nova_mobile/core/torrent/torrent_models.dart';
import 'package:nova_mobile/core/torrent/torrent_service.dart';

void main() {
  // A real Torrentio stream object (shape verified live against
  // https://torrentio.strem.fun/stream/movie/<imdbId>.json — Task 142).
  Map<String, dynamic> torrentioStream({
    String infoHash = '997eb763b0c51b09eca3ecbd5d2c27e95772f254',
    int? fileIdx = 0,
    List<String>? sources,
    Map<String, dynamic>? behaviorHints,
    dynamic size,
  }) =>
      <String, dynamic>{
        'name': 'Torrentio\n1080p',
        'title': 'Show.S01E01.1080p.WEB-DL.x264\n👤 45 💾 2.1 GB ⚙️ 1337x',
        if (infoHash.isNotEmpty) 'infoHash': infoHash,
        if (fileIdx != null) 'fileIdx': fileIdx,
        'sources': sources ??
            <String>[
              'tracker:http://bt4.t-ru.org/ann?magnet',
              'dht:$infoHash',
              'tracker:udp://tracker.opentrackr.org:1337/announce',
              'tracker:udp://open.stealth.si:80/announce',
            ],
        if (behaviorHints != null) 'behaviorHints': behaviorHints,
        if (size != null) 'size': size,
      };

  group('TorrentStreamHints.fromStream (Task 142 — the in-player path)', () {
    test('keeps Torrentio sources as plain announce trackers', () {
      final hints = TorrentStreamHints.fromStream(torrentioStream());
      expect(
        hints.trackers,
        <String>[
          'http://bt4.t-ru.org/ann?magnet',
          'udp://tracker.opentrackr.org:1337/announce',
          'udp://open.stealth.si:80/announce',
        ],
      );
    });

    test('extracts infoHash (lowercased) and fileIdx', () {
      final hints = TorrentStreamHints.fromStream(
        torrentioStream(
          infoHash: '997EB763B0C51B09ECA3ECBD5D2C27E95772F254',
          fileIdx: 3,
        ),
      );
      expect(hints.infoHash, '997eb763b0c51b09eca3ecbd5d2c27e95772f254');
      expect(hints.fileIndex, 3);
    });

    test('parses a string fileIdx (some addons ship it as a string)', () {
      final hints = TorrentStreamHints.fromStream(
        torrentioStream(fileIdx: null)..['fileIdx'] = '5',
      );
      expect(hints.fileIndex, 5);
    });

    test('behaviorHints.filename wins over the decorated title', () {
      final hints = TorrentStreamHints.fromStream(
        torrentioStream(
          behaviorHints: <String, dynamic>{
            'bingeGroup': 'torrentio|1080p',
            'filename': 'Show.S01E01.1080p.WEB-DL.x264-EVO.mkv',
          },
        ),
      );
      expect(hints.filename, 'Show.S01E01.1080p.WEB-DL.x264-EVO.mkv');
    });

    test('falls back to title, then to the caller fallback name', () {
      expect(
        TorrentStreamHints.fromStream(torrentioStream()).filename,
        startsWith('Show.S01E01.1080p.WEB-DL.x264'),
      );
      expect(
        TorrentStreamHints.fromStream(
          torrentioStream()..remove('title'),
          fallbackName: 'Fallback Item',
        ).filename,
        'Fallback Item',
      );
    });

    test('reads the byte size from size / fileSize / videoSize', () {
      expect(
        TorrentStreamHints.fromStream(torrentioStream(size: 2254857830))
            .filesize,
        2254857830,
      );
      expect(
        TorrentStreamHints.fromStream(
          torrentioStream()
            ..remove('size')
            ..['fileSize'] = 1024,
        ).filesize,
        1024,
      );
      expect(
        TorrentStreamHints.fromStream(
          torrentioStream(
            behaviorHints: <String, dynamic>{'videoSize': 2048},
          )..remove('size'),
        ).filesize,
        2048,
      );
    });

    test('magnet hash is the fallback when the stream has no infoHash', () {
      final hints = TorrentStreamHints.fromStream(
        torrentioStream(infoHash: ''),
        magnetUri:
            'magnet:?xt=urn:btih:23dfd11259dd6435dce2fef48d6721ffa8c08664'
            '&dn=test',
      );
      expect(hints.infoHash, '23dfd11259dd6435dce2fef48d6721ffa8c08664');
    });

    test('a non-torrent stream yields an empty infoHash', () {
      final hints = TorrentStreamHints.fromStream(
        <String, dynamic>{
          'name': 'Direct',
          'title': 'Direct play',
          'url': 'https://cdn.example.com/video.mp4',
        },
      );
      expect(hints.infoHash, isEmpty);
      expect(hints.trackers, isEmpty);
    });
  });

  group('Task 142 — magnetFor keeps stream trackers on magnet streams', () {
    List<String> trackers(String magnet) =>
        Uri.parse(magnet).queryParametersAll['tr'] ?? const [];

    test('extra trackers merge even when an addon magnet is provided', () {
      final addonMagnet = 'magnet:?xt=urn:btih:${'a' * 40}'
          '&tr=udp%3A%2F%2Ffrom.magnet%2Fannounce';
      final magnet = TorrentService.magnetFor(
        'a' * 40,
        magnetUri: addonMagnet,
        extraTrackers: <String>['http://stream.source/announce'],
      );
      final tr = trackers(magnet);
      // The magnet's own tracker…
      expect(tr, contains('udp://from.magnet/announce'));
      // …the stream's `sources` tracker (silently dropped before Task 142)…
      expect(tr, contains('http://stream.source/announce'));
      // …and the verified defaults.
      expect(tr, contains('udp://tracker.opentrackr.org:1337/announce'));
      expect(tr.toSet().length, tr.length);
    });
  });
}
