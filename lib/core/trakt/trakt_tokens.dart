import 'dart:async';

/// Parsed Trakt OAuth token payload — produced by the Authorization Code +
/// PKCE exchange or by the refresh grant.
///
/// Trakt returns `access_token`, `token_type`, `expires_in` (seconds),
/// `refresh_token`, `created_at` and `scope`. Per the current documentation
/// the access token is valid for 7 days and the refresh token renews it
/// without re-authorization.
class TraktTokenSet {
  const TraktTokenSet({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;

  /// True when the token is (or will be within [margin]) expired at [moment].
  bool isExpiredAt(DateTime moment, {Duration margin = Duration.zero}) =>
      !moment.isBefore(expiresAt.subtract(margin));

  /// Validates the documented response shape: `access_token` is mandatory
  /// and the lifetime must be derivable from `created_at` + `expires_in`.
  /// Throws a [FormatException] on unusable payloads so callers never store
  /// a half-valid session.
  static TraktTokenSet fromResponse(
    Map<String, dynamic> payload, {
    DateTime Function()? now,
  }) {
    final clock = now ?? DateTime.now;
    final access = payload['access_token']?.toString().trim() ?? '';
    if (access.isEmpty) {
      throw const FormatException('token response is missing access_token');
    }
    final refresh = payload['refresh_token']?.toString().trim() ?? '';
    final createdSeconds =
        (_num(payload['created_at']) ?? clock().millisecondsSinceEpoch ~/ 1000)
            .toInt();
    final expiresInSeconds = (_num(payload['expires_in']) ?? 0).toInt();
    if (expiresInSeconds <= 0) {
      throw const FormatException('token response is missing expires_in');
    }
    return TraktTokenSet(
      accessToken: access,
      refreshToken: refresh.isEmpty ? null : refresh,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (createdSeconds + expiresInSeconds) * 1000,
      ),
    );
  }

  static num? _num(Object? value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '');
  }
}

/// HTTP leg of the refresh grant. Injected so tests can drive the endpoint
/// without sockets; [NoorApi] wires it to the shared Dio client.
///
/// Contract: return the decoded JSON payload on success, return **null** for
/// a definitively dead grant (HTTP 400/401 → `invalid_grant`, revoked or
/// expired session), and throw for transient failures (network, 5xx) so the
/// caller can keep the existing tokens.
typedef TraktTokenExchange = Future<Map<String, dynamic>?> Function(
  Map<String, String> body,
);

enum TraktRefreshOutcome {
  /// New tokens obtained and persisted exactly once.
  refreshed,

  /// The refresh token is dead (single-use token consumed/revoked/expired):
  /// the caller must drop the stored session and re-authorize the user.
  grantDead,

  /// Transient failure (offline, 5xx, malformed body): the stored session
  /// stays untouched and the next call may simply retry.
  transientFailure,
}

class TraktRefreshResult {
  const TraktRefreshResult(this.outcome, [this.tokens]);

  final TraktRefreshOutcome outcome;
  final TraktTokenSet? tokens;
}

/// Single-flight refresh coordinator.
///
/// Trakt refresh tokens are single-use: two concurrent refreshes with the
/// same token would burn it twice and kill the session. Every caller shares
/// one in-flight round-trip; the fresh pair is persisted exactly once via
/// [persist] (which should write the refresh token first, then the access
/// token, then the expiry — an interrupted write then always leaves a usable
/// pair behind).
class TraktTokenRefresher {
  TraktTokenRefresher({
    required this.clientId,
    required this.exchange,
    required this.persist,
  });

  final String clientId;
  final TraktTokenExchange exchange;
  final Future<void> Function(TraktTokenSet tokens) persist;

  Future<TraktRefreshResult>? _inFlight;

  bool get isRefreshing => _inFlight != null;

  /// Refreshes [refreshToken]; concurrent callers share the same round-trip
  /// and receive the identical [TraktTokenSet] instance.
  Future<TraktRefreshResult> refresh(String refreshToken) {
    return _inFlight ??=
        _run(refreshToken).whenComplete(() => _inFlight = null);
  }

  Future<TraktRefreshResult> _run(String refreshToken) async {
    if (refreshToken.isEmpty) {
      return const TraktRefreshResult(TraktRefreshOutcome.grantDead);
    }
    try {
      // Documented refresh grant: no redirect_uri, and — for PKCE
      // applications — no client_secret (verified live: a secret-less
      // request fails with invalid_grant/"session not found" for a bad
      // token, not invalid_client, so the shape is accepted).
      final payload = await exchange(<String, String>{
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': clientId,
      });
      if (payload == null) {
        return const TraktRefreshResult(TraktRefreshOutcome.grantDead);
      }
      final tokens = TraktTokenSet.fromResponse(payload);
      await persist(tokens);
      return TraktRefreshResult(TraktRefreshOutcome.refreshed, tokens);
    } on FormatException {
      return const TraktRefreshResult(TraktRefreshOutcome.transientFailure);
    } catch (_) {
      return const TraktRefreshResult(TraktRefreshOutcome.transientFailure);
    }
  }
}
