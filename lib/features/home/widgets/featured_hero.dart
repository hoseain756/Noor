import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/featured_artwork.dart';
import '../../../core/models/media_item.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/horse_theme.dart';
import '../../../shared/widgets/image_decode.dart';
import '../../shell/noor_dock_tabs.dart' show glassDockContentClearance;

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
              // Task 136: decode at the hero's on-screen width — the TMDB
              // backdrop URL can be w1280; on a phone the hero is ~400px.
              cacheWidth: imageCacheWidth(context, size.width),
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
  Widget build(BuildContext context) => const Stack(
        fit: StackFit.expand,
        children: [
          // Bottom fade into the canvas — the original hero scrim, unchanged.
          DecoratedBox(
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
          // EDGE-TO-EDGE readability scrim (Task 119): the hero now bleeds
          // behind the transparent status bar, so a short dark band keeps
          // the clock/battery/signal icons readable over bright artwork
          // (same idea as the web home hero's top gradient).
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, .16],
                colors: [Color(0x66000000), Color(0x00000000)],
              ),
            ),
          ),
        ],
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
                    duration: reduceMotion ? Duration.zero : HorseTheme.durMed,
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
                            // Task 136: decode at the logo's on-screen size.
                            cacheWidth: imageCacheWidth(
                                context, math.min(size.width * .5, 175.0)),
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

/// First-load placeholder matching the real hero's height, scrim ladder and
/// status-bar band so the loading state is geometry-identical.
class FeaturedSkeleton extends StatelessWidget {
  const FeaturedSkeleton({super.key});

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
            // Task 119: same status-bar readability band as the real hero,
            // so the loading state matches the edge-to-edge presentation.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, .16],
                  colors: [Color(0x66000000), Color(0x00000000)],
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
  // device. Since Task 119 it bleeds BEHIND the transparent status bar
  // (its top edge is y=0), but the height guard is unchanged: the hero
  // must never extend into the glass dock zone, and keeps a small floor
  // for very short viewports (e.g. landscape phones).
  final availableHeight =
      (size.height - viewPadding.top - glassDockContentClearance(context))
          .clamp(0.0, double.infinity);
  final preferredHeight = (size.height * .58).clamp(280.0, double.infinity);
  return math.min(availableHeight, preferredHeight).toDouble();
}
