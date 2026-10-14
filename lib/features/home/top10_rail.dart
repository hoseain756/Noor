import 'package:flutter/material.dart';

import '../../core/models/media_item.dart';
import '../../core/theme/horse_theme.dart';
import '../../shared/widgets/media_rail.dart';

/// Netflix-style "Top 10" rail.
///
/// Every entry is a [Top10Item]: a huge hollow rank number with the poster
/// "sticker" stacked above it, overlapping and hiding part of the digit. The
/// whole layout is direction-aware: number on the start side, poster after
/// it — the row mirrors automatically between LTR (number left) and RTL
/// (number right), and the horizontal list scrolls from the start side.
class Top10Rail extends StatelessWidget {
  const Top10Rail({
    super.key,
    required this.title,
    required this.items,
    required this.onTap,
  });

  final String title;
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final startPad = wide ? 34.0 : 16.0;
    // The ranking never shows more than ten entries.
    final ranked = items.take(10).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsetsDirectional.symmetric(horizontal: startPad),
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        SizedBox(height: MediaRail.headerSpacing(context)),
        SizedBox(
          height: Top10Item.itemHeight,
          child: ListView.builder(
            padding: EdgeInsetsDirectional.symmetric(horizontal: startPad),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: ranked.length,
            itemBuilder: (context, index) {
              final last = index == ranked.length - 1;
              return Padding(
                padding: EdgeInsetsDirectional.only(end: last ? 0 : 14),
                child: Top10Item(
                  rank: index + 1,
                  item: ranked[index],
                  onTap: () => onTap(ranked[index]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One ranked entry: hollow number behind, poster sticker in front.
class Top10Item extends StatelessWidget {
  const Top10Item({
    super.key,
    required this.rank,
    required this.item,
    required this.onTap,
  });

  /// 1-based rank (1..10) — always rendered as Western digits.
  final int rank;
  final MediaItem item;
  final VoidCallback onTap;

  // ---- Tunable design constants (logical pixels) ----

  /// Poster width (target 115..125).
  static const double _posterWidth = 120;

  /// Portrait ratio, about 2:3 (width / height).
  static const double _posterRatio = 0.68;

  /// Single digit advance as a fraction of the font size (Roboto Black
  /// digits are ≈ 0.58 em wide).
  static const double _digitFactor = 0.58;

  /// Poster start as a fraction of the rank width for ranks 1–9:
  /// hides ~35% of the digit (task range 25–35%).
  static const double _singleOverlap = 0.65;

  /// Painted width of the tight "10" unit as a multiple of one digit.
  static const double _tenWidthFactor = 1.6;

  /// Poster start as a fraction of the "10" width: only the trailing edge of
  /// the "0" is hidden (~25% of that digit) instead of most of it.
  static const double _tenOverlap = 0.88;

  static final double _posterHeight = _posterWidth / _posterRatio;

  /// Vertical air above/below the poster so the soft shadow is not clipped
  /// by the horizontal viewport.
  static final double itemHeight = _posterHeight + 30;

  @override
  Widget build(BuildContext context) {
    final isTen = rank >= 10;
    // Task: font size is 1.0–1.1x the poster height.
    final fontSize = _posterHeight * 1.05;
    final digitWidth = fontSize * _digitFactor;
    final rankWidth = isTen ? digitWidth * _tenWidthFactor : digitWidth;
    final posterStart = rankWidth * (isTen ? _tenOverlap : _singleOverlap);

    // Center the number's text box (height: .78) against the poster, with a
    // tiny downward nudge so the glyphs sit "centered or slightly lower".
    final numberTop = (itemHeight - fontSize * .78) / 2 + 2;

    return SizedBox(
      width: posterStart + _posterWidth,
      height: itemHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 1) The hollow rank number, behind everything.
          PositionedDirectional(
            start: 0,
            top: numberTop,
            child: IgnorePointer(
              child: OutlinedRankNumber(rank: rank, fontSize: fontSize),
            ),
          ),
          // 2) The poster sticker, above the number, hiding part of it.
          PositionedDirectional(
            start: posterStart,
            top: 15,
            child: _Top10Sticker(
              item: item,
              width: _posterWidth,
              rank: rank,
              onTap: onTap,
            ),
          ),
        ],
      ),
    );
  }
}

/// Huge hollow digit: no fill, thin white rounded stroke, always Western
/// digits laid out left-to-right (never mirrored to "01" in Arabic).
class OutlinedRankNumber extends StatelessWidget {
  const OutlinedRankNumber({
    super.key,
    required this.rank,
    required this.fontSize,
  });

  final int rank;
  final double fontSize;

  TextStyle get _style => TextStyle(
        fontSize: fontSize,
        height: .78,
        fontWeight: FontWeight.w900,
        // Hollow fill: only a thin white outline is painted.
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white.withValues(alpha: .85),
      );

  @override
  Widget build(BuildContext context) {
    if (rank < 10) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Text('$rank', style: _style),
      );
    }
    // Rank 10 must read as one tight unit: the "0" is pulled toward the "1"
    // so the two outlines nearly touch. The inner LTR direction keeps the
    // digit order fixed even inside an RTL list.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('1', style: _style),
          Transform.translate(
            offset: Offset(-fontSize * 0.12, 0),
            child: Text('0', style: _style),
          ),
        ],
      ),
    );
  }
}

/// Poster sticker: the soft shadow is painted on a container OUTSIDE the
/// [ClipRRect] (so it is not clipped), falls toward the number (start side),
/// and the image loading follows the app's existing pattern (network image,
/// BoxFit.cover, dark surface while loading, icon fallback on error).
class _Top10Sticker extends StatelessWidget {
  const _Top10Sticker({
    required this.item,
    required this.width,
    required this.rank,
    required this.onTap,
  });

  final MediaItem item;
  final double width;
  final int rank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      button: true,
      label: '$rank. ${item.name}',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .35),
                blurRadius: 14,
                spreadRadius: 1,
                // Toward the number (start side) and slightly down.
                offset: Offset(rtl ? 4 : -4, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: Top10Item._posterRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Loading placeholder surface.
                  const ColoredBox(color: HorseTheme.raised),
                  if (item.poster != null)
                    Image.network(
                      item.poster!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const _PosterFallback(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback();

  @override
  Widget build(BuildContext context) => Container(
        color: HorseTheme.raised,
        child: const Center(
          child: Icon(Icons.movie_outlined, size: 34, color: HorseTheme.gold),
        ),
      );
}
