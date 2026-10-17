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

import 'package:noor_mobile/l10n/nova_strings.dart';
import 'package:noor_mobile/shared/widgets/nova_network_image.dart';
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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

const Color _kWatchedGreen = NovaColors.success;
const Color _kProgressBarRed = NovaColors.red;
const Color _kImdbYellow = NovaColors.warning;

ColorFilter _saturate(double s) => ColorFilter.matrix(<double>[
      0.213 + (1 - 0.213) * s, 0.715 * (1 - s), 0.072 * (1 - s), 0, 0, //
      0.213 * (1 - s), 0.715 + (1 - 0.715) * s, 0.072 * (1 - s), 0, 0, //
      0.213 * (1 - s), 0.715 * (1 - s), 0.072 + (1 - 0.072) * s, 0, 0, //
      0, 0, 0, 1, 0,
    ]);

/// One enriched episode item — built once per (season × sort × data) by
/// [EpisodesSection]; the row/card widgets stay pure presenters.
class EpisodeViewData {
  EpisodeViewData({
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

  static EpisodeViewData from(
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
    return EpisodeViewData(
      video: video,
      season: season,
      epNum: epNum,
      title: rawTitle.isNotEmpty
          ? rawTitle
          : (NovaStrings.lookup(english, 'message44', {'p0': epNum})),
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

class SeasonOption {
  const SeasonOption({
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

/// Owns the episodes subsystem state (season/sort/view) so toggling NEVER
/// round-trips through AppState (Task 118 perf fix: the old path called
/// app.setSetting on every view toggle, which rebuilt the whole detail page
/// AND the offstage shell before the frame). The page listens to this
/// controller and rebuilds only the slivers.
class EpisodesController extends ChangeNotifier {
  EpisodesController({
    required MediaItem item,
    required List<WatchHistoryEntry> entries,
    required String savedView,
  })  : _item = item,
        _entries = entries,
        _savedView = savedView {
    _rebuild();
  }

  MediaItem _item;
  List<WatchHistoryEntry> _entries;
  String _savedView;
  late List<Map<String, dynamic>> _sorted;
  late List<int> _seasons;

  int? pickedSeason;
  bool sortDesc = false;

  /// Local view override ('list' | 'grid'); null = follow savedView/auto.
  String? viewOverride;

  MediaItem get item => _item;
  List<Map<String, dynamic>> get sortedVideos => _sorted;
  List<int> get seasons => _seasons;
  String get savedView => _savedView;

  /// Called by the page on every rebuild with the freshest data. NEVER
  /// notifies (it runs inside build); item identity changes are picked up
  /// silently while season/sort/view survive the refresh.
  void update({
    required MediaItem item,
    required List<WatchHistoryEntry> entries,
    required String savedView,
  }) {
    final itemChanged = !identical(item, _item);
    _item = item;
    _entries = entries;
    if (savedView != _savedView) {
      _savedView = savedView;
      viewOverride = null;
    }
    if (itemChanged) _rebuild();
  }

  void _rebuild() {
    _sorted = sortEpisodes(_item.videos);
    _seasons = <int>{
      for (final video in _sorted)
        if ((video['season'] as num?) != null) (video['season'] as num).toInt(),
    }.toList()
      ..sort();
  }

  int get effectiveSeason {
    if (_seasons.isEmpty) return 0;
    return pickedSeason ??
        _sessionSeason[_item.id] ??
        defaultSeason(
          videos: _sorted,
          history: _entries,
          itemId: _item.id,
          now: DateTime.now(),
        ) ??
        _seasons.first;
  }

  String seasonLabel(int season, bool english) => season == 0
      ? (NovaStrings.lookup(english, 'message161'))
      : (NovaStrings.lookup(english, 'message162', {'p0': season}));

  List<SeasonOption> seasonOptions(bool english) {
    final progressMap = _progressMap();
    return [
      for (final season in _seasons)
        SeasonOption(
          season: season,
          label: seasonLabel(season, english),
          count: _sorted
              .where((v) => (v['season'] as num?)?.toInt() == season)
              .length,
          watched: _sorted
              .where((v) => (v['season'] as num?)?.toInt() == season)
              .where((v) => isEpisodeWatched(progressMap, v, _item.id))
              .length,
        ),
    ];
  }

  List<EpisodeViewData> seasonItems({
    required bool english,
    required bool ratingsEnabled,
  }) {
    final season = effectiveSeason;
    final progressMap = _progressMap();
    final now = DateTime.now();
    final items = [
      for (final video in _sorted)
        if ((video['season'] as num?)?.toInt() == season)
          EpisodeViewData.from(
            video,
            season: season,
            english: english,
            progressMap: progressMap,
            itemId: _item.id,
            now: now,
            ratingsEnabled: ratingsEnabled,
          ),
    ];
    items.sort((a, b) => sortDesc ? b.epNum - a.epNum : a.epNum - b.epNum);
    return items;
  }

  Map<String, EpisodeProgress> _progressMap() => episodeProgressMap(
        entries: _entries,
        itemId: _item.id,
      );

  /// View resolution: local override wins, then the persisted setting
  /// ('list'/'grid'), then auto (phone list / ≥700px grid).
  String resolvedView(bool isWide) =>
      viewOverride ??
      switch (_savedView) {
        'list' => 'list',
        'grid' => 'grid',
        _ => isWide ? 'grid' : 'list',
      };

  void pickSeason(int season) {
    pickedSeason = season;
    _sessionSeason[_item.id] = season;
    notifyListeners();
  }

  void toggleSort() {
    sortDesc = !sortDesc;
    notifyListeners();
  }

  void setView(String view) {
    viewOverride = view;
    notifyListeners();
  }
}

/// The episodes block as SLIVERS of the page's CustomScrollView (Task 118):
/// header + toolbar in a box sliver, then the episodes as a TRUE SliverList.
/// One scroll position for the whole page — scrolling past the end of the
/// list continues the page (the old 68vh nested scroller swallowed the drag
/// at its edge and stranded the user), while SliverList keeps native
/// virtualization for 100+ episode seasons.
List<Widget> buildEpisodeSlivers({
  required EpisodesController controller,
  required bool english,
  required bool isWide,
  required double contentWidth,
  required bool blurUnwatched,
  required bool ratingsEnabled,
  required ValueChanged<String> onViewChange,
  required ValueChanged<Map<String, dynamic>> onPlay,
}) {
  final item = controller.item;
  final videos = controller.sortedVideos;

  final header = Padding(
    padding: const EdgeInsetsDirectional.only(bottom: 12),
    child: Text(
      NovaStrings.lookup(english, 'message43'),
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: HorseTheme.ink,
      ),
    ),
  );

  if (videos.isEmpty || controller.seasons.isEmpty) {
    return [
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            Text(
              NovaStrings.lookup(english, 'message163'),
              style: const TextStyle(fontSize: 14, color: HorseTheme.muted),
            ),
          ],
        ),
      ),
    ];
  }

  final view = controller.resolvedView(isWide);
  final cols = contentWidth < 600
      ? 2
      : contentWidth < 1024
          ? 3
          : contentWidth < 1360
              ? 4
              : 5;
  final gap = contentWidth >= 1360
      ? 20.0
      : contentWidth >= 1024
          ? 18.0
          : contentWidth >= 600
              ? 16.0
              : 12.0;
  final thumbWidth =
      isWide ? 220.0 : (contentWidth * 0.4).clamp(120.0, 168.0).toDouble();

  final seasonControl = controller.seasons.length > 1
      ? _SeasonDropdown(
          key: ValueKey('season-${item.id}'),
          options: controller.seasonOptions(english),
          value: controller.effectiveSeason,
          english: english,
          onChanged: controller.pickSeason,
        )
      : Container(
          height: 48,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            NovaStrings.lookup(english, 'message164', {'p0': videos.length}),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: HorseTheme.muted,
            ),
          ),
        );

  final sortChip = _SortChip(
    english: english,
    sortDesc: controller.sortDesc,
    onTap: controller.toggleSort,
  );
  final viewToggle = _ViewToggle(
    english: english,
    view: view,
    onViewChange: onViewChange,
  );

  // One adjacent row: season · sort · view (user mandate, Task 118). The
  // season pill is CONTENT-SIZED instead of stretched, and the Wrap keeps
  // the trio on a single line on wide canvases, wrapping gracefully when a
  // phone is too narrow.
  final toolbar = Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [seasonControl, sortChip, viewToggle],
  );

  final items = controller.seasonItems(
    english: english,
    ratingsEnabled: ratingsEnabled,
  );
  bool blurred(EpisodeViewData entry) =>
      blurUnwatched && !entry.watched && entry.progress <= 0.02;

  return [
    SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          // RepaintBoundary: the three glass pills' blur layers don't churn
          // when the list scrolls or the hero repaints.
          RepaintBoundary(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 12),
              child: toolbar,
            ),
          ),
        ],
      ),
    ),
    if (items.isEmpty)
      const SliverToBoxAdapter(child: SizedBox.shrink())
    else if (view == 'grid')
      SliverList.builder(
        itemCount: (items.length + cols - 1) ~/ cols,
        itemBuilder: (context, index) => Padding(
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
                          backdropUrl: item.background,
                          blurred: blurred(items[index * cols + k]),
                          onTap: () => onPlay(items[index * cols + k].video),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      )
    else
      SliverList.builder(
        itemCount: items.length,
        itemBuilder: (context, index) => _EpisodeRow(
          item: items[index],
          thumbWidth: thumbWidth,
          isWide: isWide,
          english: english,
          backdropUrl: item.background,
          blurred: blurred(items[index]),
          onTap: () => onPlay(items[index].video),
        ),
      ),
  ];
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

  final List<SeasonOption> options;
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
    final box = _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    setState(() => _open = true);
    int? picked;
    try {
      picked = await showGlassMenu<int>(
        context: context,
        anchor: anchor,
        width: 256,
        maxHeight: (MediaQuery.sizeOf(context).height * 0.6).clamp(0.0, 420.0),
        builder: (close) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final option in widget.options)
              InkWell(
                onTap: () => close(option.season),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: option.season == widget.value
                            ? Icon(LucideIcons.check,
                                size: 16, color: NovaTheme.of(context).gold)
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
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: NovaTheme.of(context).ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(
                                '${option.count} · '
                                '${option.watched}/${option.count}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: NovaTheme.of(context).muted,
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
    final label =
        current?.label ?? (NovaStrings.lookup(widget.english, 'message165'));
    // Content-sized (Task 118): no minWidth forcing the pill to fill the
    // row — the label + chevron set the width, capped at 240dp for very
    // long labels (the web contract is min-w-40, content-sized).
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: NovaTheme.of(context).ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 220),
                      curve: const Cubic(0.2, 0, 0, 1),
                      child: Icon(
                        LucideIcons.chevronDown,
                        size: 20,
                        color: NovaTheme.of(context).muted,
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
/// order (web contract); tapping flips it. Task 120: wears the same
/// GlassPillSurface as its toolbar siblings (season dropdown + view
/// toggle) — the old back-pill glass recipe.
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
    return GlassPillSurface(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 16, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.arrowDownUp,
                      size: 16, color: NovaTheme.of(context).muted),
                  const SizedBox(width: 8),
                  Text(
                    sortDesc
                        ? (NovaStrings.lookup(english, 'message166'))
                        : (NovaStrings.lookup(english, 'message167')),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: NovaTheme.of(context).ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Glass pill with two 40px circles — list / grid; active = white/16 fill
/// + gold icon. The page wires the tap to the EpisodesController + a
/// fire-and-forget settings persist (never a global rebuild).
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({
    required this.english,
    required this.view,
    this.onViewChange,
  });

  final bool english;
  final String view;
  final ValueChanged<String>? onViewChange;

  Widget _segment({
    required IconData icon,
    required String value,
    required String tooltip,
  }) {
    final active = view == value;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: active ? null : () => onViewChange?.call(value),
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
              icon: LucideIcons.list,
              value: 'list',
              tooltip: NovaStrings.lookup(english, 'message168'),
            ),
            const SizedBox(width: 2),
            _segment(
              icon: LucideIcons.layoutGrid,
              value: 'grid',
              tooltip: NovaStrings.lookup(english, 'message169'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rows/cards (built as slivers by [buildEpisodeSlivers])
// ---------------------------------------------------------------------------

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

  final EpisodeViewData item;
  final double thumbWidth;
  final bool isWide;
  final bool english;
  final String? backdropUrl;
  final bool blurred;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final thumbnail = EpisodeThumbnail(
      url: (item.video['thumbnail'] ?? item.video['thumb'] ?? backdropUrl ?? '')
          .toString(),
      episodeNumber: item.epNum,
      watched: item.watched,
      progress: item.progress,
      rating: item.rating,
      blurred: blurred,
      watchedLabel: NovaStrings.lookup(english, 'message98'),
    );
    return Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 16),
        child: Material(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
              onTap: item.upcoming ? null : onTap,
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: LayoutBuilder(builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 320 ||
                        MediaQuery.textScalerOf(context).scale(16) > 24;
                    final text = _EpisodeTextBlock(
                        item: item, isWide: isWide, english: english);
                    if (stacked)
                      return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            thumbnail,
                            const SizedBox(height: 16),
                            text
                          ]);
                    return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                              width: thumbWidth.clamp(
                                  96, constraints.maxWidth * .38),
                              child: thumbnail),
                          const SizedBox(width: 16),
                          Expanded(child: text),
                          if (isWide && !item.upcoming)
                            Padding(
                                padding:
                                    const EdgeInsetsDirectional.only(start: 16),
                                child: Icon(LucideIcons.play,
                                    color: scheme.primary))
                        ]);
                  }))),
        ));
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

  final EpisodeViewData item;
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
          watchedLabel: NovaStrings.lookup(english, 'message98'),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 2),
          child:
              _EpisodeTextBlock(item: item, isWide: isWide, english: english),
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
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(12), child: content)),
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

  final EpisodeViewData item;
  final bool isWide;
  final bool english;

  @override
  Widget build(BuildContext context) {
    final metaStyle = TextStyle(
      fontSize: 12,
      height: 1.5,
      color: NovaTheme.of(context).muted,
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
        NovaStrings.lookup(english, 'message170', {'p0': item.runtimeMin}),
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
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.5,
            color: NovaTheme.of(context).ink,
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
              fontSize: 14,
              height: 1.5,
              color: NovaTheme.of(context).muted,
            ),
          ),
        ],
        if (item.upcoming) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: NovaTheme.of(context).line),
              color: NovaTheme.of(context).raised,
            ),
            child: Text(
              NovaStrings.lookup(english, 'message171'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: NovaTheme.of(context).muted,
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
///
/// Task 118: stateful so the shimmer underlay DIES on the first image frame
/// (the old one animated forever under the loaded image and restarted on
/// every view/season switch), and the network image decodes at the drawn
/// size via cacheWidth instead of holding a full-res texture.
class EpisodeThumbnail extends StatefulWidget {
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
  State<EpisodeThumbnail> createState() => _EpisodeThumbnailState();
}

class _EpisodeThumbnailState extends State<EpisodeThumbnail> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.url.isEmpty) _loaded = true;
  }

  @override
  void didUpdateWidget(EpisodeThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url.isEmpty) _loaded = true;
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
    final hasUrl = widget.url.isNotEmpty;
    Widget art;
    if (!hasUrl) {
      art = _placeholder();
    } else {
      art = Stack(
        fit: StackFit.expand,
        children: [
          if (!_loaded)
            const Positioned.fill(
              child: ShimmerBox(borderRadius: BorderRadius.zero),
            ),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final dpr = MediaQuery.devicePixelRatioOf(context);
                return NovaNetworkImage(
                  widget.url,
                  fit: BoxFit.cover,
                  cacheWidth:
                      (constraints.maxWidth * dpr).round().clamp(1, 4096),
                  frameBuilder:
                      (context, child, frame, wasSynchronouslyLoaded) {
                    if (frame != null || wasSynchronouslyLoaded) {
                      _markLoaded();
                    }
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
                    return _placeholder();
                  },
                );
              },
            ),
          ),
        ],
      );
      if (widget.blurred) {
        // Task 136 (perf): spoiler blur 20 → 10 — every unwatched episode's
        // still paid a 20-sigma gaussian on every paint while the list
        // scrolled; 10 keeps the preview unreadable at half the cost.
        art = ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
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

    final showProgress = !widget.watched &&
        widget.progress > 0.02 &&
        widget.progress < kEpisodeWatchedThreshold;
    final showRating = widget.rating != null && widget.rating! > 0;
    final endRadius = const BorderRadiusDirectional.horizontal(
      end: Radius.circular(3),
    ).resolve(Directionality.of(context));

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          children: [
            Positioned.fill(
                child: ColoredBox(
                    color: NovaTheme.of(context).raised, child: art)),
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
                    'E${widget.episodeNumber}',
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
            if (widget.watched)
              PositionedDirectional(
                bottom: 6,
                start: 6,
                child: _OverlayPill(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.check,
                          size: 12, color: _kWatchedGreen),
                      const SizedBox(width: 4),
                      Text(
                        widget.watchedLabel,
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
                          widget.rating!.toStringAsFixed(1),
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
                    widthFactor: widget.progress.clamp(0.0, 1.0),
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
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, // CSS 135deg → top-left→bottom-right
          end: Alignment.bottomRight,
          colors: [NovaTheme.of(context).raised, NovaTheme.of(context).line],
        ),
      ),
      child: Center(
        child: Text(
          '${widget.episodeNumber}',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            color: NovaTheme.of(context).muted.withValues(alpha: .70),
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
