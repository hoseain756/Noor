import 'package:flutter/foundation.dart' show immutable;

/// A normalized playback target for a Stremio stream entry: the cleaned URL
/// plus the HTTP headers the player (mpv) must send with the request.
@immutable
class PlaybackSource {
  const PlaybackSource(
      {required this.url, this.headers = const <String, String>{}});

  final String url;
  final Map<String, String> headers;
}

/// Normalizes every header-carrying shape Stremio addons use in practice:
///
/// 1. Pipe syntax (4players/MediaPipe style):
///    `https://host/file.mkv|User-Agent=Foo&Referer=Bar`
/// 2. Flat `behaviorHints.proxyHeaders` map: `{User-Agent: Foo, ...}`
/// 3. Spec-nested shape: `proxyHeaders: {request: {...}, response: {...}}`
///    (only `request` headers are sendable by the player)
/// 4. Legacy `behaviorHints.headers` map.
///
/// Absorption order below is the precedence order: pipe syntax wins, then
/// proxyHeaders, then legacy headers (first writer keeps the slot).
PlaybackSource? parsePlaybackSource(Map<String, dynamic>? stream) {
  if (stream == null) return null;
  final raw = stream['url'];
  if (raw is! String || raw.isEmpty) return null;

  var url = raw;
  final headers = <String, String>{};

  void absorb(Map rawHeaders) {
    rawHeaders.forEach((key, value) {
      if (key == null || value == null) return;
      // Scalar values only: nested maps inside a flat header block are shape
      // markers (request/response), not sendable header values.
      if (value is Map || value is List) return;
      final k = key.toString().trim();
      final v = value.toString().trim();
      if (k.isEmpty || v.isEmpty) return;
      headers.putIfAbsent(k, () => v);
    });
  }

  // 1) Pipe syntax on the URL itself.
  final pipe = url.indexOf('|');
  if (pipe >= 0) {
    final tail = url.substring(pipe + 1);
    url = url.substring(0, pipe);
    for (final pair in tail.split('&')) {
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final k = pair.substring(0, eq).trim();
      final v = pair.substring(eq + 1).trim();
      if (k.isNotEmpty && v.isNotEmpty) headers.putIfAbsent(k, () => v);
    }
  }

  final hints = stream['behaviorHints'];
  if (hints is Map) {
    // 2/3) proxyHeaders: flat map or nested {request, response}.
    final proxy = hints['proxyHeaders'];
    if (proxy is Map) {
      final request = proxy['request'];
      if (request is Map) {
        absorb(request);
      } else if (proxy['response'] is Map) {
        // Nested response-only shape: nothing the player can send.
      } else {
        absorb(proxy);
      }
    }
    // 4) Legacy flat headers block.
    final legacy = hints['headers'];
    if (legacy is Map) absorb(legacy);
  }

  return PlaybackSource(url: url, headers: Map.unmodifiable(headers));
}
