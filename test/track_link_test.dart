import 'package:flutter_test/flutter_test.dart';
import 'package:noor_mobile/core/track/track_link.dart';

void main() {
  group('TrackLink', () {
    test('newState is 43 chars inside the RFC 7636 alphabet', () {
      final state = TrackLink.newState();
      expect(state.length, 43);
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(state), isTrue);
    });

    test('malVerifier is 64 chars — valid plain PKCE verifier', () {
      final verifier = TrackLink.malVerifier();
      // MAL requires 43-128 chars, unreserved alphabet, plain method.
      expect(verifier.length, inInclusiveRange(43, 128));
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(verifier), isTrue);
    });

    test('resolvePendingService routes stateful callbacks to MAL only on match',
        () {
      expect(
        TrackLink.resolvePendingService(
          anilistPending: true,
          malPending: true,
          malStateMatches: true,
          callbackHasState: true,
        ),
        'mal',
      );
      expect(
        TrackLink.resolvePendingService(
          anilistPending: true,
          malPending: true,
          malStateMatches: false,
          callbackHasState: true,
        ),
        isNull,
      );
      expect(
        TrackLink.resolvePendingService(
          anilistPending: false,
          malPending: true,
          malStateMatches: false,
          callbackHasState: true,
        ),
        isNull,
      );
    });

    test('resolvePendingService routes state-less callbacks to AniList first',
        () {
      expect(
        TrackLink.resolvePendingService(
          anilistPending: true,
          malPending: true,
          malStateMatches: false,
          callbackHasState: false,
        ),
        'anilist',
      );
      expect(
        TrackLink.resolvePendingService(
          anilistPending: false,
          malPending: true,
          malStateMatches: false,
          callbackHasState: false,
        ),
        'mal',
      );
      expect(
        TrackLink.resolvePendingService(
          anilistPending: false,
          malPending: false,
          malStateMatches: false,
          callbackHasState: false,
        ),
        isNull,
      );
    });
  });

  group('animeStatusFromProvider', () {
    test('maps every AniList MediaListStatus', () {
      expect(
        animeStatusFromProvider('anilist', 'CURRENT'),
        AnimeTrackStatus.watching,
      );
      expect(
        animeStatusFromProvider('anilist', 'COMPLETED'),
        AnimeTrackStatus.completed,
      );
      expect(
        animeStatusFromProvider('anilist', 'PLANNING'),
        AnimeTrackStatus.planning,
      );
      expect(
        animeStatusFromProvider('anilist', 'PAUSED'),
        AnimeTrackStatus.paused,
      );
      expect(
        animeStatusFromProvider('anilist', 'DROPPED'),
        AnimeTrackStatus.dropped,
      );
      expect(
        animeStatusFromProvider('anilist', 'REPEATING'),
        AnimeTrackStatus.rewatching,
      );
    });

    test('maps every MyAnimeList status', () {
      expect(
        animeStatusFromProvider('mal', 'watching'),
        AnimeTrackStatus.watching,
      );
      expect(
        animeStatusFromProvider('mal', 'completed'),
        AnimeTrackStatus.completed,
      );
      expect(
        animeStatusFromProvider('mal', 'plan_to_watch'),
        AnimeTrackStatus.planning,
      );
      expect(
        animeStatusFromProvider('mal', 'on_hold'),
        AnimeTrackStatus.paused,
      );
      expect(
        animeStatusFromProvider('mal', 'dropped'),
        AnimeTrackStatus.dropped,
      );
    });

    test('rejects unknown values and nulls', () {
      expect(animeStatusFromProvider('anilist', 'NOPE'), isNull);
      expect(animeStatusFromProvider('mal', 'random'), isNull);
      expect(animeStatusFromProvider('anilist', null), isNull);
      expect(animeStatusFromProvider('anilist', ''), isNull);
    });

    test('kAniListStatus / kMalStatus round-trip via the provider maps', () {
      for (final status in AnimeTrackStatus.values) {
        final anilistRaw = kAniListStatus[status]!;
        final malRaw = kMalStatus[status]!;
        expect(
          animeStatusFromProvider('anilist', anilistRaw),
          status == AnimeTrackStatus.rewatching ? status : status,
        );
        // MAL rewatching intentionally collapses to watching.
        expect(
          animeStatusFromProvider('mal', malRaw),
          status == AnimeTrackStatus.rewatching
              ? AnimeTrackStatus.watching
              : status,
        );
      }
    });
  });

  group('score conversions', () {
    test('aniListScoreForFormat converts 0-10 into each format', () {
      expect(
        aniListScoreForFormat(8, AniListScoreFormat.point100),
        80,
      );
      expect(
        aniListScoreForFormat(8, AniListScoreFormat.point10),
        8,
      );
      expect(
        aniListScoreForFormat(7, AniListScoreFormat.point5),
        4,
      );
      expect(
        aniListScoreForFormat(10, AniListScoreFormat.point3),
        3,
      );
      expect(
        aniListScoreForFormat(0, AniListScoreFormat.point3),
        0,
      );
    });

    test('score10FromAniList round-trips every format', () {
      expect(
        score10FromAniList(80, AniListScoreFormat.point100),
        8,
      );
      expect(
        score10FromAniList(8, AniListScoreFormat.point10),
        8,
      );
      expect(
        score10FromAniList(4, AniListScoreFormat.point5),
        8,
      );
      expect(
        score10FromAniList(2, AniListScoreFormat.point3),
        closeTo(6.67, 0.01),
      );
    });

    test('score10FromMal clamps into 0-10', () {
      expect(score10FromMal(7), 7);
      expect(score10FromMal(null), 0);
    });

    test('aniListScoreFormatFromName defaults to POINT_100', () {
      expect(
        aniListScoreFormatFromName('POINT_10'),
        AniListScoreFormat.point10,
      );
      expect(
        aniListScoreFormatFromName('WEIRD'),
        AniListScoreFormat.point100,
      );
      expect(
        aniListScoreFormatFromName(null),
        AniListScoreFormat.point100,
      );
    });
  });

  group('authorize URL builders', () {
    test('aniListAuthorizeUrl encodes client id and redirect', () {
      final url = aniListAuthorizeUrl(
        clientId: '12345',
        redirectUri: 'app.noor.mobile://callback',
      );
      expect(url, startsWith('https://anilist.co/api/v2/oauth/authorize?'));
      expect(url, contains('client_id=12345'));
      expect(
        url,
        contains('redirect_uri=app.noor.mobile%3A%2F%2Fcallback'),
      );
      expect(url, endsWith('&response_type=code'));
    });

    test('malAuthorizeUrl carries the plain PKCE challenge + state', () {
      final url = malAuthorizeUrl(
        clientId: 'abc123',
        redirectUri: 'app.noor.mobile://callback',
        codeVerifier: 'verifier-._~VERIFIER012345678901234567890123456789',
        state: 'state-._~STATE012345678901234567890123456789',
      );
      expect(url, startsWith('https://myanimelist.net/v1/oauth2/authorize?'));
      expect(url, contains('response_type=code'));
      expect(url, contains('client_id=abc123'));
      // - . _ ~ are unreserved and stay literal in query-component encoding.
      expect(
        url,
        contains(
          'code_challenge=verifier-._~VERIFIER012345678901234567890123456789',
        ),
      );
      expect(url, contains('code_challenge_method=plain'));
      expect(
        url,
        contains('state=state-._~STATE012345678901234567890123456789'),
      );
      expect(
        url,
        contains('redirect_uri=app.noor.mobile%3A%2F%2Fcallback'),
      );
    });
  });

  group('isValidAniListClientId', () {
    test('accepts the numeric IDs AniList dashboards issue', () {
      expect(isValidAniListClientId('2789'), isTrue);
      expect(isValidAniListClientId(' 12345 '), isTrue);
      expect(isValidAniListClientId('1'), isTrue);
    });

    test('rejects secret-shaped strings, empty values and non-numbers', () {
      // The placeholder shipped with the build is a 40-char secret — it
      // must never reach the authorize URL.
      expect(
        isValidAniListClientId('b5a2wwLwux7QbOnf8koDJJenPh6e2LjbRiMmR5ef'),
        isFalse,
      );
      expect(isValidAniListClientId(''), isFalse);
      expect(isValidAniListClientId('   '), isFalse);
      expect(isValidAniListClientId('12ab'), isFalse);
      expect(isValidAniListClientId('2789x'), isFalse);
      expect(isValidAniListClientId('-5'), isFalse);
      expect(isValidAniListClientId('12345678901'), isFalse); // > 10 digits
    });
  });
}
