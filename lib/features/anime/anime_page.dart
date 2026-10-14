import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/media_item.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';
import '../../shared/widgets/media_rail.dart';
import '../settings/integrations_page.dart';
import '../shell/noor_dock_tabs.dart';
import '../media/media_detail_page.dart';
import 'anime_search_sheet.dart';

class AnimePage extends StatefulWidget {
  const AnimePage({super.key});

  @override
  State<AnimePage> createState() => _AnimePageState();
}

class _AnimePageState extends State<AnimePage> {
  late Future<List<MediaItem>> _items;
  final Set<String> _resolving = {};

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
    final planning =
        app.linkedCatalogItems['anilist'] ?? const <MediaItem>[];
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
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 24, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            english ? 'Anime, your way' : 'الأنمي على طريقتك',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: english
                              ? 'Search anime on AniList'
                              : 'ابحث عن الأنمي في AniList',
                          onPressed: () => showAnimeSearchSheet(context),
                          icon: const Icon(Icons.search_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      english
                          ? 'Trending anime movies and series, powered by AniList.'
                          : 'أفلام ومسلسلات الأنمي الرائجة من AniList.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: HorseTheme.muted),
                    ),
                  ],
                ),
              ),
            ),
            // Personal AniList rails — rendered above the public catalogs
            // so the linked account's own lists lead the tab. `anilist:`
            // identities resolve through _open like every other card.
            if (anilistLinked && watching.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    bottom: MediaRail.sectionSpacing(context),
                  ),
                  child: MediaRail(
                    title: english
                        ? 'Watching · AniList'
                        : 'أتابعها الآن · AniList',
                    items: watching,
                    onTap: _open,
                  ),
                ),
              ),
            if (anilistLinked && planning.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    bottom: MediaRail.sectionSpacing(context),
                  ),
                  child: MediaRail(
                    title: english
                        ? 'Plan to watch · AniList'
                        : 'أخطط لمشاهدتها · AniList',
                    items: planning,
                    onTap: _open,
                  ),
                ),
              ),
            if (!anilistLinked)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 18),
                  child: _AniListLinkPrompt(),
                ),
              ),
            if (snapshot.connectionState == ConnectionState.waiting &&
                items.isEmpty)
              SliverToBoxAdapter(
                child: _CatalogState(
                  icon: Icons.auto_awesome_outlined,
                  message: english ? 'Loading anime…' : 'جارٍ تحميل الأنمي…',
                  loading: true,
                ),
              )
            else if (snapshot.hasError)
              SliverToBoxAdapter(
                child: _CatalogState(
                  icon: Icons.cloud_off_outlined,
                  message: english
                      ? 'Anime could not be loaded. Check your connection and try again.'
                      : 'تعذر تحميل الأنمي. تحقق من الاتصال ثم أعد المحاولة.',
                  actionLabel: english ? 'Retry' : 'إعادة المحاولة',
                  onRetry: _retry,
                ),
              )
            else if (items.isEmpty)
              SliverToBoxAdapter(
                child: _CatalogState(
                  icon: Icons.search_off_rounded,
                  message: english
                      ? 'No anime titles are available right now.'
                      : 'لا تتوفر عناوين أنمي حاليًا.',
                  actionLabel: english ? 'Refresh' : 'تحديث',
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
                    title: english ? 'Trending anime' : 'أنمي رائج',
                    items: items.take(14).toList(),
                    onTap: _open,
                  ),
                ),
              ),
              if (series.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(
                      bottom: MediaRail.sectionSpacing(context),
                    ),
                    child: MediaRail(
                      title: english ? 'Anime series' : 'مسلسلات الأنمي',
                      items: series,
                      onTap: _open,
                    ),
                  ),
                ),
              if (movies.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(
                      bottom: MediaRail.sectionSpacing(context),
                    ),
                    child: MediaRail(
                      title: english ? 'Anime movies' : 'أفلام الأنمي',
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
            content: Text(app.english
                ? 'A playable Stremio entry was not found for this title.'
                : 'لم يُعثر على عنوان قابل للتشغيل لهذا العمل.'),
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
    this.loading = false,
    this.actionLabel,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final bool loading;
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
              if (loading)
                const CircularProgressIndicator(
                  color: HorseTheme.gold,
                  strokeWidth: 2,
                )
              else
                Icon(icon, size: 36, color: HorseTheme.gold),
              const SizedBox(height: 14),
              Text(message, textAlign: TextAlign.center),
              if (onRetry != null && actionLabel != null) ...[
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
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
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
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
                  color: HorseTheme.gold.withValues(alpha: .14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 22,
                  color: HorseTheme.gold,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  english ? 'Link your AniList account' : 'اربط حساب AniList',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            english
                ? 'Your Watching and Plan-to-watch lists appear here right after linking.'
                : 'قوائم «أتابعها الآن» و«أخطط لمشاهدتها» من حسابك تظهر هنا بعد الربط مباشرةً.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: HorseTheme.muted),
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
              child: Text(english ? 'Link account' : 'ربط الحساب'),
            ),
          ),
        ],
      ),
    );
  }
}
