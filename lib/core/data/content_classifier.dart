import '../models/media_item.dart';

abstract final class ContentClassifier {
  static const _unsafeGenres = {
    'adult',
    'action',
    'biography',
    'crime',
    'history',
    'horror',
    'romance',
    'thriller',
    'war',
  };

  static const _childRatings = {
    '0',
    '0+',
    'all',
    'g',
    'pg',
    'tv-g',
    'tv-pg',
    'tv-y',
    'tv-y7',
    'u',
    '6',
    '6+',
    '7',
    '7+',
    '9',
    '9+',
    '10',
    '10+',
    '12',
    '12+',
    'pg-12',
    'g-rated',
  };

  static bool isAnime(MediaItem item) {
    final id = item.id.toLowerCase();
    if (id.startsWith('anilist:') || id.startsWith('mal:')) return true;
    final genres = _genres(item);
    if (genres.contains('anime')) return true;
    return genres.contains('animation') && _isJapanese(item.originCountry);
  }

  static bool isKidSuitable(MediaItem item) {
    if (isAnime(item)) return false;

    final genres = _genres(item);
    if (genres.any(_unsafeGenres.contains)) return false;

    final certification = item.certification?.trim().toLowerCase();
    final hasChildCertification = certification != null &&
        certification.isNotEmpty &&
        _childRatings.contains(certification);
    if (certification != null &&
        certification.isNotEmpty &&
        !hasChildCertification) {
      return false;
    }

    final familyGenre = genres.any(
      (genre) =>
          genre == 'family' ||
          genre == 'kids' ||
          genre == 'kid' ||
          genre == 'children' ||
          genre == "children's",
    );
    if (familyGenre) {
      // Without country metadata, an animated title with no age rating is
      // ambiguous. Fail closed so anime cannot leak into Kids.
      if (genres.contains('animation') && !hasChildCertification) return false;
      return true;
    }

    // Animation can qualify without a Family genre only when its rating
    // explicitly marks it suitable for children.
    return genres.contains('animation') && hasChildCertification;
  }

  static List<String> _genres(MediaItem item) =>
      item.genres.map((genre) => genre.trim().toLowerCase()).toList();

  static bool _isJapanese(String? value) {
    if (value == null) return false;
    return value.split(RegExp(r'[,;/|]')).any((part) {
          final normalized =
              part.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
          return normalized == 'japan' ||
              normalized == 'jp' ||
              normalized == 'jpn';
        }) ||
        value.contains('日本');
  }
}
