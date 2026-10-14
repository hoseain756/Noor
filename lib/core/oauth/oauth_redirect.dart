/// Generic OAuth return leg for services that redirect back into Noor over
/// the app-identifier private-use scheme (RFC 8252 §7.1):
///
///     app.noor.mobile://callback?code=…&state=…
///
/// Both AniList and MyAnimeList officially accept private-use URI schemes as
/// redirect URIs:
///
///  - AniList (docs.anilist.co/guide/auth): the application redirect URL
///    "can be any valid URI, including custom URI schemes"; registered at
///    anilist.co/settings/developer. Codes come back as `?code=…`.
///  - MyAnimeList (official staff API guide): "The IETF best current practice
///    recommends using a private-use URI scheme … you may register the custom
///    myapp://auth handler to obtain the Authorisation Code from MAL's
///    servers"; PKCE (`code_challenge`, plain method) is REQUIRED and the
///    callback carries `?code=…&state=…`.
///
/// Trakt is intentionally NOT wired through this scheme — its flow pins
/// `noor://callback` / the registered HTTPS redirect (see TraktCallback).
class OAuthRedirect {
  const OAuthRedirect._();

  /// Android applicationId / iOS bundle identifier, used verbatim as the
  /// private-use scheme.
  static const String scheme = 'app.noor.mobile';

  /// Conventional callback authority (matches the `noor://callback` shape).
  static const String callbackHost = 'callback';

  /// The exact Redirect URI to register on AniList and MyAnimeList.
  static const String redirectUri = '$scheme://$callbackHost';

  /// Alias kept for call-site readability — the same URI on both platforms.
  static const String anilistRedirectUri = redirectUri;
  static const String malRedirectUri = redirectUri;

  /// True when [link] belongs to the app-identifier callback
  /// (`app.noor.mobile://callback?…`), case-insensitive on scheme + host.
  static bool isCallback(String link) {
    final uri = Uri.tryParse(link.trim());
    if (uri == null) return false;
    return uri.scheme.toLowerCase() == scheme &&
        uri.host.toLowerCase() == callbackHost;
  }

  /// Parses an OAuth return carried on the app-identifier scheme. Returns
  /// null for anything that is not THIS app's callback or that carries
  /// neither a code nor an error (foreign/other-feature
  /// `app.noor.mobile://…` links must not reach the OAuth path).
  static OAuthCallback? parse(String link) {
    if (!isCallback(link)) return null;
    final uri = Uri.tryParse(link.trim())!;
    final query = uri.queryParameters;
    final error = query['error']?.trim() ?? '';
    if (error.isNotEmpty) {
      return OAuthCallback(error: error, state: query['state'] ?? '');
    }
    final code = query['code']?.trim() ?? '';
    if (code.isEmpty) return null;
    return OAuthCallback(code: code, state: query['state'] ?? '');
  }
}

/// Parsed OAuth return: an authorization `code` (+ `state` echo when the
/// provider sends one) or a user-denied `error`.
class OAuthCallback {
  const OAuthCallback({
    this.code = '',
    this.state = '',
    this.error,
  });

  final String code;
  final String state;
  final String? error;

  bool get isDenied => error != null && error!.isNotEmpty;
}
