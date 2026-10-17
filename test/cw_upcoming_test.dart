import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/features/home/cw_upcoming.dart';

List<Map<String, dynamic>> _videos() => [
      {
        'id': 'tt1:1:1',
        'name': 'البداية',
        'season': 1,
        'episode': 1,
        'released': '2026-01-01T00:00:00.000Z',
      },
      {
        'id': 'tt1:1:2',
        'name': 'المتابعة',
        'season': 1,
        'episode': 2,
        'released': '2026-01-08T00:00:00.000Z',
      },
      {
        'id': 'tt1:1:3',
        'name': 'النهاية',
        'season': 1,
        'episode': 3,
        'released': '2026-01-15T00:00:00.000Z',
      },
    ];

final _now = DateTime.utc(2026, 1, 10); // ep2 aired, ep3 airs in 5 days

void main() {
  group('resolveCwUpcoming', () {
    test('mid-episode, unaired saved episode → badge for that episode', () {
      // Saved ep1, only 30% watched; ep1 aired in the past → no badge,
      // but the episode name enriches the subtitle.
      final result = resolveCwUpcoming(
        videos: _videos(),
        season: 1,
        episode: 1,
        progress: 0.3,
        watchedVideoIds: const {},
        now: _now,
      );
      expect(result.nextAirMs, isNull);
      expect(result.fresh, isFalse);
      expect(result.episodeName, 'البداية');
    });

    test('mid-episode, saved episode unaired → badge with its air time', () {
      final videos = [
        {
          'id': 'tt2:1:1',
          'name': 'حلقة مستقبلية',
          'season': 1,
          'episode': 1,
          'released': '2026-01-20T00:00:00.000Z',
        },
      ];
      final result = resolveCwUpcoming(
        videos: videos,
        season: 1,
        episode: 1,
        progress: 0.1,
        watchedVideoIds: const {},
        now: _now,
      );
      expect(
        result.nextAirMs,
        DateTime.utc(2026, 1, 20).millisecondsSinceEpoch,
      );
    });

    test('finished episode → next aired+unwatched becomes the fresh dot', () {
      // ep2 fully watched (progress ≥ 0.92), ep3 aired 2026-01-15 > now?
      // No: ep3 airs 2026-01-15 which is AFTER now (01-10) → badge, not dot.
      final badge = resolveCwUpcoming(
        videos: _videos(),
        season: 1,
        episode: 2,
        progress: 0.95,
        watchedVideoIds: const {},
        now: _now,
      );
      expect(badge.fresh, isFalse);
      expect(
        badge.nextAirMs,
        DateTime.utc(2026, 1, 15).millisecondsSinceEpoch,
      );

      // Same state but "now" after ep3 aired → fresh dot instead.
      final later = DateTime.utc(2026, 1, 16);
      final dot = resolveCwUpcoming(
        videos: _videos(),
        season: 1,
        episode: 2,
        progress: 0.95,
        watchedVideoIds: const {},
        now: later,
      );
      expect(dot.fresh, isTrue);
      expect(dot.nextAirMs, isNull);
    });

    test('finished episode whose next is already watched → nothing', () {
      final result = resolveCwUpcoming(
        videos: _videos(),
        season: 1,
        episode: 2,
        progress: 0.95,
        watchedVideoIds: const {'tt1:1:3'},
        now: DateTime.utc(2026, 1, 16),
      );
      expect(result.fresh, isFalse);
      expect(result.nextAirMs, isNull);
    });

    test('finished last episode → no badge and no dot', () {
      final result = resolveCwUpcoming(
        videos: _videos(),
        season: 1,
        episode: 3,
        progress: 1.0,
        watchedVideoIds: const {},
        now: DateTime.utc(2026, 1, 16),
      );
      expect(result.fresh, isFalse);
      expect(result.nextAirMs, isNull);
    });

    test('saved episode missing from videos → nothing (fail soft)', () {
      final result = resolveCwUpcoming(
        videos: _videos(),
        season: 2,
        episode: 9,
        progress: 0.5,
        watchedVideoIds: const {},
        now: _now,
      );
      expect(result.nextAirMs, isNull);
      expect(result.fresh, isFalse);
    });

    test('unseasoned specials (season 0) do not break ordering', () {
      final videos = [
        {'id': 'tt1:0:1', 'season': 0, 'episode': 1, 'released': '2025-12-01'},
        ..._videos(),
      ];
      final result = resolveCwUpcoming(
        videos: videos,
        season: 1,
        episode: 2,
        progress: 1.0,
        watchedVideoIds: const {},
        now: DateTime.utc(2026, 1, 16),
      );
      // Next in-order episode is S1E3 (aired 01-15) → fresh dot.
      expect(result.fresh, isTrue);
    });
  });

  group('cwUpcomingLabel', () {
    test('sub-24h releases read as tomorrow — site ceil() semantics', () {
      // Web parity: daysUntil = ceil(delta/24h), and a positive delta always
      // ceils to ≥ 1, so "airToday" is only reachable at exact-equality edge
      // and sub-24h releases read as tomorrow (midnight-aligned air dates).
      final now = DateTime.utc(2026, 3, 1, 12);
      expect(
        cwUpcomingLabel(
            now.add(const Duration(hours: 2)).millisecondsSinceEpoch,
            false,
            now),
        'يُعرض غداً',
      );
      expect(
        cwUpcomingLabel(
            now.add(const Duration(hours: 2)).millisecondsSinceEpoch,
            true,
            now),
        'Airs tomorrow',
      );
      expect(
        cwUpcomingLabel(now.add(const Duration(days: 1)).millisecondsSinceEpoch,
            false, now),
        'يُعرض غداً',
      );
      expect(
        cwUpcomingLabel(
            now.add(const Duration(days: 1, hours: 1)).millisecondsSinceEpoch,
            false,
            now),
        'يُعرض بعد يومين',
      );
    });

    test('Arabic day pluralization: يومين / أيام / يوم', () {
      final now = DateTime.utc(2026, 3, 1, 12);
      int at(int days) => now.add(Duration(days: days)).millisecondsSinceEpoch;
      expect(cwUpcomingLabel(at(2), false, now), 'يُعرض بعد يومين');
      expect(cwUpcomingLabel(at(5), false, now), 'يُعرض بعد 5 أيام');
      expect(cwUpcomingLabel(at(15), false, now), 'يُعرض بعد 15 يوم');
      expect(cwUpcomingLabel(at(2), true, now), 'Airs in two days');
      expect(cwUpcomingLabel(at(1), true, now), 'Airs tomorrow');
    });

    test('past or null air time → no label', () {
      final now = DateTime.utc(2026, 3, 1, 12);
      expect(cwUpcomingLabel(null, false, now), isNull);
      expect(
        cwUpcomingLabel(
            now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
            false,
            now),
        isNull,
      );
    });
  });
}
