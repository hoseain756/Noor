import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

export 'package:media_kit/media_kit.dart'
    show AudioTrack, SubtitleTrack, Track, Tracks;

/// Facade between the player UI and the native playback engine.
///
/// The chrome never talks to media_kit directly (except through the
/// [PlayerVideoSurface] widget below), so the engine implementation can be
/// swapped without touching a single control widget.
abstract class PlaybackEngine extends ChangeNotifier {
  /// Media is parsed and has a known duration (safe to seek).
  bool get ready;

  bool get playing;
  bool get buffering;
  bool get completed;
  bool get failed;
  String? get errorMessage;

  Duration get position;
  Duration get duration;
  Duration get bufferedEnd;

  double get rate;
  double get volume; // normalized 0..1
  bool get muted;

  List<AudioTrack> get audioTracks;
  List<SubtitleTrack> get subtitleTracks;
  AudioTrack get selectedAudio;
  SubtitleTrack get selectedSubtitle;

  /// Text lines of the subtitle mpv currently renders (embedded or external
  /// tracks alike, already shifted by `sub-delay`). The subtitle overlay
  /// listens to this stream — mpv stays the single text/timing authority
  /// while visual styling lives Flutter-side (see SubtitleOverlay).
  Stream<List<String>> get subtitleTexts;

  /// Current subtitle lines (initial value for late listeners).
  List<String> get subtitleTextSnapshot;

  Future<void> open(String url,
      {Duration? startAt, Map<String, String>? httpHeaders});
  Future<void> play();
  Future<void> pause();
  Future<void> togglePlayPause();
  Future<void> seekTo(Duration target);
  Future<void> seekBy(int seconds);
  Future<void> setRate(double rate);
  Future<void> setVolume(double volume); // 0..1
  Future<void> toggleMute();
  Future<void> selectAudio(AudioTrack track);

  /// [SubtitleTrack.no] disables subtitles.
  Future<void> selectSubtitle(SubtitleTrack track);

  /// Load an external subtitle from a URL (addon-provided SRT/VTT/ASS…).
  Future<void> setSubtitleUri(String url, {String? title});

  /// NOTE: visual subtitle styling intentionally has NO engine method.
  /// media_kit runs with `libass: false` → mpv `sub-visibility=no`, so
  /// libmpv-side style properties (sub-color, sub-font-size, sub-pos, …)
  /// would target a renderer nobody sees. Styling is applied by the
  /// Flutter-side SubtitleOverlay from SubtitleStyle (live, user-driven).

  /// Live subtitle timing offset: negative = advance (earlier),
  /// positive = delay (later). Maps to mpv `sub-delay` seconds.
  Future<void> setSubtitleDelayMs(int delayMs);

  /// Live audio timing offset in ms (positive = delay) → mpv `audio-delay`.
  Future<void> setAudioDelayMs(int delayMs);
}

/// libmpv-backed implementation (media_kit).
///
/// Why libmpv: full codec coverage (RMVB / MKV / TS / FLV / AVI …), embedded
/// audio & subtitle track switching, hardware decoding (MediaCodec /
/// VideoToolbox) and speed control — none of which the previous
/// `video_player` (ExoPlayer / AVPlayer) facade exposed. Native binaries are
/// prebuilt by `media_kit_libs_android_video` / `media_kit_libs_ios_video`,
/// so no NDK/Xcode compilation happens on the app side.
class MediaKitEngine extends PlaybackEngine {
  /// [hardwareAcceleration] = false builds the video controller around
  /// software decoding — the automatic second chance the player page gives a
  /// stream whose texture never delivers a frame on finicky GPU/driver combos
  /// (low-end Mali devices render an eternal WHITE surface when MediaCodec
  /// stalls — Task 128).
  MediaKitEngine({this.hardwareAcceleration = true}) {
    // Defensive belt-and-braces (Task 127): main() calls the idempotent
    // ensureInitialized already, but every entry point that constructs the
    // engine (player page, magnet opener, library, live TV, next-episode)
    // must survive even if a future boot path forgets it.
    MediaKit.ensureInitialized();
    _player = Player();
    _controller = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        // Use Android's native video decoder directly when available. The
        // conservative auto-safe policy can leave some device/source pairs on
        // the CPU decoder, which makes high-resolution playback stutter.
        hwdec: defaultTargetPlatform == TargetPlatform.android
            ? (hardwareAcceleration ? 'mediacodec' : 'no')
            : null,
        enableHardwareAcceleration: hardwareAcceleration,
      ),
    );
    _subscriptions = [
      _player.stream.playing.listen(_onPlaying),
      _player.stream.completed.listen(_onCompleted),
      _player.stream.buffering.listen(_onBuffering),
      _player.stream.position.listen(_onPosition),
      _player.stream.duration.listen(_onDuration),
      _player.stream.buffer.listen(_onBuffer),
      _player.stream.rate.listen(_onRate),
      _player.stream.volume.listen(_onVolume),
      _player.stream.tracks.listen(_onTracks),
      _player.stream.track.listen(_onSelectedTrack),
      _player.stream.error.listen(_onError),
    ];
  }

  late final Player _player;
  late final VideoController _controller;
  List<StreamSubscription<dynamic>> _subscriptions = const [];
  bool _disposed = false;

  /// Whether the video controller uses hardware decoding (see [ctor]).
  final bool hardwareAcceleration;

  /// True once the page's stuck-watchdog forced a software-decoding retry —
  /// a second stall must surface as an error instead of retrying forever.
  bool softwareRetryUsed = false;

  bool _playing = false;
  bool _buffering = true;
  bool _completed = false;
  bool _failed = false;
  String? _errorMessage;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;
  double _rate = 1.0;
  double _volume = 1.0;
  double _lastNonZeroVolume = 1.0;
  Tracks _tracks = const Tracks();
  Track _selected = const Track();

  // ── PlaybackEngine ──────────────────────────────────────────────────────

  @override
  bool get ready => _duration > Duration.zero;

  @override
  bool get playing => _playing;

  @override
  bool get buffering => _buffering;

  @override
  bool get completed => _completed;

  @override
  bool get failed => _failed;

  @override
  String? get errorMessage => _errorMessage;

  @override
  Duration get position => _position;

  @override
  Duration get duration => _duration;

  @override
  Duration get bufferedEnd => _buffer;

  @override
  double get rate => _rate;

  @override
  double get volume => _volume;

  @override
  bool get muted => _volume <= 0.001;

  @override
  List<AudioTrack> get audioTracks => _tracks.audio;

  @override
  List<SubtitleTrack> get subtitleTracks => _tracks.subtitle;

  @override
  AudioTrack get selectedAudio => _selected.audio;

  @override
  SubtitleTrack get selectedSubtitle => _selected.subtitle;

  @override
  Stream<List<String>> get subtitleTexts => _player.stream.subtitle;

  @override
  List<String> get subtitleTextSnapshot => _player.state.subtitle;

  /// Texture-backed video surface (subtitles render Flutter-side — see
  /// [PlayerVideoSurface.overlay] and widgets/subtitle_overlay.dart).
  VideoController get controller => _controller;

  @override
  Future<void> open(String url,
      {Duration? startAt, Map<String, String>? httpHeaders}) async {
    if (_disposed) return;
    _failed = false;
    _errorMessage = null;
    _completed = false;
    _buffering = true;
    notifyListeners();
    // VideoController initializes asynchronously after the first Flutter
    // frame. Opening mpv before that completes can let audio start while the
    // Android video output is still being configured.
    try {
      await _controller.platform.future;
    } catch (error) {
      if (!_disposed) _onError(error.toString());
      return;
    }
    if (_disposed) return;
    if (Uri.tryParse(url)?.host == '127.0.0.1') {
      await _configureTorrentBuffer();
    }
    // Opening paused, seeking to the resume point once the media is parsed,
    // then starting playback keeps mpv from decoding the first frames twice.
    await _player.open(
        Media(url,
            httpHeaders: httpHeaders == null || httpHeaders.isEmpty
                ? null
                : httpHeaders),
        play: false);
    if (startAt != null && startAt > Duration.zero) {
      await _player.seek(startAt);
    }
    if (!_disposed) await _player.play();
    if (Uri.tryParse(url)?.host == '127.0.0.1') {
      unawaited(_logTorrentDecoderPath());
    }
  }

  Future<void> _logTorrentDecoderPath() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    if (_disposed) return;
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    try {
      final codec = await platform.getProperty('video-codec');
      final decoder = await platform.getProperty('hwdec-current');
      debugPrint(
        '[NoorPlayback] video codec=$codec decoder=${decoder.isEmpty ? 'software' : decoder}',
      );
    } catch (_) {
      // Diagnostic only; playback must not depend on optional mpv properties.
    }
  }

  /// Let the local torrent stream read ahead enough data to absorb short peer
  /// speed changes. The initial wait is deliberately short so playback can
  /// start after the first few seconds of media, without waiting for a large
  /// percentage of the torrent to finish.
  Future<void> _configureTorrentBuffer() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    const properties = <String, String>{
      'cache': 'yes',
      'cache-secs': '45',
      'cache-pause': 'yes',
      'cache-pause-initial': 'yes',
      'cache-pause-wait': '3',
      // Nuvio's Android MPV path keeps each demuxer cache within 32–64 MiB.
      // A 192 MiB forward cache can pressure RAM on entry-level phones and
      // cause the very frame/audio stutter this cache is meant to prevent.
      'demuxer-max-bytes': '64MiB',
      'demuxer-max-back-bytes': '16MiB',
    };
    for (final entry in properties.entries) {
      try {
        await platform.setProperty(entry.key, entry.value);
      } catch (_) {
        // Keep playback available if this mpv build does not expose a tuning
        // option; the torrent's own rolling piece window still applies.
      }
    }
  }

  @override
  Future<void> play() async {
    if (!_disposed) await _player.play();
  }

  @override
  Future<void> pause() async {
    if (!_disposed) await _player.pause();
  }

  @override
  Future<void> togglePlayPause() async {
    if (_disposed) return;
    if (_player.state.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  @override
  Future<void> seekTo(Duration target) async {
    if (_disposed || _duration <= Duration.zero) return;
    final clamped = Duration(
      milliseconds: target.inMilliseconds.clamp(0, _duration.inMilliseconds),
    );
    await _player.seek(clamped);
  }

  @override
  Future<void> seekBy(int seconds) async {
    await seekTo(_position + Duration(seconds: seconds));
  }

  @override
  Future<void> setRate(double rate) async {
    if (_disposed) return;
    await _player.setRate(rate.clamp(0.25, 4.0));
  }

  @override
  Future<void> setVolume(double volume) async {
    if (_disposed) return;
    final v = volume.clamp(0.0, 1.0);
    if (v > 0.001) _lastNonZeroVolume = v;
    // mpv volume domain is 0..100.
    await _player.setVolume(v * 100.0);
  }

  @override
  Future<void> toggleMute() async {
    await setVolume(muted ? _lastNonZeroVolume : 0.0);
  }

  @override
  Future<void> selectAudio(AudioTrack track) async {
    if (_disposed) return;
    await _player.setAudioTrack(track);
  }

  @override
  Future<void> selectSubtitle(SubtitleTrack track) async {
    if (_disposed) return;
    await _player.setSubtitleTrack(track);
  }

  @override
  Future<void> setSubtitleUri(String url, {String? title}) async {
    if (_disposed) return;
    await _player.setSubtitleTrack(SubtitleTrack.uri(url, title: title));
  }

  @override
  Future<void> setSubtitleDelayMs(int delayMs) async {
    if (_disposed) return;
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.setProperty(
          'sub-delay', (delayMs / 1000).toStringAsFixed(3));
    } catch (_) {/* best-effort */}
  }

  @override
  Future<void> setAudioDelayMs(int delayMs) async {
    if (_disposed) return;
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.setProperty(
          'audio-delay', (delayMs / 1000).toStringAsFixed(3));
    } catch (_) {/* best-effort */}
  }

  // ── Stream handlers ─────────────────────────────────────────────────────

  void _onPlaying(bool value) {
    _playing = value;
    if (value) _buffering = false;
    _notifySafely();
  }

  void _onCompleted(bool value) {
    if (_completed == value) return;
    _completed = value;
    if (value) {
      _playing = false;
      _position = _duration;
    }
    _notifySafely();
  }

  void _onBuffering(bool value) {
    if (_buffering == value) return;
    _buffering = value;
    _notifySafely();
  }

  void _onPosition(Duration value) {
    _position = value;
    _notifySafely();
  }

  void _onDuration(Duration value) {
    _duration = value;
    _notifySafely();
  }

  void _onBuffer(Duration value) {
    _buffer = value;
    _notifySafely();
  }

  void _onRate(double value) {
    if ((_rate - value).abs() < 0.001) return;
    _rate = value;
    _notifySafely();
  }

  void _onVolume(double value) {
    final normalized = (value / 100.0).clamp(0.0, 1.0);
    if (normalized > 0.001) _lastNonZeroVolume = normalized;
    if ((_volume - normalized).abs() < 0.001) return;
    _volume = normalized;
    _notifySafely();
  }

  void _onTracks(Tracks value) {
    _tracks = value;
    _notifySafely();
  }

  void _onSelectedTrack(Track value) {
    _selected = value;
    _notifySafely();
  }

  void _onError(String message) {
    _failed = true;
    _errorMessage = message;
    _notifySafely();
  }

  void _notifySafely() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions = const [];
    unawaited(_player.dispose());
    super.dispose();
  }
}

/// The only media_kit type the player chrome is allowed to touch.
class PlayerVideoSurface extends StatelessWidget {
  const PlayerVideoSurface({
    super.key,
    required this.engine,
    required this.fit,
    this.overlay,
  });

  final MediaKitEngine engine;
  final BoxFit fit;

  /// Layered above the video inside the same surface (the settings-aware
  /// [SubtitleOverlay] — kept here so it inherits the page's pinch-zoom
  /// transform exactly like media_kit's own subtitle view used to).
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Video(
          controller: engine.controller,
          fit: fit,
          // All chrome is rendered by this app's own player widgets.
          controls: null,
          wakelock: true,
          // Subtitle text rendering is owned by [overlay]: media_kit's
          // built-in SubtitleView carries a compile-time constant TextStyle
          // (fixed white/26 — user settings could never reach the screen),
          // and native libass rendering is disabled anyway
          // (PlayerConfiguration.libass = false → mpv sub-visibility=no).
          subtitleViewConfiguration:
              const SubtitleViewConfiguration(visible: false),
        ),
        if (overlay != null) Positioned.fill(child: overlay!),
      ],
    );
  }
}
