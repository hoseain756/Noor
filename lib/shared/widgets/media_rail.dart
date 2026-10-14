import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';
import '../../core/models/media_item.dart';
import 'poster_card.dart';

class MediaRail extends StatelessWidget {
  const MediaRail({
    super.key,
    required this.title,
    required this.items,
    required this.onTap,
    this.onOpenSection,
  });

  final String title;
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onTap;

  /// When provided, the header gains the "greater-than" mark that opens the
  /// full catalog section this rail belongs to.
  final VoidCallback? onOpenSection;

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
    final posterWidth = wide ? 138.0 : 122.0;
    final posterHeight = posterWidth / .72;
    final titleHeight = showTitle ? textScaler.scale(14) * 1.3 * 2 : 0.0;
    final releaseHeight = showRelease ? textScaler.scale(12) * 1.2 : 0.0;
    final cardTextHeight = showTitle
        ? 8 + titleHeight + (showRelease ? 3 + releaseHeight : 0)
        : 0.0;
    final railHeight = posterHeight + cardTextHeight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: wide ? 34 : 20),
          child: Row(
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
              if (onOpenSection != null) _SectionChevron(onTap: onOpenSection!),
            ],
          ),
        ),
        SizedBox(height: headerSpacing(context)),
        SizedBox(
          height: railHeight,
          child: ListView.separated(
            padding: EdgeInsets.symmetric(horizontal: wide ? 34 : 20),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => SizedBox(
              width: (viewportWidth * .035).clamp(12.0, 18.0).toDouble(),
            ),
            itemBuilder: (context, index) {
              final item = items[index];
              return PosterCard(
                item: item,
                width: posterWidth,
                onTap: () => onTap(item),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The header "greater-than" mark that opens the rail's full section.
/// A chevron glyph (not a shafted arrow), pointing forward in both locales.
class _SectionChevron extends StatelessWidget {
  const _SectionChevron({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final english = context.read<AppState>().english;
    final forward = Directionality.of(context) == TextDirection.ltr;
    final label = english ? 'Open section' : 'فتح القسم';
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: HorseTheme.raised.withValues(alpha: .6),
                  border: Border.all(color: HorseTheme.line),
                ),
                child: Icon(
                  forward
                      ? Icons.chevron_right_rounded
                      : Icons.chevron_left_rounded,
                  size: 22,
                  color: HorseTheme.gold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
