import 'media_item.dart';

/// A continue-watching / catalog entry sourced from a linked tracking
/// service instead of local playback history:
///  - Trakt: paused-playback points (`/users/me/playback`),
///  - AniList: MediaListCollection entries (CURRENT for continue-watching,
///    PLANNING for the watchlist rail),
///  - MyAnimeList: `users/@me/animelist` rows.
///
/// The home page renders these with the exact Harbor-web continue-watching
/// card spec plus a small source tag. The factories are pure so the provider
/// payloads can be unit-tested without network access.
class IntegrationCwEntry {
  const IntegrationCwEntry({
    required this.item,
    required this.source,
    this.progress = 0,
    this.season,
    this.episode,
    this.episodesWatched = 0,
    this.episodesTotal,
    this.watchedAt = 0,
  });

  final MediaItem item;

  /// `'trakt' | 'anilist' | 'mal'`.
  final String source;

  /// 0..1 playback progress when the provider reports one (Trakt pause
  /// percentage, anime episode fraction). Zero hides the progress bar.
  final double progress;

  final int? season;
  final int? episode;

  /// Anime trackers: how many episodes the provider says were watched.
  final int episodesWatched;
  final int? episodesTotal;

  /// Epoch milliseconds (Trakt paused_at / AniList updatedAt arrive in
  /// seconds and are normalized).
  final int watchedAt;

  /// Continue-watching eligibility: the provider must report actual
  /// in-progress state (a paused point, or at least one watched episode).
  bool get isContinueable => progress > 0.005 || episodesWatched >= 1;

  /// Next episode to continue from on the anime trackers (null for Trakt,
  /// which carries its own season/episode position).
  int? get nextEpisode => episodesWatched > 0 ? episodesWatched + 1 : null;

  // ---------------------------------------------------------------------------
  // Trakt — raw /users/me/playback row
  // `{progress: 42.5, paused_at: <epoch s>, type: 'movie'|'episode',
  //   movie: {ids: {imdb}, title, year} | show + episode: {season, number}}`
  // ---------------------------------------------------------------------------

  static IntegrationCwEntry? fromTraktPlayback(Object? raw) {
    final entry = _asMap(raw);
    if (entry == null) return null;
    final percent = (entry['progress'] as num?)?.toDouble() ?? 0;
    // Below 1% is not meaningfully started; at ~95% the movie/episode is
    // effectively finished and Trakt itself drops it after the scrobble.
    if (percent < 1 || percent >= 95) return null;
    if (entry['type'] == 'movie') {
      final movie = _asMap(entry['movie']);
      final imdb = _asMap(movie?['ids'])?['imdb']?.toString();
      final title = movie?['title']?.toString();
      if (imdb == null || imdb.isEmpty) return null;
      if (title == null || title.isEmpty) return null;
      return IntegrationCwEntry(
        source: 'trakt',
        progress: (percent / 100).clamp(0.0, 1.0),
        watchedAt: _epochToMillis(entry['paused_at']),
        item: MediaItem(
          id: imdb,
          type: 'movie',
          name: title,
          releaseInfo: movie?['year']?.toString(),
        ),
      );
    }
    if (entry['type'] == 'episode') {
      final show = _asMap(entry['show']);
      final episodeRow = _asMap(entry['episode']);
      final imdb = _asMap(show?['ids'])?['imdb']?.toString();
      final title = show?['title']?.toString();
      if (imdb == null || imdb.isEmpty) return null;
      if (title == null || title.isEmpty) return null;
      return IntegrationCwEntry(
        source: 'trakt',
        progress: (percent / 100).clamp(0.0, 1.0),
        season: (episodeRow?['season'] as num?)?.toInt(),
        episode: (episodeRow?['number'] as num?)?.toInt(),
        watchedAt: _epochToMillis(entry['paused_at']),
        item: MediaItem(
          id: imdb,
          type: 'series',
          name: title,
          releaseInfo: show?['year']?.toString(),
        ),
      );
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // AniList — raw MediaListCollection entry
  // `{status, progress, updatedAt, media: {id, idMal, title{}, coverImage{},
  //   format, episodes, seasonYear}}`
  // ---------------------------------------------------------------------------

  /// [statusFilter] pins the provider list status (`'CURRENT'` for the
  /// continue-watching cards, `'PLANNING'` for the watchlist rail); null
  /// accepts any status.
  static IntegrationCwEntry? fromAniListRow(
    Object? raw, {
    String? statusFilter,
  }) {
    final entry = _asMap(raw);
    if (entry == null) return null;
    final status = entry['status']?.toString();
    if (statusFilter != null && status != statusFilter) return null;
    final media = _asMap(entry['media']);
    final mediaId = (media?['id'] as num?)?.toInt();
    if (mediaId == null) return null;
    final format = media?['format']?.toString().toUpperCase() ?? '';
    const seriesFormats = {'TV', 'TV_SHORT', 'OVA', 'ONA', 'SPECIAL'};
    final type = format == 'MOVIE'
        ? 'movie'
        : seriesFormats.contains(format)
            ? 'series'
            : null;
    if (type == null) return null;
    final title = _asMap(media?['title']);
    final name =
        (title?['english'] ?? title?['romaji'] ?? title?['native'])?.toString();
    if (name == null || name.isEmpty) return null;
    final watched = (entry['progress'] as num?)?.toInt() ?? 0;
    final total = (media?['episodes'] as num?)?.toInt();
    final coverImage = _asMap(media?['coverImage']);
    final cover = coverImage?['large']?.toString();
    final idMal = (media?['idMal'] as num?)?.toInt();
    return IntegrationCwEntry(
      source: 'anilist',
      progress: total != null && total > 0 && watched > 0
          ? (watched / total).clamp(0.0, 1.0)
          : 0,
      episodesWatched: watched,
      episodesTotal: total,
      watchedAt: _epochToMillis(entry['updatedAt']),
      item: MediaItem(
        id: 'anilist:$mediaId',
        type: type,
        name: name,
        poster: cover == null || cover.isEmpty ? null : cover,
        releaseInfo: media?['seasonYear']?.toString(),
        anilistId: mediaId,
        idMal: idMal,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MyAnimeList — raw animelist row
  // `{id, title, main_picture{large}, start_season{year}, media_type,
  //   list_status{num_episodes_watched, updated_at}}`
  // ---------------------------------------------------------------------------

  static IntegrationCwEntry? fromMalRow(Object? raw) {
    final node = _asMap(raw);
    final malId = (node?['id'] as num?)?.toInt();
    final name = node?['title']?.toString();
    if (malId == null) return null;
    if (name == null || name.isEmpty) return null;
    final isMovie = node?['media_type']?.toString().toLowerCase() == 'movie';
    final status = _asMap(node?['list_status']);
    final watched = (status?['num_episodes_watched'] as num?)?.toInt() ?? 0;
    final poster = _asMap(node?['main_picture'])?['large']?.toString();
    final updatedAt =
        DateTime.tryParse(status?['updated_at']?.toString() ?? '');
    return IntegrationCwEntry(
      source: 'mal',
      episodesWatched: watched,
      watchedAt: updatedAt?.millisecondsSinceEpoch ?? 0,
      item: MediaItem(
        id: 'mal:$malId',
        type: isMovie ? 'movie' : 'series',
        name: name,
        poster: poster == null || poster.isEmpty ? null : poster,
        releaseInfo: _asMap(node?['start_season'])?['year']?.toString(),
        idMal: malId,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Merging / rail helpers
  // ---------------------------------------------------------------------------

  /// Flattens provider groups, newest first, one entry per source+item,
  /// capped at [limit]. Local cards keep priority in the rail, so duplicates
  /// between linked services are collapsed here.
  static List<IntegrationCwEntry> merge(
    Iterable<Iterable<IntegrationCwEntry>> groups, {
    int limit = 12,
  }) {
    final sorted = groups.expand((group) => group).toList()
      ..sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
    final seen = <String>{};
    final result = <IntegrationCwEntry>[];
    for (final entry in sorted) {
      if (result.length >= limit) break;
      if (!seen.add('${entry.source}|${entry.item.id}')) continue;
      result.add(entry);
    }
    return result;
  }

  /// Maps a Trakt/Simkl watchlist sync row
  /// (`{type, imdb|id, title|name, year}`) into a rail item. Returns null
  /// when no usable identity is present.
  static MediaItem? watchlistItemFromRow(Object? raw) {
    final row = _asMap(raw);
    final id = (row?['imdb'] ?? row?['id'])?.toString() ?? '';
    final name = (row?['title'] ?? row?['name'])?.toString() ?? '';
    if (id.isEmpty || name.isEmpty) return null;
    final type = row?['type']?.toString() == 'series' ? 'series' : 'movie';
    return MediaItem(
      id: id,
      type: type,
      name: name,
      releaseInfo: row?['year']?.toString(),
    );
  }

  static Map<String, dynamic>? _asMap(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  /// Accepts epoch seconds or milliseconds (AniList `updatedAt` and Trakt
  /// `paused_at` are seconds; app timestamps are milliseconds).
  static int _epochToMillis(Object? value) {
    final number = (value as num?)?.toInt() ?? 0;
    if (number <= 0) return 0;
    return number < 100000000000 ? number * 1000 : number;
  }
}
