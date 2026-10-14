import 'media_item.dart';

class AnimeAiring {
  const AnimeAiring({
    required this.airingAt,
    required this.episode,
    required this.media,
  });

  final DateTime airingAt;
  final int episode;
  final MediaItem media;
}
