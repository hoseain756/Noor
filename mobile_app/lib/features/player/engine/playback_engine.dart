import 'dart:async';

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

  Future<void> open(String url, {Duration? startAt, Map<String, String>? httpHeaders});
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

  /// Best-effort user subtitle styling via libmpv properties.
  Future<void> applySubtitleStyle({
    int? fontSize,
    String? colorHex,      // #RRGGBB
    String? borderColorHex,
    int? borderSize,
    double? backgroundOpacity, // 0..1
    String? style,             // shadow|opaque|outline
  });
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
  MediaKitEngine() {
    _player = Player();
    _controller = VideoController(_player);
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

  /// Texture-backed video surface with libass subtitle rendering.
  VideoController get controller => _controller;

  @override
  Future<void> open(String url, {Duration? startAt, Map<String, String>? httpHeaders}) async {
    if (_disposed) return;
    _failed = false;
    _errorMessage = null;
    _completed = false;
    _buffering = true;
    notifyListeners();
    // Opening paused, seeking to the resume point once the media is parsed,
    // then starting playback keeps mpv from decoding the first frames twice.
        await _player.open(
        Media(url, httpHeaders: httpHeaders == null || httpHeaders.isEmpty ? null : httpHeaders),
        play: false);
    if (startAt != null && startAt > Duration.zero) {
      await _player.seek(startAt);
    }
    if (!_disposed) await _player.play();
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
  Future<void> applySubtitleStyle({
    int? fontSize,
    String? colorHex,
    String? borderColorHex,
    int? borderSize,
    double? backgroundOpacity,
    String? style,
  }) async {
    if (_disposed) return;
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    Future<void> prop(String name, String value) async {
      try {
        await platform.setProperty(name, value);
      } catch (_) {/* best-effort: some platforms lack native props */}
    }

    if (fontSize != null) await prop('sub-font-size', '$fontSize');
    if (colorHex != null) await prop('sub-color', colorHex);
    if (borderColorHex != null) await prop('sub-border-color', borderColorHex);
    if (borderSize != null) await prop('sub-border-size', '$borderSize');
    if (style == 'opaque') await prop('sub-border-style', 'opaque');
    if (style == 'outline' || style == 'shadow') {
      await prop('sub-border-style', 'outline-and-shadow');
    }
    if (backgroundOpacity != null) {
      final a = (backgroundOpacity.clamp(0.0, 1.0) * 255).round();
      await prop('sub-back-color', '#${a.toRadixString(16).padLeft(2, '0')}000000');
    }
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
  });

  final MediaKitEngine engine;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Video(
      controller: engine.controller,
      fit: fit,
      // All chrome is rendered by this app's own player widgets.
      controls: null,
      wakelock: true,
      // libass subtitle rendering over the texture.
      subtitleViewConfiguration: const SubtitleViewConfiguration(
        style: TextStyle(
          color: Colors.white,
          fontSize: 26,
          height: 1.35,
          shadows: [
            Shadow(color: Colors.black, blurRadius: 6),
            Shadow(color: Colors.black, blurRadius: 2),
          ],
        ),
      ),
    );
  }
}
