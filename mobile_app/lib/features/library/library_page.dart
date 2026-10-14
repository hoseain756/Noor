import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/media_item.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';
import '../../shared/widgets/poster_card.dart';
import '../../shared/widgets/glass_navigation.dart';
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

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final english = app.english;
    final width = MediaQuery.sizeOf(context).width;
    final maxCardWidth = width >= 800 ? 184.0 : 160.0;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final posterExtent = maxCardWidth / .72;
    final showPosterTitles = app.webSettings['hidePosterTitles'] != true;
    final cardTextHeight =
        showPosterTitles ? 8 + 36 * textScale + 3 + 14 * textScale + 12 : 0.0;
    final cardExtent = showPosterTitles
        ? math.max(296.0, posterExtent + cardTextHeight)
        : posterExtent;
    final librarySort = app.webSettings['librarySort']?.toString() ?? 'recent';
    final watchlist = [...app.watchlist]..sort((a, b) => switch (librarySort) {
          'title' => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          'year' => (int.tryParse(b.releaseInfo ?? '') ?? 0)
              .compareTo(int.tryParse(a.releaseInfo ?? '') ?? 0),
          _ => 0,
        });
    final history = [...app.history]..sort((a, b) => switch (librarySort) {
          'title' =>
            a.item.name.toLowerCase().compareTo(b.item.name.toLowerCase()),
          'year' => (int.tryParse(b.item.releaseInfo ?? '') ?? 0)
              .compareTo(int.tryParse(a.item.releaseInfo ?? '') ?? 0),
          _ => b.watchedAt.compareTo(a.watchedAt),
        });
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            english ? 'My library' : 'مكتبتي',
                            style:
                                Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            english
                                ? 'Keep your watchlist, collections and recent plays together.'
                                : 'اجمع قوائمك وآخر ما شغّلته في مكان واحد.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: HorseTheme.muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _OpenTorrentButton(english: english),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: HorseTheme.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      _LibraryTab(
                        label: english ? 'Watchlist' : 'قائمتي',
                        count: watchlist.length,
                        selected: _tab == 0,
                        onTap: () => setState(() => _tab = 0),
                      ),
                      _LibraryTab(
                        label: english ? 'History' : 'المشاهدة',
                        count: history.length,
                        selected: _tab == 1,
                        onTap: () => setState(() => _tab = 1),
                      ),
                      _LibraryTab(
                        label: english ? 'Lists' : 'قوائم',
                        count: app.customLists.length,
                        selected: _tab == 2,
                        onTap: () => setState(() => _tab = 2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_tab == 0) ...[
          if (watchlist.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyLibrary(
                icon: Icons.bookmark_border_rounded,
                title: english ? 'Nothing saved yet' : 'لم تحفظ أي عنوان بعد',
                body: english
                    ? 'Open a title and tap “My list” to keep it here.'
                    : 'افتح أي عنوان واضغط «قائمتي» لحفظه هنا.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 30),
              sliver: SliverGrid.builder(
                itemCount: watchlist.length,
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: maxCardWidth,
                  mainAxisExtent: cardExtent,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 16,
                ),
                itemBuilder: (context, index) =>
                    _WatchlistCard(item: watchlist[index]),
              ),
            ),
        ] else if (_tab == 1) ...[
          if (history.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyLibrary(
                icon: Icons.history_rounded,
                title: english ? 'No recent plays' : 'لا يوجد سجل مشاهدة',
                body: english
                    ? 'Titles you play will appear here.'
                    : 'ستظهر هنا العناوين التي تشغّلها.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 30),
              sliver: SliverList.separated(
                itemCount: history.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: HorseTheme.line),
                itemBuilder: (context, index) =>
                    _HistoryRow(entry: history[index]),
              ),
            ),
        ] else ...[
          const SliverToBoxAdapter(child: CustomListsPanel()),
        ],
        SliverToBoxAdapter(
          child: SizedBox(
            height: MediaQuery.paddingOf(context).bottom +
                GlassNavigationBar.contentBottomInset,
          ),
        ),
      ],
    );
  }
}

class _LibraryTab extends StatelessWidget {
  const _LibraryTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 500 ||
        MediaQuery.textScalerOf(context).scale(14) / 14 >= 1.5;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF28231B) : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: compact
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: TextStyle(
                        color: selected ? HorseTheme.gold : HorseTheme.muted,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11,
                        color: selected ? HorseTheme.gold : HorseTheme.muted,
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: selected ? HorseTheme.gold : HorseTheme.muted,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11,
                        color: selected ? HorseTheme.gold : HorseTheme.muted,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
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
              color: Colors.black.withValues(alpha: .68),
              shape: const CircleBorder(),
              child: IconButton(
                iconSize: 18,
                constraints:
                    const BoxConstraints.tightFor(width: 38, height: 38),
                onPressed: () => context.read<AppState>().toggleWatchlist(item),
                icon:
                    const Icon(Icons.bookmark_rounded, color: HorseTheme.gold),
              ),
            ),
          ),
        ],
      );
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
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => MediaDetailPage(item: item)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 54,
                height: 76,
                child: item.poster == null
                    ? const ColoredBox(
                        color: HorseTheme.raised,
                        child: Icon(
                          Icons.movie_outlined,
                          color: HorseTheme.gold,
                        ),
                      )
                    : Image.network(
                        item.poster!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const ColoredBox(
                          color: HorseTheme.raised,
                          child: Icon(
                            Icons.movie_outlined,
                            color: HorseTheme.gold,
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
                    '${item.type == 'series' ? (english ? 'Series' : 'مسلسل') : (english ? 'Movie' : 'فيلم')} · ${MaterialLocalizations.of(context).formatMediumDate(date)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (entry.durationMs > 0) ...[
                    const SizedBox(height: 9),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      backgroundColor: HorseTheme.line,
                      color: HorseTheme.gold,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_left_rounded, color: HorseTheme.muted),
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
                  color: HorseTheme.surface,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: HorseTheme.gold, size: 27),
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

/// Gold-tinted entry pill that opens the paste-a-magnet torrent flow.
class _OpenTorrentButton extends StatelessWidget {
  const _OpenTorrentButton({required this.english});

  final bool english;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HorseTheme.gold.withValues(alpha: .14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: HorseTheme.gold.withValues(alpha: .45)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () => unawaited(openMagnetFlow(context)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bolt_rounded,
                  color: HorseTheme.gold, size: 18),
              const SizedBox(width: 7),
              Text(
                english ? 'Torrent' : 'تورنت',
                style: const TextStyle(
                  color: HorseTheme.gold,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
