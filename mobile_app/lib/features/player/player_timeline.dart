import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/horse_theme.dart';

/// Seek bar that renders the engine's buffered ranges and exposes slider
/// semantics while keeping seeking under the owning player page's control.
class PlayerTimeline extends StatefulWidget {
  const PlayerTimeline({
    super.key,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.onSeekStart,
    required this.onSeekPreview,
    required this.onSeekEnd,
  });

  final Duration position;
  final Duration duration;
  final List<DurationRange> buffered;
  final ValueChanged<Duration> onSeekStart;
  final ValueChanged<Duration> onSeekPreview;
  final ValueChanged<Duration> onSeekEnd;

  @override
  State<PlayerTimeline> createState() => _PlayerTimelineState();
}

class _PlayerTimelineState extends State<PlayerTimeline> {
  Duration? _dragPosition;

  @override
  void didUpdateWidget(covariant PlayerTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) _dragPosition = null;
  }

  @override
  Widget build(BuildContext context) {
    final durationMs = widget.duration.inMilliseconds;
    final max = durationMs > 0 ? durationMs.toDouble() : 1.0;
    final sourcePosition = _dragPosition ?? widget.position;
    final positionMs = sourcePosition.inMilliseconds
        .clamp(0, durationMs > 0 ? durationMs : 0)
        .toDouble();
    final canSeek = durationMs > 0;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(
              formatPlayerTime(Duration(milliseconds: positionMs.round())),
              textAlign: TextAlign.start,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 38,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _TimelineTrackPainter(
                          duration: widget.duration,
                          position: Duration(milliseconds: positionMs.round()),
                          buffered: widget.buffered,
                        ),
                      ),
                    ),
                  ),
                  Directionality(
                    // Playback always advances from left to right, including
                    // when the surrounding application uses Arabic RTL.
                    textDirection: TextDirection.ltr,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 0,
                        trackShape: const _InvisibleSliderTrackShape(),
                        activeTrackColor: Colors.transparent,
                        inactiveTrackColor: Colors.transparent,
                        thumbColor: Colors.white,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayColor: Colors.white.withValues(alpha: .14),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 18),
                        minThumbSeparation: 0,
                      ),
                      child: Slider(
                        semanticFormatterCallback: (value) =>
                            '${formatPlayerTime(Duration(milliseconds: value.round()))} / ${formatPlayerTime(widget.duration)}',
                        value: positionMs.clamp(0, max),
                        max: max,
                        onChangeStart: canSeek
                            ? (value) {
                                final target =
                                    Duration(milliseconds: value.round());
                                setState(() => _dragPosition = target);
                                widget.onSeekStart(target);
                              }
                            : null,
                        onChanged: canSeek
                            ? (value) {
                                final target =
                                    Duration(milliseconds: value.round());
                                setState(() => _dragPosition = target);
                                widget.onSeekPreview(target);
                              }
                            : null,
                        onChangeEnd: canSeek
                            ? (value) {
                                final target =
                                    Duration(milliseconds: value.round());
                                setState(() => _dragPosition = null);
                                widget.onSeekEnd(target);
                              }
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 42,
            child: Text(
              formatPlayerTime(widget.duration),
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvisibleSliderTrackShape extends SliderTrackShape {
  const _InvisibleSliderTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final thumbWidth = sliderTheme.thumbShape
            ?.getPreferredSize(
              isEnabled,
              isDiscrete,
            )
            .width ??
        12;
    final trackHeight = sliderTheme.trackHeight ?? 0;
    final trackLeft = offset.dx + thumbWidth / 2;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    return Rect.fromLTWH(
      trackLeft,
      trackTop,
      parentBox.size.width - thumbWidth,
      trackHeight,
    );
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
  }) {}
}

class _TimelineTrackPainter extends CustomPainter {
  const _TimelineTrackPainter({
    required this.duration,
    required this.position,
    required this.buffered,
  });

  final Duration duration;
  final Duration position;
  final List<DurationRange> buffered;

  @override
  void paint(Canvas canvas, Size size) {
    final durationMs = duration.inMilliseconds;
    if (durationMs <= 0 || size.width <= 0) return;
    final centerY = size.height / 2;
    const horizontalInset = 6.0;
    final trackWidth = size.width > horizontalInset * 2
        ? size.width - horizontalInset * 2
        : 0.0;
    final trackRect = Rect.fromLTWH(
      horizontalInset,
      centerY - 1.5,
      trackWidth,
      3,
    );
    final radius = const Radius.circular(3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, radius),
      Paint()..color = Colors.white.withValues(alpha: .32),
    );

    final bufferedPaint = Paint()..color = Colors.white.withValues(alpha: .58);
    for (final range in buffered) {
      final start = range.start.inMilliseconds.clamp(0, durationMs);
      final end = range.end.inMilliseconds.clamp(start, durationMs);
      if (end <= start) continue;
      final left = horizontalInset + trackWidth * start / durationMs;
      final right = horizontalInset + trackWidth * end / durationMs;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, centerY - 1.5, right - left, 3),
          radius,
        ),
        bufferedPaint,
      );
    }

    final playedMs = position.inMilliseconds.clamp(0, durationMs);
    final playedWidth = trackWidth * playedMs / durationMs;
    if (playedWidth > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(horizontalInset, centerY - 1.5, playedWidth, 3),
          radius,
        ),
        Paint()..color = HorseTheme.gold,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineTrackPainter oldDelegate) =>
      oldDelegate.duration != duration ||
      oldDelegate.position != position ||
      oldDelegate.buffered != buffered;
}

String formatPlayerTime(Duration value) {
  final safeSeconds = value.inSeconds < 0 ? 0 : value.inSeconds;
  final hours = safeSeconds ~/ 3600;
  final minutes = (safeSeconds ~/ 60).remainder(60).toString().padLeft(2, '0');
  final seconds = (safeSeconds % 60).toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:$minutes:$seconds'
      : '${safeSeconds ~/ 60}:$seconds';
}
