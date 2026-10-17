import 'package:nova_mobile/l10n/nova_strings.dart';
import 'package:nova_mobile/shared/widgets/nova_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/anime_airing.dart';
import '../../core/models/media_item.dart';
import '../../core/state/app_state.dart';
import '../shell/nova_browse_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../shared/widgets/app_state_message.dart';
import '../../shared/widgets/image_decode.dart';
import '../media/media_detail_page.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  static final Map<String, Future<List<_CalendarEpisode>>> _cache = {};
  static final Map<String, DateTime> _cachedAt = {};
  int _weekOffset = 0;
  int? _selectedDay;
  late Future<List<_CalendarEpisode>> _episodes;

  @override
  void initState() {
    super.initState();
    _episodes = _load();
  }

  DateTime get _weekStart {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return monday.add(Duration(days: _weekOffset * 7));
  }

  Future<List<_CalendarEpisode>> _load() {
    final app = context.read<AppState>();
    final start = _weekStart;
    final tracked = <String, MediaItem>{};
    for (final item in app.watchlist.where((item) => item.type == 'series')) {
      tracked[item.id] = item;
    }
    for (final entry
        in app.history.where((entry) => entry.item.type == 'series')) {
      tracked.putIfAbsent(entry.item.id, () => entry.item);
    }
    final trackedIds = tracked.keys.toList()..sort();
    final cacheKey =
        '${start.year}-${start.month}-${start.day}|${trackedIds.join(',')}';
    final now = DateTime.now();
    _cache.removeWhere((key, _) =>
        _cachedAt[key] == null ||
        now.difference(_cachedAt[key]!).inMinutes >= 15);
    while (_cache.length >= 12) {
      _cachedAt.remove(_cache.keys.first);
      _cache.remove(_cache.keys.first);
    }
    _cachedAt[cacheKey] = now;
    return _cache.putIfAbsent(cacheKey, () async {
      final end = start.add(const Duration(days: 7));
      final episodes = <_CalendarEpisode>[];
      final entries = tracked.values.take(60).toList();
      final airingFuture = _weekOffset < -1 || _weekOffset > 3
          ? Future.value(const <AnimeAiring>[])
          : app.catalogs
              .animeAiringWeek(start, end)
              .catchError((Object _) => <AnimeAiring>[]);
      for (var offset = 0; offset < entries.length; offset += 8) {
        final batch = entries.skip(offset).take(8);
        final results = await Future.wait(batch.map((entry) async {
          try {
            return await app.catalogs.detail('series', entry.id, app.addons) ??
                entry;
          } catch (_) {
            return entry;
          }
        }));
        for (final series in results) {
          for (final video in series.videos) {
            final released =
                _releaseDate(video['released'] ?? video['releaseInfo']);
            if (released == null ||
                released.isBefore(start) ||
                !released.isBefore(end)) {
              continue;
            }
            episodes.add(_CalendarEpisode(
                series: series, video: video, released: released));
          }
        }
      }
      for (final airing in await airingFuture) {
        episodes.add(_CalendarEpisode(
          series: airing.media,
          video: {
            'id': '${airing.media.id}:episode:${airing.episode}',
            'episode': airing.episode,
          },
          released: airing.airingAt.toLocal(),
        ));
      }
      episodes.sort((a, b) => a.released.compareTo(b.released));
      return episodes;
    });
  }

  Future<void> _openEpisode(_CalendarEpisode episode) async {
    var item = episode.series;
    if (item.id.startsWith('anilist:')) {
      final resolved =
          await context.read<AppState>().catalogs.resolveAnime(item);
      if (!mounted) return;
      if (resolved == null) {
        final english = context.read<AppState>().english;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(NovaStrings.lookup(english, 'message564')),
          ),
        );
        return;
      }
      item = resolved;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaDetailPage(
          item: item,
          resumeVideoId: item.id.startsWith('anilist:')
              ? null
              : episode.video['id']?.toString(),
        ),
      ),
    );
  }

  void _moveWeek(int delta) {
    setState(() {
      _weekOffset += delta;
      _selectedDay = null;
      _episodes = _load();
    });
  }

  void _retry() {
    final prefix = '${_weekStart.year}-${_weekStart.month}-${_weekStart.day}|';
    _cache.removeWhere((key, _) => key.startsWith(prefix));
    setState(() => _episodes = _load());
  }

  @override
  Widget build(BuildContext context) {
    context.select<AppState, bool>((app) => app.english);
    final app = context.read<AppState>();
    final theme = Theme.of(context);
    final local = MaterialLocalizations.of(context);
    final start = _weekStart;
    return Scaffold(
        appBar: AppBar(title: Text(app.tr('message565')), actions: [
          IconButton(
              tooltip: app.tr('message68'),
              onPressed: _retry,
              icon: const Icon(LucideIcons.refreshCw))
        ]),
        body: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: FutureBuilder<List<_CalendarEpisode>>(
              future: _episodes,
              builder: (context, snapshot) {
                final all = snapshot.data ?? const <_CalendarEpisode>[];
                final episodes = all
                    .where((entry) =>
                        _selectedDay == null ||
                        entry.released.weekday == _selectedDay)
                    .toList();
                final sections = <Object>[];
                DateTime? previous;
                for (final episode in episodes) {
                  final day = DateTime(episode.released.year,
                      episode.released.month, episode.released.day);
                  if (day != previous) {
                    sections.add(day);
                    previous = day;
                  }
                  sections.add(episode);
                }
                return CustomScrollView(slivers: [
                  SliverToBoxAdapter(
                      child: NovaBrowseHeader(
                          compact: true,
                          eyebrow: app.tr('message566'),
                          title: app.tr('message567'),
                          subtitle: app.tr('message568'))),
                  SliverToBoxAdapter(
                      child: Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              16, 0, 16, 16),
                          child: Row(children: [
                            IconButton.filledTonal(
                                tooltip: app.tr('message569'),
                                onPressed: () => _moveWeek(-1),
                                icon: Icon(Directionality.of(context) ==
                                        TextDirection.rtl
                                    ? LucideIcons.chevronRight
                                    : LucideIcons.chevronLeft)),
                            Expanded(
                                child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    child: Text(
                                        '${local.formatMediumDate(start)} — ${local.formatMediumDate(start.add(const Duration(days: 6)))}',
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.titleMedium))),
                            IconButton.filledTonal(
                                tooltip: app.tr('message570'),
                                onPressed: () => _moveWeek(1),
                                icon: Icon(Directionality.of(context) ==
                                        TextDirection.rtl
                                    ? LucideIcons.chevronLeft
                                    : LucideIcons.chevronRight)),
                          ]))),
                  SliverToBoxAdapter(
                      child: Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              24, 0, 24, 24),
                          child: Wrap(spacing: 8, runSpacing: 8, children: [
                            ChoiceChip(
                                label: Text(app.tr('message571')),
                                selected: _selectedDay == null,
                                onSelected: (_) =>
                                    setState(() => _selectedDay = null)),
                            for (var i = 0; i < 7; i++)
                              ChoiceChip(
                                  label: Text(local.formatShortDate(
                                      start.add(Duration(days: i)))),
                                  selected: _selectedDay == i + 1,
                                  onSelected: (_) =>
                                      setState(() => _selectedDay = i + 1)),
                            if (_weekOffset != 0)
                              ActionChip(
                                  label: Text(app.tr('message572')),
                                  onPressed: () => _moveWeek(-_weekOffset)),
                          ]))),
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      all.isEmpty)
                    const SliverToBoxAdapter(
                        child: SizedBox(
                            height: 500, child: NovaBrowseSkeleton(rows: true)))
                  else if (snapshot.hasError || episodes.isEmpty)
                    SliverFillRemaining(
                        hasScrollBody: false,
                        child: AppStateMessage(
                            icon: LucideIcons.calendarDays,
                            message: snapshot.hasError
                                ? app.tr('message573')
                                : app.tr('message574'),
                            actionLabel: app.tr('message68'),
                            onAction: _retry))
                  else
                    SliverPadding(
                        padding:
                            const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 48),
                        sliver: SliverList.builder(
                            itemCount: sections.length,
                            itemBuilder: (context, index) {
                              final section = sections[index];
                              if (section is DateTime) {
                                return Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                        top: 16, bottom: 16),
                                    child: Text(local.formatFullDate(section),
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                                color: theme
                                                    .colorScheme.secondary)));
                              }
                              final episode = section as _CalendarEpisode;
                              return _EpisodeTile(
                                  episode: episode,
                                  english: app.english,
                                  onTap: () => _openEpisode(episode));
                            })),
                ]);
              }),
        )));
  }
}

class _CalendarEpisode {
  const _CalendarEpisode(
      {required this.series, required this.video, required this.released});
  final MediaItem series;
  final Map<String, dynamic> video;
  final DateTime released;
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile(
      {required this.episode, required this.english, required this.onTap});
  final _CalendarEpisode episode;
  final bool english;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final still =
        (episode.video['thumbnail'] ?? episode.series.poster)?.toString();
    final season = (episode.video['season'] as num?)?.toInt();
    final number = (episode.video['episode'] as num?)?.toInt();
    final episodeLabel = season != null && number != null
        ? 'S$season E$number'
        : (NovaStrings.lookup(english, 'message44', {'p0': number ?? ''}));
    final title =
        (episode.video['name'] ?? episode.video['title'] ?? episodeLabel)
            .toString();
    final app = context.read<AppState>();
    final theme = Theme.of(context);
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(episode.released),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context));
    return Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 16),
        child: Material(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: LayoutBuilder(builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 500;
                    final art = ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox(
                            width: wide ? 160 : 88,
                            height: wide ? 96 : 112,
                            child: still == null
                                ? ColoredBox(
                                    color: theme
                                        .colorScheme.surfaceContainerHighest,
                                    child: const Icon(LucideIcons.tv))
                                : NovaNetworkImage(still,
                                    fit: BoxFit.cover,
                                    cacheWidth: imageCacheWidth(
                                        context, wide ? 160 : 88),
                                    errorBuilder: (_, __, ___) => ColoredBox(
                                        color: theme.colorScheme
                                            .surfaceContainerHighest,
                                        child: const Icon(LucideIcons.tv)))));
                    return Row(children: [
                      art,
                      const SizedBox(width: 16),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(time,
                                style: theme.textTheme.labelLarge?.copyWith(
                                    color: theme.colorScheme.secondary)),
                            const SizedBox(height: 6),
                            Text(episode.series.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium),
                            const SizedBox(height: 6),
                            Text('$episodeLabel · $title',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall),
                            const SizedBox(height: 6),
                            Text(app.tr('message575'),
                                style: theme.textTheme.labelMedium),
                          ])),
                      if (wide) ...[
                        const SizedBox(width: 16),
                        const Icon(LucideIcons.play, size: 24)
                      ],
                    ]);
                  })),
            )));
  }
}

DateTime? _releaseDate(dynamic raw) {
  if (raw is! String || raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw.trim())?.toLocal();
}
