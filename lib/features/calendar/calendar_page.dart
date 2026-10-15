import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/anime_airing.dart';
import '../../core/models/media_item.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';
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
  int _weekOffset = 0;
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
            'name': 'Episode ${airing.episode}',
          },
          released: airing.airingAt,
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
            content: Text(english
                ? 'No playable catalog entry was found for this anime.'
                : 'لم يُعثر على عنوان قابل للتشغيل لهذا الأنمي.'),
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
    final app = context.watch<AppState>();
    final english = app.english;
    final start = _weekStart;
    final end = start.add(const Duration(days: 6));
    return Scaffold(
      appBar: AppBar(
        title: Text(english ? 'Calendar' : 'التقويم'),
        actions: [
          IconButton(
            tooltip: english ? 'Refresh' : 'تحديث',
            onPressed: _retry,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 14),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: english ? 'Previous week' : 'الأسبوع السابق',
                      onPressed: () => _moveWeek(-1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Text(
                        '${_formatDate(start, english)} – ${_formatDate(end, english)}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: english ? 'Next week' : 'الأسبوع التالي',
                      onPressed: () => _moveWeek(1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<List<_CalendarEpisode>>(
                  future: _episodes,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child:
                            CircularProgressIndicator(color: HorseTheme.gold),
                      );
                    }
                    if (snapshot.hasError) {
                      return AppStateMessage(
                        icon: Icons.calendar_month_outlined,
                        message: english
                            ? 'The calendar could not be loaded.'
                            : 'تعذر تحميل التقويم.',
                        actionLabel: english ? 'Retry' : 'إعادة المحاولة',
                        onAction: _retry,
                      );
                    }
                    final episodes = snapshot.data ?? const [];
                    if (episodes.isEmpty) {
                      return AppStateMessage(
                        icon: Icons.calendar_month_outlined,
                        message: app.watchlist
                                    .any((item) => item.type == 'series') ||
                                app.history
                                    .any((entry) => entry.item.type == 'series')
                            ? (english
                                ? 'No tracked episodes are scheduled this week.'
                                : 'لا توجد حلقات لعناوينك المسجلة هذا الأسبوع.')
                            : (english
                                ? 'Save a series or start watching one to see its new episodes here.'
                                : 'أضف مسلسلًا إلى قائمتك أو ابدأ مشاهدته لعرض حلقاته الجديدة هنا.'),
                        actionLabel: english ? 'Refresh' : 'تحديث',
                        onAction: _retry,
                      );
                    }
                    final grouped = <DateTime, List<_CalendarEpisode>>{};
                    for (final episode in episodes) {
                      final day = DateTime(episode.released.year,
                          episode.released.month, episode.released.day);
                      grouped.putIfAbsent(day, () => []).add(episode);
                    }
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: [
                        for (final entry in grouped.entries) ...[
                          Padding(
                            padding: const EdgeInsetsDirectional.only(
                                top: 12, bottom: 8),
                            child: Text(
                              _formatDay(entry.key, english),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(color: HorseTheme.gold),
                            ),
                          ),
                          for (final episode in entry.value)
                            _EpisodeTile(
                              episode: episode,
                              english: english,
                              onTap: () => _openEpisode(episode),
                            ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
        : (english ? 'Episode ${number ?? ''}' : 'الحلقة ${number ?? ''}');
    final title =
        (episode.video['name'] ?? episode.video['title'] ?? episodeLabel)
            .toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        contentPadding: const EdgeInsetsDirectional.fromSTEB(10, 5, 12, 5),
        leading: SizedBox(
          width: 112,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: still == null
                ? const ColoredBox(
                    color: HorseTheme.raised,
                    child: Icon(Icons.live_tv_rounded))
                : Image.network(still,
                    fit: BoxFit.cover,
                    // Task 136: decode at the 112px list thumbnail size.
                    cacheWidth: imageCacheWidth(context, 112),
                    errorBuilder: (_, __, ___) => const ColoredBox(
                        color: HorseTheme.raised,
                        child: Icon(Icons.live_tv_rounded))),
          ),
        ),
        title: Text(episode.series.name,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('$episodeLabel · $title',
            maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Text(_formatTime(episode.released, english),
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: HorseTheme.gold)),
        onTap: onTap,
      ),
    );
  }
}

DateTime? _releaseDate(dynamic raw) {
  if (raw is! String || raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw.trim());
}

String _formatDate(DateTime date, bool english) =>
    '${date.day} ${_monthName(date.month, english)} ${date.year}';

String _formatDay(DateTime date, bool english) =>
    '${_weekdayName(date.weekday, english)}, ${_formatDate(date, english)}';

String _formatTime(DateTime date, bool english) {
  final minute = date.minute.toString().padLeft(2, '0');
  if (!english) return '${date.hour.toString().padLeft(2, '0')}:$minute';
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  return '$hour:$minute ${date.hour < 12 ? 'AM' : 'PM'}';
}

String _monthName(int month, bool english) => english
    ? const [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ][month - 1]
    : const [
        'يناير',
        'فبراير',
        'مارس',
        'أبريل',
        'مايو',
        'يونيو',
        'يوليو',
        'أغسطس',
        'سبتمبر',
        'أكتوبر',
        'نوفمبر',
        'ديسمبر'
      ][month - 1];

String _weekdayName(int weekday, bool english) => english
    ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1]
    : const [
        'الاثنين',
        'الثلاثاء',
        'الأربعاء',
        'الخميس',
        'الجمعة',
        'السبت',
        'الأحد'
      ][weekday - 1];
