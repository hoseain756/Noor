import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/catalog_repository.dart';
import '../../core/models/media_item.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';
import '../../core/data/content_classifier.dart';
import '../../shared/widgets/media_rail.dart';
import '../../shared/widgets/noor_toast.dart';
import '../shell/noor_dock_tabs.dart';
import 'widgets/async_media_section.dart';
import 'widgets/continue_watching_rail.dart';
import 'widgets/featured_hero.dart';
import '../anime/anime_page.dart';
import '../catalog/catalog_browser_page.dart';
import '../catalog/catalog_grid_page.dart';
import '../media/media_detail_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.active = true});

  final bool active;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Future<List<MediaItem>>? _featuredSlides;
  Future<List<MediaItem>>? _topTen;
  Future<List<MediaItem>>? _movies;
  Future<List<MediaItem>>? _series;
  Future<List<MediaItem>>? _theaters;
  Future<List<MediaItem>>? _anime;
  Future<List<MediaItem>>? _animeMovies;
  Future<List<MediaItem>>? _newEpisodes;
  Future<List<MediaItem>>? _recommendations;

  /// Per-catalog home rows (web AddonRail parity): every eligible add-on
  /// catalog gets its own rail with its own future, deduped against the
  /// anchor rows above.
  List<AddonCatalogRow> _catalogRows = const [];
  final Map<String, Future<List<MediaItem>>> _catalogRowFutures = {};
  String? _addonSignature;
  // AniList/MAL taps resolve to a playable Stremio identity before opening.
  final Set<String> _resolving = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.watch<AppState>();
    final signature = [
      app.addons.map((e) => '${e.id}:${e.enabled}').join('|'),
      app.history
          .map((entry) => '${entry.item.id}:${entry.watchedAt}')
          .join(','),
      app.webSettings['homeShowAllAddonRows'],
      app.webSettings['hideWatchedInCatalogs'],
      app.webSettings['hideContent'],
      app.webSettings['tmdbEnabled'],
      app.webSettings['tmdbLanguage'],
      app.webSettings['region'],
      app.linkedServicesSignature,
    ].join('|');
    if (_topTen == null || signature != _addonSignature) {
      _addonSignature = signature;
      _load(app);
    }
    // Linked-service cards + rails refresh on a short TTL; a link/unlink
    // change forces an immediate refresh from inside AppState.
    unawaited(app.refreshLinkedContent());
  }

  void _load(AppState app) {
    // Keep each source independent: a slow or failed add-on must not hold the
    // featured hero or Top 10 row behind one shared Future.wait.
    _topTen =
        app.catalogs.homeTopTen().then((items) => _visibleItems(app, items));
    _movies = app.catalogs
        .catalog('movie', 'trailer')
        .then((items) => _visibleItems(app, items));
    _series = app.catalogs
        .catalog('series', 'trailer')
        .then((items) => _visibleItems(app, items));
    _theaters = app.catalogs
        .catalog('movie', 'top')
        .then((items) => _visibleItems(app, items));
    _anime = app.catalogs.anime().then((items) => _visibleItems(app, items));
    _animeMovies = _anime!.then(
      (items) =>
          items.where((item) => item.type == 'movie').toList(growable: false),
    );
    _newEpisodes = app.catalogs
        .catalog('series', 'last-videos')
        .then((items) => _visibleItems(app, items));
    // Per-catalog rows (web AddonRail parity): eligible add-on catalogs each
    // get their own rail; the "show all" setting lifts the row cap.
    final showAllRows = app.webSettings['homeShowAllAddonRows'] == true;
    _catalogRows = CatalogRepository.selectAddonCatalogRows(
      app.addons,
      anchorKeys: const {
        'movie:trailer',
        'series:trailer',
        'movie:top',
        'series:last-videos',
      },
      limit: showAllRows ? 30 : 8,
    );
    _catalogRowFutures
      ..clear()
      ..addEntries(
        _catalogRows.map(
          (row) => MapEntry(
            row.key,
            app.catalogs
                .catalog(row.catalog.type, row.catalog.id, addon: row.addon)
                .then((items) => _visibleItems(app, items)),
          ),
        ),
      );
    _featuredSlides = Future.wait<List<MediaItem>>([
      _movies!.catchError((Object _) => <MediaItem>[]),
      _theaters!.catchError((Object _) => <MediaItem>[]),
      _series!.catchError((Object _) => <MediaItem>[]),
    ]).then((rows) {
      final slides = <MediaItem>[];
      for (final row in rows) {
        slides.addAll(row.take(3));
      }
      return slides.take(8).toList(growable: false);
    });
    final language = app.webSettings['tmdbLanguage']?.toString() ?? 'en-US';
    final region = app.webSettings['region']?.toString() ?? 'US';
    if (app.webSettings['tmdbEnabled'] == false) {
      _recommendations = Future.value(const <MediaItem>[]);
    } else {
      final recentHistory = [...app.history]
        ..sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
      final seed = app.continueWatching.firstOrNull?.item ??
          recentHistory.firstOrNull?.item;
      _recommendations = seed != null
          ? app.catalogs.tmdbRecommendations(
              seed,
              language: language,
              region: region,
            )
          : _topTen!.then((items) => items.isEmpty
              ? const <MediaItem>[]
              : app.catalogs.tmdbRecommendations(
                  items.first,
                  language: language,
                  region: region,
                ));
    }
  }

  List<MediaItem> _visibleItems(AppState app, List<MediaItem> items) {
    final hidden = app.webSettings['hideContent'] as Map? ?? const {};
    final watched = app.webSettings['hideWatchedInCatalogs'] == true
        ? app.history
            .where((entry) =>
                entry.durationMs > 0 &&
                entry.positionMs >= entry.durationMs - 120000)
            .map((entry) => entry.item.id)
            .toSet()
        : <String>{};
    const adultRatings = {'r', 'nc-17', 'tv-ma', '18', '18+', 'x', 'ao'};
    return items.where((item) {
      if (watched.contains(item.id)) return false;
      if (hidden['anime'] == true && ContentClassifier.isAnime(item)) {
        return false;
      }
      if (hidden['adult'] == true &&
          adultRatings.contains(item.certification?.trim().toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final english = app.english;
    final classicHome = app.webSettings['homeMode'] == 'classic';
    // EDGE-TO-EDGE (Task 119): the shell no longer SafeArea-pads this page,
    // so the featured hero bleeds behind the transparent status bar. This
    // inset is added ONLY where real content must stay clear of the status
    // icons (classic header / service message) — the hero itself handles
    // icon readability with its top scrim.
    final safeTop = MediaQuery.paddingOf(context).top;
    return CustomScrollView(
      slivers: [
        if (classicHome)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(20, 22 + safeTop, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    english
                        ? 'Your next story starts here'
                        : 'حكايتك التالية تبدأ هنا',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    english
                        ? 'Discover something worth watching.'
                        : 'اكتشف شيئًا يستحق المشاهدة.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: HorseTheme.muted),
                  ),
                ],
              ),
            ),
          ),
        if (!classicHome)
          SliverToBoxAdapter(
            child: FutureBuilder<List<MediaItem>>(
              future: _featuredSlides,
              builder: (context, snapshot) {
                final featured = snapshot.data;
                if (featured != null && featured.isNotEmpty) {
                  return FeaturedHero(
                    items: featured.take(8).toList(growable: false),
                    autoplayActive: widget.active,
                    onTap: _open,
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const FeaturedSkeleton();
                }
                return Padding(
                  padding:
                      EdgeInsetsDirectional.fromSTEB(20, 28 + safeTop, 20, 0),
                  child: _ServiceMessage(
                    english: english,
                    onRetry: () => setState(() => _load(app)),
                  ),
                );
              },
            ),
          ),
        if (app.continueWatching.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                bottom: MediaRail.sectionSpacing(context),
              ),
              child: ContinueWatchingRail(
                entries: app.continueWatching,
                english: english,
              ),
            ),
          ),
        // Continue watching sourced from the LINKED tracking services
        // (Trakt paused playback + AniList/MAL currently-watching) — same
        // Harbor-web card spec, rendered right after the local row.
        if (app.linkedContinueWatching.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                bottom: MediaRail.sectionSpacing(context),
              ),
              child: LinkedContinueRail(
                entries: app.linkedContinueWatching,
                english: english,
                onOpen: _open,
              ),
            ),
          )
        else if (app.linkedServices.isNotEmpty && app.linkedContentLoading)
          // First fetch in flight (rows arrive after the link completes) —
          // geometry-matched placeholder instead of a silent pop-in.
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                bottom: MediaRail.sectionSpacing(context),
              ),
              child: LinkedContinueSkeleton(english: english),
            ),
          ),
        SliverToBoxAdapter(
          child: AsyncMediaSection(
            title: english ? 'Recommended for you' : 'مقترح لك',
            future: _recommendations!,
            onTap: _open,
            onRetry: () => setState(() => _load(app)),
            english: english,
          ),
        ),
        SliverToBoxAdapter(
          child: AsyncMediaSection(
            title: english ? 'Top 10 Today' : 'أفضل 10 اليوم',
            future: _topTen!,
            numbered: true,
            onTap: _open,
            onRetry: () => setState(
              () => _topTen = app.catalogs.homeTopTen().then(
                    (items) => _visibleItems(app, items),
                  ),
            ),
            english: english,
            showEmptyState: true,
          ),
        ),
        SliverToBoxAdapter(
          child: AsyncMediaSection(
            title: english ? 'Trending series' : 'مسلسلات رائجة',
            future: _series!,
            onTap: _open,
            onOpenSection: () => _openSection(
              const CatalogBrowserPage(mode: CatalogBrowseMode.shows),
            ),
            onRetry: () => setState(
              () => _series = app.catalogs
                  .catalog('series', 'trailer')
                  .then((items) => _visibleItems(app, items)),
            ),
            english: english,
          ),
        ),
        SliverToBoxAdapter(
          child: AsyncMediaSection(
            title: english ? 'Trending movies' : 'أفلام رائجة',
            future: _movies!,
            onTap: _open,
            onOpenSection: () => _openSection(
              const CatalogBrowserPage(mode: CatalogBrowseMode.movies),
            ),
            onRetry: () => setState(
              () => _movies = app.catalogs
                  .catalog('movie', 'trailer')
                  .then((items) => _visibleItems(app, items)),
            ),
            english: english,
          ),
        ),
        SliverToBoxAdapter(
          child: AsyncMediaSection(
            title: english ? 'Trending anime' : 'أنمي رائج',
            future: _anime!,
            onTap: _open,
            onOpenSection: () => _openSection(const AnimePage()),
            onRetry: () => setState(() => _reloadAnime()),
            english: english,
          ),
        ),
        SliverToBoxAdapter(
          child: AsyncMediaSection(
            title: english ? 'Anime movies' : 'أفلام الأنمي',
            future: _animeMovies!,
            onTap: _open,
            onOpenSection: () => _openSection(const AnimePage()),
            onRetry: () => setState(() => _reloadAnime()),
            english: english,
          ),
        ),
        // One rail per eligible add-on catalog (web AddonRail parity) —
        // rows that fail or stay empty simply don't render.
        for (final row in _catalogRows)
          SliverToBoxAdapter(
            child: AsyncMediaSection(
              title: row.title,
              subtitle: row.subtitle,
              future: _catalogRowFutures[row.key] ??
                  Future<List<MediaItem>>.value(const <MediaItem>[]),
              onTap: _open,
              onRetry: () => setState(() => _load(app)),
              onOpenSection: () => _openSection(
                CatalogGridPage(
                  title: row.title,
                  subtitle: row.subtitle,
                  onOpen: _open,
                  loader: () => context.read<AppState>().catalogs.catalog(
                        row.catalog.type,
                        row.catalog.id,
                        addon: row.addon,
                      ),
                ),
              ),
              english: english,
            ),
          ),
        SliverToBoxAdapter(
          child: AsyncMediaSection(
            title: english ? 'New episodes' : 'حلقات جديدة',
            future: _newEpisodes!,
            onTap: _open,
            onOpenSection: () => _openSection(
              const CatalogBrowserPage(mode: CatalogBrowseMode.shows),
            ),
            onRetry: () => setState(
              () => _newEpisodes = app.catalogs
                  .catalog('series', 'last-videos')
                  .then((items) => _visibleItems(app, items)),
            ),
            english: english,
          ),
        ),
        SliverToBoxAdapter(
          child: AsyncMediaSection(
            title: english ? 'In theaters' : 'في السينما',
            future: _theaters!,
            onTap: _open,
            onOpenSection: () => _openSection(
              const CatalogBrowserPage(mode: CatalogBrowseMode.movies),
            ),
            onRetry: () => setState(
              () => _theaters = app.catalogs
                  .catalog('movie', 'top')
                  .then((items) => _visibleItems(app, items)),
            ),
            english: english,
          ),
        ),
        // Watchlist rails from the linked services — Trakt / Simkl
        // watchlists and the AniList / MyAnimeList plan-to-watch lists.
        for (final rail in _linkedRails(app, english))
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                bottom: MediaRail.sectionSpacing(context),
              ),
              child: MediaRail(
                title: rail.$1,
                items: rail.$2,
                onTap: _open,
                onOpenSection: () => _openSection(
                  CatalogGridPage(
                    title: rail.$1,
                    items: rail.$2,
                    onOpen: _open,
                  ),
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: glassDockContentClearance(context),
          ),
        ),
      ],
    );
  }

  void _open(MediaItem item) {
    final needsResolve =
        item.id.startsWith('anilist:') || item.id.startsWith('mal:');
    if (!needsResolve) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => MediaDetailPage(item: item)),
      );
      return;
    }
    // Tracker records resolve to their playable Stremio identity first,
    // mirroring the anime page behavior.
    unawaited(_openAnime(item));
  }

  Future<void> _openAnime(MediaItem item) async {
    if (!_resolving.add(item.id)) return;
    setState(() {});
    try {
      final resolved =
          await context.read<AppState>().catalogs.resolveAnime(item);
      if (!mounted) return;
      if (resolved == null) {
        final english = context.read<AppState>().english;
        NoorToast.show(
          context,
          english
              ? 'A playable Stremio entry was not found for this title.'
              : 'لم يُعثر على عنوان قابل للتشغيل لهذا العمل.',
          error: true,
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          // Carry the AniList/MAL identity onto the playable item so
          // library toggles and playback mirror to the linked trackers
          // (mirrors anime_page.dart).
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

  void _reloadAnime() {
    final app = context.read<AppState>();
    _anime = app.catalogs.anime().then((items) => _visibleItems(app, items));
    _animeMovies = _anime!.then(
      (items) =>
          items.where((item) => item.type == 'movie').toList(growable: false),
    );
  }

  /// Linked-service catalog rails: one watchlist rail per linked service
  /// (Trakt/Simkl watchlists, AniList/MAL plan-to-watch) as `(title, items)`.
  /// Hidden entirely when anime content is hidden — the tracker rails are
  /// anime-only by definition.
  List<(String, List<MediaItem>)> _linkedRails(
    AppState app,
    bool english,
  ) {
    if ((app.webSettings['hideContent'] as Map?)?['anime'] == true) {
      return const [];
    }
    return [
      for (final service in const <(String, String, String)>[
        ('trakt', 'Watchlist · Trakt', 'قائمة المشاهدة · Trakt'),
        ('simkl', 'Watchlist · Simkl', 'قائمة المشاهدة · Simkl'),
        ('anilist', 'Watchlist · AniList', 'قائمة المشاهدة · AniList'),
        ('mal', 'Watchlist · MyAnimeList', 'قائمة المشاهدة · MyAnimeList'),
      ])
        if (app.linkedCatalogItems[service.$1]?.isNotEmpty ?? false)
          (
            english ? service.$2 : service.$3,
            app.linkedCatalogItems[service.$1]!
          ),
    ];
  }

  void _openSection(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}

/// Home-local "could not load the catalog" card for the featured-hero slot.
/// Deliberately NOT the shared [AppStateMessage]: this one is a decorated
/// surface card (radius 20, padding 20, `minHeight` 180) with a
/// `titleMedium` message and NO leading icon — a different shape from the
/// shared "icon → 12 → message → 14 → button" column (audit 121-a2), so
/// adopting it would change the visuals.
class _ServiceMessage extends StatelessWidget {
  const _ServiceMessage({required this.english, required this.onRetry});
  final bool english;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 180),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: HorseTheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  english
                      ? 'Could not load the catalog'
                      : 'تعذر تحميل الكتالوج',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: Text(english ? 'Try again' : 'إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ),
      );
}
