/// Detail-page hero + back pill + content-column atoms — the Flutter replica
/// of the Harbor web `DetailView` presentation layer (Task 30 premium
/// redesign):
///   · [DetailBackPill]  — the fixed glass back button overlaying the hero
///   · [DetailHero]      — cinematic backdrop: phone card variant (< 700px)
///                         with the embedded logo, full-bleed band ≥ 700px
///   · [DetailContentColumn] — title logo, single-line meta row, synopsis,
///                         action row (CTA + expandable glass menu + lists
///                         circle) and the cast/crew block
///   · [ShimmerBox] / [DetailLoadingSkeleton] — the loading state
library;

import 'package:flutter/material.dart';

import '../../core/models/media_item.dart';
import '../../core/theme/horse_theme.dart';
import '../../shared/widgets/glass_navigation.dart';
import '../../shared/widgets/image_decode.dart';
import '../../shared/widgets/shimmer_box.dart';
import 'detail_glass.dart';

// Task 121: ShimmerBox moved to lib/shared/widgets/shimmer_box.dart (it is
// still used below by _HeroImage/DetailLoadingSkeleton); the export shim
// keeps existing consumers (episode_views.dart, tests) resolving it from
// this library.
export '../../shared/widgets/shimmer_box.dart';

/// Press feedback shared by the action-row controls (web: active:scale-…).
class _PressableScale extends StatefulWidget {
  const _PressableScale({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:
          widget.onTap == null ? null : (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

const _cubicEmphasized = Cubic(0.2, 0, 0, 1);

/// The compact glass back button (user mandate, Task 118): a small circular
/// liquid-glass button in the top-start corner wearing the EXACT same
/// recipe as the home-page search button (GlassSearchButton) — saturate+
/// blur backdrop, 0.434 panel fill, 160° sheen, 1px tint ring — just 40dp
/// with the locale-aware back arrow, RTL-mirrored automatically.
class DetailBackPill extends StatelessWidget {
  const DetailBackPill({super.key, required this.english});

  final bool english;

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: 16,
        top: safeTop + 12,
      ),
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: GlassSearchButton(
          size: 40,
          tooltip: english ? 'Back' : 'رجوع',
          // RTL: Arabic pages go forward-pointing (right), English pages
          // back-pointing (left) — the arrow follows reading direction.
          icon:
              english ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded,
          onPressed: () {
            final navigator = Navigator.of(context);
            if (navigator.canPop()) navigator.pop();
          },
        ),
      ),
    );
  }
}

/// The cinematic hero. < 700px: contained card (width − 32 inside 16px
/// padding, 16/11 art height + 72px, rounded bottom corners) with the title
/// logo embedded over the legibility bed. ≥ 700px: full-bleed landscape
/// band fading into the canvas at the bottom.
class DetailHero extends StatelessWidget {
  const DetailHero({
    super.key,
    required this.item,
    required this.backdropUrl,
    required this.logoUrl,
    required this.isWide,
    required this.viewportHeight,
    required this.viewportWidth,
  });

  final MediaItem item;
  final String? backdropUrl;
  final String? logoUrl;
  final bool isWide;
  final double viewportHeight;
  final double viewportWidth;

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary: hero art/scrims repaint independently of the episodes
    // list and vice versa (view/season toggles never invalidate this layer).
    return RepaintBoundary(
      child: !isWide ? _buildPhoneCard(context) : _buildWideBand(context),
    );
  }

  // ---------------- phone card variant ----------------

  Widget _buildPhoneCard(BuildContext context) {
    final width = (viewportWidth - 32).clamp(0.0, viewportWidth);
    final height = width * 11 / 16 + 72;
    const radius = BorderRadius.vertical(bottom: Radius.circular(28));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .9),
              blurRadius: 90,
              offset: const Offset(0, 36),
              spreadRadius: -36,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: SizedBox(
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _HeroImage(url: backdropUrl),
                // Top scrim — hosts the floating back pill.
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 120,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x59000000), Color(0x00000000)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: height * 0.6,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Color(0xE6000000), // black .90
                          Color(0x73000000), // black .45
                          Color(0x00000000),
                        ],
                        stops: [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),
                // Embedded compact logo / fallback title.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Center(
                      child: _HeroTitleLogo(
                        logoUrl: logoUrl,
                        title: item.name,
                        maxLogoHeight: 56,
                        maxLogoWidth: width * 0.78,
                        fallbackFontSize: 30,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------- wide full-bleed variant ----------------

  Widget _buildWideBand(BuildContext context) {
    final height = (viewportHeight * 0.52).clamp(360.0, 680.0);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _HeroImage(url: backdropUrl, alignment: const Alignment(0, -0.3)),
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 120,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x59000000), Color(0x00000000)],
                ),
              ),
            ),
          ),
          // Start-side canvas gradient (AlignmentDirectional mirrors in RTL).
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentDirectional.centerStart,
                  end: AlignmentDirectional.centerEnd,
                  colors: [
                    Color(0xE6000000), // canvas .90
                    Color(0x66000000), // canvas .40
                    Color(0x00000000),
                  ],
                ),
              ),
            ),
          ),
          // Bottom fade into the page background.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: height * 0.45,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Color(0xFF000000), // canvas
                    Color(0x8C000000), // canvas .55
                    Color(0x00000000),
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Backdrop artwork: shimmer underlay ONLY until the first image frame
/// lands (Task 118 perf fix — the old underlay ran an infinite animation
/// controller for the page's whole lifetime), then a plain painted stack.
class _HeroImage extends StatefulWidget {
  const _HeroImage({required this.url, this.alignment = Alignment.center});

  final String? url;
  final Alignment alignment;

  @override
  State<_HeroImage> createState() => _HeroImageState();
}

class _HeroImageState extends State<_HeroImage> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // No artwork at all — the shimmer never has a frame to retire it.
    if ((widget.url ?? '').isEmpty) _markLoaded();
  }

  void _markLoaded() {
    if (!_loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _loaded = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final src = widget.url;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: HorseTheme.raised),
        if (!_loaded && src != null && src.isNotEmpty)
          const Positioned.fill(
            child: ShimmerBox(borderRadius: BorderRadius.zero),
          ),
        if (src != null && src.isNotEmpty)
          Positioned.fill(
            child: Image.network(
              src,
              fit: BoxFit.cover,
              // Task 136: decode at the hero's on-screen width, not the
              // w1280 URL the API hands out.
              cacheWidth:
                  imageCacheWidth(context, MediaQuery.sizeOf(context).width),
              alignment: widget.alignment,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (frame != null || wasSynchronouslyLoaded) _markLoaded();
                if (wasSynchronouslyLoaded) return child;
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  child: child,
                );
              },
              errorBuilder: (_, __, ___) {
                _markLoaded();
                return const ColoredBox(color: HorseTheme.raised);
              },
            ),
          ),
      ],
    );
  }
}

/// Title logo with graceful fallback to the display title.
class _HeroTitleLogo extends StatelessWidget {
  const _HeroTitleLogo({
    required this.logoUrl,
    required this.title,
    required this.maxLogoHeight,
    required this.maxLogoWidth,
    required this.fallbackFontSize,
    required this.textAlign,
  });

  final String? logoUrl;
  final String title;
  final double maxLogoHeight;
  final double maxLogoWidth;
  final double fallbackFontSize;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final src = logoUrl;
    if (src != null && src.isNotEmpty) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxLogoHeight,
          maxWidth: maxLogoWidth,
        ),
        child: Image.network(
          src,
          fit: BoxFit.contain,
          // Task 136: decode at the logo's on-screen size.
          cacheWidth: imageCacheWidth(context, maxLogoWidth),
          alignment: AlignmentDirectional.bottomCenter,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              child: child,
            );
          },
          errorBuilder: (_, __, ___) => _fallbackTitle(),
        ),
      );
    }
    return _fallbackTitle();
  }

  Widget _fallbackTitle() {
    return Text(
      title,
      textAlign: textAlign,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: fallbackFontSize,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: Colors.white,
        height: 1.15,
        shadows: const [
          Shadow(
              offset: Offset(0, 6), blurRadius: 20, color: Color(0xE6000000)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Content column
// ---------------------------------------------------------------------------

/// Title logo / fallback title — rendered in the column on wide layouts only
/// (the phone hero embeds it).
class DetailColumnTitle extends StatelessWidget {
  const DetailColumnTitle({
    super.key,
    required this.logoUrl,
    required this.title,
    required this.isWide,
    required this.viewportWidth,
  });

  final String? logoUrl;
  final String title;
  final bool isWide;
  final double viewportWidth;

  @override
  Widget build(BuildContext context) {
    final maxLogoHeight = viewportWidth >= 840 ? 96.0 : 64.0;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 2),
      child: _HeroTitleLogo(
        logoUrl: logoUrl,
        title: title,
        maxLogoHeight: maxLogoHeight,
        maxLogoWidth: 600,
        fallbackFontSize: viewportWidth >= 840 ? 48 : 30,
        textAlign: TextAlign.start,
      ),
    );
  }
}

/// The single-line, horizontally-scrolling metadata row (never wraps):
/// IMDb chip • year • runtime (LTR) • first genre pill • certification.
class DetailMetaRow extends StatelessWidget {
  const DetailMetaRow({
    super.key,
    required this.item,
    required this.isWide,
  });

  final MediaItem item;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final imdb = double.tryParse(item.rating?.trim() ?? '');
    final score = imdb != null && imdb > 0 ? item.rating!.trim() : null;
    final year = item.releaseInfo?.trim();
    final runtime = item.runtime?.trim();
    final genre =
        item.genres.where((value) => value.trim().isNotEmpty).firstOrNull;
    final hasAny = score != null ||
        (year != null && year.isNotEmpty) ||
        (runtime != null && runtime.isNotEmpty) ||
        genre != null ||
        (item.certification?.trim().isNotEmpty ?? false);
    if (!hasAny) return const SizedBox.shrink();

    final chips = <Widget>[];
    void add(Widget widget) {
      if (chips.isNotEmpty) chips.add(_MetaBullet());
      chips.add(widget);
    }

    if (score != null) {
      add(_ImdbChip(score: score));
    }
    if (year != null && year.isNotEmpty) {
      add(Text(
        year,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: HorseTheme.ink,
        ),
      ));
    }
    if (runtime != null && runtime.isNotEmpty) {
      add(Directionality(
        textDirection: TextDirection.ltr,
        child: Text(
          runtime,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: HorseTheme.muted,
          ),
        ),
      ));
    }
    if (genre != null) {
      add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
          color: HorseTheme.raised.withValues(alpha: .70),
        ),
        child: Text(
          genre,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: HorseTheme.muted,
          ),
        ),
      ));
    }
    final certification = item.certification?.trim();
    if (certification != null && certification.isNotEmpty) {
      add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: HorseTheme.muted.withValues(alpha: .40)),
        ),
        child: Text(
          certification,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.6,
            color: HorseTheme.muted,
          ),
        ),
      ));
    }

    // Center when it fits, scroll from the true start edge when it doesn't.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment:
                isWide ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              for (final chip in chips)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 10),
                  child: chip,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaBullet extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 10),
        child: Text(
          '•',
          style: TextStyle(
            fontSize: 11,
            height: 1,
            color: HorseTheme.muted.withValues(alpha: .60),
          ),
        ),
      );
}

class _ImdbChip extends StatelessWidget {
  const _ImdbChip({required this.score});

  final String score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.amber.shade300.withValues(alpha: .25),
        ),
        color: Colors.amber.shade400.withValues(alpha: .10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 14, color: Colors.amber.shade300),
          const SizedBox(width: 6),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              score,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.amber.shade300,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Synopsis: 14px/1.8 muted (15px ≥ 840); centered full-width on phones,
/// start-aligned 3-line clamp on wide layouts.
class DetailSynopsis extends StatelessWidget {
  const DetailSynopsis({
    super.key,
    required this.description,
    required this.isWide,
    required this.viewportWidth,
  });

  final String description;
  final bool isWide;
  final double viewportWidth;

  @override
  Widget build(BuildContext context) {
    final fontSize = viewportWidth >= 840 ? 15.0 : 14.0;
    final style = TextStyle(
      fontSize: fontSize,
      height: 1.8,
      color: HorseTheme.muted,
    );
    final text = Text(
      description,
      style: style,
      textAlign: isWide ? TextAlign.start : TextAlign.center,
      maxLines: isWide ? 3 : null,
      overflow: isWide ? TextOverflow.ellipsis : null,
    );
    if (!isWide) return text;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 504), // 60ch @ 14px
      child: text,
    );
  }
}

/// Cast & crew block — director line + starring line. The page hides it
/// entirely when both lists are empty.
class DetailCastCrew extends StatelessWidget {
  const DetailCastCrew({
    super.key,
    required this.item,
    required this.english,
    this.centered = false,
  });

  final MediaItem item;
  final bool english;

  /// Phones center the block under the hero card (web: text-center < 600px).
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final lines = <Widget>[
      if (item.director.isNotEmpty)
        DetailCastLine(
          label: english ? 'DIRECTOR' : 'المخرج',
          names: item.director.take(2).join(', '),
          maxLines: 2,
          centered: centered,
        ),
      if (item.cast.isNotEmpty)
        DetailCastLine(
          label: english ? 'STARRING' : 'بطولة',
          names: item.cast.take(4).join(', '),
          maxLines: 2,
          centered: centered,
        ),
    ];
    return Column(
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < lines.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          lines[i],
        ],
      ],
    );
  }
}

/// One "LABEL — names" line: 11px w600 uppercase tracking label + 13px w500
/// ink names, clamped to [maxLines].
class DetailCastLine extends StatelessWidget {
  const DetailCastLine({
    super.key,
    required this.label,
    required this.names,
    required this.maxLines,
    this.centered = false,
  });

  final String label;
  final String names;
  final int maxLines;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label   ',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: HorseTheme.muted,
            ),
          ),
          TextSpan(
            text: names,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: HorseTheme.ink,
            ),
          ),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: centered ? TextAlign.center : TextAlign.start,
    );
  }
}

/// The action row: primary CTA + expandable glass menu trigger + the
/// custom-lists circle. Wraps on narrow screens; centered on phones,
/// start-aligned on wide layouts.
class DetailActionRow extends StatefulWidget {
  const DetailActionRow({
    super.key,
    required this.english,
    required this.isWide,
    required this.inList,
    required this.showTrackAnime,
    required this.primaryLabel,
    required this.primaryIsResume,
    required this.loading,
    required this.onPrimaryPressed,
    required this.onToggleWatchlist,
    required this.onOpenStreams,
    required this.onTrackAnime,
    required this.onShare,
    required this.onAddToList,
  });

  final bool english;
  final bool isWide;
  final bool inList;
  final bool showTrackAnime;
  final String primaryLabel;
  final bool primaryIsResume;
  final bool loading;
  final VoidCallback onPrimaryPressed;
  final VoidCallback onToggleWatchlist;
  final VoidCallback onOpenStreams;
  final VoidCallback onTrackAnime;
  final VoidCallback onShare;
  final VoidCallback onAddToList;

  @override
  State<DetailActionRow> createState() => _DetailActionRowState();
}

class _DetailActionRowState extends State<DetailActionRow> {
  final GlobalKey _menuKey = GlobalKey();
  bool _menuOpen = false;

  Future<void> _toggleMenu() async {
    if (_menuOpen) return;
    final box = _menuKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    setState(() => _menuOpen = true);
    try {
      await showGlassMenu<Object?>(
        context: context,
        anchor: anchor,
        width: 240,
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        builder: (close) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GlassMenuItem(
              leading: Icon(
                widget.inList ? Icons.check_rounded : Icons.add_rounded,
                size: 18,
                color: widget.inList ? HorseTheme.gold : HorseTheme.ink,
              ),
              label: widget.inList
                  ? (widget.english ? 'In my list' : 'في قائمتي')
                  : (widget.english ? 'Add to my list' : 'إضافة لقائمتي'),
              onTap: () {
                close(null);
                widget.onToggleWatchlist();
              },
            ),
            GlassMenuItem(
              leading: const Icon(Icons.layers_rounded,
                  size: 18, color: HorseTheme.ink),
              label: widget.english ? 'Available streams' : 'مصادر التشغيل',
              onTap: () {
                close(null);
                widget.onOpenStreams();
              },
            ),
            if (widget.showTrackAnime)
              GlassMenuItem(
                leading: const Icon(Icons.track_changes_rounded,
                    size: 18, color: HorseTheme.ink),
                label: widget.english ? 'Track anime' : 'تتبّع الأنمي',
                onTap: () {
                  close(null);
                  widget.onTrackAnime();
                },
              ),
            GlassMenuItem(
              leading: const Icon(Icons.ios_share_rounded,
                  size: 18, color: HorseTheme.ink),
              label: widget.english ? 'Share' : 'مشاركة',
              onTap: () {
                close(null);
                widget.onShare();
              },
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _menuOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: widget.isWide ? WrapAlignment.start : WrapAlignment.center,
      children: [
        _PrimaryCta(
          english: widget.english,
          isWide: widget.isWide,
          label: widget.primaryLabel,
          isResume: widget.primaryIsResume,
          loading: widget.loading,
          onTap: widget.loading ? null : widget.onPrimaryPressed,
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MenuTrigger(
              menuKey: _menuKey,
              open: _menuOpen,
              onTap: _toggleMenu,
            ),
            const SizedBox(width: 10),
            _CircleButton(
              icon: Icons.playlist_add_rounded,
              iconSize: 20,
              onTap: widget.onAddToList,
            ),
          ],
        ),
      ],
    );
  }
}

/// 52px-tall gold pill with the glow shadow and press-scale contract.
class _PrimaryCta extends StatelessWidget {
  const _PrimaryCta({
    required this.english,
    required this.isWide,
    required this.label,
    required this.isResume,
    required this.loading,
    required this.onTap,
  });

  final bool english;
  final bool isWide;
  final String label;
  final bool isResume;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _PressableScale(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: HorseTheme.gold.withValues(alpha: .88),
          border: Border.all(color: HorseTheme.gold.withValues(alpha: .45)),
          boxShadow: [
            BoxShadow(
              color: HorseTheme.gold,
              offset: const Offset(0, 14),
              blurRadius: 36,
              spreadRadius: -14,
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsetsDirectional.symmetric(
            horizontal: isWide ? 32 : 24,
            vertical: 0,
          ),
          child: Container(
            height: 52,
            alignment: AlignmentDirectional.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Color(0xFF1A1209),
                    ),
                  )
                else
                  Icon(
                    isResume ? Icons.replay_rounded : Icons.play_arrow_rounded,
                    size: 18,
                    color: scheme.onPrimary,
                  ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: scheme.onPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 52px glass circle with the rotating chevron.
class _MenuTrigger extends StatelessWidget {
  const _MenuTrigger({
    required this.menuKey,
    required this.open,
    required this.onTap,
  });

  final GlobalKey menuKey;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PressableScale(
      onTap: onTap,
      child: _CircleButtonBody(
        key: menuKey,
        child: AnimatedRotation(
          turns: open ? 0.5 : 0,
          duration: const Duration(milliseconds: 220),
          curve: _cubicEmphasized,
          child: const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 20,
            color: HorseTheme.ink,
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.iconSize, this.onTap});

  final IconData icon;
  final double iconSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _PressableScale(
      onTap: onTap,
      child: _CircleButtonBody(
        child: Icon(icon, size: iconSize, color: HorseTheme.ink),
      ),
    );
  }
}

/// border white/8 + bg raised/85 circle (the web menu trigger recipe,
/// Task 136: the blur-12 backdrop is retired — several of these buttons sit
/// over the scrolling hero artwork and each one re-blurred its backdrop on
/// every scroll frame); [key] is honored so callers can measure the anchor.
class _CircleButtonBody extends StatelessWidget {
  const _CircleButtonBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: HorseTheme.raised.withValues(alpha: .85),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: SizedBox(
        width: 52,
        height: 52,
        child: Center(child: child),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton
// ---------------------------------------------------------------------------

/// Hero-shaped skeleton + content-column lines (mirrors the real layout).
class DetailLoadingSkeleton extends StatelessWidget {
  const DetailLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isWide = media.size.width >= 700;
    final heroHeight = isWide
        ? (media.size.height * 0.52).clamp(360.0, 680.0)
        : (media.size.width - 32) * 11 / 16 + 72;
    Widget hero;
    if (isWide) {
      hero = SizedBox(
        width: double.infinity,
        height: heroHeight,
        child: const ShimmerBox(borderRadius: BorderRadius.zero),
      );
    } else {
      hero = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ShimmerBox(
          height: heroHeight,
          borderRadius:
              const BorderRadius.vertical(bottom: Radius.circular(28)),
        ),
      );
    }
    final cross = isWide ? CrossAxisAlignment.start : CrossAxisAlignment.center;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        hero,
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isWide ? 34 : 20),
          child: Column(
            crossAxisAlignment: cross,
            children: [
              const SizedBox(height: 24),
              const ShimmerBox(
                  width: 288,
                  height: 24,
                  borderRadius: BorderRadius.all(Radius.circular(999))),
              const SizedBox(height: 12),
              const ShimmerBox(
                  height: 14,
                  borderRadius: BorderRadius.all(Radius.circular(8))),
              const SizedBox(height: 12),
              FractionallySizedBox(
                widthFactor: 2 / 3,
                child: const ShimmerBox(
                    height: 14,
                    borderRadius: BorderRadius.all(Radius.circular(8))),
              ),
              const SizedBox(height: 14),
              const ShimmerBox(
                  width: 256,
                  height: 52,
                  borderRadius: BorderRadius.all(Radius.circular(999))),
            ],
          ),
        ),
      ],
    );
  }
}
