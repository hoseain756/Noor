import 'package:flutter_test/flutter_test.dart';

import 'package:noor_mobile/core/data/cache_reset_service.dart';

void main() {
  group('CacheResetService.isDue', () {
    final now = DateTime(2025, 6, 1, 12);
    DateTime hoursAgo(num h) =>
        now.subtract(Duration(minutes: (h * 60).round()));

    test('first run (no timestamp) is due for any enabled interval', () {
      expect(
        CacheResetService.isDue(lastResetMs: null, hours: 12, now: now),
        isTrue,
      );
      expect(
        CacheResetService.isDue(lastResetMs: null, hours: 1, now: now),
        isTrue,
      );
    });

    test('disabled (0) never resets — even with an ancient timestamp', () {
      expect(
        CacheResetService.isDue(lastResetMs: null, hours: 0, now: now),
        isFalse,
      );
      expect(
        CacheResetService.isDue(
          lastResetMs: hoursAgo(1000).millisecondsSinceEpoch,
          hours: 0,
          now: now,
        ),
        isFalse,
      );
    });

    test('12h default: before the interval → not due, at/after → due', () {
      expect(
        CacheResetService.isDue(
          lastResetMs: hoursAgo(11.9).millisecondsSinceEpoch,
          hours: 12,
          now: now,
        ),
        isFalse,
      );
      expect(
        CacheResetService.isDue(
          lastResetMs: hoursAgo(12).millisecondsSinceEpoch,
          hours: 12,
          now: now,
        ),
        isTrue,
      );
      expect(
        CacheResetService.isDue(
          lastResetMs: hoursAgo(12.1).millisecondsSinceEpoch,
          hours: 12,
          now: now,
        ),
        isTrue,
      );
    });

    test('invalid timestamps (0 / negative) count as due', () {
      expect(
        CacheResetService.isDue(lastResetMs: 0, hours: 12, now: now),
        isTrue,
      );
      expect(
        CacheResetService.isDue(lastResetMs: -5, hours: 12, now: now),
        isTrue,
      );
    });
  });

  group('CacheResetService.hoursFromSettings', () {
    test('missing key falls back to the 12h default', () {
      expect(CacheResetService.hoursFromSettings(const {}), 12);
    });

    test('parses ints, doubles and numeric strings', () {
      expect(
        CacheResetService.hoursFromSettings(const {'cacheResetHours': 6}),
        6,
      );
      expect(
        CacheResetService.hoursFromSettings(const {'cacheResetHours': 0}),
        0,
      );
      expect(
        CacheResetService.hoursFromSettings(const {'cacheResetHours': 24.0}),
        24,
      );
      expect(
        CacheResetService.hoursFromSettings(const {'cacheResetHours': '3'}),
        3,
      );
    });

    test('unknown shapes fall back to the default', () {
      expect(
        CacheResetService.hoursFromSettings(const {'cacheResetHours': 'x'}),
        12,
      );
      expect(
        CacheResetService.hoursFromSettings(const {'cacheResetHours': null}),
        12,
      );
    });
  });
}
