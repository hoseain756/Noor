import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/trakt/trakt_tokens.dart';

const int _createdAt = 1700000000;
final DateTime _createdAtDt =
    DateTime.fromMillisecondsSinceEpoch(_createdAt * 1000);

TraktTokenSet _tokens({
  int expiresIn = 604800, // 7 days, per the current docs
  int createdAt = _createdAt,
}) {
  return TraktTokenSet.fromResponse(
    <String, dynamic>{
      'access_token': 'access-1',
      'refresh_token': 'refresh-1',
      'token_type': 'bearer',
      'expires_in': expiresIn,
      'created_at': createdAt,
      'scope': 'public',
    },
    now: () => _createdAtDt,
  );
}

void main() {
  group('TraktTokenSet.fromResponse', () {
    test('computes the expiry from created_at + expires_in', () {
      final tokens = _tokens();
      expect(tokens.accessToken, 'access-1');
      expect(tokens.refreshToken, 'refresh-1');
      expect(
        tokens.expiresAt,
        DateTime.fromMillisecondsSinceEpoch((_createdAt + 604800) * 1000),
      );
    });

    test('rejects payloads without access_token', () {
      expect(
        () => TraktTokenSet.fromResponse(<String, dynamic>{
          'refresh_token': 'r',
          'expires_in': 100,
          'created_at': _createdAt,
        }),
        throwsFormatException,
      );
    });

    test('rejects payloads without a usable lifetime', () {
      expect(
        () => TraktTokenSet.fromResponse(<String, dynamic>{
          'access_token': 'a',
        }),
        throwsFormatException,
      );
      expect(
        () => TraktTokenSet.fromResponse(<String, dynamic>{
          'access_token': 'a',
          'expires_in': 0,
          'created_at': _createdAt,
        }),
        throwsFormatException,
      );
    });

    test('tolerates a missing refresh_token (kept-session semantics)', () {
      final tokens = TraktTokenSet.fromResponse(<String, dynamic>{
        'access_token': 'a',
        'expires_in': 604800,
        'created_at': _createdAt,
      }, now: () => _createdAtDt);
      expect(tokens.refreshToken, isNull);
    });

    test('isExpiredAt honours the margin', () {
      final tokens = _tokens(expiresIn: 600); // ten minutes of life
      expect(
        tokens.isExpiredAt(_createdAtDt, margin: const Duration(minutes: 1)),
        isFalse,
      );
      expect(
        tokens.isExpiredAt(_createdAtDt, margin: const Duration(minutes: 30)),
        isTrue,
      );
    });
  });

  group('TraktTokenRefresher (single-flight)', () {
    test('concurrent callers share ONE exchange round-trip', () async {
      var exchangeCalls = 0;
      var persistCalls = 0;
      final gate = Completer<void>();
      TraktTokenSet? delivered;

      final refresher = TraktTokenRefresher(
        clientId: 'client-id',
        exchange: (body) async {
          exchangeCalls++;
          expect(body['grant_type'], 'refresh_token');
          expect(body['refresh_token'], 'refresh-1');
          expect(body['client_id'], 'client-id');
          // PKCE apps never send a client_secret — guard against a
          // regression that would break the user's secret-less app.
          expect(body.containsKey('client_secret'), isFalse);
          await gate.future;
          return <String, dynamic>{
            'access_token': 'access-2',
            'refresh_token': 'refresh-2',
            'expires_in': 604800,
            'created_at': _createdAt,
          };
        },
        persist: (tokens) async {
          persistCalls++;
          delivered = tokens;
        },
      );

      final first = refresher.refresh('refresh-1');
      final second = refresher.refresh('refresh-1');
      expect(refresher.isRefreshing, isTrue);
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      final firstResult = await first;
      final secondResult = await second;

      expect(exchangeCalls, 1, reason: 'refresh tokens are single-use');
      expect(firstResult.outcome, TraktRefreshOutcome.refreshed);
      expect(secondResult.outcome, TraktRefreshOutcome.refreshed);
      expect(firstResult.tokens!.accessToken, 'access-2');
      expect(identical(firstResult.tokens, secondResult.tokens), isTrue);
      expect(persistCalls, 1, reason: 'the fresh pair is persisted once');
      expect(delivered!.refreshToken, 'refresh-2');
      expect(refresher.isRefreshing, isFalse);
    });

    test('a dead grant (400 → null payload) fails every waiter', () async {
      var exchangeCalls = 0;
      final refresher = TraktTokenRefresher(
        clientId: 'client-id',
        exchange: (_) async {
          exchangeCalls++;
          return null;
        },
        persist: (_) async {},
      );
      final results = await Future.wait(<Future<TraktRefreshResult>>[
        refresher.refresh('dead-token'),
        refresher.refresh('dead-token'),
      ]);
      expect(exchangeCalls, 1);
      expect(
        results.every((r) => r.outcome == TraktRefreshOutcome.grantDead),
        isTrue,
      );
      expect(results.every((r) => r.tokens == null), isTrue);
    });

    test('transient errors keep the session decision with the caller',
        () async {
      final refresher = TraktTokenRefresher(
        clientId: 'client-id',
        exchange: (_) async => throw Exception('socket offline'),
        persist: (_) async {},
      );
      var persistCalls = 0;
      final second = TraktTokenRefresher(
        clientId: 'client-id',
        exchange: (_) async {
          throw StateError('5xx');
        },
        persist: (_) async {
          persistCalls++;
        },
      );
      final result = await refresher.refresh('r');
      final result2 = await second.refresh('r');
      expect(result.outcome, TraktRefreshOutcome.transientFailure);
      expect(result.tokens, isNull);
      expect(result2.outcome, TraktRefreshOutcome.transientFailure);
      expect(persistCalls, 0);
    });

    test('an empty refresh token never reaches the endpoint', () async {
      var exchangeCalls = 0;
      final refresher = TraktTokenRefresher(
        clientId: 'client-id',
        exchange: (_) async {
          exchangeCalls++;
          return null;
        },
        persist: (_) async {},
      );
      final result = await refresher.refresh('');
      expect(exchangeCalls, 0);
      expect(result.outcome, TraktRefreshOutcome.grantDead);
    });

    test('a malformed payload is transient, not a dead grant', () async {
      final refresher = TraktTokenRefresher(
        clientId: 'client-id',
        exchange: (_) async => <String, dynamic>{'unexpected': true},
        persist: (_) async {},
      );
      final result = await refresher.refresh('r');
      expect(result.outcome, TraktRefreshOutcome.transientFailure);
    });

    test('sequential refreshes run a fresh round-trip each time', () async {
      var calls = 0;
      final refresher = TraktTokenRefresher(
        clientId: 'client-id',
        exchange: (_) async {
          calls++;
          return <String, dynamic>{
            'access_token': 'access-$calls',
            'expires_in': 604800,
            'created_at': _createdAt,
          };
        },
        persist: (_) async {},
      );
      final first = await refresher.refresh('r');
      final second = await refresher.refresh('r');
      expect(calls, 2);
      expect(first.tokens!.accessToken, 'access-1');
      expect(second.tokens!.accessToken, 'access-2');
    });
  });
}
