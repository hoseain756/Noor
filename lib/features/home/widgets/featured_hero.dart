import 'package:noor_mobile/l10n/nova_strings.dart';
import 'package:noor_mobile/shared/widgets/nova_network_image.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/featured_artwork.dart';
import '../../../core/models/media_item.dart';
import '../../../core/state/app_state.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../shared/widgets/image_decode.dart';

/// The featured hero carousel (home's top slot): full-bleed autoplaying
/// artwork with TMDB-enriched logo / portrait / landscape picks, the bottom
/// scrim ladder, metadata row, "View details" pill and page dots — plus the
/// geometry-matched [FeaturedSkeleton] loading state. Moved verbatim from
/// home_page.dart (Task 121-c); visuals, keys and ordering are unchanged.
class FeaturedHero extends StatefulWidget {
  const FeaturedHero({
    super.key,
    required this.items,
    required this.autoplayActive,
    required this.onTap,
  });

  final List<MediaItem> items;
  final bool autoplayActive;
  final ValueChanged<MediaItem> onTap;

  @override
  State<FeaturedHero> createState() => _FeaturedCardState();
}

class _FeaturedCardState extends State<FeaturedHero>
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
  void didUpdateWidget(covariant FeaturedHero oldWidget) {
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
    // Task 122-d: hero artwork, logo and overview language follow the
    // CONTENT language (app.contentTmdbLocale — the same basis home_page
    // reloads on) instead of the legacy UI-less TMDB-locale fallback plus
    // the UI language. The repository normalizes uiLanguage to its primary
    // subtag for the include_image_language list and logo pick (the
    // '<subtag>,en,null' fallback chain is unchanged), so the full locale
    // is safe to pass through.
    final language = app.contentTmdbLocale;
    final region = app.webSettings['region']?.toString() ?? 'US';
    final uiLanguage = language.split(RegExp('[-_]')).first.toLowerCase();
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
      _precacheNext();
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
    _precacheNext();
  }

  void _precacheNext() {
    if (!mounted || widget.items.isEmpty) return;
    final next = widget.items[(_activeIndex + 1) % widget.items.length];
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final art = _artwork[next.id];
    final url = wide
        ? (art?.landscape ?? next.background ?? next.poster)
        : (art?.portrait ?? next.poster ?? next.background);
    if (url != null)
      unawaited(precacheImage(
          ResizeImage.resizeIfNeeded(
              imageCacheWidth(context, MediaQuery.sizeOf(context).width),
              null,
              NetworkImage(url)),
          context));
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
    final heroHeight = featuredHeroHeight(context);
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
  const _FeaturedArtwork(
      {super.key, required this.item, required this.artwork});
  final MediaItem item;
  final FeaturedArtwork? artwork;
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 700 || size.width > size.height;
    final url = wide
        ? (artwork?.landscape ?? item.background ?? item.poster)
        : (artwork?.portrait ?? item.poster ?? item.background);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.expand(
      child: url == null
          ? ColoredBox(color: scheme.surfaceContainerHighest)
          : NovaNetworkImage(
              url,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              cacheWidth: imageCacheWidth(context, size.width),
              alignment: Alignment.topCenter,
              excludeFromSemantics: true,
              frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 320),
                child: child,
              ),
              errorBuilder: (_, __, ___) =>
                  ColoredBox(color: scheme.surfaceContainerHighest),
            ),
    );
  }
}

class _FeaturedScrim extends StatelessWidget {
  const _FeaturedScrim();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
        decoration: BoxDecoration(
            gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        scheme.scrim.withValues(alpha: .25),
        scheme.scrim.withValues(alpha: .05),
        scheme.scrim.withValues(alpha: .86),
        scheme.scrim
      ],
      stops: const [0, .35, .78, 1],
    )));
  }
}

class _FeaturedOverlay extends StatelessWidget {
  const _FeaturedOverlay(
      {required this.item,
      required this.artwork,
      required this.itemsCount,
      required this.activeIndex,
      required this.reduceMotion,
      required this.onSelectPage,
      required this.onTap});
  final MediaItem item;
  final FeaturedArtwork? artwork;
  final int itemsCount;
  final int activeIndex;
  final bool reduceMotion;
  final ValueChanged<int> onSelectPage;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final english = app.english;
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 700;
    // Cinematic art always has a dark palette-derived legibility bed.
    final foreground = Theme.of(context).brightness == Brightness.dark
        ? scheme.onSurface
        : scheme.surface;
    final logo = artwork?.logo ?? item.logo;
    final genre = artwork?.genre ?? item.genres.firstOrNull;
    final type = item.type == 'movie'
        ? (NovaStrings.lookup(english, 'message128'))
        : (NovaStrings.lookup(english, 'message129'));
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
          wide ? 40 : 24, 72, wide ? 40 : 24, 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(NovaStrings.lookup(english, 'message130'),
              style: TextStyle(
                  color: foreground.withValues(alpha: .85),
                  fontSize: 12,
                  letterSpacing: english ? 2.5 : 0,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          if (logo != null)
            NovaNetworkImage(logo,
                width: math.min(size.width * .65, 320),
                height: wide ? 88 : 72,
                fit: BoxFit.contain,
                alignment: AlignmentDirectional.centerStart
                    .resolve(Directionality.of(context)),
                cacheWidth: imageCacheWidth(context, 320),
                semanticLabel: item.name,
                errorBuilder: (_, __, ___) => Text(item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: foreground,
                        fontSize: wide ? 40 : 32,
                        fontWeight: FontWeight.w800,
                        height: 1.2)))
          else
            Text(item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: foreground,
                    fontSize: wide ? 40 : 32,
                    fontWeight: FontWeight.w800,
                    height: 1.2)),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 4, children: [
            Text(type,
                style:
                    TextStyle(color: foreground, fontWeight: FontWeight.w700)),
            if (item.releaseInfo?.isNotEmpty == true)
              Text(item.releaseInfo!,
                  style: TextStyle(color: foreground.withValues(alpha: .85))),
            if (genre != null)
              Text(genre,
                  style: TextStyle(color: foreground.withValues(alpha: .85))),
          ]),
          if (wide &&
              (artwork?.overview ?? item.description)?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Text(artwork?.overview ?? item.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: foreground.withValues(alpha: .85),
                        height: 1.6))),
          ],
          const SizedBox(height: 24),
          Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                    onPressed: onTap,
                    icon: const Icon(LucideIcons.play, size: 20),
                    label: Text(NovaStrings.lookup(english, 'message131')),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(160, 52))),
                IconButton.filledTonal(
                    onPressed: () => unawaited(app.toggleWatchlist(item)),
                    tooltip: app.contains(item)
                        ? (NovaStrings.lookup(english, 'message132'))
                        : (NovaStrings.lookup(english, 'message133')),
                    icon: Icon(app.contains(item)
                        ? LucideIcons.check
                        : LucideIcons.plus),
                    style: IconButton.styleFrom(
                        minimumSize: const Size.square(52))),
              ]),
          if (itemsCount > 1) ...[
            const SizedBox(height: 12),
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                  onPressed: () => onSelectPage(activeIndex - 1),
                  tooltip: NovaStrings.lookup(english, 'message134'),
                  icon: Icon(
                      Directionality.of(context) == TextDirection.rtl
                          ? LucideIcons.chevronRight
                          : LucideIcons.chevronLeft,
                      color: foreground)),
              Text('${activeIndex + 1} / $itemsCount',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      color: foreground,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              IconButton(
                  onPressed: () => onSelectPage(activeIndex + 1),
                  tooltip: NovaStrings.lookup(english, 'message135'),
                  icon: Icon(
                      Directionality.of(context) == TextDirection.rtl
                          ? LucideIcons.chevronLeft
                          : LucideIcons.chevronRight,
                      color: foreground)),
            ]),
          ],
        ],
      ),
    );
  }
}

class FeaturedSkeleton extends StatelessWidget {
  const FeaturedSkeleton({super.key});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
        height: featuredHeroHeight(context),
        child: ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 40),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final width in [120.0, 240.0, 160.0]) ...[
                      Container(
                          width: width,
                          height: 20,
                          decoration: BoxDecoration(
                              color: scheme.onSurface.withValues(alpha: .08),
                              borderRadius: BorderRadius.circular(8))),
                      const SizedBox(height: 16),
                    ],
                    Container(
                        width: 168,
                        height: 52,
                        decoration: BoxDecoration(
                            color: scheme.onSurface.withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(16))),
                  ]),
            )));
  }
}

double featuredHeroHeight(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
  final landscape = size.width > size.height;
  final base = landscape
      ? (size.height * .95).clamp(420.0, 620.0)
      : (size.height * .78).clamp(540.0, 760.0);
  return base + (scale - 1).clamp(0.0, 2.0) * 160;
}
