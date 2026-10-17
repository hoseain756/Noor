// Noor — linked-services CLI probe.
//
// Tests every external integration the app links against, using the SAME
// endpoints, headers and body shapes as lib/core/api/noor_api.dart, directly
// from the command line (no Flutter, no emulator needed):
//
//   dart run tool/test_linkings.dart
//
// What is tested:
//   1. Trakt   — device-code start (client_id only), then a token exchange
//                WITHOUT a client secret and with a dummy one, to document
//                whether Trakt really requires the secret.
//   2. Simkl   — device-code start, then an immediate token poll with the
//                embedded client_id/secret (expect authorization_pending =>
//                credentials are valid; invalid_client => embedded keys are
//                the reason linking fails).
//   3. Real-Debrid / AllDebrid / TorBox — /user probes with a dummy key:
//                proves reachability + request shape (expect 401 / error JSON,
//                NOT DNS or 404 errors).
//
// Exit code 0 when every section ran (individual probes may legitimately
// return 4xx — that is what we are measuring).

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

// ---- Mirrors of the embedded constants in lib/core/api/noor_api.dart ----
const String traktClientId = 'pk0CCmQaUuZt3VqpWu0lphpro_i52wX9QnkbGbf_fUY';
const String simklClientId =
    '77b9125e4f1148d09b4fec74474171a02daefe24272cc1aa8b2efcb4da367bee';
const String simklClientSecret = 'simkl_cs_bFZ4x7Sgrkc2hhslQDD38LVnkM7D1bI0Ym';

const String traktBase = 'https://api.trakt.tv';
const String simklBase = 'https://api.simkl.com';

final Dio _dio = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 15),
  receiveTimeout: const Duration(seconds: 25),
  validateStatus: (_) => true, // never throw — we inspect every status
));

int _section = 0;
int _pass = 0;
int _fail = 0;
final Stopwatch _clock = Stopwatch();

void _title(String text) {
  _section++;
  print('\n════════════════════════════════════════════════════════════');
  print('[$_section] $text');
  print('════════════════════════════════════════════════════════════');
}

void _ok(String text) {
  _pass++;
  print('  ✅ PASS  $text');
}

void _bad(String text) {
  _fail++;
  print('  ❌ FAIL  $text');
}

void _info(String text) => print('  ℹ️  $text');

Future<Response<String>> _postRaw(
  String url, {
  Object? body,
  Map<String, String>? headers,
  Map<String, String>? query,
}) async {
  final response = await _dio.post<String>(
    url,
    data: body ?? const <String, dynamic>{},
    queryParameters: query,
    options: Options(
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        ...?headers,
      },
      responseType: ResponseType.plain, // show the raw truth
    ),
  );
  return response;
}

Future<Response<String>> _getRaw(
  String url, {
  Map<String, String>? headers,
  Map<String, String>? query,
}) async {
  return _dio.get<String>(
    url,
    queryParameters: query,
    options: Options(
      headers: <String, String>{
        'Accept': 'application/json',
        ...?headers,
      },
      responseType: ResponseType.plain,
    ),
  );
}

Map<String, dynamic>? _json(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

String _brief(Object? data) {
  if (data == null) return '<empty body>';
  final text = data is Map ? jsonEncode(data) : data.toString();
  return text.length > 300 ? '${text.substring(0, 300)}…' : text;
}

Future<void> main(List<String> args) async {
  _clock.start();
  stdout.writeln('Noor linked-services probe — ${DateTime.now().toUtc()}');
  stdout
      .writeln('Network reachability + request-shape test for every service.');

  await _testTrakt();
  await _testSimkl();
  await _testRealDebrid();
  await _testAllDebrid();
  await _testTorbox();

  _clock.stop();
  print('\n────────────────────────────────────────────────────────────');
  print('Done in ${_clock.elapsed.inSeconds}s — $_pass passed, $_fail failed.');
  print('Interpretation:');
  print(' • Trakt 400 without/with dummy secret => Trakt API really requires');
  print('   the OAuth client secret for the device token exchange.');
  print(' • Simkl authorization_pending => embedded client id+secret are');
  print('   VALID (linking code is correct — waiting for user approval).');
  print(' • Simkl invalid_client/401 => the embedded Simkl keys are wrong —');
  print('   that is why linking never succeeds in the app.');
  print(' • Debrid 401/error-status with dummy key => endpoint reachable and');
  print('   request shape correct; a real key should verify in the app.');
  exit(_fail == 0 ? 0 : 1);
}

// ---------------------------------------------------------------------------
// Trakt
// ---------------------------------------------------------------------------
Future<void> _testTrakt() async {
  _title('Trakt — device/code with BOGUS client_id (does it validate?)');
  try {
    final bogus = await _postRaw(
      '$traktBase/oauth/device/code',
      body: <String, String>{'client_id': 'bogus-client-id-probe'},
      headers: <String, String>{
        'trakt-api-version': '2',
        'trakt-api-key': 'bogus-client-id-probe',
      },
    );
    _info('HTTP ${bogus.statusCode} — ${_brief(bogus.data)}');
    if (bogus.statusCode == 200) {
      _info('Trakt does NOT validate the client_id at this step — only the '
          'token exchange validates the id+secret pair.');
    } else {
      _ok('Trakt validates the client_id at device/code.');
    }
  } catch (error) {
    _bad('network error: $error');
  }

  _title('Trakt — POST /oauth/device/code (embedded client_id, no secret)');
  Response<String> start;
  try {
    start = await _postRaw(
      '$traktBase/oauth/device/code',
      body: <String, String>{'client_id': traktClientId},
      headers: <String, String>{
        'trakt-api-version': '2',
        'trakt-api-key': traktClientId,
      },
    );
  } catch (error) {
    _bad('network error: $error');
    return;
  }
  final body = _json(start.data) ?? const <String, dynamic>{};
  _info('HTTP ${start.statusCode} — ${_brief(start.data)}');

  final deviceCode = body['device_code']?.toString() ?? '';
  final userCode = body['user_code']?.toString() ?? '';
  if (start.statusCode == 200 && deviceCode.isNotEmpty && userCode.isNotEmpty) {
    _ok('device code issued: user_code=$userCode '
        'verification=${body['verification_url']}');
  } else {
    _bad('device code request failed — embedded client_id may be invalid.');
    return;
  }

  _title('Trakt — POST /oauth/device/token WITHOUT client_secret (raw)');
  final noSecret = await _postRaw(
    '$traktBase/oauth/device/token',
    body: <String, String>{
      'code': deviceCode,
      'client_id': traktClientId,
    },
    headers: <String, String>{
      'trakt-api-version': '2',
      'trakt-api-key': traktClientId,
    },
  );
  _info('HTTP ${noSecret.statusCode} — ${_brief(noSecret.data)}');
  if (noSecret.statusCode == 400) {
    final err = _json(noSecret.data)?['error']?.toString() ?? '<no JSON body>';
    if (err.contains('pending')) {
      _ok('Trakt proceeds WITHOUT a secret (pending) — the app can stop '
          'asking for one!');
    } else {
      _ok('Trakt refuses the exchange without a secret ($err) — asking for '
          'the secret IS required by Trakt, not an app bug.');
    }
  } else {
    _info('unexpected status ${noSecret.statusCode}.');
  }

  _title('Trakt — POST /oauth/device/token with DUMMY client_secret (raw)');
  await Future<void>.delayed(const Duration(seconds: 2));
  final dummy = await _postRaw(
    '$traktBase/oauth/device/token',
    body: <String, String>{
      'code': deviceCode,
      'client_id': traktClientId,
      'client_secret': 'not-a-real-secret',
    },
    headers: <String, String>{
      'trakt-api-version': '2',
      'trakt-api-key': traktClientId,
    },
  );
  _info('HTTP ${dummy.statusCode} — ${_brief(dummy.data)}');
  final dummyErr = _json(dummy.data)?['error']?.toString() ?? '';
  if (dummy.statusCode == 400 &&
      (dummyErr.contains('invalid_client') ||
          dummyErr.contains('invalid_grant'))) {
    _ok('Trakt validates the secret VALUE — the secret must come from the '
        'same Trakt app as the client_id (trakt.tv/settings/api).');
  } else if (dummy.statusCode == 429) {
    _info('429 slow_down — rate limited by the previous poll (the app '
        'already treats 429 as pending).');
  } else {
    _info('unexpected status ${dummy.statusCode} / error="$dummyErr".');
  }
}

// ---------------------------------------------------------------------------
// Simkl
// ---------------------------------------------------------------------------
Future<void> _testSimkl() async {
  _title('Simkl — POST /oauth2/device?client_id=… (the FIXED app shape)');
  Response<String> start;
  try {
    start = await _postRaw(
      '$simklBase/oauth2/device',
      query: <String, String>{'client_id': simklClientId},
      headers: <String, String>{'simkl-api-key': simklClientId},
    );
  } catch (error) {
    _bad('network error: $error');
    return;
  }
  final body = _json(start.data) ?? const <String, dynamic>{};
  _info('HTTP ${start.statusCode} — ${_brief(start.data)}');

  final deviceCode = body['device_code']?.toString() ?? '';
  final userCode = body['user_code']?.toString() ?? '';
  final verificationUrl = (body['verification_uri_complete'] ??
              body['verification_uri'] ??
              body['verification_url'])
          ?.toString() ??
      '';
  if (start.statusCode == 200 && deviceCode.isNotEmpty && userCode.isNotEmpty) {
    _ok('device code issued: user_code=$userCode url=$verificationUrl');
  } else {
    _bad('POST /oauth2/device failed — the embedded client_id itself may be '
        'invalid. Verify at simkl.com/settings/api.');
    return;
  }

  _title('Simkl — POST /oauth2/token with RFC 8628 grant (expect pending)');
  final poll = await _postRaw(
    '$simklBase/oauth2/token',
    body: <String, String>{
      'client_id': simklClientId,
      'client_secret': simklClientSecret,
      'device_code': deviceCode,
      'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
    },
    headers: <String, String>{'simkl-api-key': simklClientId},
  );
  _info('HTTP ${poll.statusCode} — ${_brief(poll.data)}');
  final errText = (_json(poll.data)?['error'] ??
          _json(poll.data)?['error_description'] ??
          '')
      .toString();
  if (poll.statusCode == 400 &&
      (errText.contains('pending') || errText.contains('slow_down'))) {
    _ok('authorization_pending with the embedded secret => client_id + '
        'secret are VALID — Simkl linking now works up to user approval.');
  } else if (poll.statusCode == 401 ||
      errText.contains('invalid_client') ||
      errText.contains('unsupported_grant_type')) {
    _bad('Simkl rejected the request ("$errText") — fresh keys must be '
        'created at simkl.com/settings/api.');
  } else {
    _info('unexpected — inspect the body above.');
  }
}

// ---------------------------------------------------------------------------
// Debrid — negative probes with a dummy key
// ---------------------------------------------------------------------------
Future<void> _testRealDebrid() async {
  _title('Real-Debrid — GET /rest/1.0/user with dummy Bearer key');
  try {
    final response = await _getRaw(
      'https://api.real-debrid.com/rest/1.0/user',
      headers: <String, String>{'Authorization': 'Bearer invalid-key-probe'},
    );
    _info('HTTP ${response.statusCode} — ${_brief(response.data)}');
    if (response.statusCode == 401) {
      _ok('endpoint reachable, auth shape correct (401 for a bad key).');
    } else {
      _info('unexpected status — inspect.');
    }
  } catch (error) {
    _bad('network error: $error');
  }
}

Future<void> _testAllDebrid() async {
  _title('AllDebrid — GET /v4/user?agent=noor&apikey=… dummy key');
  try {
    final response = await _getRaw(
      'https://api.alldebrid.com/v4/user',
      query: <String, String>{'agent': 'noor', 'apikey': 'invalid-key-probe'},
    );
    _info('HTTP ${response.statusCode} — ${_brief(response.data)}');
    final status = _json(response.data)?['status']?.toString();
    if (response.statusCode == 200 && status == 'error') {
      _ok('endpoint reachable, JSON envelope correct (status=error for a '
          'bad key, code=${_json(response.data)?['error']?['code']}).');
    } else {
      _info('unexpected envelope — inspect.');
    }
  } catch (error) {
    _bad('network error: $error');
  }
}

Future<void> _testTorbox() async {
  _title('TorBox — GET /v1/api/user/me with dummy Bearer key');
  try {
    final response = await _getRaw(
      'https://api.torbox.app/v1/api/user/me',
      query: <String, String>{'settings': 'false'},
      headers: <String, String>{'Authorization': 'Bearer invalid-key-probe'},
    );
    _info('HTTP ${response.statusCode} — ${_brief(response.data)}');
    final err = _json(response.data)?['error']?.toString() ?? '';
    if ((response.statusCode == 401 || response.statusCode == 403) &&
        err.contains('BAD_TOKEN')) {
      _ok('endpoint reachable, auth shape correct ($err for a bad key).');
    } else {
      _info('unexpected status — inspect.');
    }
  } catch (error) {
    _bad('network error: $error');
  }
}
