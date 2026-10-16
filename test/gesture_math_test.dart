import 'package:flutter_test/flutter_test.dart';

import 'package:noor_mobile/features/player/gesture_math.dart';

void main() {
  group('gestureScaledValue (volume / brightness mapping)', () {
    test('drag up increases, drag down decreases', () {
      expect(gestureScaledValue(start: 0.5, totalDy: -250, height: 500), 1.0);
      expect(gestureScaledValue(start: 0.5, totalDy: 250, height: 500), 0.0);
      expect(
        gestureScaledValue(start: 0.5, totalDy: -100, height: 500),
        closeTo(0.7, 1e-9),
      );
    });

    test('one full screen height of drag covers the full range', () {
      // Proportional to the ACTUAL surface height — no per-device constants.
      // Dragging UP a full screen from mid-range pins at the maximum;
      // dragging DOWN a full screen pins at zero.
      expect(
        gestureScaledValue(start: 0.5, totalDy: -390, height: 390),
        1.0,
      );
      expect(
        gestureScaledValue(start: 0.5, totalDy: 390, height: 390),
        0.0,
      );
      expect(
        gestureScaledValue(start: 0.2, totalDy: -820, height: 820),
        closeTo(1.0, 1e-9),
      );
    });

    test('clamps at both ends — never out of 0..1', () {
      expect(gestureScaledValue(start: 0.9, totalDy: -9999, height: 100), 1.0);
      expect(gestureScaledValue(start: 0.1, totalDy: 9999, height: 100), 0.0);
    });

    test('zero/negative height cannot divide-by-zero', () {
      expect(gestureScaledValue(start: 0.4, totalDy: -100, height: 0), 0.4);
    });

    test('zero drag keeps the start value (dead zone makes taps no-ops)', () {
      expect(gestureScaledValue(start: 0.33, totalDy: 0, height: 400), 0.33);
    });
  });

  group('clampSeekTargetMs', () {
    test('seeks past the end land on the end', () {
      expect(clampSeekTargetMs(999999, 600000), 600000);
    });
    test('seeks before the start land on zero', () {
      expect(clampSeekTargetMs(-5000, 600000), 0);
    });
    test('in-range targets pass through', () {
      expect(clampSeekTargetMs(12345, 600000), 12345);
    });
    test('unknown duration (0) clamps to zero', () {
      expect(clampSeekTargetMs(5000, 0), 0);
    });
  });

  group('kGestureAxisLockPx (dead zone contract)', () {
    test('is a small positive threshold', () {
      expect(kGestureAxisLockPx, greaterThan(0));
      expect(kGestureAxisLockPx, lessThan(20));
    });
  });
}
