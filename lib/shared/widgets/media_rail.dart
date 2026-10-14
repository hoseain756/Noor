import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/app_state.dart';
import '../../core/models/media_item.dart';
import 'poster_card.dart';

class MediaRail extends StatelessWidget {
  const MediaRail({
    super.key,
    required this.title,
    required this.items,
    required this.onTap,
    this.numbered = false,
  });

  final String title;
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onTap;
  final bool numbered;

  static double sectionSpacing(BuildContext context) =>
      (MediaQuery.sizeOf(context).width * .045).clamp(14.0, 24.0).toDouble();

  static double headerSpacing(BuildContext context) =>
      (MediaQuery.sizeOf(context).width * .03).clamp(8.0, 14.0).toDouble();

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final wide = viewportWidth >= 700;
    final textScaler = MediaQuery.textScalerOf(context);
    final settings = context.watch<AppState>().webSettings;
    final showTitle = settings['hidePosterTitles'] != true;
    final showRelease =
        showTitle && items.any((item) => item.releaseInfo != null);
    final posterWidth = numbered
        ? (viewportWidth * .075).clamp(104.0, 128.0).toDouble()
        : wide
            ? 138.0
            : 122.0;
    final posterHeight = posterWidth / .72;
    final titleHeight = showTitle ? textScaler.scale(14) * 1.3 * 2 : 0.0;
    final releaseHeight = showRelease ? textScaler.scale(12) * 1.2 : 0.0;
    final cardTextHeight = showTitle
        ? 8 + titleHeight + (showRelease ? 3 + releaseHeight : 0)
        : 0.0;
    final verticalInset = numbered ? 14.0 : 0.0;
    final railHeight = posterHeight + cardTextHeight + verticalInset * 2;
    final rankSize = (viewportWidth * .12).clamp(120.0, 190.0).toDouble();
    final rankOverlap = posterWidth * .24;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: wide ? 34 : 20),
          child: numbered
              ? Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                )
              : Row(
                  children: [
                    Container(
                      width: 3,
                      height: 19,
                      decoration: BoxDecoration(
                        color: const Color(0xFFC99C62),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
        ),
        SizedBox(height: numbered ? 2 : headerSpacing(context)),
        SizedBox(
          height: railHeight,
          child: ListView.separated(
            padding: EdgeInsets.symmetric(
              horizontal: numbered ? (wide ? 34 : 24) : (wide ? 34 : 20),
              vertical: verticalInset,
            ),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => SizedBox(
              width: numbered
                  ? (viewportWidth * .035).clamp(12.0, 24.0).toDouble()
                  : (viewportWidth * .035).clamp(12.0, 18.0).toDouble(),
            ),
            itemBuilder: (context, index) {
              final item = items[index];
              if (!numbered) {
                return PosterCard(
                  item: item,
                  width: posterWidth,
                  onTap: () => onTap(item),
                );
              }
              final itemTextHeight = showTitle
                  ? 8 +
                      titleHeight +
                      (item.releaseInfo == null ? 0 : 3 + releaseHeight)
                  : 0.0;
              final numberTextWidth = rankSize * (index + 1 > 9 ? 1.08 : .58);
              final itemWidth = posterWidth + numberTextWidth - rankOverlap;
              return SizedBox(
                height: posterHeight + cardTextHeight,
                width: itemWidth,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    PositionedDirectional(
                      start: 0,
                      // The web Top 10 rank adds 0.12em of bottom padding;
                      // lift the outline by the same amount so it peeks from
                      // behind the poster instead of sitting below its edge.
                      bottom: itemTextHeight + rankSize * .12,
                      child: IgnorePointer(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: rankSize,
                            height: .78,
                            fontWeight: FontWeight.w300,
                            letterSpacing: -rankSize * .08,
                            foreground: Paint()
                              ..style = PaintingStyle.stroke
                              ..strokeWidth = 1.35
                              ..color = Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: .58),
                          ),
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      end: 0,
                      bottom: 0,
                      child: PosterCard(
                        item: item,
                        width: posterWidth,
                        onTap: () => onTap(item),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
