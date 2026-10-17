import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../core/models/media_item.dart';
import '../../core/state/app_state.dart';
import '../../features/anime/anime_tracker_sheet.dart';
import 'nova_network_image.dart';
import 'image_decode.dart';
import 'noor_toast.dart';

/// Compact action sheet; no full-screen blur or oversized poster animation.
Future<void> showMediaQuickLook(BuildContext context,
    {required MediaItem item, required VoidCallback onOpen}) async {
  HapticFeedback.selectionClick();
  final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => _QuickLook(item: item));
  if (!context.mounted) return;
  if (action == 'watch') onOpen();
  if (action == 'track') await showAnimeTrackerSheet(context, item);
}

class _QuickLook extends StatelessWidget {
  const _QuickLook({required this.item});
  final MediaItem item;
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final inLibrary = app.contains(item);
    final watched = app.history.any((entry) => entry.item.id == item.id);
    final canTrack = item.hasAnimeIds &&
        (app.linkedServices['anilist']?['linked'] == true ||
            app.linkedServices['mal']?['linked'] == true);
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 24),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                          width: 96,
                          height: 144,
                          child: item.poster == null
                              ? ColoredBox(
                                  color: scheme.surfaceContainerHigh,
                                  child: const Icon(LucideIcons.film))
                              : NovaNetworkImage(item.poster!,
                                  fit: BoxFit.cover,
                                  cacheWidth: imageCacheWidth(context, 96)))),
                  const SizedBox(width: 20),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(item.name,
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        if (item.releaseInfo != null)
                          Text(item.releaseInfo!,
                              style: Theme.of(context).textTheme.bodySmall),
                        if (item.description?.isNotEmpty == true) ...[
                          const SizedBox(height: 12),
                          Text(item.description!,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant))
                        ],
                      ])),
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      tooltip: app.tr('close'),
                      icon: const Icon(LucideIcons.x)),
                ]),
                const SizedBox(height: 24),
                FilledButton.icon(
                    onPressed: () => Navigator.pop(context, 'watch'),
                    icon: const Icon(LucideIcons.play),
                    label: Text(app.tr('message95'))),
                const SizedBox(height: 16),
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(inLibrary
                        ? LucideIcons.bookmarkCheck
                        : LucideIcons.bookmarkPlus),
                    title: Text(
                        inLibrary ? app.tr('message96') : app.tr('message97')),
                    onTap: () async {
                      await app.toggleWatchlist(item);
                      if (context.mounted) {
                        NoorToast.show(
                            context,
                            inLibrary
                                ? app.tr('message91')
                                : app.tr('message92'));
                        Navigator.pop(context);
                      }
                    }),
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                        watched ? LucideIcons.circleCheck : LucideIcons.eye),
                    title: Text(
                        watched ? app.tr('message98') : app.tr('message99')),
                    onTap: watched
                        ? null
                        : () async {
                            await app.recordPlayback(item,
                                positionMs: 1, durationMs: 0);
                            if (context.mounted) {
                              NoorToast.show(context, app.tr('message94'));
                              Navigator.pop(context);
                            }
                          }),
                if (canTrack)
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(LucideIcons.listChecks),
                      title: Text(app.tr('message100')),
                      onTap: () => Navigator.pop(context, 'track')),
              ]),
        ));
  }
}
