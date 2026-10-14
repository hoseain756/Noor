import 'package:flutter/material.dart';

import '../../core/models/media_item.dart';
import '../../core/theme/horse_theme.dart';
import '../../shared/widgets/media_quick_look.dart';
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

  /// Horizontal pull of the "1" onto the "0" inside the tight "10" unit,
  /// as a fraction of one digit width. The two outlines cross so the pair
  /// reads as a single-digit-wide lockup (Netflix style).
  static const double _tenOnePull = 0.30;

  /// Poster start as a fraction of the rank width for rank 10. The "10"
  /// unit is one digit wide, so only its trailing edge (~12%) is hidden
  /// behind the poster and the crossing of the two digits stays visible.
  static const double _tenOverlap = 0.88;

  static final double _posterHeight = _posterWidth / _posterRatio;

  /// Vertical air above/below the poster so the soft shadow is not clipped
  /// by the horizontal viewport.
  static final double itemHeight = _posterHeight + 30;

  @override
  Widget build(BuildContext context) {
    final isTen = rank == 10;
    // Task: font size is 1.0–1.1x the poster height.
    final fontSize = _posterHeight * 1.05;
    // The "10" lockup occupies exactly one digit's width — the same
    // footprint as ranks 1–9 — so only the poster-start fraction differs.
    final digitWidth = fontSize * _digitFactor;
    final rankWidth = digitWidth;
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
              onLongPress: () => showMediaQuickLook(
                context,
                item: item,
                onOpen: onTap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Huge rank number: the glyph interior is filled with the app background
/// color (it occludes whatever sits behind it) while the same thin white
/// rounded stroke stays on top — fill + rim (user spec). Always Western
/// digits laid out left-to-right (never mirrored to "01" in Arabic).
/// Rank 10 is a special tight lockup: the "1" and "0" overlap so the whole
/// unit occupies a single digit's width.
class OutlinedRankNumber extends StatelessWidget {
  const OutlinedRankNumber({
    super.key,
    required this.rank,
    required this.fontSize,
  });

  final int rank;
  final double fontSize;

  /// The white outline layer (identical to the previous hollow look).
  TextStyle get _style => TextStyle(
        fontSize: fontSize,
        height: .78,
        fontWeight: FontWeight.w900,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white.withValues(alpha: .85),
      );

  /// The fill layer: the app background color variable (#000000), painted
  /// under the stroke so the numeral reads as cut out of the page.
  TextStyle get _fillStyle => TextStyle(
        fontSize: fontSize,
        height: .78,
        fontWeight: FontWeight.w900,
        color: HorseTheme.canvas,
      );

  /// One digit = background-colored fill under the white stroke.
  Widget _glyph(String text) => Stack(
        clipBehavior: Clip.none,
        children: [
          Text(text, style: _fillStyle),
          Text(text, style: _style),
        ],
      );

  @override
  Widget build(BuildContext context) {
    if (rank != 10) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: _glyph('$rank'),
      );
    }
    // Rank 10 renders as ONE tight unit occupying a single digit's width:
    // the "1" is pulled onto the "0" until the two outlines cross, so the
    // digits overlap instead of sitting side by side with a gap. The inner
    // LTR direction keeps the digit order fixed ("10", never "01") even
    // inside an RTL list; the whole unit is mirrored as one block by the
    // parent PositionedDirectional.
    final digitWidth = fontSize * Top10Item._digitFactor;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: digitWidth,
        height: fontSize * .78,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // The "0" fills the digit box…
            Positioned(
              left: 0,
              top: 0,
              child: _glyph('0'),
            ),
            // …and the "1" is pulled left onto it until the outlines
            // intersect (one digit appears on top of the other).
            Positioned(
              left: -digitWidth * Top10Item._tenOnePull,
              top: 0,
              child: _glyph('1'),
            ),
          ],
        ),
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
    required this.onLongPress,
  });

  final MediaItem item;
  final double width;
  final int rank;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      button: true,
      label: '$rank. ${item.name}',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
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
