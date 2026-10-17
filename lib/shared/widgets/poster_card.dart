import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:noor_mobile/shared/widgets/nova_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/media_item.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';
import 'image_decode.dart';
import 'media_quick_look.dart';

class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.item,
    required this.onTap,
    this.width = 122,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    // Task 122-b (F5): every card on every page used to `watch` AppState and
    // rebuild on ANY notification. Select the exact four settings this card
    // renders as a positional record (structural equality) — the rebuild now
    // fires only when one of them actually changes. Same values, same UI.
    final (radius, showTitle, showRating) =
        context.select<AppState, (double, bool, bool)>(
      (app) => (
        (app.webSettings['posterRadius'] as num?)?.toDouble() ?? 14,
        app.webSettings['hidePosterTitles'] != true,
        app.webSettings['showImdbBadge'] != false &&
            app.webSettings['showCardBadges'] != false,
      ),
    );
    final ratio = MediaQuery.sizeOf(context).width >= 700 ? 0.72 : 0.72;
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        label: item.name,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          // Long-press quick look: enlarged poster over a blurred page with
          // the watch / library / watched menu (shared for every card).
          onLongPress: () => showMediaQuickLook(
            context,
            item: item,
            onOpen: onTap,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: ratio,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (item.poster != null)
                        NovaNetworkImage(
                          item.poster!,
                          fit: BoxFit.cover,
                          // Task 136: decode at the card's on-screen size.
                          cacheWidth: imageCacheWidth(context, width),
                          errorBuilder: (_, __, ___) => const _PosterFallback(),
                        )
                      else
                        const _PosterFallback(),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          height: 42,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Colors.black54, Colors.transparent],
                            ),
                          ),
                        ),
                      ),
                      if (showRating && item.rating != null)
                        PositionedDirectional(
                          top: 8,
                          end: 8,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .72),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 4,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    LucideIcons.star,
                                    color: NovaTheme.of(context).gold,
                                    size: 12,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    item.rating!,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (showTitle) ...[
                const SizedBox(height: 8),
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                ),
              ],
              if (showTitle && item.releaseInfo != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    item.releaseInfo!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
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
        color: NovaTheme.of(context).raised,
        child: Center(
          child: Icon(LucideIcons.film,
              size: 34, color: NovaTheme.of(context).gold),
        ),
      );
}
