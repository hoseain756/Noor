import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/media_item.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/horse_theme.dart';
import '../../../shared/widgets/media_rail.dart';
import '../top10_rail.dart';

/// One home catalog row driven by a future: the geometry-matched rail
/// skeleton while waiting, a title + message + retry row on error/empty
/// (Top 10 rows only — other rows fail/empty silently), else the standard
/// poster rail or the ranked Top 10 layout. Moved verbatim from
/// home_page.dart (Task 121-c).
class AsyncMediaSection extends StatelessWidget {
  const AsyncMediaSection({
    super.key,
    required this.title,
    required this.future,
    required this.onTap,
    required this.onRetry,
    required this.english,
    this.subtitle,
    this.numbered = false,
    this.showEmptyState = false,
    this.onOpenSection,
  });

  final String title;

  /// Optional source line under the rail title (the add-on name, mirroring
  /// the web Rail subtitle).
  final String? subtitle;
  final Future<List<MediaItem>> future;
  final ValueChanged<MediaItem> onTap;
  final VoidCallback onRetry;
  final bool english;
  final bool numbered;
  final bool showEmptyState;

  /// Opens the full catalog section this rail belongs to (the header
  /// "greater-than" mark).
  final VoidCallback? onOpenSection;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<MediaItem>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return RailLoadingSkeleton(title: title);
          }
          final items = snapshot.data ?? const <MediaItem>[];
          if (snapshot.hasError) {
            if (!showEmptyState) return const SizedBox.shrink();
            return _RailMessage(
              title: title,
              message: english
                  ? 'Could not load today’s ranking.'
                  : 'تعذر تحميل قائمة اليوم.',
              actionLabel: english ? 'Retry' : 'إعادة المحاولة',
              onRetry: onRetry,
            );
          }
          if (items.isEmpty) {
            if (!showEmptyState) return const SizedBox.shrink();
            return _RailMessage(
              title: title,
              message: english
                  ? 'No ranked titles are available right now.'
                  : 'لا تتوفر عناوين في القائمة حاليًا.',
              actionLabel: english ? 'Refresh' : 'تحديث',
              onRetry: onRetry,
            );
          }
          return Padding(
            padding: EdgeInsetsDirectional.only(
              bottom: MediaRail.sectionSpacing(context),
            ),
            // The Top 10 row uses the ranked sticker layout; every other
            // section keeps the standard poster rail.
            child: numbered
                ? Top10Rail(title: title, items: items, onTap: onTap)
                : MediaRail(
                    title: title,
                    subtitle: subtitle,
                    items: items,
                    onTap: onTap,
                    onOpenSection: onOpenSection,
                  ),
          );
        },
      );
}

/// Loading placeholder matching the real rail's geometry: title, then a
/// horizontal row of surface "posters" (138px wide at the 700px breakpoint,
/// else 122) with the two-line label stub when poster titles are shown.
class RailLoadingSkeleton extends StatelessWidget {
  const RailLoadingSkeleton({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppState>().webSettings;
    final showTitle = settings['hidePosterTitles'] != true;
    final width = MediaQuery.sizeOf(context).width;
    final posterWidth = width >= 700 ? 138.0 : 122.0;
    final posterHeight = posterWidth / .72;
    final labelHeight = showTitle
        ? 8 + MediaQuery.textScalerOf(context).scale(14) * 1.3 * 2
        : 0.0;
    final railHeight = posterHeight + labelHeight;
    return Padding(
      padding: EdgeInsetsDirectional.only(
        bottom: MediaRail.sectionSpacing(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 20),
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          SizedBox(height: MediaRail.headerSpacing(context)),
          SizedBox(
            height: railHeight,
            child: ListView.separated(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: 6,
              separatorBuilder: (_, __) => SizedBox(
                width: (width * .035).clamp(12.0, 18.0).toDouble(),
              ),
              itemBuilder: (_, __) => SizedBox(
                width: posterWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: posterHeight,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: HorseTheme.surface,
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    if (showTitle) ...[
                      const SizedBox(height: 8),
                      const SizedBox(
                        width: 96,
                        height: 11,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: HorseTheme.surface,
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      const SizedBox(
                        width: 64,
                        height: 9,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: HorseTheme.surface,
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rail-level error/empty message: title line, message, then the retry
/// [TextButton.icon]. Deliberately NOT the shared [AppStateMessage] — that
/// widget renders a centered icon-over-text column for page-level states,
/// while this rail-level row keeps its start-aligned title + inline button
/// shape (audit 121-a2: a different family).
class _RailMessage extends StatelessWidget {
  const _RailMessage({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onRetry,
  });
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          20,
          4,
          20,
          MediaRail.sectionSpacing(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(actionLabel),
              ),
            ),
          ],
        ),
      );
}
