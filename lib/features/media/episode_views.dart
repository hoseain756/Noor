/// Detail-page episodes system — the Flutter replica of the Harbor web
/// `EpisodesSection` rebuild (episodes/ folder):
///   · toolbar: glass season dropdown (> 1 season) or episode count, sort
///     chip, and the persisted list/grid view toggle (end-aligned cluster)
///   · per-episode art chain (thumbnail → thumb → series background →
///     gradient placeholder carrying the episode number) with the full
///     overlay kit: E-pill, watched pill, IMDb chip, red progress bar,
///     spoiler blur and the dimmed/untappable upcoming state
///   · ListView.builder virtualization replaces the web's windowing hook,
///     and the old take(60) cap is gone — every episode renders
/// Data helpers (sort/progress/default-season) live in `episode_data.dart`.
library;

import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/material.dart';

import '../../core/models/media_item.dart';
import '../../core/theme/horse_theme.dart';
import 'detail_glass.dart';
import 'detail_hero.dart' show ShimmerBox;
import 'episode_data.dart';

/// Session (per page load) season memory keyed by title id — the web keeps
/// the same per-session map so revisits reopen the user's last season.
final Map<String, int> _sessionSeason = {};

/// rgba(8,8,10,.72) — the web --ep-overlay-bg.
const Color _kOverlayBg = Color(0xB808080A);

const Color _kWatchedGreen = Color(0xFF22C55E);
const Color _kProgressBarRed = Color(0xFFDC2626);
const Color _kImdbYellow = Color(0xFFF5C518);

ColorFilter _saturate(double s) => ColorFilter.matrix(<double>[
      0.213 + (1 - 0.213) * s, 0.715 * (1 - s), 0.072 * (1 - s), 0, 0, //
      0.213 * (1 - s), 0.715 + (1 - 0.715) * s, 0.072 * (1 - s), 0, 0, //
      0.213 * (1 - s), 0.715 * (1 - s), 0.072 + (1 - 0.072) * s, 0, 0, //
      0, 0, 0, 1, 0,
    ]);

/// One enriched episode item — built once per (season × sort × data) by
/// [EpisodesSection]; the row/card widgets stay pure presenters.
class _EpisodeViewData {
  _EpisodeViewData({
    required this.video,
    required this.season,
    required this.epNum,
    required this.title,
    required this.story,
    required this.watched,
    required this.progress,
    required this.upcoming,
    required this.rating,
    required this.runtimeMin,
  });

  final Map<String, dynamic> video;
  final int season;
  final int epNum;
  final String title;
  final String story;
  final bool watched;

  /// 0..1 playback progress (0 = untouched).
  final double progress;
  final bool upcoming;
  final double? rating;
  final int? runtimeMin;

  static _EpisodeViewData from(
    Map<String, dynamic> video, {
    required int season,
    required bool english,
    required Map<String, EpisodeProgress> progressMap,
    required String itemId,
    required DateTime now,
    required bool ratingsEnabled,
  }) {
    final epNum = (video['episode'] as num?)?.toInt() ?? 0;
    final progress =
        progressForVideo(progressMap, video, itemId)?.progress ?? 0.0;
    final rawTitle = (video['name'] ?? video['title'] ?? '').toString().trim();
    final rawStory =
        (video['overview'] ?? video['description'] ?? '').toString().trim();
    final rawRating = video['rating'] ?? video['imdbRating'];
    final parsedRating = switch (rawRating) {
      num value => value.toDouble(),
      String value => double.tryParse(value.trim()),
      _ => null,
    };
    return _EpisodeViewData(
      video: video,
      season: season,
      epNum: epNum,
      title: rawTitle.isNotEmpty
          ? rawTitle
          : (english ? 'Episode $epNum' : 'الحلقة $epNum'),
      story: rawStory,
      watched: isEpisodeWatched(progressMap, video, itemId),
      progress: progress,
      upcoming: isUpcomingEpisode(video, now),
      rating: ratingsEnabled && parsedRating != null && parsedRating > 0
          ? parsedRating
          : null,
      runtimeMin: parseRuntimeMinutes(video['duration']?.toString()),
    );
  }
}

class _SeasonOption {
  const _SeasonOption({
    required this.season,
    required this.label,
    required this.count,
    required this.watched,
  });

  final int season;
  final String label;
  final int count;
  final int watched;
}

/// The whole episodes block for a series with videos. Owns season/sort/view
/// state so toggling never rebuilds the rest of the detail page.
class EpisodesSection extends StatefulWidget {
  const EpisodesSection({
    super.key,
    required this.item,
    required this.english,
    required this.entries,
    required this.blurUnwatched,
    required this.ratingsEnabled,
    required this.savedView,
    required this.onViewChange,
    required this.onPlay,
  });

  final MediaItem item;

  /// Watch-history entries for this title only (drives watched/progress).
  final List<WatchHistoryEntry> entries;
  final bool english;

  /// `blurEpisodeThumbnails` setting.
  final bool blurUnwatched;

  /// `ratingsEnabled` setting — false hides the per-episode IMDb chips.
  final bool ratingsEnabled;

  /// Persisted `episodesView` setting: 'auto' | 'list' | 'grid'.
  final String savedView;

  /// Persists the new view ('list' | 'grid') via app.setSetting.
  final ValueChanged<String> onViewChange;

  /// Plays the tapped episode's video through the detail page's flow.
  final ValueChanged<Map<String, dynamic>> onPlay;

  @override
  State<EpisodesSection> createState() => _EpisodesSectionState();
}

class _EpisodesSectionState extends State<EpisodesSection> {
  int? _pickedSeason;
  bool _sortDesc = false;

  String _seasonLabel(int season) => season == 0
      ? (widget.english ? 'Specials' : 'حلقات خاصة')
      : (widget.english ? 'Season $season' : 'الموسم $season');

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final english = widget.english;
    final videos = sortEpisodes(item.videos);
    final now = DateTime.now();
    final seasons = <int>{
      for (final video in videos)
        if ((video['season'] as num?) != null) (video['season'] as num).toInt(),
    }.toList()
      ..sort();

    // Header is shared by the populated and empty states.
    final header = Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 12),
      child: Text(
        english ? 'Episodes' : 'الحلقات',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: HorseTheme.ink,
        ),
      ),
    );

    if (videos.isEmpty || seasons.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          Text(
            english
                ? 'No episode information available for this series.'
                : 'لا تتوفر معلومات حلقات لهذا المسلسل.',
            style: const TextStyle(fontSize: 14, color: HorseTheme.muted),
          ),
        ],
      );
    }

    final progressMap = episodeProgressMap(
      entries: widget.entries,
      itemId: item.id,
    );
    final effectiveSeason = _pickedSeason ??
        _sessionSeason[item.id] ??
        defaultSeason(
          videos: videos,
          history: widget.entries,
          itemId: item.id,
          now: now,
        ) ??
        seasons.first;
    final seasonVideos = [
      for (final video in videos)
        if ((video['season'] as num?)?.toInt() == effectiveSeason) video,
    ];
    var items = [
      for (final video in seasonVideos)
        _EpisodeViewData.from(
          video,
          season: effectiveSeason,
          english: english,
          progressMap: progressMap,
          itemId: item.id,
          now: now,
          ratingsEnabled: widget.ratingsEnabled,
        ),
    ];
    items.sort((a, b) => _sortDesc ? b.epNum - a.epNum : a.epNum - b.epNum);

    final seasonOptions = [
      for (final season in seasons)
        _SeasonOption(
          season: season,
          label: _seasonLabel(season),
          count: videos
              .where((v) => (v['season'] as num?)?.toInt() == season)
              .length,
          watched: videos
              .where((v) => (v['season'] as num?)?.toInt() == season)
              .where((v) => isEpisodeWatched(progressMap, v, item.id))
              .length,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final isWide = MediaQuery.sizeOf(context).width >= 700;

            // View mode: explicit setting wins; auto = phone list / ≥700 grid.
            final view = switch (widget.savedView) {
              'list' => 'list',
              'grid' => 'grid',
              _ => isWide ? 'grid' : 'list',
            };
            final cols = width < 600
                ? 2
                : width < 1024
                    ? 3
                    : width < 1360
                        ? 4
                        : 5;
            final gap = width >= 1360
                ? 20.0
                : width >= 1024
                    ? 18.0
                    : width >= 600
                        ? 16.0
                        : 12.0;
            final thumbWidth =
                isWide ? 220.0 : (width * 0.4).clamp(120.0, 168.0).toDouble();

            final seasonControl = seasons.length > 1
                ? _SeasonDropdown(
                    key: ValueKey('season-${item.id}'),
                    options: seasonOptions,
                    value: effectiveSeason,
                    english: english,
                    onChanged: (season) {
                      setState(() {
                        _pickedSeason = season;
                        _sessionSeason[item.id] = season;
                      });
                    },
                  )
                : Container(
                    height: 48,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      english
                          ? '${videos.length} episodes'
                          : '${videos.length} حلقة',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: HorseTheme.muted,
                      ),
                    ),
                  );

            final sortChip = _SortChip(
              english: english,
              sortDesc: _sortDesc,
              onTap: () => setState(() => _sortDesc = !_sortDesc),
            );
            final viewToggle = _ViewToggle(
              english: english,
              view: view,
              onViewChange: widget.onViewChange,
            );

            final toolbar = width >= 440
                ? Row(
                    children: [
                      seasonControl,
                      const Spacer(),
                      sortChip,
                      const SizedBox(width: 8),
                      viewToggle,
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      seasonControl,
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Spacer(),
                          sortChip,
                          const SizedBox(width: 8),
                          viewToggle,
                        ],
                      ),
                    ],
                  );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: 12),
                  child: toolbar,
                ),
                _EpisodeScroller(
                  items: items,
                  view: view,
                  cols: cols,
                  gap: gap,
                  thumbWidth: thumbWidth,
                  isWide: isWide,
                  english: english,
                  backdropUrl: item.background,
                  blurUnwatched: widget.blurUnwatched,
                  onPlay: widget.onPlay,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Toolbar controls
// ---------------------------------------------------------------------------

/// Glass season pill (dock glass recipe verbatim) opening the glass season
/// menu; per-season sub-line "{count} · {watched}/{count}".
class _SeasonDropdown extends StatefulWidget {
  const _SeasonDropdown({
    super.key,
    required this.options,
    required this.value,
    required this.english,
    required this.onChanged,
  });

  final List<_SeasonOption> options;
  final int value;
  final bool english;
  final ValueChanged<int> onChanged;

  @override
  State<_SeasonDropdown> createState() => _SeasonDropdownState();
}

class _SeasonDropdownState extends State<_SeasonDropdown> {
  final GlobalKey _triggerKey = GlobalKey();
  bool _open = false;

  Future<void> _openMenu() async {
    if (_open) return;
    final box =
        _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    setState(() => _open = true);
    int? picked;
    try {
      picked = await showGlassMenu<int>(
        context: context,
        anchor: anchor,
        width: 256,
        maxHeight:
            (MediaQuery.sizeOf(context).height * 0.6).clamp(0.0, 420.0),
        builder: (close) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final option in widget.options)
              InkWell(
                onTap: () => close(option.season),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: option.season == widget.value
                            ? const Icon(Icons.check_rounded,
                                size: 16, color: HorseTheme.gold)
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              option.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: HorseTheme.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(
                                '${option.count} · '
                                '${option.watched}/${option.count}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: HorseTheme.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _open = false);
    }
    if (picked != null && picked != widget.value) widget.onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final current =
        widget.options.where((o) => o.season == widget.value).firstOrNull;
    final label = current?.label ??
        (widget.english ? 'Select season' : 'اختر الموسم');
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 240),
      child: GlassPillSurface(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: _openMenu,
            child: SizedBox(
              key: _triggerKey,
              height: 48,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: HorseTheme.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 220),
                      curve: const Cubic(0.2, 0, 0, 1),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: HorseTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sort pill: 'الأحدث أولاً'/'الأقدم أولاً' — the label states the CURRENT
/// order (web contract); tapping flips it.
class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.english,
    required this.sortDesc,
    required this.onTap,
  });

  final bool english;
  final bool sortDesc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
        color: HorseTheme.raised.withValues(alpha: .70),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 16, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.swap_vert_rounded,
                    size: 16, color: HorseTheme.muted),
                const SizedBox(width: 8),
                Text(
                  sortDesc
                      ? (english ? 'Newest first' : 'الأحدث أولاً')
                      : (english ? 'Oldest first' : 'الأقدم أولاً'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: HorseTheme.ink,
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

/// Glass pill with two 40px circles — list / grid; active = white/16 fill
/// + gold icon. Persisted through [EpisodesSection.onViewChange].
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({
    required this.english,
    required this.view,
    required this.onViewChange,
  });

  final bool english;
  final String view;
  final ValueChanged<String> onViewChange;

  Widget _segment({
    required IconData icon,
    required String value,
    required String tooltip,
  }) {
    final active = view == value;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: active ? null : () => onViewChange(value),
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? Colors.white.withValues(alpha: .16) : null,
          ),
          child: Icon(
            icon,
            size: 18,
            color: active ? HorseTheme.gold : HorseTheme.muted,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassPillSurface(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _segment(
              icon: Icons.view_list_rounded,
              value: 'list',
              tooltip: english ? 'List view' : 'عرض قائمة',
            ),
            const SizedBox(width: 2),
            _segment(
              icon: Icons.grid_view_rounded,
              value: 'grid',
              tooltip: english ? 'Grid view' : 'عرض شبكة',
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scroller + rows/cards
// ---------------------------------------------------------------------------

class _EpisodeScroller extends StatelessWidget {
  const _EpisodeScroller({
    required this.items,
    required this.view,
    required this.cols,
    required this.gap,
    required this.thumbWidth,
    required this.isWide,
    required this.english,
    required this.backdropUrl,
    required this.blurUnwatched,
    required this.onPlay,
  });

  final List<_EpisodeViewData> items;
  final String view;
  final int cols;
  final double gap;
  final double thumbWidth;
  final bool isWide;
  final bool english;

  /// Series-level backdrop — the last art fallback before the placeholder.
  final String? backdropUrl;
  final bool blurUnwatched;
  final ValueChanged<Map<String, dynamic>> onPlay;

  bool _blurred(_EpisodeViewData item) =>
      blurUnwatched && !item.watched && item.progress <= 0.02;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final scrollable = items.length > 6;
    final listView = ListView.builder(
      shrinkWrap: !scrollable,
      physics:
          scrollable ? null : const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount:
          view == 'grid' ? (items.length + cols - 1) ~/ cols : items.length,
      itemBuilder: (context, index) {
        if (view == 'grid') {
          return Padding(
            padding: EdgeInsetsDirectional.only(bottom: gap),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var k = 0; k < cols; k++) ...[
                  if (k > 0) SizedBox(width: gap),
                  Expanded(
                    child: index * cols + k < items.length
                        ? _EpisodeCard(
                            item: items[index * cols + k],
                            english: english,
                            isWide: isWide,
                            backdropUrl: backdropUrl,
                            blurred: _blurred(items[index * cols + k]),
                            onTap: () => onPlay(items[index * cols + k].video),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          );
        }
        final item = items[index];
        return _EpisodeRow(
          item: item,
          thumbWidth: thumbWidth,
          isWide: isWide,
          english: english,
          backdropUrl: backdropUrl,
          blurred: _blurred(item),
          onTap: () => onPlay(item.video),
        );
      },
    );
    if (!scrollable) return listView;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: viewportHeight * 0.68,
        child: listView,
      ),
    );
  }
}

/// List row: thumbnail at the inline-start (width = [thumbWidth]), text
/// block beside it — title (2 lines), meta line, story (2 lines).
class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.item,
    required this.thumbWidth,
    required this.isWide,
    required this.english,
    required this.backdropUrl,
    required this.blurred,
    required this.onTap,
  });

  final _EpisodeViewData item;
  final double thumbWidth;
  final bool isWide;
  final bool english;
  final String? backdropUrl;
  final bool blurred;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: thumbWidth,
            child: EpisodeThumbnail(
              url: (item.video['thumbnail'] ??
                      item.video['thumb'] ??
                      backdropUrl ??
                      '')
                  .toString(),
              episodeNumber: item.epNum,
              watched: item.watched,
              progress: item.progress,
              rating: item.rating,
              blurred: blurred,
              watchedLabel: english ? 'Watched' : 'تمت المشاهدة',
            ),
          ),
          SizedBox(width: isWide ? 16 : 12),
          Expanded(
            child: _EpisodeTextBlock(item: item, isWide: isWide, english: english),
          ),
        ],
      ),
    );
    if (item.upcoming) {
      // Future episode: dimmed, desaturated and NOT playable.
      content = Opacity(
        opacity: 0.5,
        child: ColorFiltered(
          colorFilter: _saturate(0.5),
          child: content,
        ),
      );
      return content;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: content,
    );
  }
}

/// Grid card: 16:9 thumbnail on top, then title/meta/story below
/// (no card background — the web card matches target image 1).
class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    required this.item,
    required this.english,
    required this.isWide,
    required this.backdropUrl,
    required this.blurred,
    required this.onTap,
  });

  final _EpisodeViewData item;
  final bool english;
  final bool isWide;
  final String? backdropUrl;
  final bool blurred;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EpisodeThumbnail(
          url: (item.video['thumbnail'] ??
                  item.video['thumb'] ??
                  backdropUrl ??
                  '')
              .toString(),
          episodeNumber: item.epNum,
          watched: item.watched,
          progress: item.progress,
          rating: item.rating,
          blurred: blurred,
          watchedLabel: english ? 'Watched' : 'تمت المشاهدة',
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 2),
          child: _EpisodeTextBlock(item: item, isWide: isWide, english: english),
        ),
      ],
    );
    if (item.upcoming) {
      content = Opacity(
        opacity: 0.5,
        child: ColorFiltered(
          colorFilter: _saturate(0.5),
          child: content,
        ),
      );
      return content;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: content,
    );
  }
}

/// Title (max 2 lines) + meta line (E{n} · runtime · air date) + story
/// (max 2 lines) + the Upcoming chip when future-dated.
class _EpisodeTextBlock extends StatelessWidget {
  const _EpisodeTextBlock({
    required this.item,
    required this.isWide,
    required this.english,
  });

  final _EpisodeViewData item;
  final bool isWide;
  final bool english;

  @override
  Widget build(BuildContext context) {
    final metaStyle = TextStyle(
      fontSize: 12,
      height: 1.35,
      color: HorseTheme.muted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final parts = <Widget>[
      Directionality(
        textDirection: TextDirection.ltr,
        child: Text(
          'E${item.epNum}',
          style: metaStyle.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    ];
    if (item.runtimeMin != null) {
      parts.add(Text('·', style: metaStyle));
      parts.add(Text(
        english ? '${item.runtimeMin} min' : '${item.runtimeMin} دقيقة',
        style: metaStyle,
      ));
    }
    final released = formatEpisodeDate(
      item.video['released']?.toString(),
    );
    if (released.isNotEmpty) {
      parts.add(Text('·', style: metaStyle));
      parts.add(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(released, style: metaStyle),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: isWide ? 16 : 15,
            fontWeight: FontWeight.w600,
            height: 1.25,
            color: HorseTheme.ink,
          ),
        ),
        if (parts.length > 1) ...[
          const SizedBox(height: 5),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: parts,
          ),
        ] else
          const SizedBox(height: 5),
        if (item.story.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            item.story,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: isWide ? 14 : 13,
              height: 1.35,
              color: HorseTheme.muted,
            ),
          ),
        ],
        if (item.upcoming) ...[
          const SizedBox(height: 8),
          Container(
            padding:
                const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: HorseTheme.line),
              color: HorseTheme.raised,
            ),
            child: Text(
              english ? 'Upcoming' : 'لم تُعرض بعد',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: HorseTheme.muted,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Thumbnail
// ---------------------------------------------------------------------------

/// 16:9 episode art with the web overlay kit. The spoiler blur wraps the ART
/// ONLY — the overlays are siblings outside the filtered subtree and stay
/// sharp (the web contract).
class EpisodeThumbnail extends StatelessWidget {
  const EpisodeThumbnail({
    super.key,
    required this.url,
    required this.episodeNumber,
    required this.watched,
    required this.progress,
    required this.watchedLabel,
    this.rating,
    this.blurred = false,
  });

  /// Resolved art URL (thumbnail → thumb → series background); empty = the
  /// gradient placeholder carrying the episode number.
  final String url;
  final int episodeNumber;
  final bool watched;
  final double progress;
  final String watchedLabel;
  final double? rating;
  final bool blurred;

  @override
  Widget build(BuildContext context) {
    final hasUrl = url.isNotEmpty;
    Widget art;
    if (!hasUrl) {
      art = _placeholder();
    } else {
      art = Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(
            child: ShimmerBox(borderRadius: BorderRadius.zero),
          ),
          Positioned.fill(
            child: Image.network(
              url,
              fit: BoxFit.cover,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded) return child;
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  child: child,
                );
              },
              errorBuilder: (_, __, ___) => _placeholder(),
            ),
          ),
        ],
      );
      if (blurred) {
        art = ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Transform.scale(
            scale: 1.14,
            child: ColorFiltered(
              colorFilter: _saturate(1.1),
              child: art,
            ),
          ),
        );
      }
    }

    final showProgress = !watched && progress > 0.02 && progress < kEpisodeWatchedThreshold;
    final showRating = rating != null && rating! > 0;
    final endRadius = const BorderRadiusDirectional.horizontal(
      end: Radius.circular(3),
    ).resolve(Directionality.of(context));

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: HorseTheme.raised, child: art)),
            // Legibility scrim for the bottom overlay row.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 40,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: .55),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // E{n} pill — top inline-end.
            PositionedDirectional(
              top: 6,
              end: 6,
              child: _OverlayPill(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    'E$episodeNumber',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: Colors.white,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
            if (watched)
              PositionedDirectional(
                bottom: 6,
                start: 6,
                child: _OverlayPill(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_rounded,
                          size: 12, color: _kWatchedGreen),
                      const SizedBox(width: 4),
                      Text(
                        watchedLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (showRating)
              PositionedDirectional(
                bottom: 6,
                end: 6,
                child: _OverlayPill(
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: _kImdbYellow,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'IMDb',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              height: 1.2,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          rating!.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                            color: Colors.white,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (showProgress)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 3,
                  color: Colors.black.withValues(alpha: .35),
                  alignment: AlignmentDirectional.centerStart,
                  child: FractionallySizedBox(
                    widthFactor: progress.clamp(0.0, 1.0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _kProgressBarRed,
                        borderRadius: endRadius,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, // CSS 135deg → top-left→bottom-right
          end: Alignment.bottomRight,
          colors: [HorseTheme.raised, HorseTheme.line],
        ),
      ),
      child: Center(
        child: Text(
          '$episodeNumber',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            color: HorseTheme.muted.withValues(alpha: .70),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// rgba(8,8,10,.72) rounded-full overlay pill with the web's soft shadow.
class _OverlayPill extends StatelessWidget {
  const _OverlayPill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _kOverlayBg,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .4),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }
}
