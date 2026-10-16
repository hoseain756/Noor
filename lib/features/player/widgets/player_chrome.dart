import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/horse_theme.dart';

/// Visual language of the cinematic player chrome (reference design):
/// white controls over the video, a teal→blue gradient timeline, a large
/// outlined central play control and slim translucent scrims.
///
/// Task 124/125 layout mandate:
///  · top bar — exit at the directional END, title at the START, with a
///    zero-padded `S01E12` tag underneath for series;
///  · progress row (current · timeline · total) sits ABOVE every control and
///    is NEVER mirrored (always LTR fill);
///  · bottom row: fullscreen+volume at the directional END, source /
///    subtitles / audio at the START; the [rewind][play][forward] trio is
///    dead CENTER and NEVER mirrored (rewind always left);
///  · gestures are side-fixed: left = brightness, right = volume.
/// Mirroring follows the inherited Directionality (Arabic RTL / English LTR).
class PlayerPalette {
  static const Color gradientStart = Color(0xFF2FE3B4);
  static const Color gradientEnd = Color(0xFF3B82F6);
  static const Color thumb = Color(0xFF36E5C0);

  static const List<Shadow> iconShadow = [
    Shadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 1)),
  ];

  static const LinearGradient played = LinearGradient(
    colors: [gradientStart, gradientEnd],
  );
}

String formatPlayerTime(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '${value.inMinutes}:$seconds';
}

/// Zero-padded episode tag per the user mandate: `S01E12`.
String seasonEpisodeTag(int? season, int? episode) {
  if (season == null || episode == null) return '';
  final s = season.toString().padLeft(2, '0');
  final e = episode.toString().padLeft(2, '0');
  return 'S${s}E$e';
}

// ── Top bar ────────────────────────────────────────────────────────────────

class PlayerTopBar extends StatelessWidget {
  const PlayerTopBar({
    super.key,
    required this.title,
    required this.episodeTag,
    required this.onClose,
    this.wide = false,
  });

  final String title;

  /// Empty for movies; `S01E12` for series (rendered under the title).
  final String episodeTag;
  final VoidCallback onClose;

  /// Tablet sizing (larger title font).
  final bool wide;

  @override
  Widget build(BuildContext context) {
    // Directional mirror (spec §0): RTL → title right / exit left;
    // LTR → title left / exit right. START = title, END = exit.
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x99000000), Colors.transparent],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 6, wide ? 24 : 12, 26),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: wide ? 16.5 : 14,
                          fontWeight: FontWeight.w600,
                          shadows: PlayerPalette.iconShadow,
                        ),
                      ),
                      if (episodeTag.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Directionality(
                            // Mixed-script mandate: the tag is always LTR.
                            textDirection: TextDirection.ltr,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: .35),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Text(
                                episodeTag,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .92),
                                  fontSize: wide ? 12 : 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: .8,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                  shadows: PlayerPalette.iconShadow,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                PlayerBackButton(onTap: onClose),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PlayerBackButton extends StatelessWidget {
  const PlayerBackButton({super.key, required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white.withValues(alpha: .10),
        shape: const CircleBorder(
          side: BorderSide(color: Colors.white24),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Icon(LucideIcons.x, color: Colors.white, size: 22),
          ),
        ),
      );
}

// ── Rails ──────────────────────────────────────────────────────────────────

class PlayerRailButton extends StatelessWidget {
  const PlayerRailButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.active = false,
    this.iconSize = 22,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;
  final bool active;
  final double iconSize;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semanticLabel,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              color: active ? PlayerPalette.thumb : Colors.white,
              size: iconSize,
              shadows: PlayerPalette.iconShadow,
            ),
          ),
        ),
      );
}

/// Task 139 (user mandate): the transport trio [rewind][play/pause][forward]
/// lives in the MIDDLE of the screen — floating center controls — never
/// mirrored (rewind always left), with the seek step rendered inside the
/// circular arrows exactly as configured in settings.
class PlayerCenterTransport extends StatelessWidget {
  const PlayerCenterTransport({
    super.key,
    required this.isPlaying,
    required this.backStepSec,
    required this.forwardStepSec,
    required this.scale,
    required this.wide,
    required this.onPlayPause,
    required this.onSkip,
  });

  final bool isPlaying;
  final int backStepSec;
  final int forwardStepSec;
  final double scale;
  final bool wide;
  final VoidCallback onPlayPause;
  final ValueChanged<int> onSkip;

  @override
  Widget build(BuildContext context) {
    final big = wide ? 76.0 : 64.0;
    final skipSize = (wide ? 54.0 : 48.0) * scale;
    return Positioned.fill(
      child: Center(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SkipButton(
                forward: false,
                seconds: backStepSec,
                size: skipSize,
                onTap: () => onSkip(-backStepSec),
              ),
              SizedBox(width: 20 * scale),
              Semantics(
                button: true,
                label: isPlaying ? 'Pause' : 'Play',
                child: GestureDetector(
                  onTap: onPlayPause,
                  child: Container(
                    width: big,
                    height: big,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .14),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 2.4,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 16,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      isPlaying ? LucideIcons.pause : LucideIcons.play,
                      color: Colors.white,
                      size: big * .5,
                      shadows: PlayerPalette.iconShadow,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 20 * scale),
              _SkipButton(
                forward: true,
                seconds: forwardStepSec,
                size: skipSize,
                onTap: () => onSkip(forwardStepSec),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlayerSpeedPill extends StatelessWidget {
  const PlayerSpeedPill({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semanticLabel,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Container(
            width: 52,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .30),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Colors.white.withValues(alpha: .85)),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: .4,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      );
}

class PlayerSideRail extends StatelessWidget {
  const PlayerSideRail({
    super.key,
    required this.side,
    required this.topInset,
    required this.children,
  });

  final AxisSide side;
  final double topInset;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final isLeft = side == AxisSide.left;
    return Positioned(
      top: topInset,
      left: isLeft ? 6 : null,
      right: isLeft ? null : 6,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: isLeft ? 4 : 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final child in children) ...[
              child,
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

enum AxisSide { left, right }

// ── Gradient timeline ──────────────────────────────────────────────────────

class GradientTimeline extends StatefulWidget {
  const GradientTimeline({
    super.key,
    required this.durationMs,
    required this.positionMs,
    required this.bufferedMs,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
    this.thickness = 4.0,
  });

  final int durationMs;
  final int positionMs;
  final int bufferedMs;

  /// Bar thickness — slightly thicker on tablets (spec §0-ب).
  final double thickness;

  /// Called when a scrub gesture starts (hold controls visible).
  final VoidCallback onScrubStart;
  final ValueChanged<double> onScrubUpdate; // seconds preview
  final ValueChanged<double> onScrubEnd; // seconds commit

  @override
  State<GradientTimeline> createState() => _GradientTimelineState();
}

class _GradientTimelineState extends State<GradientTimeline> {
  bool _dragging = false;
  double _dragValue = 0;

  double get _progress {
    if (widget.durationMs <= 0) return 0;
    final value = _dragging ? _dragValue : widget.positionMs;
    return (value / widget.durationMs).clamp(0.0, 1.0);
  }

  double _valueFromDx(double dx, double width) =>
      (dx / (width == 0 ? 1 : width)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final duration = widget.durationMs;
        final thickness = widget.thickness;
        final thumbSize = thickness + 10;
        final buffered =
            duration > 0 ? (widget.bufferedMs / duration).clamp(0.0, 1.0) : 0.0;
        final progress = _progress;

        void handleTap(double dx) {
          final value = _valueFromDx(dx, width);
          widget.onScrubStart();
          widget.onScrubEnd(value * duration / 1000);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: duration <= 0
              ? null
              : (details) {
                  widget.onScrubStart();
                  setState(() {
                    _dragging = true;
                    _dragValue = _valueFromDx(details.localPosition.dx, width) *
                        duration;
                  });
                  widget.onScrubUpdate(_dragValue / 1000);
                },
          onHorizontalDragUpdate: duration <= 0
              ? null
              : (details) {
                  setState(() {
                    _dragging = true;
                    _dragValue = _valueFromDx(details.localPosition.dx, width) *
                        duration;
                  });
                  widget.onScrubUpdate(_dragValue / 1000);
                },
          onHorizontalDragEnd: duration <= 0
              ? null
              : (details) {
                  widget.onScrubEnd(_dragValue / 1000);
                  setState(() => _dragging = false);
                },
          onHorizontalDragCancel: () => setState(() => _dragging = false),
          onTapUp: duration <= 0
              ? null
              : (details) => handleTap(details.localPosition.dx),
          child: SizedBox(
            height: 40,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Remaining track.
                Container(
                  height: thickness,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                // Buffered portion — second color per spec §2.
                FractionallySizedBox(
                  widthFactor: buffered,
                  child: Container(
                    height: thickness,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .38),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                // Played gradient.
                FractionallySizedBox(
                  widthFactor: progress,
                  child: Container(
                    height: thickness,
                    decoration: BoxDecoration(
                      gradient: PlayerPalette.played,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                // Thumb + scrub bubble.
                Positioned(
                  left: (progress * width - thumbSize / 2)
                      .clamp(0.0, (width - thumbSize).clamp(0.0, width)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: _dragging ? thumbSize + 4 : thumbSize,
                    height: _dragging ? thumbSize + 4 : thumbSize,
                    decoration: BoxDecoration(
                      color: PlayerPalette.thumb,
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 5,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_dragging && duration > 0)
                  Positioned(
                    left: (progress * width - 44)
                        .clamp(0.0, (width - 88).clamp(0.0, width)),
                    bottom: 26,
                    child: Container(
                      width: thickness > 4 ? 120 : 88,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .78),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        formatPlayerTime(
                          Duration(milliseconds: (progress * duration).round()),
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Bottom cluster ─────────────────────────────────────────────────────────

/// Spec-exact bottom block (Task 124/125, trimmed by Task 139): progress row
/// above ALL controls; fullscreen+volume at the directional END, source /
/// subtitles / audio at the directional START. The [rewind][play][forward]
/// trio moved to the MIDDLE OF THE SCREEN (PlayerCenterTransport — Task 139
/// user mandate), so this row is slimmer and purely positional.
class PlayerBottomCluster extends StatelessWidget {
  const PlayerBottomCluster({
    super.key,
    required this.durationMs,
    required this.positionMs,
    required this.bufferedMs,
    required this.showRemaining,
    required this.volume,
    required this.muted,
    required this.fullscreen,
    required this.canPrev,
    required this.canNext,
    required this.scale,
    required this.wide,
    required this.english,
    required this.onPrev,
    required this.onNext,
    required this.onVolumeChanged,
    required this.onVolumeDragEnd,
    required this.onMuteToggle,
    required this.onToggleFullscreen,
    required this.onOpenStreams,
    required this.onOpenSubtitles,
    required this.onOpenAudio,
    required this.onToggleRemaining,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
  });

  final int durationMs;
  final int positionMs;
  final int bufferedMs;
  final bool showRemaining;

  /// mpv volume, normalized 0..1 (drives the left slider).
  final double volume;
  final bool muted;

  /// True = system UI hidden (immersive); false = system UI visible.
  final bool fullscreen;

  final bool canPrev;
  final bool canNext;
  final double scale; // 1.0 phone · ~1.28 tablet

  /// Tablet mode: wider margins, labels under side icons, thicker bar.
  final bool wide;
  final bool english;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onVolumeDragEnd;
  final VoidCallback onMuteToggle;
  final VoidCallback onToggleFullscreen;

  /// Task 139: the pickers now open the right-half side panel — always
  /// available (the panel loads/refreshes its own data), never null.
  final VoidCallback onOpenStreams;
  final VoidCallback onOpenSubtitles;
  final VoidCallback onOpenAudio;
  final VoidCallback onToggleRemaining;
  final VoidCallback onScrubStart;
  final ValueChanged<double> onScrubUpdate;
  final ValueChanged<double> onScrubEnd;

  @override
  Widget build(BuildContext context) {
    final controlSize = 44.0 * scale;
    final margin = wide ? 28.0 : 14.0;
    final thickness = wide ? 6.0 : 4.0;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Color(0xB3000000),
              Color(0x66000000),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(margin, 30, margin, 8 * scale),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Progress row — NEVER mirrored: full duration at the far
                // right, current time to its left, fill left→right always.
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(
                    children: [
                      _TimeLabel(
                        text: formatPlayerTime(
                          Duration(milliseconds: positionMs),
                        ),
                        wide: wide,
                        onTap: onToggleRemaining,
                      ),
                      Expanded(
                        child: GradientTimeline(
                          durationMs: durationMs,
                          positionMs: positionMs,
                          bufferedMs: bufferedMs,
                          thickness: thickness,
                          onScrubStart: onScrubStart,
                          onScrubUpdate: onScrubUpdate,
                          onScrubEnd: onScrubEnd,
                        ),
                      ),
                      _TimeLabel(
                        text: showRemaining && durationMs > 0
                            ? '-${formatPlayerTime(Duration(milliseconds: durationMs - positionMs))}'
                            : formatPlayerTime(
                                Duration(milliseconds: durationMs)),
                        wide: wide,
                        onTap: onToggleRemaining,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 2 * scale),
                // Control row: side groups mirror with the direction; the
                // transport trio lives center-screen (Task 139).
                SizedBox(
                  height: controlSize + (wide ? 26 : 6),
                  child: Stack(
                    children: [
                      // END side (RTL: left · LTR: right):
                      // fullscreen + volume.
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: _mediaGroup(controlSize),
                      ),
                      // START side (RTL: right · LTR: left):
                      // source / subtitles / audio.
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: _trackGroup(controlSize),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // END side: volume icon (tap = mute) + slider + fullscreen, with small
  // labels underneath on tablets (spec §0-ب).
  Widget _mediaGroup(double controlSize) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RaillessControl(
            icon: muted
                ? LucideIcons.volumeX
                : volume < .5
                    ? LucideIcons.volume1
                    : LucideIcons.volume2,
            semanticLabel: muted ? 'Unmute' : 'Mute',
            label: wide ? (english ? 'Sound' : 'الصوت') : null,
            scale: scale,
            onTap: onMuteToggle,
          ),
          _VolumeSlider(
            value: muted ? 0 : volume,
            width: (wide ? 130 : 84) * scale,
            onChanged: onVolumeChanged,
            onChangeEnd: (_) => onVolumeDragEnd(),
          ),
          _RaillessControl(
            icon: fullscreen
                ? LucideIcons.maximize
                : LucideIcons.minimize,
            semanticLabel: fullscreen ? 'Exit fullscreen' : 'Fullscreen',
            label: wide ? (english ? 'Full screen' : 'ملء الشاشة') : null,
            scale: scale,
            onTap: onToggleFullscreen,
          ),
        ],
      );

  // START side: source / subtitles / audio (+ prev & next episode for
  // series), with small labels underneath on tablets. The pickers open the
  // right-half side panel (Task 139) — always available.
  Widget _trackGroup(double controlSize) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canPrev)
            _RaillessControl(
              icon: LucideIcons.skipBack,
              semanticLabel: 'Previous episode',
              scale: scale,
              iconSize: 28,
              onTap: onPrev,
            ),
          _RaillessControl(
            icon: LucideIcons.arrowLeftRight,
            semanticLabel: 'Change source',
            label: wide ? (english ? 'Source' : 'المصدر') : null,
            scale: scale,
            onTap: onOpenStreams,
          ),
          _RaillessControl(
            icon: LucideIcons.captions,
            semanticLabel: 'Subtitles',
            label: wide ? (english ? 'Subs' : 'الترجمة') : null,
            scale: scale,
            onTap: onOpenSubtitles,
          ),
          _RaillessControl(
            icon: LucideIcons.audioLines,
            semanticLabel: 'Audio track / dub',
            label: wide ? (english ? 'Audio' : 'الدبلاج') : null,
            scale: scale,
            onTap: onOpenAudio,
          ),
          if (canNext)
            _RaillessControl(
              icon: LucideIcons.skipForward,
              semanticLabel: 'Next episode',
              scale: scale,
              iconSize: 28,
              onTap: onNext,
            ),
        ],
      );
}

/// Compact persistent volume bar (user mandate: "volume icon AND bar").
class _VolumeSlider extends StatelessWidget {
  const _VolumeSlider({
    required this.value,
    required this.width,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double value; // 0..1
  final double width;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            padding: EdgeInsets.zero,
          ),
          child: Slider(
            value: value.clamp(0.0, 1.0),
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
            activeColor: Colors.white,
            inactiveColor: Colors.white24,
          ),
        ),
      );
}

/// Circular-arrow skip button with the configurable seconds rendered inside
/// (replaces the fixed replay_10/forward_10 glyphs).
class _SkipButton extends StatelessWidget {
  const _SkipButton({
    required this.forward,
    required this.seconds,
    required this.size,
    required this.onTap,
  });

  final bool forward;
  final int seconds;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '${forward ? 'Forward' : 'Rewind'} $seconds seconds',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  forward ? LucideIcons.rotateCw : LucideIcons.rotateCcw,
                  color: Colors.white,
                  size: size * .62,
                  shadows: PlayerPalette.iconShadow,
                ),
                Padding(
                  padding: EdgeInsets.only(
                    top: size * .08,
                    left: forward ? size * .16 : 0,
                    right: forward ? 0 : size * .16,
                  ),
                  child: Text(
                    '$seconds',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel(
      {required this.text, required this.onTap, this.wide = false});
  final String text;
  final bool wide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white70,
              fontSize: wide ? 13.5 : 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      );
}

class _RaillessControl extends StatelessWidget {
  const _RaillessControl({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    required this.scale,
    this.iconSize = 25,
    this.label,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;
  final double scale;
  final double iconSize;

  /// Small caption under the icon — tablet only (spec §0-ب).
  final String? label;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final iconWidget = Icon(
      icon,
      color: enabled ? Colors.white : Colors.white30,
      size: iconSize * scale,
      shadows: enabled ? PlayerPalette.iconShadow : null,
    );
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Opacity(
        opacity: enabled ? 1.0 : .55,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: label == null
              ? SizedBox(
                  width: 44 * scale,
                  height: 44 * scale,
                  child: Center(child: iconWidget),
                )
              : Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 44 * scale,
                        height: 44 * scale,
                        child: Center(child: iconWidget),
                      ),
                      Text(
                        label!,
                        style: TextStyle(
                          color: enabled ? Colors.white70 : Colors.white24,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

// ── Double-tap ripple (user mandate: animated ±N feedback) ────────────────

/// YouTube-style double-tap feedback: a soft circular burst anchored to the
/// tapped side, showing the arrow glyph and the ±N seconds label, scaling in
/// and fading out once.
class DoubleTapRipple extends StatefulWidget {
  const DoubleTapRipple({
    super.key,
    required this.forward,
    required this.seconds,
    required this.english,
  });

  final bool forward;
  final int seconds;
  final bool english;

  @override
  State<DoubleTapRipple> createState() => _DoubleTapRippleState();
}

class _DoubleTapRippleState extends State<DoubleTapRipple>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..forward();

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: .55, end: 1.0)
          .chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 42,
    ),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 58),
  ]).animate(_controller);

  late final Animation<double> _fade = TweenSequence<double>([
    TweenSequenceItem(
      tween:
          Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)),
      weight: 18,
    ),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 42),
    TweenSequenceItem(
      tween:
          Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
      weight: 40,
    ),
  ]).animate(_controller);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _fade,
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            width: 190,
            height: 190,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.white.withValues(alpha: .20),
                  Colors.white.withValues(alpha: .06),
                  Colors.white.withValues(alpha: 0),
                ],
              ),
            ),
            alignment: Alignment.center,
            child: Container(
              width: 118,
              height: 118,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .13),
                border: Border.all(color: Colors.white24),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.forward
                        ? LucideIcons.chevronsRight
                        : LucideIcons.chevronsLeft,
                    color: Colors.white,
                    size: 32,
                    shadows: PlayerPalette.iconShadow,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.english
                        ? '${widget.forward ? '+' : '-'}${widget.seconds}s'
                        : '${widget.forward ? '+' : '-'}${widget.seconds}ث',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                      shadows: PlayerPalette.iconShadow,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

// ── Gesture HUDs ───────────────────────────────────────────────────────────

class SeekHud extends StatelessWidget {
  const SeekHud({
    super.key,
    required this.deltaSeconds,
    required this.targetText,
  });

  final int deltaSeconds;
  final String targetText;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .72),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    deltaSeconds >= 0
                        ? LucideIcons.chevronsRight
                        : LucideIcons.chevronsLeft,
                    color: PlayerPalette.thumb,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${deltaSeconds >= 0 ? '+' : ''}$deltaSeconds s',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                targetText,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      );
}

class VerticalHud extends StatelessWidget {
  const VerticalHud({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.vertical = false,
  });

  final IconData icon;
  final String label;
  final double value; // 0..1

  /// True = spec §6 side-anchored indicator (icon + vertical bar + percent);
  /// false = legacy compact centered card.
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    if (vertical) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .66),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white12),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(value * 100).round()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 5,
                height: 150,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Stack(
                    alignment: AlignmentDirectional.bottomStart,
                    children: [
                      Container(color: Colors.white24),
                      FractionallySizedBox(
                        heightFactor: value.clamp(0.0, 1.0),
                        child: Container(color: PlayerPalette.thumb),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Icon(icon, color: Colors.white, size: 20),
            ],
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 8),
            SizedBox(
              width: 110,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: value.clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation(PlayerPalette.thumb),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$label · ${(value * 100).round()}%',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ZoomHud extends StatelessWidget {
  const ZoomHud({super.key, required this.scale});
  final double scale;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .72),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '${scale.toStringAsFixed(1)}×',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      );
}

class LockHintHud extends StatelessWidget {
  const LockHintHud({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .72),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.lock, color: Colors.white, size: 15),
            const SizedBox(width: 7),
            Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

// ── Cards ──────────────────────────────────────────────────────────────────

class PlayerCardShell extends StatelessWidget {
  const PlayerCardShell({
    super.key,
    required this.child,
    this.width,
  });

  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: HorseTheme.raised.withValues(alpha: .97),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .07)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: child,
      );
}

class PlayerCardHeader extends StatelessWidget {
  const PlayerCardHeader({
    super.key,
    required this.icon,
    required this.label,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 15, color: HorseTheme.gold),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      );
}

class PlayerPrimaryAction extends StatelessWidget {
  const PlayerPrimaryAction({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: HorseTheme.gold,
          foregroundColor: const Color(0xFF1A1209),
          minimumSize: const Size.fromHeight(36),
        ),
        onPressed: onPressed,
        child: Text(label),
      );
}

class PlayerSecondaryAction extends StatelessWidget {
  const PlayerSecondaryAction({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(36),
        ),
        onPressed: onPressed,
        child: Text(label),
      );
}
