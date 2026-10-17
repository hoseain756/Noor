import 'package:flutter_test/flutter_test.dart';

import 'package:nova_mobile/core/torrent/torrent_models.dart';
import 'package:nova_mobile/core/torrent/torrent_service.dart';

void main() {
  group('normalizeTrackerSources', () {
    test('strips the tracker: prefix and keeps announce URLs', () {
      final out = normalizeTrackerSources([
        'tracker:udp://tracker.opentrackr.org:1337/announce',
        'tracker:http://bt.t-ru.org/ann?magnet',
        'udp://open.stealth.si:80/announce',
        'https://tracker.tamersunion.org:443/announce',
      ]);
      expect(out, [
        'udp://tracker.opentrackr.org:1337/announce',
        'http://bt.t-ru.org/ann?magnet',
        'udp://open.stealth.si:80/announce',
        'https://tracker.tamersunion.org:443/announce',
      ]);
    });

    test('drops dht:, wss: and junk entries', () {
      final out = normalizeTrackerSources([
        'dht:23dfd11259dd6435dce2fef48d6721ffa8c08664',
        'wss://tracker.openwebtorrent.com',
        'tracker:',
        '   ',
        42,
        null,
      ]);
      expect(out, isEmpty);
    });

    test('de-duplicates while preserving order', () {
      final out = normalizeTrackerSources([
        'tracker:udp://a/announce',
        'udp://a/announce',
        'tracker:udp://b/announce',
        'tracker:udp://a/announce',
      ]);
      expect(out, ['udp://a/announce', 'udp://b/announce']);
    });

    test('tolerates non-list input', () {
      expect(normalizeTrackerSources(null), isEmpty);
      expect(normalizeTrackerSources('tracker:udp://a/announce'), isEmpty);
    });
  });

  group('magnetFor', () {
    const defaults = [
      'udp://tracker.opentrackr.org:1337/announce',
      'http://tracker.dler.org:6969/announce',
    ];

    List<String> trackers(String magnet) =>
        Uri.parse(magnet).queryParametersAll['tr'] ?? const [];

    test('appends the verified default trackers for a bare info-hash', () {
      final magnet = TorrentService.magnetFor(
        '23DFD11259DD6435DCE2FEF48D6721FFA8C08664',
      );
      expect(
          magnet,
          startsWith(
              'magnet:?xt=urn:btih:23dfd11259dd6435dce2fef48d6721ffa8c08664'));
      final tr = trackers(magnet);
      expect(tr, containsAll(defaults));
      // No duplicates.
      expect(tr.toSet().length, tr.length);
    });

    test('extra (addon) trackers win over defaults and are de-duplicated', () {
      final magnet = TorrentService.magnetFor(
        'a' * 40,
        extraTrackers: [
          'udp://addon.tracker/announce',
          'udp://tracker.opentrackr.org:1337/announce',
        ],
      );
      final tr = trackers(magnet);
      expect(tr.first, 'udp://addon.tracker/announce');
      expect(
          tr
              .where((t) => t == 'udp://tracker.opentrackr.org:1337/announce')
              .length,
          1);
    });

    test('keeps the dn hint and merges trackers from an existing magnet', () {
      final existing = 'magnet:?xt=urn:btih:${'b' * 40}'
          '&dn=One%20Piece%20S01'
          '&tr=udp%3A%2F%2Ffrom.magnet%2Fannounce';
      final magnet = TorrentService.magnetFor('c' * 40, magnetUri: existing);
      expect(magnet, contains('dn=One%20Piece%20S01'));
      final tr = trackers(magnet);
      expect(tr, contains('udp://from.magnet/announce'));
      expect(tr, containsAll(defaults));
      expect(tr.toSet().length, tr.length);
    });

    test('extracts trackers from a magnet without touching other params', () {
      final tr = TorrentService.trackersFromMagnet(
        'magnet:?xt=urn:btih:${'d' * 40}'
        '&tr=udp%3A%2F%2Fx%2Fa'
        '&dn=Test'
        '&tr=http%3A%2F%2Fx%2Fb',
      );
      expect(tr, ['udp://x/a', 'http://x/b']);
    });
  });

  group('selectTorrentFile', () {
    final meta = TorrentMetadata(
      name: 'pack',
      infoHash: 'a' * 40,
      files: const [
        TorrentFileInfo(index: 0, name: 'pack/sample.txt', size: 1000),
        TorrentFileInfo(
          index: 1,
          name: 'pack/S01E01 - Pilot.mkv',
          size: 400 * 1024 * 1024,
        ),
        TorrentFileInfo(
          index: 2,
          name: 'pack/S01E02 - Home.mkv',
          size: 380 * 1024 * 1024,
        ),
        TorrentFileInfo(
          index: 3,
          name: 'pack/extra.big',
          size: 900 * 1024 * 1024,
        ),
      ],
    );

    test('prefers the addon fileIdx when it points at a video', () {
      final f = selectTorrentFile(meta, 'whatever', 2);
      expect(f?.index, 2);
    });

    test('falls back to filename matching for a non-video fileIdx', () {
      final f = selectTorrentFile(meta, 'S01E01 - Pilot.mkv', 0);
      expect(f?.index, 1);
    });

    test('falls back to filename matching for an out-of-range fileIdx', () {
      final f = selectTorrentFile(meta, 's01e02 - home.mkv', 99);
      expect(f?.index, 2);
    });

    test('falls back to the largest video with no hints at all', () {
      final f = selectTorrentFile(meta, null, null);
      expect(
          f?.index, 1); // E01 (400MB) beats E02 (380MB); extra.big is not video
    });

    test('last resort: indexed non-video file before arbitrary largest', () {
      final f = selectTorrentFile(meta, null, 3);
      expect(f?.index, 3);
    });

    test('returns null only for an empty torrent', () {
      final empty = TorrentMetadata(
        name: 'e',
        infoHash: 'e' * 40,
        files: const [],
      );
      expect(selectTorrentFile(empty, null, null), isNull);
    });
  });

  group('torrentFileMatches', () {
    test('is lenient about case, slashes and paths', () {
      expect(
        torrentFileMatches('Pack/Sub/Show.S01E01.mkv', 'show.s01e01.mkv'),
        isTrue,
      );
      expect(
        torrentFileMatches('Show.S01E01.mkv', 'Pack/Sub/Show.S01E01.mkv'),
        isTrue,
      );
      expect(torrentFileMatches('Show.S01E01.mkv', 'Show.S01E02.mkv'), isFalse);
    });
  });
}
