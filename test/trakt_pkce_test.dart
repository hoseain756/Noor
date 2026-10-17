import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/trakt/trakt_pkce.dart';

void main() {
  group('TraktPkce.challengeS256', () {
    test('matches the RFC 7636 appendix B test vector', () {
      const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      expect(
        TraktPkce.challengeS256(verifier),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('is deterministic for the same verifier', () {
      const verifier =
          'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~x';
      expect(
        TraktPkce.challengeS256(verifier),
        TraktPkce.challengeS256(verifier),
      );
    });

    test('never emits base64 padding', () {
      final challenge = TraktPkce.challengeS256(TraktPkce.generateVerifier());
      expect(challenge.contains('='), isFalse);
      expect(challenge.length, 43); // 32-byte SHA-256 → 43 base64url chars
    });
  });

  group('TraktPkce.generateVerifier', () {
    test('is 64 characters inside the RFC 7636 window (43..128)', () {
      final verifier = TraktPkce.generateVerifier();
      expect(verifier.length, inInclusiveRange(43, 128));
      expect(TraktPkce.isValidVerifier(verifier), isTrue);
    });

    test('is unique per call (cryptographically random)', () {
      final seen = <String>{};
      for (var i = 0; i < 25; i++) {
        seen.add(TraktPkce.generateVerifier());
      }
      expect(seen.length, 25);
    });

    test('rejects values outside the RFC 7636 window', () {
      expect(TraktPkce.isValidVerifier('short'), isFalse);
      expect(TraktPkce.isValidVerifier('a' * 42), isFalse);
      expect(TraktPkce.isValidVerifier('a' * 43), isTrue);
      expect(TraktPkce.isValidVerifier('a' * 128), isTrue);
      expect(TraktPkce.isValidVerifier('a' * 129), isFalse);
      expect(
        TraktPkce.isValidVerifier('${'a' * 20} ${'a' * 22}'), // illegal space
        isFalse,
      );
    });
  });

  group('TraktPkce.generateState', () {
    test('yields URL-safe unique values', () {
      final a = TraktPkce.generateState();
      final b = TraktPkce.generateState();
      expect(a, isNot(b));
      expect(a.length, greaterThanOrEqualTo(16));
      expect(RegExp(r'^[A-Za-z0-9\-_]+$').hasMatch(a), isTrue);
      expect(TraktPkce.isValidState(a), isTrue);
    });

    test('rejects malformed states', () {
      expect(TraktPkce.isValidState('tiny'), isFalse);
      expect(TraktPkce.isValidState('has spaces and symbols!'), isFalse);
      expect(TraktPkce.isValidState('a' * 300), isFalse);
    });
  });

  group('TraktCallback.fromUri', () {
    test('parses the primary HTTPS return on the allowed host', () {
      final callback = TraktCallback.fromUri(
        'https://example.com/?code=xyz123&state=st-1',
        allowedHttpsHost: 'example.com',
      );
      expect(callback, isNotNull);
      expect(callback!.code, 'xyz123');
      expect(callback.state, 'st-1');
      expect(callback.isDenied, isFalse);
    });

    test('parses the legacy noor://callback return', () {
      final callback = TraktCallback.fromUri(
        'noor://callback?code=abc&state=st2',
      );
      expect(callback, isNotNull);
      expect(callback!.code, 'abc');
      expect(callback.state, 'st2');
    });

    test('rejects HTTPS returns on foreign hosts (code interception)', () {
      expect(
        TraktCallback.fromUri(
          'https://evil.example/?code=xyz&state=st',
          allowedHttpsHost: 'example.com',
        ),
        isNull,
      );
    });

    test('rejects http and unknown schemes (docs: https returns only)', () {
      expect(
        TraktCallback.fromUri(
          'http://example.com/?code=x&state=y',
          allowedHttpsHost: 'example.com',
        ),
        isNull,
      );
      expect(
        TraktCallback.fromUri('magnet:?xt=urn:btih:xyz'),
        isNull,
      );
      expect(
        TraktCallback.fromUri('noor://other?code=x&state=y'),
        isNull,
      );
    });

    test('surfaces the denial error parameter', () {
      final callback = TraktCallback.fromUri(
        'noor://callback?error=access_denied&state=st3',
      );
      expect(callback, isNotNull);
      expect(callback!.isDenied, isTrue);
      expect(callback.error, 'access_denied');
    });

    test('rejects callbacks without a code or garbage input', () {
      expect(
        TraktCallback.fromUri(
          'noor://callback?state=only_state',
          allowedHttpsHost: 'example.com',
        ),
        isNull,
      );
      expect(TraktCallback.fromUri('not a url at all'), isNull);
      expect(TraktCallback.fromUri(''), isNull);
    });
  });
}
