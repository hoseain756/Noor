import 'package:flutter/material.dart';

import '../../../core/theme/horse_theme.dart';

/// Visual language of the cinematic player chrome (reference design):
/// white controls over the video, a teal→blue gradient timeline, a large
/// outlined central play control and slim translucent scrims.
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

// ── Top bar ────────────────────────────────────────────────────────────────

class PlayerTopBar extends StatelessWidget {
  const PlayerTopBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onClose,
    required this.onSettings,
    this.onSubtitles,
    this.onQueue,
    this.onStreams,
    this.streamLabel,
  });

  final String title;
  final String subtitle;
  final VoidCallback onClose;
  final VoidCallback onSettings;
  final VoidCallback? onSubtitles;
  final VoidCallback? onQueue;
  final VoidCallback? onStreams;
  final String? streamLabel;

  @override
  Widget build(BuildContext context) {
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
            padding: const EdgeInsets.fromLTRB(12, 6, 10, 26),
            child: Row(
              children: [
                PlayerBackButton(onTap: onClose),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          shadows: PlayerPalette.iconShadow,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .62),
                            fontSize: 12,
                            shadows: PlayerPalette.iconShadow,
                          ),
                        ),
                    ],
                  ),
                ),
                if (onStreams != null && streamLabel != null) ...[
                  const SizedBox(width: 8),
                  Material(
                    color: Colors.black.withValues(alpha: .40),
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: onStreams,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.swap_horiz_rounded,
                              size: 15,
                              color: Colors.white,
                              shadows: PlayerPalette.iconShadow,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 110),
                                child: Text(
                                  streamLabel!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                // Reference top-right icons: settings · queue · subtitles.
                if (onSubtitles != null)
                  PlayerRailButton(
                    icon: Icons.subtitles_outlined,
                    semanticLabel: 'Subtitles',
                    onTap: onSubtitles!,
                  ),
                if (onQueue != null)
                  PlayerRailButton(
                    icon: Icons.format_list_bulleted_rounded,
                    semanticLabel: 'Episodes',
                    onTap: onQueue!,
                  ),
                PlayerRailButton(
                  icon: Icons.settings_rounded,
                  semanticLabel: 'Playback settings',
                  onTap: onSettings,
                ),
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
            child: Icon(Icons.close_rounded, color: Colors.white, size: 22),
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
  });

  final int durationMs;
  final int positionMs;
  final int bufferedMs;

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

  void _startDrag(double value) {
    widget.onScrubStart();
    setState(() {
      _dragging = true;
      _dragValue = value * widget.durationMs;
    });
    widget.onScrubUpdate(_dragValue * widget.durationMs / 1000);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final duration = widget.durationMs;
        final buffered = duration > 0
            ? (widget.bufferedMs / duration).clamp(0.0, 1.0)
            : 0.0;
        final progress = _progress;

        void handleTap(DragUpdateDetails? d, double dx) {
          final value = _valueFromDx(dx, width);
          widget.onScrubStart();
          widget.onScrubEnd(value * duration / 1000);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: duration <= 0
              ? null
              : (details) => _startDrag(_valueFromDx(details.localPosition.dx, width)),
          onHorizontalDragUpdate: duration <= 0
              ? null
              : (details) {
                  setState(() {
                    _dragging = true;
                    _dragValue =
                        _valueFromDx(details.localPosition.dx, width) * duration;
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
          onTapUp: duration <= 0 ? null : (details) => handleTap(null, details.localPosition.dx),
          child: SizedBox(
            height: 40,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Remaining track.
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                // Buffered portion.
                FractionallySizedBox(
                  widthFactor: buffered,
                  child: Container(
                    height: 4,
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
                    height: 4,
                    decoration: BoxDecoration(
                      gradient: PlayerPalette.played,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                // Thumb + scrub bubble.
                Positioned(
                  left: (progress * width - 9)
                      .clamp(0.0, (width - 18).clamp(0.0, width)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: _dragging ? 18 : 14,
                    height: _dragging ? 18 : 14,
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
                      width: 88,
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

class PlayerBottomCluster extends StatelessWidget {
  const PlayerBottomCluster({
    super.key,
    required this.durationMs,
    required this.positionMs,
    required this.bufferedMs,
    required this.previewSeconds,
    required this.isPlaying,
    required this.muted,
    required this.showRemaining,
    required this.canPrev,
    required this.canNext,
    required this.scale,
    required this.onPlayPause,
    required this.onSkip,
    required this.onPrev,
    required this.onNext,
    required this.onMuteToggle,
    required this.onFitCycle,
    required this.onToggleRemaining,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
  });

  final int durationMs;
  final int positionMs;
  final int bufferedMs;
  final double previewSeconds; // −1 = none (surface scrub HUD shown instead)
  final bool isPlaying;
  final bool muted;
  final bool showRemaining;
  final bool canPrev;
  final bool canNext;
  final double scale; // 1.0 phone · ~1.15 tablet
  final VoidCallback onPlayPause;
  final ValueChanged<int> onSkip;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback onMuteToggle;
  final VoidCallback onFitCycle;
  final VoidCallback onToggleRemaining;
  final VoidCallback onScrubStart;
  final ValueChanged<double> onScrubUpdate;
  final ValueChanged<double> onScrubEnd;

  @override
  Widget build(BuildContext context) {
    final shownPosition =
        previewSeconds >= 0 ? (previewSeconds * 1000).round() : positionMs;
    final big = 64.0 * scale;
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
            padding: EdgeInsets.fromLTRB(18, 30, 18, 8 * scale),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Time row — bar always LTR (media convention).
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(
                    children: [
                      _TimeLabel(
                        text: formatPlayerTime(
                          Duration(milliseconds: shownPosition),
                        ),
                        onTap: onToggleRemaining,
                      ),
                      Expanded(
                        child: GradientTimeline(
                          durationMs: durationMs,
                          positionMs: positionMs,
                          bufferedMs: bufferedMs,
                          onScrubStart: onScrubStart,
                          onScrubUpdate: onScrubUpdate,
                          onScrubEnd: onScrubEnd,
                        ),
                      ),
                      _TimeLabel(
                        text: showRemaining && durationMs > 0
                            ? '-${formatPlayerTime(Duration(milliseconds: durationMs - positionMs))}'
                            : formatPlayerTime(Duration(milliseconds: durationMs)),
                        onTap: onToggleRemaining,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 2 * scale),
                // Cinematic control row — symmetric around the big play.
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _RaillessControl(
                          icon: muted
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                          semanticLabel: muted ? 'Unmute' : 'Mute',
                          scale: scale,
                          onTap: onMuteToggle,
                        ),
                        _RaillessControl(
                          icon: Icons.replay_10_rounded,
                          semanticLabel: 'Rewind 10 seconds',
                          scale: scale,
                          onTap: () => onSkip(-10),
                        ),
                        if (canPrev)
                          _RaillessControl(
                            icon: Icons.skip_previous_rounded,
                            semanticLabel: 'Previous episode',
                            scale: scale,
                            iconSize: 30,
                            onTap: onPrev,
                          ),
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
                                isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: big * .52,
                                shadows: PlayerPalette.iconShadow,
                              ),
                            ),
                          ),
                        ),
                        if (canNext)
                          _RaillessControl(
                            icon: Icons.skip_next_rounded,
                            semanticLabel: 'Next episode',
                            scale: scale,
                            iconSize: 30,
                            onTap: onNext,
                          ),
                        _RaillessControl(
                          icon: Icons.forward_10_rounded,
                          semanticLabel: 'Forward 10 seconds',
                          scale: scale,
                          onTap: () => onSkip(10),
                        ),
                        _RaillessControl(
                          icon: Icons.aspect_ratio_rounded,
                          semanticLabel: 'Cycle video fit',
                          scale: scale,
                          onTap: onFitCycle,
                        ),
                      ],
                    ),
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

class _TimeLabel extends StatelessWidget {
  const _TimeLabel({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontFeatures: [FontFeature.tabularFigures()],
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
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;
  final double scale;
  final double iconSize;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semanticLabel,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44 * scale,
            height: 44 * scale,
            child: Icon(
              icon,
              color: Colors.white,
              size: iconSize * scale,
              shadows: PlayerPalette.iconShadow,
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
                        ? Icons.fast_forward_rounded
                        : Icons.fast_rewind_rounded,
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
  });

  final IconData icon;
  final String label;
  final double value; // 0..1

  @override
  Widget build(BuildContext context) => Container(
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
                    valueColor:
                        const AlwaysStoppedAnimation(PlayerPalette.thumb),
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
            const Icon(Icons.lock_rounded, color: Colors.white, size: 15),
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
