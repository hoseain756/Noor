class MediaItem {
  const MediaItem({
    required this.id,
    required this.type,
    required this.name,
    this.logo,
    this.poster,
    this.background,
    this.description,
    this.releaseInfo,
    this.rating,
    this.certification,
    this.originCountry,
    this.genres = const [],
    this.videos = const [],
  });

  final String id;
  final String type;
  final String name;
  final String? logo;
  final String? poster;
  final String? background;
  final String? description;
  final String? releaseInfo;
  final String? rating;
  final String? certification;
  final String? originCountry;
  final List<String> genres;
  final List<Map<String, dynamic>> videos;

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? 'movie').toString(),
      name: (json['name'] ?? json['title'] ?? 'Untitled').toString(),
      logo: _string(json['logo']),
      poster: _string(json['poster']),
      background: _string(json['background']),
      description: _string(json['description']),
      releaseInfo: _string(json['releaseInfo']),
      rating: _string(json['imdbRating']),
      certification: _firstString([
        json['certification'],
        json['contentRating'],
        json['ageRating'],
      ]),
      originCountry: _country(json),
      genres: (json['genres'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      videos: (json['videos'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'name': name,
        if (logo != null) 'logo': logo,
        if (poster != null) 'poster': poster,
        if (background != null) 'background': background,
        if (description != null) 'description': description,
        if (releaseInfo != null) 'releaseInfo': releaseInfo,
        if (rating != null) 'imdbRating': rating,
        if (certification != null) 'certification': certification,
        if (originCountry != null) 'originCountry': originCountry,
        'genres': genres,
        'videos': videos,
      };

  static String? _string(dynamic value) =>
      value is String && value.isNotEmpty ? value : null;

  static String? _firstString(List<dynamic> values) {
    for (final value in values) {
      final parsed = _string(value);
      if (parsed != null) return parsed;
      if (value is num) return value.toString();
    }
    return null;
  }

  static String? _country(Map<String, dynamic> json) {
    final value = json['originCountry'] ??
        json['country'] ??
        json['countryOfOrigin'] ??
        json['countries'];
    if (value is List) {
      final names = value
          .map((entry) => entry is Map ? entry['name'] : entry)
          .whereType<String>()
          .where((entry) => entry.isNotEmpty)
          .toList();
      return names.isEmpty ? null : names.join(', ');
    }
    if (value is Map) return _string(value['name'] ?? value['iso_3166_1']);
    return _string(value);
  }
}

class WatchHistoryEntry {
  const WatchHistoryEntry({
    required this.item,
    required this.watchedAt,
    this.positionMs = 0,
    this.durationMs = 0,
    this.videoId,
    this.season,
    this.episode,
  });

  final MediaItem item;
  final int watchedAt;
  final int positionMs;
  final int durationMs;
  final String? videoId;
  final int? season;
  final int? episode;

  factory WatchHistoryEntry.fromJson(Map<String, dynamic> json) =>
      WatchHistoryEntry(
        item: MediaItem.fromJson(json),
        watchedAt: (json['t'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
        positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        videoId: json['videoId'] as String?,
        season: (json['season'] as num?)?.toInt(),
        episode: (json['episode'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        ...item.toJson(),
        't': watchedAt,
        'positionMs': positionMs,
        'durationMs': durationMs,
        if (videoId != null) 'videoId': videoId,
        if (season != null) 'season': season,
        if (episode != null) 'episode': episode,
      };
}
