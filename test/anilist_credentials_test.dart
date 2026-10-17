import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/api/noor_api.dart';
import 'package:nova_mobile/core/track/track_link.dart';

/// Regression lock for the owner's AniList dashboard credentials.
///
/// History: builds before the fix embedded the 40-character CLIENT SECRET in
/// the client-ID slot (and let users paste overrides), so the authorize page
/// died on an unknown client after login. The dashboard truth is:
///   Client ID  = 53823 (numeric, client "noor")
///   Secret     = 40-char value — deliberately NEVER embedded; the official
///                IMPLICIT grant carries no secret.
void main() {
  group('embedded AniList credentials (owner dashboard)', () {
    test('default client ID is the numeric dashboard ID 53823', () {
      expect(NoorApi.defaultAniListClientId, '53823');
      // The embedded value must always satisfy the numeric-ID validator.
      expect(isValidAniListClientId(NoorApi.defaultAniListClientId), isTrue);
    });

    test('authorize URL from the embedded ID is a clean implicit-grant URL',
        () {
      final url = Uri.parse(
        aniListAuthorizeUrl(clientId: NoorApi.defaultAniListClientId),
      );
      expect(url.host, 'anilist.co');
      expect(url.path, '/api/v2/oauth/authorize');
      expect(url.queryParameters['client_id'], '53823');
      expect(url.queryParameters['response_type'], 'token');
      // The implicit flow never carries a secret or a redirect parameter —
      // the dashboard-registered Redirect URL is used as-is.
      expect(url.queryParameters.containsKey('client_secret'), isFalse);
      expect(url.queryParameters.containsKey('redirect_uri'), isFalse);
    });
  });
}
