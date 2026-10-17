import 'package:nova_mobile/shared/widgets/nova_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/models/media_item.dart';
import '../../shared/widgets/image_decode.dart';
import '../../shared/widgets/media_quick_look.dart';

/// NOVA's editorial ranking: clear numbered captions, consistent posters,
/// and real title names instead of overlapping, decorative numeral artwork.
class Top10Rail extends StatelessWidget {
  const Top10Rail(
      {super.key,
      required this.title,
      required this.items,
      required this.onTap});
  final String title;
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onTap;
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final gutter = MediaQuery.sizeOf(context).width >= 700 ? 40.0 : 24.0;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: EdgeInsetsDirectional.symmetric(horizontal: gutter),
          child: Row(children: [
            Icon(LucideIcons.trendingUp,
                color: Theme.of(context).colorScheme.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
                child:
                    Text(title, style: Theme.of(context).textTheme.titleLarge))
          ])),
      const SizedBox(height: 20),
      SizedBox(
          height: Top10Item.itemHeight + (scale - 1) * 44,
          child: ListView.separated(
              padding: EdgeInsetsDirectional.symmetric(horizontal: gutter),
              scrollDirection: Axis.horizontal,
              itemCount: items.length.clamp(0, 10),
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, index) => Top10Item(
                  rank: index + 1,
                  item: items[index],
                  onTap: () => onTap(items[index])))),
    ]);
  }
}

class Top10Item extends StatelessWidget {
  const Top10Item(
      {super.key, required this.rank, required this.item, required this.onTap});
  final int rank;
  final MediaItem item;
  final VoidCallback onTap;
  static const double itemHeight = 288;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
        width: 144,
        child: InkWell(
            onTap: onTap,
            onLongPress: () =>
                showMediaQuickLook(context, item: item, onOpen: onTap),
            borderRadius: BorderRadius.circular(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                      width: 144,
                      height: 216,
                      child: ColoredBox(
                          color: scheme.surfaceContainerHighest,
                          child: item.poster?.isNotEmpty == true
                              ? NovaNetworkImage(item.poster!,
                                  fit: BoxFit.cover,
                                  cacheWidth: imageCacheWidth(context, 144),
                                  semanticLabel: item.name,
                                  errorBuilder: (_, __, ___) => Icon(
                                      LucideIcons.film,
                                      color: scheme.onSurfaceVariant))
                              : Icon(LucideIcons.film,
                                  color: scheme.onSurfaceVariant)))),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(rank.toString().padLeft(2, '0'),
                    textDirection: TextDirection.ltr,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: scheme.primary, fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall)),
              ]),
            ])));
  }
}

/// Compatibility for downstream consumers of the earlier ranking presenter.
class OutlinedRankNumber extends StatelessWidget {
  const OutlinedRankNumber(
      {super.key, required this.rank, required this.fontSize});
  final int rank;
  final double fontSize;
  static const String rankFontFamily = 'Tajawal';
  @override
  Widget build(BuildContext context) => Text('$rank',
      textDirection: TextDirection.ltr,
      style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          color: Theme.of(context).colorScheme.primary));
}
