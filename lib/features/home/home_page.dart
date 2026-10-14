import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/media_item.dart';
import '../../core/models/featured_artwork.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';
import '../../core/data/content_classifier.dart';
import '../../shared/widgets/media_rail.dart';
import '../../shared/widgets/media_quick_look.dart';
import '../../shared/widgets/noor_toast.dart';
import '../shell/noor_dock_tabs.dart';
import 'top10_rail.dart';
import '../anime/anime_page.dart';
import '../catalog/catalog_browser_page.dart';
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
  Future<List<MediaItem>>? _addons;
  Future<List<MediaItem>>? _recommendations;
  String? _addonSignature;
  // AniList taps resolve to a playable Stremio identity before opening.
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
    ].join('|');
    if (_topTen == null || signature != _addonSignature) {
      _addonSignature = signature;
      _load(app);
    }
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
    _anime =
        app.catalogs.anime().then((items) => _visibleItems(app, items));
    _animeMovies = _anime!.then(
      (items) => items
          .where((item) => item.type == 'movie')
          .toList(growable: false),
    );
    _newEpisodes = app.catalogs
        .catalog('series', 'last-videos')
        .then((items) => _visibleItems(app, items));
    _addons = app.catalogs
        .addonCatalogs(
          app.addons,
          showAll: app.webSettings['homeShowAllAddonRows'] == true,
        )
        .then((items) => _visibleItems(app, items));
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
    return CustomScrollView(
      slivers: [
        if (classicHome)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 22, 20, 24),
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
                  return _FeaturedCard(
                    items: featured.take(8).toList(growable: false),
                    autoplayActive: widget.active,
                    onTap: _open,
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _FeaturedSkeleton();
                }
                return Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 28, 20, 0),
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
              child: _ContinueRail(
                entries: app.continueWatching,
                english: english,
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: _AsyncMediaSection(
            title: english ? 'Recommended for you' : 'مقترح لك',
            future: _recommendations!,
            onTap: _open,
            onRetry: () => setState(() => _load(app)),
            english: english,
          ),
        ),
        SliverToBoxAdapter(
          child: _AsyncMediaSection(
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
          child: _AsyncMediaSection(
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
          child: _AsyncMediaSection(
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
          child: _AsyncMediaSection(
            title: english ? 'Trending anime' : 'أنمي رائج',
            future: _anime!,
            onTap: _open,
            onOpenSection: () => _openSection(const AnimePage()),
            onRetry: () => setState(() => _reloadAnime()),
            english: english,
          ),
        ),
        SliverToBoxAdapter(
          child: _AsyncMediaSection(
            title: english ? 'Anime movies' : 'أفلام الأنمي',
            future: _animeMovies!,
            onTap: _open,
            onOpenSection: () => _openSection(const AnimePage()),
            onRetry: () => setState(() => _reloadAnime()),
            english: english,
          ),
        ),
        SliverToBoxAdapter(
          child: _AsyncMediaSection(
            title: english ? 'From your add-ons' : 'من إضافاتك',
            future: _addons!,
            onTap: _open,
            onOpenSection: () => _openSection(
              const CatalogBrowserPage(mode: CatalogBrowseMode.catalogs),
            ),
            onRetry: () => setState(
              () => _addons = app.catalogs
                  .addonCatalogs(
                    app.addons,
                    showAll: app.webSettings['homeShowAllAddonRows'] == true,
                  )
                  .then((items) => _visibleItems(app, items)),
            ),
            english: english,
          ),
        ),
        SliverToBoxAdapter(
          child: _AsyncMediaSection(
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
          child: _AsyncMediaSection(
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
        SliverToBoxAdapter(
          child: SizedBox(
            height: glassDockContentClearance(context),
          ),
        ),
      ],
    );
  }

  void _open(MediaItem item) {
    if (!item.id.startsWith('anilist:')) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => MediaDetailPage(item: item)),
      );
      return;
    }
    // AniList records resolve to their Stremio identity first, mirroring the
    // anime page behavior.
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
          builder: (_) => MediaDetailPage(item: resolved),
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
      (items) => items
          .where((item) => item.type == 'movie')
          .toList(growable: false),
    );
  }

  void _openSection(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}

class _AsyncMediaSection extends StatelessWidget {
  const _AsyncMediaSection({
    required this.title,
    required this.future,
    required this.onTap,
    required this.onRetry,
    required this.english,
    this.numbered = false,
    this.showEmptyState = false,
    this.onOpenSection,
  });

  final String title;
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
            return _RailLoading(title: title);
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
                    items: items,
                    onTap: onTap,
                    onOpenSection: onOpenSection,
                  ),
          );
        },
      );
}

class _RailLoading extends StatelessWidget {
  const _RailLoading({required this.title});
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

/// Continue watching, rebuilt to the Harbor web round-21 mobile spec:
/// 16:9 rectangular cards (min(66vw, 300px) wide), the S/E tag + title +
/// episode/remaining subtitle painted INSIDE the card over a bottom scrim,
/// hairline white border, and the signature red track-less progress bar.
/// Rows are ordered most-recently-watched first, exactly like the site.
class _ContinueRail extends StatelessWidget {
  const _ContinueRail({required this.entries, required this.english});
  final List<WatchHistoryEntry> entries;
  final bool english;

  @override
  Widget build(BuildContext context) {
    // Most recently watched first — same ordering as the Harbor web row.
    final sorted = [...entries]
      ..sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
    final wide = MediaQuery.sizeOf(context).width >= 700;
    // Web tokens: --cw-card-w = min(66vw, 300px) with aspect-ratio 16 / 9.
    final cardWidth = math.min(MediaQuery.sizeOf(context).width * .66, 300.0);
    final cardHeight = cardWidth * 9 / 16;
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
                  color: HorseTheme.gold,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  english ? 'Continue watching' : 'تابع المشاهدة',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: cardHeight,
          child: ListView.separated(
            padding: EdgeInsets.symmetric(horizontal: wide ? 34 : 20),
            scrollDirection: Axis.horizontal,
            itemCount: sorted.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _ContinueCard(
              entry: sorted[index],
              english: english,
              width: cardWidth,
              height: cardHeight,
            ),
          ),
        ),
      ],
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.entry,
    required this.english,
    required this.width,
    required this.height,
  });

  final WatchHistoryEntry entry;
  final bool english;
  final double width;
  final double height;

  // Web token: --cw-progress: #e53935.
  static const _progressRed = Color(0xFFE53935);

  String? _remainingLabel() {
    final remaining = entry.durationMs - entry.positionMs;
    if (remaining <= 60000) return null;
    final totalMin = (remaining / 60000).round();
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    final parts = <String>[
      if (h > 0) '$h${english ? 'h' : 'س'}',
      if (m > 0 || h == 0) '$m${english ? 'm' : 'د'}',
    ];
    return english ? '${parts.join(' ')} left' : 'تبقى ${parts.join(' ')}';
  }

  @override
  Widget build(BuildContext context) {
    final item = entry.item;
    final progress = entry.durationMs > 0
        ? (entry.positionMs / entry.durationMs).clamp(0.0, 1.0)
        : 0.0;
    final image = item.background ?? item.poster;
    final isSeries =
        item.type == 'series' && entry.season != null && entry.episode != null;
    // Web seasonEpisodeTag: "S1 E4", bidi-isolated LTR.
    final epTag = isSeries ? 'S${entry.season} E${entry.episode}' : null;
    // Web fallback: episode number for series, remaining time for movies.
    final subtitle = isSeries
        ? (english ? 'Episode ${entry.episode}' : 'الحلقة ${entry.episode}')
        : _remainingLabel();
    final semantics = [
      english ? 'Resume' : 'استئناف',
      item.name,
      if (epTag != null) epTag,
      if (subtitle != null) subtitle,
      if (progress > 0) '${(progress * 100).round()}%',
    ].join(', ');

    void openDetail() => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MediaDetailPage(
              item: item,
              resumeVideoId: entry.videoId,
              resumePositionMs: entry.positionMs,
            ),
          ),
        );

    return SizedBox(
      width: width,
      height: height,
      child: Semantics(
        button: true,
        label: semantics,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: openDetail,
          onLongPress: () =>
              showMediaQuickLook(context, item: item, onOpen: openDetail),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      image == null
                          ? const ColoredBox(color: HorseTheme.surface)
                          : Image.network(
                              image,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const ColoredBox(
                                color: HorseTheme.surface,
                              ),
                            ),
                      // Web scrim: to top, 85% black → 45% → transparent.
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            stops: [0, .45, .75],
                            colors: [
                              Color(0xD9000000),
                              Color(0x73000000),
                              Color(0x00000000),
                            ],
                          ),
                        ),
                      ),
                      PositionedDirectional(
                        start: 10,
                        end: 10,
                        bottom: 12,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (epTag != null) ...[
                              Directionality(
                                textDirection: TextDirection.ltr,
                                child: Text(
                                  epTag,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                    color:
                                        Colors.white.withValues(alpha: .95),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                            ],
                            Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                                color: Colors.white,
                              ),
                            ),
                            if (subtitle != null)
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  height: 1.35,
                                  color: Colors.white.withValues(alpha: .65),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (progress > 0)
                        PositionedDirectional(
                          start: 8,
                          end: 8,
                          bottom: 4,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 3,
                              backgroundColor:
                                  Colors.white.withValues(alpha: .24),
                              color: _progressRed,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // Web card border: 1px rgba(255,255,255,.22), radius 16.
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .22),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturedCard extends StatefulWidget {
  const _FeaturedCard({
    required this.items,
    required this.autoplayActive,
    required this.onTap,
  });
  final List<MediaItem> items;
  final bool autoplayActive;
  final ValueChanged<MediaItem> onTap;

  @override
  State<_FeaturedCard> createState() => _FeaturedCardState();
}

class _FeaturedCardState extends State<_FeaturedCard>
    with WidgetsBindingObserver {
  Timer? _autoplayTimer;
  Timer? _touchResumeTimer;
  int _activeIndex = 0;
  double _dragDistance = 0;
  bool _reducedMotion = false;
  bool _appActive = true;
  bool _touching = false;
  String? _artworkSignature;
  final Map<String, FeaturedArtwork> _artwork = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion != _reducedMotion) {
      _reducedMotion = reduceMotion;
    }
    _enrichSlides();
    _startAutoplay();
  }

  @override
  void didUpdateWidget(covariant _FeaturedCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_itemsSignature(oldWidget.items) != _itemsSignature(widget.items)) {
      _activeIndex = 0;
      _artworkSignature = null;
      _startAutoplay();
    }
    if (oldWidget.autoplayActive != widget.autoplayActive) _startAutoplay();
    _enrichSlides();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoplayTimer?.cancel();
    _touchResumeTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (_appActive) {
      _startAutoplay();
    } else {
      _autoplayTimer?.cancel();
    }
  }

  String _itemsSignature(List<MediaItem> items) =>
      items.map((item) => item.id).join('|');

  void _enrichSlides() {
    if (widget.items.isEmpty) return;
    final app = context.read<AppState>();
    final language = app.webSettings['tmdbLanguage']?.toString() ?? 'en-US';
    final region = app.webSettings['region']?.toString() ?? 'US';
    final uiLanguage = app.english ? 'en' : 'ar';
    final signature =
        '${_itemsSignature(widget.items)}:$language:$region:$uiLanguage:'
        '${app.webSettings['tmdbEnabled']}:${app.api.hasUserTmdbKey ? 'user' : 'default'}';
    if (signature == _artworkSignature) return;
    _artworkSignature = signature;
    _artwork.clear();
    if (app.webSettings['tmdbEnabled'] == false) return;
    unawaited(_loadFeaturedArtwork(
      app,
      signature: signature,
      language: language,
      region: region,
      uiLanguage: uiLanguage,
    ));
  }

  Future<void> _loadFeaturedArtwork(
    AppState app, {
    required String signature,
    required String language,
    required String region,
    required String uiLanguage,
  }) async {
    for (final item in widget.items) {
      if (!mounted || signature != _artworkSignature) return;
      final result = await app.catalogs.featuredArtwork(
        item,
        language: language,
        region: region,
        uiLanguage: uiLanguage,
      );
      if (!mounted || signature != _artworkSignature) return;
      setState(() => _artwork[item.id] = result);
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }

  void _startAutoplay() {
    _autoplayTimer?.cancel();
    if (_reducedMotion ||
        !_appActive ||
        _touching ||
        !widget.autoplayActive ||
        widget.items.length < 2) {
      return;
    }
    _autoplayTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || _touching) return;
      _setActiveSlide((_activeIndex + 1) % widget.items.length);
    });
  }

  void _pauseForTouch() {
    _touchResumeTimer?.cancel();
    _autoplayTimer?.cancel();
    _touching = true;
  }

  void _resumeAfterTouch() {
    _touchResumeTimer?.cancel();
    _touchResumeTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      _touching = false;
      _startAutoplay();
    });
  }

  void _goToSlide(int targetIndex) {
    _pauseForTouch();
    _resumeAfterTouch();
    _setActiveSlide(targetIndex);
  }

  void _setActiveSlide(int targetIndex) {
    if (!mounted || widget.items.length < 2) return;
    final count = widget.items.length;
    final target = ((targetIndex % count) + count) % count;
    if (target == _activeIndex) return;
    setState(() => _activeIndex = target);
  }

  void _handleSwipeEnd() {
    if (_dragDistance.abs() < 36 || widget.items.length < 2) return;
    final forward = Directionality.of(context) == TextDirection.rtl
        ? _dragDistance > 0
        : _dragDistance < 0;
    _setActiveSlide((_activeIndex + (forward ? 1 : -1)) % widget.items.length);
    _dragDistance = 0;
  }

  @override
  Widget build(BuildContext context) {
    final heroHeight = _featuredHeroHeight(context);
    final activeItem = widget.items[_activeIndex];
    return SizedBox(
      height: heroHeight,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _pauseForTouch(),
        onPointerUp: (_) => _resumeAfterTouch(),
        onPointerCancel: (_) => _resumeAfterTouch(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => _dragDistance = 0,
          onHorizontalDragUpdate: (details) =>
              _dragDistance += details.delta.dx,
          onHorizontalDragEnd: (_) => _handleSwipeEnd(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedSwitcher(
                duration: _reducedMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 380),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeOutCubic,
                child: _FeaturedArtwork(
                  key: ValueKey(activeItem.id),
                  item: activeItem,
                  artwork: _artwork[activeItem.id],
                ),
              ),
              const Positioned.fill(child: _FeaturedScrim()),
              Positioned.fill(
                child: _FeaturedOverlay(
                  item: activeItem,
                  artwork: _artwork[activeItem.id],
                  itemsCount: widget.items.length,
                  activeIndex: _activeIndex,
                  reduceMotion: _reducedMotion,
                  onSelectPage: _goToSlide,
                  onTap: () => widget.onTap(activeItem),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturedArtwork extends StatelessWidget {
  const _FeaturedArtwork({
    super.key,
    required this.item,
    required this.artwork,
  });

  final MediaItem item;
  final FeaturedArtwork? artwork;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final large = size.width >= 600;
    final portrait = artwork?.portrait ?? item.poster;
    final landscape = artwork?.landscape ?? item.background;
    final background =
        large ? (landscape ?? portrait) : (portrait ?? landscape);

    // FIX: Keep AnimatedSwitcher artwork at the full hero size instead of its image's intrinsic size.
    return SizedBox.expand(
      child: background != null
          ? Image.network(
              background,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              alignment: large ? Alignment.center : Alignment.topCenter,
              errorBuilder: (_, __, ___) =>
                  const ColoredBox(color: HorseTheme.raised),
            )
          : const ColoredBox(color: HorseTheme.raised),
    );
  }
}

class _FeaturedScrim extends StatelessWidget {
  const _FeaturedScrim();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0, .34, .64, .9],
            colors: [
              Color(0x00000000),
              Color(0x18000000),
              Color(0xB8000000),
              Color(0xFF000000),
            ],
          ),
        ),
      );
}

class _FeaturedOverlay extends StatelessWidget {
  const _FeaturedOverlay({
    required this.item,
    required this.artwork,
    required this.itemsCount,
    required this.activeIndex,
    required this.reduceMotion,
    required this.onSelectPage,
    required this.onTap,
  });

  final MediaItem item;
  final FeaturedArtwork? artwork;
  final int itemsCount;
  final int activeIndex;
  final bool reduceMotion;
  final ValueChanged<int> onSelectPage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final large = size.width >= 600;
    final english = context.read<AppState>().english;
    final logo = artwork?.logo ?? item.logo;
    final genre = artwork?.genre ?? item.genres.firstOrNull;
    final year = item.releaseInfo?.split('–').first.trim();
    final metadataHeight = math
        .max(24.0, MediaQuery.textScalerOf(context).scale(16) * 1.3)
        .toDouble();
    final typeLabel = switch (item.type.toLowerCase()) {
      'movie' => english ? 'Movie' : 'فيلم',
      'series' => english ? 'Series' : 'مسلسل',
      _ => item.type,
    };

    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SizedBox(
                height: 50,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: child,
                    ),
                    child: logo == null
                        ? const SizedBox.shrink(key: ValueKey('empty-logo'))
                        : Image.network(
                            logo,
                            key: ValueKey(logo),
                            width: math.min(size.width * .5, 175.0),
                            height: 50,
                            fit: BoxFit.contain,
                            semanticLabel: item.name,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: metadataHeight,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: child,
                    ),
                    child: ConstrainedBox(
                      key: ValueKey(item.id),
                      constraints: BoxConstraints(maxWidth: size.width - 32),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (year?.isNotEmpty == true) ...[
                            Text(year!, style: _heroMetadataStyle),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: _HeroMetadataDot(),
                            ),
                          ],
                          if (genre?.isNotEmpty == true) ...[
                            Flexible(
                              child: Text(
                                genre!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _heroMetadataStyle,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: _HeroMetadataDot(),
                            ),
                          ],
                          Text(typeLabel, style: _heroMetadataStyle),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: large ? 12 : 10),
              FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  minimumSize: Size(146, large ? 42 : 38),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: const Color(0xFFF5F6F8),
                  foregroundColor: const Color(0xFF0B0B0B),
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
                child: Text(english ? 'View details' : 'عرض التفاصيل'),
              ),
              if (itemsCount > 1) ...[
                const SizedBox(height: 10),
                Semantics(
                  label: english ? 'Featured items' : 'العناوين المميزة',
                  child: SizedBox(
                    height: 8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var index = 0; index < itemsCount; index++) ...[
                          if (index > 0) const SizedBox(width: 8),
                          Semantics(
                            button: true,
                            selected: index == activeIndex,
                            label: english
                                ? 'Item ${index + 1} of $itemsCount'
                                : 'العنوان ${index + 1} من $itemsCount',
                            onTap: () => onSelectPage(index),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => onSelectPage(index),
                              child: AnimatedContainer(
                                duration: reduceMotion
                                    ? Duration.zero
                                    : const Duration(milliseconds: 180),
                                width: index == activeIndex ? 32 : 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (itemsCount > 1)
          PositionedDirectional(
            start: 0,
            end: 0,
            bottom: 0,
            child: Center(
              child: SizedBox(
                width: itemsCount * 16.0 + 16,
                height: 40,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) {
                    final rowWidth = itemsCount * 16.0 + 16;
                    final logicalX =
                        Directionality.of(context) == TextDirection.rtl
                            ? rowWidth - details.localPosition.dx
                            : details.localPosition.dx;
                    var cursor = 0.0;
                    var nearestIndex = 0;
                    var nearestDistance = double.infinity;
                    for (var dot = 0; dot < itemsCount; dot++) {
                      final slotWidth = dot == activeIndex ? 32.0 : 8.0;
                      final distance =
                          (logicalX - (cursor + slotWidth / 2)).abs();
                      if (distance < nearestDistance) {
                        nearestDistance = distance;
                        nearestIndex = dot;
                      }
                      cursor += slotWidth + 8;
                    }
                    onSelectPage(nearestIndex);
                  },
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Hero metadata row: plain white text with a soft shadow, as before the
/// outlined-text experiment (user: "ارجع نص الهيرو كما هو سابقاً").
const _heroMetadataStyle = TextStyle(
  color: Colors.white,
  fontSize: 16,
  fontWeight: FontWeight.w700,
  shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
);

class _HeroMetadataDot extends StatelessWidget {
  const _HeroMetadataDot();

  @override
  Widget build(BuildContext context) => Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .6),
          shape: BoxShape.circle,
        ),
      );
}

class _FeaturedSkeleton extends StatelessWidget {
  const _FeaturedSkeleton();
  @override
  Widget build(BuildContext context) {
    final heroHeight = _featuredHeroHeight(context);
    final english = context.read<AppState>().english;
    final metadataHeight = math
        .max(24.0, MediaQuery.textScalerOf(context).scale(16) * 1.3)
        .toDouble();
    return SizedBox(
      height: heroHeight,
      child: Semantics(
        label:
            english ? 'Loading featured titles' : 'جارٍ تحميل العناوين المميزة',
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF050608)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, .34, .64, .9],
                  colors: [
                    Color(0x00000000),
                    Color(0x18000000),
                    Color(0xB8000000),
                    Color(0xFF000000),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const SizedBox(height: 50),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: metadataHeight,
                      child: Center(
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 10,
                          children: [
                            _HeroSkeletonChip(width: 38),
                            _HeroSkeletonChip(width: 52),
                            _HeroSkeletonChip(width: 30),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: 146,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .2),
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _HeroSkeletonDot(active: true),
                        SizedBox(width: 8),
                        _HeroSkeletonDot(),
                        SizedBox(width: 8),
                        _HeroSkeletonDot(),
                        SizedBox(width: 8),
                        _HeroSkeletonDot(),
                        SizedBox(width: 8),
                        _HeroSkeletonDot(),
                        SizedBox(width: 8),
                        _HeroSkeletonDot(),
                        SizedBox(width: 8),
                        _HeroSkeletonDot(),
                        SizedBox(width: 8),
                        _HeroSkeletonDot(),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroSkeletonChip extends StatelessWidget {
  const _HeroSkeletonChip({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: 16,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .2),
          borderRadius: BorderRadius.circular(12),
        ),
      );
}

class _HeroSkeletonDot extends StatelessWidget {
  const _HeroSkeletonDot({this.active = false});

  final bool active;

  @override
  Widget build(BuildContext context) => Container(
        width: active ? 32 : 8,
        height: 8,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .28),
          borderRadius: BorderRadius.circular(8),
        ),
      );
}

double _featuredHeroHeight(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final viewPadding = MediaQuery.viewPaddingOf(context);
  // Task: the featured hero takes ~58% of the screen height on every
  // device. It must never exceed the visible area under the system bars
  // and the glass dock, and keeps a small floor for very short
  // viewports (e.g. landscape phones).
  final availableHeight = (size.height -
          viewPadding.top -
          glassDockContentClearance(context))
      .clamp(0.0, double.infinity);
  final preferredHeight = (size.height * .58).clamp(280.0, double.infinity);
  return math.min(availableHeight, preferredHeight).toDouble();
}

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
