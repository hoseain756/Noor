/// Harbor web → Flutter port — Continue Watching "upcoming episode"
/// enrichment, translated from Harbor web `home-cw.tsx` (`useUpcomingEpisode`,
/// `loadSeriesMeta` cache) and `i18n.ts` (`upcomingLabel` / `daysUntil`).
///
/// Pure logic lives here so it is unit-testable without network or widgets:
///  - [resolveCwUpcoming] decides, for one CW entry, whether the NEXT
///    relevant episode is unaired (badge with the air date) or already aired
///    and unwatched (amber "fresh" dot) — identical decision tree to the web.
///  - [cwUpcomingLabel] renders the badge text with the site's exact strings
///    and Arabic plural categories (اليوم / غداً / يومان / أيام / يوم).
///  - [CwEnrichmentCache] mirrors the web's module-level `seriesMetaCache`:
///    one in-flight/future per series id, fail-soft, so rail rebuilds never
///    re-fetch metadata.
library;

import '../../core/models/media_item.dart';

/// One CW card's enrichment result (web `UpcomingInfo` + episode name).
class CwEnrichment {
  const CwEnrichment({this.nextAirMs, this.fresh = false, this.episodeName});

  /// Next episode airs at this epoch ms → show the "يُعرض بعد…" badge.
  final int? nextAirMs;

  /// The next episode already aired and is unwatched → show the amber dot.
  final bool fresh;

  /// Saved episode's display name from the metadata provider (null → the
  /// card keeps its "الحلقة {n}" fallback).
  final String? episodeName;

  bool get isEmpty => nextAirMs == null && !fresh && episodeName == null;
}

/// Parsed release instant of one Stremio video row (web `Date.parse(released)`).
DateTime? _videoReleased(Map<String, dynamic> video) {
  final raw = video['released'] ?? video['releaseInfo'];
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toUtc();
}

/// Web `useUpcomingEpisode` decision tree as a pure function.
///
/// [videos] is the series' `meta.videos` list; [season]/[episode] identify the
/// saved CW episode; [progress] is the saved fraction (0..1); [watchedVideoIds]
/// holds finished episode ids from history; [now] anchors "unaired".
CwEnrichment resolveCwUpcoming({
  required List<Map<String, dynamic>> videos,
  required int? season,
  required int? episode,
  required double progress,
  required Set<String> watchedVideoIds,
  required DateTime now,
}) {
  if (season == null || episode == null) return const CwEnrichment();
  final sorted = [
    ...videos.where((v) => v['season'] != null && v['episode'] != null),
  ]..sort((a, b) {
      final sa = (a['season'] as num).toInt();
      final sb = (b['season'] as num).toInt();
      if (sa != sb) return sa.compareTo(sb);
      return ((a['episode'] as num).toInt())
          .compareTo((b['episode'] as num).toInt());
    });
  var curIdx = -1;
  for (var i = 0; i < sorted.length; i++) {
    if ((sorted[i]['season'] as num).toInt() == season &&
        (sorted[i]['episode'] as num).toInt() == episode) {
      curIdx = i;
      break;
    }
  }
  if (curIdx < 0) return const CwEnrichment();

  final current = sorted[curIdx];
  final currentId = current['id'] as String?;
  // Web: finished = progress >= 0.92 || watched.has(current.id). The app's
  // CW filter already guarantees < 2 minutes remaining, so progress here is
  // always below the web cutoff — the history check carries the parity.
  final finished = progress >= 0.92 ||
      (currentId != null && watchedVideoIds.contains(currentId));
  final currentName = (current['name'] as String?)?.trim();

  if (!finished) {
    // Mid-episode: badge only when THIS episode hasn't aired yet.
    final rel = _videoReleased(current);
    if (rel != null && rel.isAfter(now)) {
      return CwEnrichment(
        nextAirMs: rel.millisecondsSinceEpoch,
        episodeName: currentName,
      );
    }
    return CwEnrichment(episodeName: currentName);
  }

  if (curIdx + 1 >= sorted.length) {
    return CwEnrichment(episodeName: currentName);
  }
  final next = sorted[curIdx + 1];
  final nextId = next['id'] as String?;
  final nextRel = _videoReleased(next);
  if (nextRel != null && nextRel.isAfter(now)) {
    return CwEnrichment(
      nextAirMs: nextRel.millisecondsSinceEpoch,
      episodeName: currentName,
    );
  }
  final fresh = nextId != null && !watchedVideoIds.contains(nextId);
  return CwEnrichment(
    fresh: fresh,
    episodeName: currentName,
  );
}

/// Web `daysUntil(releasedMs, now)`: ceil of whole days until air time.
int cwDaysUntil(int releasedMs, DateTime now) {
  final delta = releasedMs - now.millisecondsSinceEpoch;
  if (delta <= 0) return 0;
  return (delta / 86400000).ceil();
}

/// Web `upcomingLabel(releasedMs, lang)` — exact site strings:
/// EN "Airs today" / "Airs tomorrow" / "In {n} day(s)";
/// AR "يُعرض اليوم" / "يُعرض غداً" / "يُعرض بعد {n} {unit}" with the site's
/// Arabic day pluralization (يومان for 2, أيام for 3–10, يوم otherwise).
String? cwUpcomingLabel(int? nextAirMs, bool english, DateTime now) {
  if (nextAirMs == null) return null;
  final days = cwDaysUntil(nextAirMs, now);
  if (nextAirMs <= now.millisecondsSinceEpoch) return null;
  if (days == 0) return english ? 'Airs today' : 'يُعرض اليوم';
  if (days == 1) return english ? 'Airs tomorrow' : 'يُعرض غداً';
  if (!english) {
    // Intl.PluralRules('ar') categories: one=1, two=2, few=3–10, many=11+.
    final unit = days == 2 ? 'يومين' : (days >= 3 && days <= 10) ? 'أيام' : 'يوم';
    return 'يُعرض بعد $days $unit';
  }
  final unit = days == 1 ? 'day' : 'days';
  return 'In $days $unit';
}

/// Fail-soft per-series enrichment cache (web `seriesMetaCache`): one shared
/// future per series id — repeated rail rebuilds never re-fetch, and a failed
/// lookup removes itself so a later pass can retry.
class CwEnrichmentCache {
  CwEnrichmentCache(this._loadDetail);

  /// Fetches the series detail (meta.videos) for one item id. Expected to
  /// already swallow network errors and return null on failure.
  final Future<MediaItem?> Function(MediaItem item) _loadDetail;

  final Map<String, Future<CwEnrichment?>> _requests = {};

  /// Bounded concurrency like the web's `enrich: i < 6` — only the first six
  /// visible cards trigger lookups.
  static const int maxEnrichedCards = 6;

  Future<CwEnrichment?> enrichmentFor(
    MediaItem item,
    WatchHistoryEntry entry,
    Set<String> watchedVideoIds,
    DateTime now,
  ) {
    final existing = _requests[item.id];
    if (existing != null) return existing;
    final future = _load(item, entry, watchedVideoIds, now);
    _requests[item.id] = future;
    return future;
  }

  Future<CwEnrichment?> _load(
    MediaItem item,
    WatchHistoryEntry entry,
    Set<String> watchedVideoIds,
    DateTime now,
  ) async {
    try {
      final detail = await _loadDetail(item);
      if (detail == null || detail.videos.isEmpty) return null;
      final progress = entry.durationMs > 0
          ? (entry.positionMs / entry.durationMs).clamp(0.0, 1.0)
          : 0.0;
      return resolveCwUpcoming(
        videos: detail.videos,
        season: entry.season,
        episode: entry.episode,
        progress: progress,
        watchedVideoIds: watchedVideoIds,
        now: now,
      );
    } catch (_) {
      _requests.remove(item.id); // allow a retry on the next rail pass
      return null;
    }
  }
}
