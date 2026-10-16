/// Pure math behind the player's volume / brightness / scrub gestures, so
/// the mapping rules are unit-testable without a widget tree or an engine.
library;

/// Minimum vertical movement (logical px) before a one-finger drag claims an
/// axis — the dead zone that keeps taps and micro-jitters from scrubbing,
/// dimming or changing the volume. Chosen small enough to feel immediate.
const double kGestureAxisLockPx = 8.0;

/// Maps a vertical drag onto a 0..1 control value (volume, brightness).
///
/// [start] is the value captured ONCE at drag start; [totalDy] is the
/// ACCUMULATED drag distance (up = negative = increase); [height] is the
/// actual surface height, so one full screen of drag covers the full range —
/// proportional on every device, no per-device constants.
double gestureScaledValue({
  required double start,
  required double totalDy,
  required double height,
}) {
  if (height <= 0) return start.clamp(0.0, 1.0);
  return (start - totalDy / height).clamp(0.0, 1.0);
}

/// Clamps a scrub / double-tap target inside the media timeline (seeking
/// past the start or end lands on the boundary, never outside).
int clampSeekTargetMs(int targetMs, int durationMs) {
  if (durationMs <= 0) return targetMs.clamp(0, 0).toInt();
  return targetMs.clamp(0, durationMs).toInt();
}
