import 'dart:math' as math;

/// Shared OAuth + list-mapping primitives for the anime trackers (AniList and
/// MyAnimeList).
///
/// Both providers redirect back into the app over the app-identifier scheme
/// (`app.noor.mobile://callback?code=…`, see OAuthRedirect in core/oauth);
/// this module owns everything that is pure and therefore unit-testable:
/// authorize-URL builders, the MyAnimeList PLAIN PKCE pair, anime
/// list-status mapping and the per-service score-format conversion.
class TrackLink {
  const TrackLink._();

  /// CSRF echo value carried through the browser round-trip. MyAnimeList
  /// returns it verbatim; AniList's documented flow does not return a state,
  /// so AniList pendings are matched by presence instead.
  static String newState() => _randomChars(43);

  /// MyAnimeList REQUIRES PKCE with the PLAIN transformation
  /// (code_challenge_method=plain → challenge == verifier, 43–128 chars,
  /// unreserved alphabet per RFC 7636 §4.1).
  static String malVerifier() => _randomChars(64);

  static String _randomChars(int length) {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = math.Random.secure();
    return String.fromCharCodes(
      List<int>.generate(
        length,
        (_) => alphabet.codeUnitAt(random.nextInt(alphabet.length)),
      ),
    );
  }

  /// Decides which pending tracker a callback belongs to.
  ///
  ///  - a callback that echoes a `state` belongs to MyAnimeList when the
  ///    stored MAL state matches (equality enforced by the caller);
  ///  - a state-less callback (AniList's documented shape) belongs to the
  ///    AniList flow when one is pending;
  ///  - a state-less callback falls back to a pending MAL flow only when no
  ///    AniList flow is waiting (defensive — MAL always echoes state).
  static String? resolvePendingService({
    required bool anilistPending,
    required bool malPending,
    required bool malStateMatches,
    required bool callbackHasState,
  }) {
    if (callbackHasState) {
      if (malPending && malStateMatches) return 'mal';
      return null;
    }
    if (anilistPending) return 'anilist';
    if (malPending) return 'mal';
    return null;
  }
}

/// Canonical anime watch statuses the app UI exposes; every provider maps to
/// and from these.
enum AnimeTrackStatus { watching, completed, planning, paused, dropped, rewatching }

/// App status → AniList MediaListStatus.
const Map<AnimeTrackStatus, String> kAniListStatus = {
  AnimeTrackStatus.watching: 'CURRENT',
  AnimeTrackStatus.completed: 'COMPLETED',
  AnimeTrackStatus.planning: 'PLANNING',
  AnimeTrackStatus.paused: 'PAUSED',
  AnimeTrackStatus.dropped: 'DROPPED',
  AnimeTrackStatus.rewatching: 'REPEATING',
};

/// App status → MyAnimeList my_list_status.status (rewatching is expressed
/// through the is_rewatching flag, so it maps onto `watching`).
const Map<AnimeTrackStatus, String> kMalStatus = {
  AnimeTrackStatus.watching: 'watching',
  AnimeTrackStatus.completed: 'completed',
  AnimeTrackStatus.planning: 'plan_to_watch',
  AnimeTrackStatus.paused: 'on_hold',
  AnimeTrackStatus.dropped: 'dropped',
  AnimeTrackStatus.rewatching: 'watching',
};

/// Provider raw status → app status for the given service.
AnimeTrackStatus? animeStatusFromProvider(String? service, String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  if (service == 'mal') {
    final lowered = value.toLowerCase();
    for (final entry in kMalStatus.entries) {
      if (entry.value == lowered && entry.key != AnimeTrackStatus.rewatching) {
        return entry.key;
      }
    }
    return null;
  }
  final upper = value.toUpperCase();
  for (final entry in kAniListStatus.entries) {
    if (entry.value == upper) return entry.key;
  }
  return null;
}

/// AniList per-user scoring formats (Viewer.mediaListOptions.scoreFormat).
enum AniListScoreFormat { point100, point10, point5, point3 }

AniListScoreFormat aniListScoreFormatFromName(String? name) {
  switch (name) {
    case 'POINT_10':
      return AniListScoreFormat.point10;
    case 'POINT_5':
      return AniListScoreFormat.point5;
    case 'POINT_3':
      return AniListScoreFormat.point3;
    default:
      return AniListScoreFormat.point100; // AniList default
  }
}

/// Converts the app's 0–10 score into the value AniList expects for the
/// user's scoring format. POINT_3 is the 3-point smiley scale — the nearest
/// step wins (AniList documents no fraction support).
double aniListScoreForFormat(double score10, AniListScoreFormat format) {
  final clamped = score10.clamp(0, 10).toDouble();
  switch (format) {
    case AniListScoreFormat.point100:
      return (clamped * 10).roundToDouble();
    case AniListScoreFormat.point10:
      return clamped.roundToDouble();
    case AniListScoreFormat.point5:
      return (clamped / 2).roundToDouble();
    case AniListScoreFormat.point3:
      return (clamped / 10 * 3).roundToDouble();
  }
}

/// Converts an AniList score (stored in the user's format) back into the
/// app's 0–10 scale.
double score10FromAniList(num? raw, AniListScoreFormat format) {
  if (raw == null) return 0;
  final value = raw.toDouble();
  switch (format) {
    case AniListScoreFormat.point100:
      return (value / 10).clamp(0, 10).toDouble();
    case AniListScoreFormat.point10:
      return value.clamp(0, 10).toDouble();
    case AniListScoreFormat.point5:
      return (value * 2).clamp(0, 10).toDouble();
    case AniListScoreFormat.point3:
      return (value / 3 * 10).clamp(0, 10).toDouble();
  }
}

/// Converts a MyAnimeList score (0–10 integer) back into the app scale.
double score10FromMal(num? raw) =>
    raw == null ? 0 : raw.toDouble().clamp(0, 10).toDouble();

/// Builds the AniList authorize URL (Authorization Code Grant).
/// `redirectUri` must byte-match the developer-dashboard registration.
String aniListAuthorizeUrl({
  required String clientId,
  required String redirectUri,
}) {
  return 'https://anilist.co/api/v2/oauth/authorize'
      '?client_id=${Uri.encodeQueryComponent(clientId)}'
      '&redirect_uri=${Uri.encodeQueryComponent(redirectUri)}'
      '&response_type=code';
}

/// Builds the MyAnimeList authorize URL: PKCE (plain) is REQUIRED, state is
/// strongly recommended, redirect_uri optional but sent byte-for-byte when
/// registered.
String malAuthorizeUrl({
  required String clientId,
  required String redirectUri,
  required String codeVerifier,
  required String state,
}) {
  return 'https://myanimelist.net/v1/oauth2/authorize'
      '?response_type=code'
      '&client_id=${Uri.encodeQueryComponent(clientId)}'
      '&code_challenge=${Uri.encodeQueryComponent(codeVerifier)}'
      '&code_challenge_method=plain'
      '&state=${Uri.encodeQueryComponent(state)}'
      '&redirect_uri=${Uri.encodeQueryComponent(redirectUri)}';
}
