import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/integration_cw.dart';
import '../../../core/models/media_item.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/horse_theme.dart';
import '../../../shared/widgets/image_decode.dart';
import '../../../shared/widgets/noor_toast.dart';
import '../../media/media_detail_page.dart';
import '../cw_upcoming.dart';
import 'home_section_header.dart';

/// Web CW rail geometry solved once per build for the current width — the
/// single copy of the math that used to be triplicated across the local
/// rail, the linked rail and the linked skeleton: the web tokens
/// `--cw-card-w = min(66vw, 300px)` with aspect-ratio 16 / 9, and the 700px
/// breakpoint flipping the 34/20 rail gutter.
class _CwRailMetrics {
  const _CwRailMetrics({
    required this.cardWidth,
    required this.cardHeight,
    required this.pad,
  });

  factory _CwRailMetrics.solve(double width) {
    final wide = width >= HorseTheme.bpWide;
    final cardWidth = math.min(width * .66, 300.0);
    return _CwRailMetrics(
      cardWidth: cardWidth,
      cardHeight: cardWidth * 9 / 16,
      pad: wide ? 34 : 20,
    );
  }

  final double cardWidth;
  final double cardHeight;
  final double pad;
}

/// Continue watching, rebuilt to the Harbor web round-21 mobile spec:
/// 16:9 rectangular cards (min(66vw, 300px) wide), the S/E tag + title +
/// episode/remaining subtitle painted INSIDE the card over a bottom scrim,
/// hairline white border, the signature red track-less progress bar, the
/// "upcoming episode" badge + amber fresh dot (bounded metadata enrichment,
/// Task 111) and the Harbor long-press menu (details / mark watched / remove).
/// Rows are ordered most-recently-watched first, exactly like the site.
class ContinueWatchingRail extends StatefulWidget {
  const ContinueWatchingRail({
    super.key,
    required this.entries,
    required this.english,
  });

  final List<WatchHistoryEntry> entries;
  final bool english;

  @override
  State<ContinueWatchingRail> createState() => _ContinueRailState();
}

class _ContinueRailState extends State<ContinueWatchingRail> {
  final Map<String, CwEnrichment?> _enrichment = {};
  late final CwEnrichmentCache _cache = CwEnrichmentCache(_loadDetail);
  String? _enrichSignature;

  Future<MediaItem?> _loadDetail(MediaItem item) {
    final app = context.read<AppState>();
    return app.catalogs
        .detail(item.type, item.id, app.addons)
        .timeout(const Duration(seconds: 10), onTimeout: () => null);
  }

  /// Finished episode ids from history — the web `episodeWatchedSet()` that
  /// drives the fresh-dot decision.
  Set<String> _watchedVideoIds(AppState app) => app.history
      .where(
        (h) =>
            h.durationMs > 0 &&
            h.positionMs >= h.durationMs - 120000 &&
            h.videoId != null,
      )
      .map((h) => h.videoId!)
      .toSet();

  /// Web parity: only the first six visible series cards trigger metadata
  /// lookups (`enrich: i < 6`); results land via setState, fail soft.
  void _ensureEnrichment() {
    final app = context.read<AppState>();
    final signature =
        widget.entries.map((e) => '${e.item.id}:${e.watchedAt}').join('|');
    if (signature == _enrichSignature) return;
    _enrichSignature = signature;
    final watched = _watchedVideoIds(app);
    final now = DateTime.now();
    var launched = 0;
    for (final entry in widget.entries) {
      if (launched >= CwEnrichmentCache.maxEnrichedCards) break;
      if (entry.item.type != 'series') continue;
      if (entry.season == null || entry.episode == null) continue;
      if (_enrichment.containsKey(entry.item.id)) continue;
      launched++;
      final itemId = entry.item.id;
      unawaited(
        _cache.enrichmentFor(entry.item, entry, watched, now).then((value) {
          if (!mounted) return;
          setState(() => _enrichment[itemId] = value);
        }),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureEnrichment();
  }

  @override
  void didUpdateWidget(covariant ContinueWatchingRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureEnrichment();
  }

  /// Web token parity: movies show the remaining-time subtitle
  /// ("1h 20m left" / "تبقى 1س 20د") when more than a minute remains.
  static String? _remainingLabel(WatchHistoryEntry entry, bool english) {
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
    // Most recently watched first — same ordering as the Harbor web row.
    final sorted = [...widget.entries]
      ..sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
    // Web tokens: --cw-card-w = min(66vw, 300px) with aspect-ratio 16 / 9 —
    // solved once (with the 34/20 gutter) by [_CwRailMetrics].
    final metrics = _CwRailMetrics.solve(MediaQuery.sizeOf(context).width);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: metrics.pad),
          child: HomeSectionHeader(
            // Exact site strings (web homeT "continueWatching").
            title: widget.english ? 'Continue Watching' : 'متابعة المشاهدة',
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: metrics.cardHeight,
          child: ListView.separated(
            padding: EdgeInsets.symmetric(horizontal: metrics.pad),
            scrollDirection: Axis.horizontal,
            itemCount: sorted.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final entry = sorted[index];
              final item = entry.item;
              final isSeries = item.type == 'series' &&
                  entry.season != null &&
                  entry.episode != null;
              final enrichment = _enrichment[item.id];
              final epName = enrichment?.episodeName;
              final data = CwCardData(
                id: '${entry.item.id}:${entry.watchedAt}',
                item: item,
                progress: entry.durationMs > 0
                    ? (entry.positionMs / entry.durationMs).clamp(0.0, 1.0)
                    : 0.0,
                epTag: isSeries ? 'S${entry.season} E${entry.episode}' : null,
                subtitle: isSeries
                    ? (epName != null && epName.isNotEmpty
                        ? epName
                        : (widget.english
                            ? 'Episode ${entry.episode}'
                            : 'الحلقة ${entry.episode}'))
                    : _remainingLabel(entry, widget.english),
                badge: cwUpcomingLabel(
                    enrichment?.nextAirMs, widget.english, DateTime.now()),
                fresh: enrichment?.fresh ?? false,
              );
              return ContinueCard(
                data: data,
                english: widget.english,
                width: metrics.cardWidth,
                height: metrics.cardHeight,
                onOpen: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MediaDetailPage(
                      item: item,
                      resumeVideoId: entry.videoId,
                      resumePositionMs: entry.positionMs,
                    ),
                  ),
                ),
                onMarkWatched: () {
                  unawaited(
                    context
                        .read<AppState>()
                        .markContinueWatchingWatched(item.id)
                        .then((_) {
                      if (context.mounted) {
                        NoorToast.show(
                          context,
                          widget.english
                              ? 'Marked as watched'
                              : 'تم التحديد كمشاهد',
                        );
                      }
                    }),
                  );
                },
                onRemove: () => unawaited(
                  context.read<AppState>().removeContinueWatchingEntry(item.id),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Visual payload of one continue-watching card — built either from a local
/// history entry (with metadata enrichment) or from a linked-service entry
/// (source tag instead of menu actions).
class CwCardData {
  const CwCardData({
    required this.id,
    required this.item,
    required this.progress,
    this.epTag,
    this.subtitle,
    this.badge,
    this.fresh = false,
    this.sourceLabel,
  });

  final String id;
  final MediaItem item;

  /// 0..1 — drives the red track-less progress bar (0 hides it).
  final double progress;
  final String? epTag;
  final String? subtitle;
  final String? badge;
  final bool fresh;

  /// Small provenance pill ("Trakt" / "AniList" / "MyAnimeList") on cards
  /// sourced from a linked service.
  final String? sourceLabel;
}

class ContinueCard extends StatelessWidget {
  const ContinueCard({
    super.key,
    required this.data,
    required this.english,
    required this.width,
    required this.height,
    required this.onOpen,
    this.onMarkWatched,
    this.onRemove,
  });

  final CwCardData data;
  final bool english;
  final double width;
  final double height;

  final VoidCallback onOpen;

  /// Present only on LOCAL continue-watching cards — they unlock the
  /// "mark as watched" / "remove" actions in the long-press menu.
  final VoidCallback? onMarkWatched;
  final VoidCallback? onRemove;

  // Web token: --cw-progress: #e53935.
  static const _progressRed = Color(0xFFE53935);
  // Web token: --cw-fresh-dot: #f5b301.
  static const _freshDot = Color(0xFFF5B301);

  @override
  Widget build(BuildContext context) {
    final item = data.item;
    final progress = data.progress;
    final image = item.background ?? item.poster;
    final epTag = data.epTag;
    final subtitle = data.subtitle;
    final badge = data.badge;
    final fresh = data.fresh;
    final sourceLabel = data.sourceLabel;
    final semantics = [
      english ? 'Resume' : 'استئناف',
      item.name,
      if (epTag != null) epTag,
      if (subtitle != null) subtitle,
      if (badge != null) badge,
      if (progress > 0) '${(progress * 100).round()}%',
    ].join(', ');

    void openDetail() => onOpen();

    /// Harbor-web long-press menu (web CwContextMenu → the mobile M3 sheet):
    /// view details always; mark-as-watched / remove only on LOCAL cards —
    /// linked-service cards carry no local position data to act on.
    Future<void> openMenu() {
      return showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        backgroundColor: HorseTheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (sheetContext) {
          void close() => Navigator.of(sheetContext).pop();
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 20, 2),
                  child: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 6),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: Text(english ? 'View details' : 'عرض التفاصيل'),
                  onTap: () {
                    close();
                    openDetail();
                  },
                ),
                if (onMarkWatched != null)
                  ListTile(
                    leading: const Icon(Icons.visibility_outlined),
                    title: Text(english ? 'Mark as watched' : 'تحديد كمشاهد'),
                    onTap: () {
                      close();
                      onMarkWatched!();
                    },
                  ),
                if (onRemove != null)
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline_rounded,
                      color: _progressRed,
                    ),
                    title: Text(
                      english
                          ? 'Remove from Continue Watching'
                          : 'إزالة من متابعة المشاهدة',
                      style: const TextStyle(color: _progressRed),
                    ),
                    onTap: () {
                      close();
                      onRemove!();
                    },
                  ),
              ],
            ),
          );
        },
      );
    }

    return SizedBox(
      width: width,
      height: height,
      child: Semantics(
        button: true,
        label: semantics,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: openDetail,
          onLongPress: () => unawaited(openMenu()),
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
                              // Task 136: decode at the card's on-screen size.
                              cacheWidth: imageCacheWidth(context, width),
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
                                    color: Colors.white.withValues(alpha: .95),
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
                      // Web .cw-badge: top-end black-70 pill, radius 8,
                      // 12px/500 white text, 8px inset.
                      if (badge != null)
                        PositionedDirectional(
                          top: 8,
                          end: 8,
                          child: Container(
                            height: 22,
                            constraints: BoxConstraints(maxWidth: width * .7),
                            padding: const EdgeInsetsDirectional.symmetric(
                              horizontal: 7,
                            ),
                            alignment: AlignmentDirectional.center,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              badge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      // Source pill (linked-service cards only): top-start
                      // black-60 pill naming the provider — Trakt, AniList,
                      // MyAnimeList — so provenance is visible at a glance.
                      if (sourceLabel != null)
                        PositionedDirectional(
                          top: 8,
                          start: 8,
                          child: Container(
                            height: 20,
                            padding: const EdgeInsetsDirectional.symmetric(
                              horizontal: 7,
                            ),
                            alignment: AlignmentDirectional.center,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .6),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(
                              sourceLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: .2,
                                color: Colors.white.withValues(alpha: .92),
                              ),
                            ),
                          ),
                        ),
                      // Web .cw-fresh: 5px amber dot above the progress bar.
                      if (fresh)
                        const PositionedDirectional(
                          start: 8,
                          bottom: 12,
                          child: SizedBox(
                            width: 5,
                            height: 5,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: _freshDot,
                                shape: BoxShape.circle,
                              ),
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

/// Continue-watching cards sourced from the LINKED tracking services —
/// Trakt paused playback and the anime trackers' "currently watching" list.
/// Exactly the Harbor-web card spec (16:9, scrim, S/E tag, red progress
/// bar) plus a small source pill; taps flow through the tracker-resolve
/// path for `anilist:`/`mal:` identities. The long-press menu intentionally
/// offers "view details" only — there is no local position data to mark or
/// remove.
class LinkedContinueRail extends StatelessWidget {
  const LinkedContinueRail({
    super.key,
    required this.entries,
    required this.english,
    required this.onOpen,
  });

  final List<IntegrationCwEntry> entries;
  final bool english;
  final ValueChanged<MediaItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final metrics = _CwRailMetrics.solve(MediaQuery.sizeOf(context).width);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: metrics.pad),
          child: HomeSectionHeader(
            title: english
                ? 'Continue Watching · Linked accounts'
                : 'متابعة المشاهدة · الحسابات المرتبطة',
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: metrics.cardHeight,
          child: ListView.separated(
            padding: EdgeInsets.symmetric(horizontal: metrics.pad),
            scrollDirection: Axis.horizontal,
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ContinueCard(
                data: _cardData(entry, english),
                english: english,
                width: metrics.cardWidth,
                height: metrics.cardHeight,
                onOpen: () => onOpen(entry.item),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Anime trackers surface the NEXT episode to watch as the subtitle
  /// (there is no mid-episode position to resume); Trakt carries a real
  /// pause percentage and, for shows, the exact season/episode.
  static CwCardData _cardData(IntegrationCwEntry entry, bool english) {
    final isTracker = entry.source != 'trakt';
    final next = entry.nextEpisode;
    return CwCardData(
      id: '${entry.source}:${entry.item.id}',
      item: entry.item,
      progress: entry.progress,
      epTag: entry.season != null && entry.episode != null
          ? 'S${entry.season} E${entry.episode}'
          : null,
      subtitle: isTracker && next != null
          ? (english ? 'Episode $next' : 'الحلقة $next')
          : null,
      sourceLabel: switch (entry.source) {
        'trakt' => 'Trakt',
        'anilist' => 'AniList',
        _ => 'MyAnimeList',
      },
    );
  }
}

/// First-load placeholder for the linked continue-watching row: mirrors the
/// real rail's geometry (web card spec, same widths) so the layout doesn't
/// jump when the rows arrive. Rendered only while a linked refresh is in
/// flight and no rows exist yet.
class LinkedContinueSkeleton extends StatelessWidget {
  const LinkedContinueSkeleton({super.key, required this.english});

  final bool english;

  @override
  Widget build(BuildContext context) {
    final metrics = _CwRailMetrics.solve(MediaQuery.sizeOf(context).width);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: metrics.pad),
          child: HomeSectionHeader(
            title: english
                ? 'Continue Watching · Linked accounts'
                : 'متابعة المشاهدة · الحسابات المرتبطة',
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: metrics.cardHeight,
          child: ListView.separated(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: metrics.pad),
            scrollDirection: Axis.horizontal,
            itemCount: 3,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) => Container(
              width: metrics.cardWidth,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: HorseTheme.hairline),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
