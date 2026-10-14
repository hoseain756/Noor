import 'package:flutter_test/flutter_test.dart';
import 'package:noor_mobile/core/oauth/oauth_redirect.dart';

void main() {
  group('OAuthRedirect constants', () {
    test('redirect URI is the app identifier scheme + callback authority', () {
      expect(OAuthRedirect.scheme, 'app.noor.mobile');
      expect(OAuthRedirect.redirectUri, 'app.noor.mobile://callback');
      // The exact URI to register on AniList and MyAnimeList.
      expect(OAuthRedirect.anilistRedirectUri, 'app.noor.mobile://callback');
      expect(OAuthRedirect.malRedirectUri, 'app.noor.mobile://callback');
    });
  });

  group('OAuthRedirect.isCallback', () {
    test('accepts the canonical callback shape', () {
      expect(
        OAuthRedirect.isCallback(
          'app.noor.mobile://callback?code=a1B2c3&state=RequestID42',
        ),
        isTrue,
      );
    });

    test('is case-insensitive on scheme and host', () {
      expect(
        OAuthRedirect.isCallback('APP.NOOR.MOBILE://CALLBACK?code=x'),
        isTrue,
      );
      expect(
        OAuthRedirect.isCallback('App.Noor.Mobile://Callback?code=x'),
        isTrue,
      );
    });

    test('rejects foreign schemes and hosts', () {
      expect(OAuthRedirect.isCallback('noor://callback?code=x'), isFalse);
      expect(OAuthRedirect.isCallback('https://example.com/?code=x'), isFalse);
      expect(
        OAuthRedirect.isCallback('app.noor.mobile://other?code=x'),
        isFalse,
      );
      expect(OAuthRedirect.isCallback('magnet:?xt=urn:btih:abc'), isFalse);
      expect(OAuthRedirect.isCallback('not a url'), isFalse);
      expect(OAuthRedirect.isCallback(''), isFalse);
    });
  });

  group('OAuthRedirect.parse', () {
    test('parses code + state (MyAnimeList callback shape)', () {
      final callback = OAuthRedirect.parse(
        'app.noor.mobile://callback?code=a1B2c3...&state=RequestID42',
      );
      expect(callback, isNotNull);
      expect(callback!.code, 'a1B2c3...');
      expect(callback.state, 'RequestID42');
      expect(callback.isDenied, isFalse);
    });

    test('parses code-only (AniList callback shape)', () {
      final callback = OAuthRedirect.parse(
        'app.noor.mobile://callback?code=auth_code_123',
      );
      expect(callback, isNotNull);
      expect(callback!.code, 'auth_code_123');
      expect(callback.state, isEmpty);
    });

    test('parses a user-denied return', () {
      final callback = OAuthRedirect.parse(
        'app.noor.mobile://callback?error=access_denied&error_description=nope',
      );
      expect(callback, isNotNull);
      expect(callback!.isDenied, isTrue);
      expect(callback.error, 'access_denied');
      expect(callback.code, isEmpty);
    });

    test('tolerates surrounding whitespace', () {
      final callback = OAuthRedirect.parse(
        '  app.noor.mobile://callback?code=zz  ',
      );
      expect(callback, isNotNull);
      expect(callback!.code, 'zz');
    });

    test('returns null for callback without code or error', () {
      expect(
        OAuthRedirect.parse('app.noor.mobile://callback'),
        isNull,
      );
      expect(
        OAuthRedirect.parse('app.noor.mobile://callback?foo=bar'),
        isNull,
      );
    });

    test('returns null for foreign links that never reach the OAuth path', () {
      expect(OAuthRedirect.parse('noor://callback?code=x'), isNull);
      expect(
        OAuthRedirect.parse('app.noor.mobile://other?code=x'),
        isNull,
      );
      expect(OAuthRedirect.parse('https://attacker.example/?code=x'), isNull);
    });
  });
}
