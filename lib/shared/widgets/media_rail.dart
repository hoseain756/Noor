import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:noor_mobile/l10n/nova_strings.dart';
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
    this.subtitle,
    this.onOpenSection,
  });

  final String title;

  /// Optional source line under the rail title (the add-on name on the web
  /// AddonRail).
  final String? subtitle;
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
    // Task 122-b (F5): the rail used to `watch` AppState (rebuilding the
    // whole rail on any notification) for a single setting — select exactly
    // that field instead (identical value, identical UI).
    final showTitle = context.select<AppState, bool>(
      (app) => app.webSettings['hidePosterTitles'] != true,
    );
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
                  color: NovaTheme.of(context).gold,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: subtitle == null
                    ? Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: NovaTheme.of(context).muted),
                          ),
                        ],
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
    final label = NovaStrings.lookup(english, 'message101');
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
                  color: NovaTheme.of(context).raised.withValues(alpha: .6),
                  border: Border.all(color: NovaTheme.of(context).line),
                ),
                child: Icon(
                  forward ? LucideIcons.chevronRight : LucideIcons.chevronLeft,
                  size: 22,
                  color: NovaTheme.of(context).gold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
