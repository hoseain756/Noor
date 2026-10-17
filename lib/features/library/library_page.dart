import 'package:nova_mobile/l10n/nova_strings.dart';
import 'package:nova_mobile/shared/widgets/nova_network_image.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/media_item.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';
import '../../core/torrent/torrent_models.dart';
import '../../core/torrent/torrent_service.dart';
import '../../shared/widgets/image_decode.dart';
import '../../shared/widgets/poster_card.dart';
import '../shell/noor_dock_tabs.dart';
import '../shell/nova_browse_widgets.dart';
import '../downloads/downloads_page.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../player/video_player_page.dart';
import '../torrent/magnet_opener.dart';
import 'custom_lists_page.dart';
import '../media/media_detail_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  int _tab = 0;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final librarySort = app.webSettings['librarySort']?.toString() ?? 'recent';
    final watchlist = app.watchlist
        .where((item) => item.name.toLowerCase().contains(_query))
        .toList()
      ..sort((a, b) => switch (librarySort) {
            'title' => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            'year' => (int.tryParse(b.releaseInfo ?? '') ?? 0)
                .compareTo(int.tryParse(a.releaseInfo ?? '') ?? 0),
            _ => 0,
          });
    final history = app.history
        .where((entry) => entry.item.name.toLowerCase().contains(_query))
        .toList()
      ..sort((a, b) => switch (librarySort) {
            'title' =>
              a.item.name.toLowerCase().compareTo(b.item.name.toLowerCase()),
            'year' => (int.tryParse(b.item.releaseInfo ?? '') ?? 0)
                .compareTo(int.tryParse(a.item.releaseInfo ?? '') ?? 0),
            _ => b.watchedAt.compareTo(a.watchedAt),
          });
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
          child: NovaBrowseHeader(
              eyebrow: app.tr('message636'),
              title: app.tr('message637'),
              subtitle: app.tr('message638'),
              actions: [
            FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const DownloadsPage())),
                icon: const Icon(LucideIcons.download),
                label: Text(app.tr('downloads'))),
            OutlinedButton.icon(
                onPressed: () => unawaited(openMagnetFlow(context)),
                icon: const Icon(LucideIcons.magnet),
                label: Text(app.tr('message639'))),
          ])),
      SliverToBoxAdapter(
          child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 24),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final entry in [
                  (
                    0,
                    app.tr('message640'),
                    watchlist.length,
                    LucideIcons.bookmark
                  ),
                  (
                    1,
                    app.tr('message641'),
                    history.length,
                    LucideIcons.history
                  ),
                  (
                    2,
                    app.tr('message642'),
                    app.customLists.length,
                    LucideIcons.library
                  ),
                ])
                  ChoiceChip(
                      avatar: Icon(entry.$4, size: 18),
                      label: Text('${entry.$2} · ${entry.$3}'),
                      selected: _tab == entry.$1,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      onSelected: (_) => setState(() {
                            _tab = entry.$1;
                          })),
              ]))),
      if (_tab != 2)
        SliverToBoxAdapter(
            child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 24),
                child: TextField(
                    onChanged: (value) =>
                        setState(() => _query = value.trim().toLowerCase()),
                    decoration: InputDecoration(
                        prefixIcon: const Icon(LucideIcons.search),
                        hintText: app.tr('message643'))))),
      if (_tab == 0) ...[
        if (watchlist.isEmpty)
          SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyLibrary(
                  icon: LucideIcons.bookmark,
                  title: _query.isEmpty
                      ? app.tr('message104')
                      : app.tr('message644'),
                  body: app.tr('message645')))
        else
          SliverPadding(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 24),
              sliver: SliverLayoutBuilder(builder: (context, constraints) {
                final columns =
                    (constraints.crossAxisExtent / 190).floor().clamp(2, 7);
                final width =
                    (constraints.crossAxisExtent - (columns - 1) * 20) /
                        columns;
                return SliverGrid.builder(
                    itemCount: watchlist.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisExtent: width / .72 +
                            78 * MediaQuery.textScalerOf(context).scale(1),
                        crossAxisSpacing: 20,
                        mainAxisSpacing: 24),
                    itemBuilder: (_, i) => _WatchlistCard(item: watchlist[i]));
              })),
      ] else if (_tab == 1) ...[
        if (history.isEmpty)
          SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyLibrary(
                  icon: LucideIcons.history,
                  title: app.tr('message646'),
                  body: app.tr('message647')))
        else
          SliverPadding(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 24),
              sliver: SliverList.separated(
                  itemCount: history.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (_, i) => _HistoryRow(entry: history[i]))),
      ] else
        const CustomListsPanel(),
      SliverToBoxAdapter(
          child: SizedBox(height: glassDockContentClearance(context))),
    ]);
  }
}

class _WatchlistCard extends StatelessWidget {
  const _WatchlistCard({required this.item});
  final MediaItem item;
  @override
  Widget build(BuildContext context) => Stack(
        alignment: AlignmentDirectional.topEnd,
        children: [
          PosterCard(
            item: item,
            width: double.infinity,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => MediaDetailPage(item: item)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(5),
            child: Material(
              color: NovaColors.ink.withValues(alpha: .68),
              shape: const CircleBorder(),
              child: IconButton(
                iconSize: 18,
                constraints:
                    const BoxConstraints.tightFor(width: 48, height: 48),
                tooltip: context.read<AppState>().tr('message648'),
                onPressed: () {
                  final app = context.read<AppState>();
                  app.toggleWatchlist(item);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(app.tr('message649')),
                      action: SnackBarAction(
                          label: app.tr('message618'),
                          onPressed: () => app.toggleWatchlist(item))));
                },
                icon: Icon(LucideIcons.bookmark,
                    color: NovaTheme.of(context).gold),
              ),
            ),
          ),
        ],
      );
}

/// Re-opens a torrent history entry straight from the engine: the files
/// kept on disk make this an instant resume (no metadata round-trip).
Future<void> _openTorrentHistoryEntry(
  BuildContext context,
  MediaItem item,
  dynamic entry,
) async {
  final app = context.read<AppState>();
  final english = app.english;
  final messenger = ScaffoldMessenger.of(context);
  final hash = item.id.substring('torrent:'.length).toLowerCase();
  if (hash.isEmpty) return;

  final navigator = Navigator.of(context, rootNavigator: true);
  var cancelled = false;
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: NovaTheme.of(context).surface,
      content: Row(
        children: [
          const SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              NovaStrings.lookup(english, 'message650'),
              style: Theme.of(dialogContext).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            cancelled = true;
            Navigator.of(dialogContext).pop();
          },
          child: Text(NovaStrings.lookup(english, 'cancel')),
        ),
      ],
    ),
  ));
  PreparedTorrent? prepared;
  try {
    prepared = await TorrentService.instance.prepare(
      infoHash: hash,
      magnet: TorrentService.magnetFor(hash, dn: item.name),
      displayName: item.name,
    );
    if (cancelled) {
      unawaited(prepared.stop());
      return;
    }
    final positionMs = (entry.positionMs as num?)?.toInt() ?? 0;
    if (!context.mounted) {
      unawaited(prepared.stop());
      return;
    }
    // Final local so the route-builder closure sees a promoted value.
    final torrent = prepared;
    navigator.pop();
    await navigator.push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => VideoPlayerPage(
          item: item,
          url: torrent.url,
          torrent: torrent,
          streamName: item.name,
          videoId: item.id,
          initialPositionMs: positionMs > 5000 ? positionMs : null,
        ),
      ),
    );
  } on TorrentException catch (error) {
    if (navigator.canPop()) navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          NovaStrings.lookup(english, 'message651', {'p0': error.message}),
        ),
      ),
    );
  } catch (_) {
    if (navigator.canPop()) navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          NovaStrings.lookup(english, 'message652'),
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});
  final dynamic entry;
  @override
  Widget build(BuildContext context) {
    final item = entry.item as MediaItem;
    final english = context.read<AppState>().english;
    final progress = entry.durationMs > 0
        ? (entry.positionMs / entry.durationMs).clamp(0.0, 1.0)
        : 0.0;
    final date = DateTime.fromMillisecondsSinceEpoch(entry.watchedAt as int);
    final isTorrent = item.id.startsWith('torrent:');
    return InkWell(
      onTap: isTorrent
          ? () => unawaited(_openTorrentHistoryEntry(context, item, entry))
          : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => MediaDetailPage(item: item)),
              ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 88,
                height: 124,
                child: isTorrent
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(
                            color: NovaTheme.of(context).raised,
                            child: Icon(
                              LucideIcons.film,
                              color: NovaTheme.of(context).gold,
                            ),
                          ),
                          PositionedDirectional(
                            start: 4,
                            top: 4,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: NovaColors.ink.withValues(alpha: .55),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Icon(
                                LucideIcons.zap,
                                color: NovaTheme.of(context).gold,
                                size: 13,
                              ),
                            ),
                          ),
                        ],
                      )
                    : item.poster == null
                        ? ColoredBox(
                            color: NovaTheme.of(context).raised,
                            child: Icon(
                              LucideIcons.film,
                              color: NovaTheme.of(context).gold,
                            ),
                          )
                        : NovaNetworkImage(
                            item.poster!,
                            fit: BoxFit.cover,
                            // Task 136: decode at the 54px history thumb.
                            cacheWidth: imageCacheWidth(context, 88),
                            errorBuilder: (_, __, ___) => ColoredBox(
                              color: NovaTheme.of(context).raised,
                              child: Icon(
                                LucideIcons.film,
                                color: NovaTheme.of(context).gold,
                              ),
                            ),
                          ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.type == 'series' ? (NovaStrings.lookup(english, 'message129')) : (NovaStrings.lookup(english, 'message128'))} · ${MaterialLocalizations.of(context).formatMediumDate(date)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (entry.durationMs > 0) ...[
                    const SizedBox(height: 9),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      backgroundColor: NovaTheme.of(context).line,
                      color: NovaTheme.of(context).gold,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? LucideIcons.chevronLeft
                    : LucideIcons.chevronRight,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: NovaTheme.of(context).surface,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: NovaTheme.of(context).gold, size: 27),
              ),
              const SizedBox(height: 15),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 5),
              Text(
                body,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
}
