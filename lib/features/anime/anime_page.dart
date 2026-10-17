import 'package:nova_mobile/l10n/nova_strings.dart';
import '../shell/nova_catalog_refresh.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/media_item.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';
import '../../shared/widgets/media_rail.dart';
import '../settings/integrations_page.dart';
import '../shell/nova_browse_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../shell/noor_dock_tabs.dart';
import '../media/media_detail_page.dart';
import 'anime_search_sheet.dart';

class AnimePage extends StatefulWidget {
  const AnimePage({super.key});

  @override
  State<AnimePage> createState() => _AnimePageState();
}

class _AnimePageState extends State<AnimePage>
    with NovaCatalogRefresh<AnimePage> {
  @override
  void refreshCachedCatalogs() => _retry();

  late Future<List<MediaItem>> _items;
  final Set<String> _resolving = {};
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _items = context.read<AppState>().catalogs.anime();
  }

  void _retry() {
    setState(() => _items = context.read<AppState>().catalogs.anime());
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final english = app.english;
    // Personal lists from the LINKED AniList account — CURRENT becomes the
    // "watching" rail, PLANNING the "plan to watch" rail (the same rows the
    // home page uses, scoped here so the tab is self-sufficient).
    final watching =
        app.linkedCatalogItems['anilist-watching'] ?? const <MediaItem>[];
    final planning = app.linkedCatalogItems['anilist'] ?? const <MediaItem>[];
    final anilistLinked = app.linkedServices['anilist']?['linked'] == true;
    return FutureBuilder<List<MediaItem>>(
      future: _items,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <MediaItem>[];
        final series = items.where((item) => item.type == 'series').toList();
        final movies = items.where((item) => item.type == 'movie').toList();
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
                child: NovaBrowseHeader(
              eyebrow: app.tr('message521'),
              title: app.tr('message522'),
              subtitle: app.tr('message523'),
              actions: [
                FilledButton.tonalIcon(
                    onPressed: () => showAnimeSearchSheet(context),
                    icon: const Icon(LucideIcons.search),
                    label: Text(app.tr('message524')))
              ],
            )),
            SliverToBoxAdapter(
                child: Padding(
                    padding:
                        const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 24),
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final entry in [
                        ('all', app.tr('message525')),
                        ('series', app.tr('message107')),
                        ('movie', app.tr('message526')),
                      ])
                        ChoiceChip(
                            label: Text(entry.$2),
                            selected: _filter == entry.$1,
                            onSelected: (_) =>
                                setState(() => _filter = entry.$1))
                    ]))),
            if (items.isNotEmpty)
              SliverToBoxAdapter(
                  child: NovaBrowseFeature(
                item: (_filter == 'series' && series.isNotEmpty)
                    ? series.first
                    : (_filter == 'movie' && movies.isNotEmpty)
                        ? movies.first
                        : items.first,
                label: app.tr('message130'),
                actionLabel: app.tr('message527'),
                onOpen: () => _open((_filter == 'series' && series.isNotEmpty)
                    ? series.first
                    : (_filter == 'movie' && movies.isNotEmpty)
                        ? movies.first
                        : items.first),
              )),
            // Personal AniList rails — rendered above the public catalogs
            // so the linked account's own lists lead the tab. `anilist:`
            // identities resolve through _open like every other card.
            if (_filter == 'all' && anilistLinked && watching.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    bottom: MediaRail.sectionSpacing(context),
                  ),
                  child: MediaRail(
                    title: NovaStrings.lookup(english, 'message528'),
                    items: watching,
                    onTap: _open,
                  ),
                ),
              ),
            if (_filter == 'all' && anilistLinked && planning.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    bottom: MediaRail.sectionSpacing(context),
                  ),
                  child: MediaRail(
                    title: NovaStrings.lookup(english, 'message529'),
                    items: planning,
                    onTap: _open,
                  ),
                ),
              ),
            if (_filter == 'all' && !anilistLinked)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 18),
                  child: _AniListLinkPrompt(),
                ),
              ),
            if (snapshot.connectionState == ConnectionState.waiting &&
                items.isEmpty)
              const SliverToBoxAdapter(
                  child: SizedBox(height: 440, child: NovaBrowseSkeleton()))
            else if (snapshot.hasError)
              SliverToBoxAdapter(
                child: _CatalogState(
                  icon: LucideIcons.cloudOff,
                  message: NovaStrings.lookup(english, 'message530'),
                  actionLabel: NovaStrings.lookup(english, 'message120'),
                  onRetry: _retry,
                ),
              )
            else if (items.isEmpty)
              SliverToBoxAdapter(
                child: _CatalogState(
                  icon: LucideIcons.searchX,
                  message: NovaStrings.lookup(english, 'message531'),
                  actionLabel: NovaStrings.lookup(english, 'message68'),
                  onRetry: _retry,
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    bottom: MediaRail.sectionSpacing(context),
                  ),
                  child: MediaRail(
                    title: NovaStrings.lookup(english, 'message113'),
                    items: items
                        .where(
                            (item) => _filter == 'all' || item.type == _filter)
                        .take(14)
                        .toList(),
                    onTap: _open,
                  ),
                ),
              ),
              if (_filter != 'movie' && series.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(
                      bottom: MediaRail.sectionSpacing(context),
                    ),
                    child: MediaRail(
                      title: NovaStrings.lookup(english, 'message532'),
                      items: series,
                      onTap: _open,
                    ),
                  ),
                ),
              if (_filter != 'series' && movies.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(
                      bottom: MediaRail.sectionSpacing(context),
                    ),
                    child: MediaRail(
                      title: NovaStrings.lookup(english, 'message114'),
                      items: movies,
                      onTap: _open,
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: glassDockContentClearance(context),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _open(MediaItem item) async {
    if (!_resolving.add(item.id)) return;
    setState(() {});
    try {
      final app = context.read<AppState>();
      final resolved = item.id.startsWith('anilist:')
          ? await app.catalogs.resolveAnime(item)
          : item;
      if (!mounted) return;
      if (resolved == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(NovaStrings.lookup(app.english, 'message117')),
          ),
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          // Carry the AniList/MAL identity onto the playable item so
          // library toggles and playback mirror to the linked trackers.
          builder: (_) => MediaDetailPage(
            item: resolved.withAnimeIds(
              anilistId: item.anilistId,
              idMal: item.idMal,
            ),
          ),
        ),
      );
    } finally {
      _resolving.remove(item.id);
      if (mounted) setState(() {});
    }
  }
}

class _CatalogState extends StatelessWidget {
  const _CatalogState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          // Compact (not viewport-filling): the tab now always carries a
          // personal section above (rails or the link prompt), so a full-
          // screen state would push the public rails out of reach.
          padding: const EdgeInsetsDirectional.fromSTEB(28, 8, 28, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 36, color: NovaTheme.of(context).gold),
              const SizedBox(height: 14),
              Text(message, textAlign: TextAlign.center),
              if (onRetry != null && actionLabel != null) ...[
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(LucideIcons.refreshCw),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      );
}

/// Invitation shown on the Anime tab while no AniList account is linked:
/// one tap jumps straight into the integrations page — after linking, the
/// card is replaced by the personal watching/planning rails above.
class _AniListLinkPrompt extends StatelessWidget {
  const _AniListLinkPrompt();

  @override
  Widget build(BuildContext context) {
    final english = context.watch<AppState>().english;
    return Container(
      padding: const EdgeInsetsDirectional.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: .55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NovaColors.white.withValues(alpha: .08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: NovaTheme.of(context).gold.withValues(alpha: .14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.sparkles,
                  size: 22,
                  color: NovaTheme.of(context).gold,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  NovaStrings.lookup(english, 'message533'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            NovaStrings.lookup(english, 'message534'),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: NovaTheme.of(context).muted),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.tonal(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const IntegrationsPage(),
                ),
              ),
              child: Text(NovaStrings.lookup(english, 'message535')),
            ),
          ),
        ],
      ),
    );
  }
}
