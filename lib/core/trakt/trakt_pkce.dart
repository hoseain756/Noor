import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

/// RFC 7636 PKCE primitives for the Trakt browser handshake plus the parser
/// for the authorization return leg.
///
/// The user's Trakt application is PKCE-only — Trakt issues no client secret
/// for it, and the current official documentation
/// (developer.trakt.tv/docs/pkce) makes PKCE the way to sign users in: it
/// deprecates `client_secret` for user sign-in entirely, mandates the S256
/// challenge method, and tells mobile apps to receive the return over HTTPS
/// (verified App Links / Universal Links) instead of custom schemes.
class TraktPkce {
  const TraktPkce._();

  /// 48 random bytes → 64 base64url characters, inside the documented
  /// 43–128 character verifier window (A-Z a-z 0-9 - . _ ~).
  static String generateVerifier({int bytes = 48}) {
    if (bytes < 32 || bytes > 96) {
      throw ArgumentError.value(bytes, 'bytes', 'expected 32..96');
    }
    final random = math.Random.secure();
    return base64UrlEncode(
      List<int>.generate(bytes, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
  }

  /// S256 challenge: SHA-256 over the ASCII verifier, base64url, no padding.
  static String challengeS256(String verifier) => base64UrlEncode(
        sha256.convert(utf8.encode(verifier)).bytes,
      ).replaceAll('=', '');

  /// CSRF guard value carried through the browser round-trip.
  static String generateState() => generateVerifier(bytes: 32);

  /// RFC 7636 verifier alphabet + the 43–128 length window.
  static bool isValidVerifier(String value) {
    if (value.length < 43 || value.length > 128) return false;
    return RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(value);
  }

  /// Our state values are 43-character base64url strings; anything longer or
  /// outside the alphabet is rejected before it can reach the exchange.
  static bool isValidState(String value) =>
      value.length >= 16 &&
      value.length <= 256 &&
      RegExp(r'^[A-Za-z0-9\-_]+$').hasMatch(value);
}

/// The authorization return leg: either the primary HTTPS redirect (App
/// Links / browser → web companion → relay) or the legacy `noor://callback`
/// custom scheme fallback.
class TraktCallback {
  const TraktCallback({
    required this.code,
    required this.state,
    this.error,
  });

  final String code;
  final String state;
  final String? error;

  bool get isDenied => error != null && error!.isNotEmpty;

  /// Parses [link] and returns null for anything that is not a Trakt return
  /// for THIS app:
  ///  - `noor://callback?code=…&state=…` (legacy fallback)
  ///  - `https://<allowedHttpsHost>/?code=…&state=…` (primary, documented)
  ///
  /// A missing `state` is tolerated at parse time — [NoorApi] enforces the
  /// strict equality check against the pending flow's stored state.
  static TraktCallback? fromUri(String link, {String? allowedHttpsHost}) {
    final uri = Uri.tryParse(link.trim());
    if (uri == null || uri.scheme.isEmpty) return null;
    switch (uri.scheme.toLowerCase()) {
      case 'noor':
        // Only the dedicated callback authority — other noor:// links belong
        // to different features and must not reach the OAuth path.
        if (uri.host.toLowerCase() != 'callback') return null;
        return _fromQuery(uri);
      case 'https':
        final allowed = allowedHttpsHost?.toLowerCase() ?? '';
        if (allowed.isEmpty) return null;
        if (uri.host.toLowerCase() != allowed) return null;
        return _fromQuery(uri);
      default:
        // http:// and custom schemes are rejected: the current Trakt docs
        // require https returns on mobile (custom schemes are explicitly
        // discouraged — any installed app can claim the same scheme).
        return null;
    }
  }

  static TraktCallback? _fromQuery(Uri uri) {
    final query = uri.queryParameters;
    final error = query['error']?.trim() ?? '';
    if (error.isNotEmpty) {
      return TraktCallback(code: '', state: query['state'] ?? '', error: error);
    }
    final code = query['code']?.trim() ?? '';
    if (code.isEmpty) return null;
    return TraktCallback(code: code, state: query['state'] ?? '');
  }
}
