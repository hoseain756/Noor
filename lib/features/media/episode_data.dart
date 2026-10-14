/// Pure (widget-free) data helpers behind the detail page's episodes system —
/// a 1:1 port of the Harbor web `EpisodesSection` data layer:
///   · canonical (season, episode) ordering
///   · the per-episode progress map derived from watch history
///     (keyed by BOTH the video id and the `{itemId}:{s}:{e}` composite)
///   · the watched threshold (0.85, matching the web `WATCHED_THRESHOLD`)
///   · upcoming-episode detection (future air date)
///   · the default-season heuristic (in-progress season → first unwatched
///     with regular seasons ascending and specials LAST → first season)
///   · runtime/date string parsing ("23min", "58 min", "1h 52m")
/// Kept free of Flutter imports so it stays unit-testable.
library;

import '../../core/models/media_item.dart' show WatchHistoryEntry;

/// Progress at/above which an episode counts as watched (web: 0.85).
const double kEpisodeWatchedThreshold = 0.85;

/// Playback position for one episode, with the 0..1 progress derived from it.
class EpisodeProgress {
  const EpisodeProgress({required this.positionMs, required this.durationMs});

  final int positionMs;
  final int durationMs;

  double get progress =>
      durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0).toDouble() : 0.0;
}

/// Canonical episode order: season ascending, then episode ascending.
/// Returns a new list; the input is never mutated. Every consumer of
/// `item.videos` on the detail page must go through this (the web sort is
/// identical, and the old Flutter `_nextEpisode` bug came from skipping it).
List<Map<String, dynamic>> sortEpisodes(List<Map<String, dynamic>> videos) {
  final sorted = [...videos];
  int key(Map<String, dynamic> video, String field) =>
      (video[field] as num?)?.toInt() ?? 0;
  sorted.sort((a, b) {
    final season = key(a, 'season').compareTo(key(b, 'season'));
    if (season != 0) return season;
    return key(a, 'episode').compareTo(key(b, 'episode'));
  });
  return sorted;
}

/// Newest-wins progress map for one title, keyed by BOTH the video id and
/// the `{itemId}:{season}:{episode}` composite (the web `episodeProgressMap`
/// + watched-set pair collapsed into one map). [entries] must already be
/// filtered to the title; ordering inside is handled here.
Map<String, EpisodeProgress> episodeProgressMap({
  required List<WatchHistoryEntry> entries,
  String? itemId,
}) {
  final ordered = [...entries]..sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
  final map = <String, EpisodeProgress>{};
  for (final entry in ordered) {
    final progress = EpisodeProgress(
      positionMs: entry.positionMs,
      durationMs: entry.durationMs,
    );
    final videoId = entry.videoId;
    if (videoId != null && videoId.isNotEmpty) {
      map.putIfAbsent(videoId, () => progress);
    }
    final season = entry.season;
    final episode = entry.episode;
    if (itemId != null && itemId.isNotEmpty && season != null && episode != null) {
      map.putIfAbsent('$itemId:$season:$episode', () => progress);
    }
  }
  return map;
}

/// Progress for one video: the video-id key first, then the composite key.
EpisodeProgress? progressForVideo(
  Map<String, EpisodeProgress> map,
  Map<String, dynamic> video,
  String itemId,
) {
  final videoId = video['id']?.toString();
  if (videoId != null && videoId.isNotEmpty) {
    final direct = map[videoId];
    if (direct != null) return direct;
  }
  final season = (video['season'] as num?)?.toInt();
  final episode = (video['episode'] as num?)?.toInt();
  if (season == null || episode == null) return null;
  return map['$itemId:$season:$episode'];
}

/// Watched = progress at/above the threshold under either key form.
bool isEpisodeWatched(
  Map<String, EpisodeProgress> map,
  Map<String, dynamic> video,
  String itemId,
) =>
    (progressForVideo(map, video, itemId)?.progress ?? 0) >=
    kEpisodeWatchedThreshold;

/// Future-dated episode (air date parses and lies after [now]).
bool isUpcomingEpisode(Map<String, dynamic> video, DateTime now) {
  final released = video['released']?.toString();
  if (released == null || released.isEmpty) return false;
  final date = DateTime.tryParse(released);
  return date != null && date.isAfter(now);
}

/// The season the episodes section opens on:
///  1. the latest history entry's season while it is still in progress,
///  2. else the season of the first unwatched episode, scanning regular
///     seasons ascending with specials (season 0) LAST — a fresh user lands
///     on Season 1, not Specials,
///  3. else the first regular season (or the only season there is).
int? defaultSeason({
  required List<Map<String, dynamic>> videos,
  List<WatchHistoryEntry> history = const [],
  String? itemId,
  DateTime? now,
}) {
  if (videos.isEmpty) return null;
  final seasons = <int>{
    for (final video in videos)
      if ((video['season'] as num?) != null) (video['season'] as num).toInt(),
  };
  if (seasons.isEmpty) return null;

  // 1) Continue-watching season.
  final entries = [...history]..sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
  for (final entry in entries) {
    final season = entry.season;
    if (season == null || !seasons.contains(season)) continue;
    final progress = EpisodeProgress(
      positionMs: entry.positionMs,
      durationMs: entry.durationMs,
    ).progress;
    if (progress < kEpisodeWatchedThreshold) return season;
    break; // the newest episode-level entry is finished → ignore history
  }

  // 2) First season with something unwatched (specials last).
  final regular = seasons.where((season) => season > 0).toList()..sort();
  final orderedSeasons = [...regular, if (seasons.contains(0)) 0];
  final orderIndex = <int, int>{
    for (var i = 0; i < orderedSeasons.length; i++) orderedSeasons[i]: i,
  };
  final map = episodeProgressMap(entries: history, itemId: itemId);
  final withSeason = [
    for (final video in videos)
      if ((video['season'] as num?) != null) video,
  ]..sort((a, b) {
      final oa = orderIndex[(a['season'] as num).toInt()] ?? 99;
      final ob = orderIndex[(b['season'] as num).toInt()] ?? 99;
      if (oa != ob) return oa.compareTo(ob);
      final ea = (a['episode'] as num?)?.toInt() ?? 0;
      final eb = (b['episode'] as num?)?.toInt() ?? 0;
      return ea.compareTo(eb);
    });
  for (final video in withSeason) {
    if (!isEpisodeWatched(map, video, itemId ?? '')) {
      return (video['season'] as num).toInt();
    }
  }

  // 3) Everything watched → first regular season (else the very first).
  return orderedSeasons.first;
}

/// Stremio addon runtime strings are latin ("23min", "58 min", "1h 52m");
/// normalize to whole minutes (null when nothing parseable and positive).
int? parseRuntimeMinutes(String? raw) {
  if (raw == null) return null;
  final text = raw.trim().toLowerCase();
  if (text.isEmpty) return null;
  var total = 0;
  var matched = false;
  final hours = RegExp(r'(\d+)\s*(?:h|hr|hrs|hours?)\b').firstMatch(text);
  final minutes =
      RegExp(r'(\d+)\s*(?:m|min|mins|minutes?)\b').firstMatch(text);
  if (hours != null) {
    total += int.parse(hours.group(1)!) * 60;
    matched = true;
  }
  if (minutes != null) {
    total += int.parse(minutes.group(1)!);
    matched = true;
  }
  if (!matched) {
    final bare = RegExp(r'^(\d+)$').firstMatch(text);
    if (bare == null) return null;
    total = int.parse(bare.group(1)!);
  }
  return total > 0 ? total : null;
}

const List<String> _monthAbbreviations = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "12 Mar 2024" — English month abbreviation, LATIN digits in every locale
/// (the web formats with `ar-u-nu-latn`; plain Dart interpolation is latin by
/// definition). Empty string when the date does not parse.
String formatEpisodeDate(String? iso) {
  if (iso == null) return '';
  final trimmed = iso.trim();
  if (trimmed.isEmpty) return '';
  final date = DateTime.tryParse(trimmed);
  if (date == null) return '';
  return '${date.day} ${_monthAbbreviations[date.month - 1]} ${date.year}';
}
