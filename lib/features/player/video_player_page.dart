import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

import '../../core/models/media_item.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';
import '../../core/torrent/torrent_models.dart';
import '../../core/torrent/torrent_service.dart';
import 'engine/playback_engine.dart';
import 'widgets/player_chrome.dart';
import 'widgets/player_sheets.dart';

/// Cinematic player (reference design): the video is the screen — white
/// controls, teal→blue gradient timeline, large outlined central play
/// control, side rails (orientation / fit / lock · audio / episodes / speed)
/// and gesture-first interaction:
///   · tap            — show / hide chrome
///   · double-tap     — ±10 s (edges) · play/pause (center)
///   · horizontal drag— scrub with live seek HUD
///   · vertical drag  — left: brightness · right: system volume
///   · pinch          — zoom 1×–4×
/// Engine is libmpv (media_kit) behind the [PlaybackEngine] facade.
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    super.key,
    required this.item,
    required this.url,
    required this.streamName,
    required this.videoId,
    this.initialPositionMs,
    this.season,
    this.episode,
    this.streams = const [],
    this.streamIndex,
    this.onSwitchStream,
    this.headers,
    this.filename,
    this.torrent,
    this.nextEpisode,
    this.recordProgress = true,
  });

  final MediaItem item;
  final String url;
  final String streamName;
  final String videoId;
  final int? initialPositionMs;
  final int? season;
  final int? episode;
  final List<Map<String, dynamic>> streams;
  final int? streamIndex;
  final Future<void> Function(Map<String, dynamic> stream)? onSwitchStream;

  /// Extra HTTP headers (addon behaviorHints.proxyHeaders) for direct streams.
  final Map<String, String>? headers;

  /// Human stream name hint (used for debrid resolution).
  final String? filename;

  /// Prepared on-device torrent stream (when source was an infoHash).
  final PreparedTorrent? torrent;

  /// Explicit next-episode map from the detail page (fallback: computed).
  final Map<String, dynamic>? nextEpisode;
  final bool recordProgress;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

enum _GestureMode { none, seek, brightness, volume, zoom }

enum _OrientationMode { auto, landscape, portrait }

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  MediaKitEngine? _engine;
  Timer? _hideTimer;
  Timer? _progressTimer;
  StreamSubscription<TorrentStatus>? _torrentSub;
  TorrentStatus? _torrentStatus;
  Timer? _hintTimer;

  bool _controlsVisible = true;
  bool _locked = false;
  bool _sheetOpen = false;
  BoxFit _fit = BoxFit.contain;
  double _zoom = 1.0;
  bool _showRemaining = false;
  bool _fullscreen = true;

  // Resume flow.
  bool _resuming = false;
  int? _resumePositionMs;
  bool _stopScrobbled = false;
  bool _upNextDismissed = false;
  int _streamIndex = 0;

  // Gesture state.
  _GestureMode _mode = _GestureMode.none;
  double _zoomStart = 1.0;
  double _dragStartDx = 0;
  double _dragAccumDx = 0;
  int _positionAtDragStartMs = 0;
  double? _brightnessStart;
  double _hudValue = 0;
  int _hudDeltaSeconds = 0;
  int _hudTargetMs = 0;

  // Double-tap ripple state (Task 124 mandate: animated ±N feedback).
  int _rippleKey = 0;
  bool _rippleForward = false;
  int _rippleSeconds = 10;
  Timer? _rippleTimer;

  _OrientationMode _orientation = _OrientationMode.auto;

  @override
  void initState() {
    super.initState();
    _streamIndex = widget.streamIndex ?? 0;
    _resumePositionMs = widget.initialPositionMs;
    _resuming = (_resumePositionMs ?? 0) > 30000;
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _progressTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_saveProgress()),
    );
    _createEngine();
    _listenTorrent();
    _applySubtitleStyle();
  }

  void _listenTorrent() {
    final torrent = widget.torrent;
    if (torrent == null) return;
    _torrentSub = torrent.statusStream.listen((status) {
      if (!mounted) return;
      setState(() => _torrentStatus = status);
    });
  }

  void _applySubtitleStyle() {
    final st = context.read<AppState>().webSettings;
    final engineRef = _engine;
    if (engineRef == null) return;
    unawaited(engineRef.applySubtitleStyle(
      fontSize: (st['subFontSize'] as num?)?.toInt(),
      colorHex: st['subFontColor'] as String?,
      borderColorHex: st['subBorderColor'] as String?,
      borderSize: (st['subBorderSize'] as num?)?.toInt(),
      backgroundOpacity: (st['subBackgroundOpacity'] as num?)?.toDouble(),
      style: st['subStyle'] as String?,
      position: (st['subPos'] as num?)?.toInt(),
    ));
    unawaited(engineRef
        .setSubtitleDelayMs((st['subtitleOffsetMs'] as num?)?.toInt() ?? 0));
    if (st['subtitlesOffByDefault'] == true) {
      unawaited(engineRef.selectSubtitle(SubtitleTrack.no()));
    }
  }

  /// Configurable skip steps (spec: "preset seconds in the settings").
  int get _backStepSec =>
      (context.read<AppState>().webSettings['seekBackStepSec'] as num?)
          ?.toInt() ??
      10;

  int get _forwardStepSec =>
      (context.read<AppState>().webSettings['seekForwardStepSec'] as num?)
          ?.toInt() ??
      10;

  void _createEngine() {
    final engine = MediaKitEngine();
    _engine = engine;
    engine.addListener(_onEngineTick);
    unawaited(
      engine.open(
        widget.url,
        startAt:
            !_resuming ? Duration(milliseconds: _resumePositionMs ?? 0) : null,
        httpHeaders: widget.headers,
      ),
    );
    _bumpControls();
  }

  void _onEngineTick() {
    if (!mounted) return;
    final engine = _engine;
    if (engine == null) return;
    if (engine.completed && !_stopScrobbled) {
      _stopScrobbled = true;
      _scrobble('stop');
      unawaited(_saveProgress());
    }
    setState(() {});
  }

  // ── Episodes ────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get _episodes => widget.item.videos
      .where((v) => ((v['season'] as num?)?.toInt() ?? 0) > 0)
      .toList()
    ..sort((a, b) {
      final bySeason =
          ((a['season'] as num?) ?? 0).compareTo((b['season'] as num?) ?? 0);
      if (bySeason != 0) return bySeason;
      return ((a['episode'] as num?) ?? 0)
          .compareTo((b['episode'] as num?) ?? 0);
    });

  int _currentEpisodeIndex() {
    if (widget.item.type != 'series') return -1;
    final episodes = _episodes;
    for (var i = 0; i < episodes.length; i++) {
      if (episodes[i]['id'] == widget.videoId) return i;
    }
    return episodes.isEmpty ? -1 : 0;
  }

  Map<String, dynamic>? _episodeAt(int index) {
    final episodes = _episodes;
    if (index < 0 || index >= episodes.length) return null;
    return episodes[index];
  }

  // ── Chrome visibility ───────────────────────────────────────────────────

  void _bumpControls() {
    if (_locked) return;
    setState(() => _controlsVisible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 4000), () {
      if (!mounted) return;
      final engine = _engine;
      final playing = engine?.playing ?? false;
      if (playing && !_sheetOpen && _mode == _GestureMode.none) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _bumpControls();
    }
  }

  void _flashHint(String message) {
    _hintTimer?.cancel();
    _lastHint = message;
    setState(() {});
    _hintTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() {});
    });
  }

  String _lastHint = '';

  bool get _hintVisible => _hintTimer?.isActive ?? false;

  // ── Transport ───────────────────────────────────────────────────────────

  Future<void> _togglePlay() async {
    final engine = _engine;
    if (engine == null || !engine.ready) return;
    if (engine.playing) {
      await engine.pause();
      _scrobble('pause');
      _hideTimer?.cancel();
      if (mounted) setState(() => _controlsVisible = true);
    } else {
      await engine.play();
      _scrobble('start');
      _bumpControls();
    }
  }

  Future<void> _seekBy(int seconds) async {
    final engine = _engine;
    if (engine == null || !engine.ready) return;
    await engine.seekBy(seconds);
    _flashHint(
      english
          ? '${seconds > 0 ? '+' : ''}$seconds s'
          : '${seconds > 0 ? '+' : ''}$seconds ث',
    );
    _bumpControls();
  }

  /// Fullscreen toggle (Task 124): hides/shows the system UI around the
  /// immersive video surface.
  Future<void> _toggleFullscreen() async {
    final next = !_fullscreen;
    setState(() => _fullscreen = next);
    await SystemChrome.setEnabledSystemUIMode(
      next ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    _bumpControls();
  }

  /// Shows the mandated double-tap ripple (Task 124) on the tapped side.
  void _showRipple({required bool forward, required int seconds}) {
    _rippleTimer?.cancel();
    setState(() {
      _rippleKey++;
      _rippleForward = forward;
      _rippleSeconds = seconds;
    });
    _rippleTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() {});
    });
  }

  bool get _rippleVisible => _rippleTimer?.isActive ?? false;

  Future<void> _saveProgress() async {
    if (!widget.recordProgress) return;
    final engine = _engine;
    if (engine == null || !engine.ready) return;
    await context.read<AppState>().recordPlayback(
          widget.item,
          positionMs: engine.position.inMilliseconds,
          durationMs: engine.duration.inMilliseconds,
          videoId: widget.videoId,
          season: widget.season,
          episode: widget.episode,
        );
  }

  void _scrobble(String action) {
    final app = context.read<AppState>();
    final engine = _engine;
    final duration = engine?.duration.inMilliseconds ?? 0;
    final progress = duration <= 0
        ? 0.0
        : (engine!.position.inMilliseconds / duration) * 100;
    final type = widget.item.type == 'series' ? 'series' : 'movie';
    final year =
        RegExp(r'^\d{4}').firstMatch(widget.item.releaseInfo ?? '')?.group(0);
    for (final service in const ['trakt', 'simkl']) {
      if (!app.api.isLinked(service)) continue;
      unawaited(app.api.scrobbleLinkedService(
        service,
        action: action,
        type: type,
        title: widget.item.name,
        year: year,
        imdb: widget.item.id,
        progress: progress,
      ));
    }
  }

  Future<void> _close() async {
    _scrobble('stop');
    _stopScrobbled = true;
    await _saveProgress();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _switchStream(Map<String, dynamic> stream) async {
    final callback = widget.onSwitchStream;
    if (callback == null) return;
    await _saveProgress();
    await callback(stream);
  }

  Future<void> _resumeFromSaved() async {
    final engine = _engine;
    if (engine == null || !engine.ready) return;
    final end = engine.duration.inMilliseconds;
    await engine.seekTo(
      Duration(
        milliseconds: (_resumePositionMs ?? 0).clamp(0, end - 5000).toInt(),
      ),
    );
    await engine.play();
    if (mounted) setState(() => _resuming = false);
    _bumpControls();
  }

  // ── Chrome actions ──────────────────────────────────────────────────────

  void _lock() {
    _hideTimer?.cancel();
    setState(() {
      _locked = true;
      _controlsVisible = false;
    });
  }

  void _unlock() {
    setState(() => _locked = false);
    _bumpControls();
  }

  Future<void> _cycleOrientation() async {
    switch (_orientation) {
      case _OrientationMode.auto:
        _orientation = _OrientationMode.landscape;
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        _flashHint(english ? 'Landscape' : 'أفقي');
      case _OrientationMode.landscape:
        _orientation = _OrientationMode.portrait;
        await SystemChrome.setPreferredOrientations(
          const [DeviceOrientation.portraitUp],
        );
        _flashHint(english ? 'Portrait' : 'عمودي');
      case _OrientationMode.portrait:
        _orientation = _OrientationMode.auto;
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
          DeviceOrientation.portraitUp,
        ]);
        _flashHint(english ? 'Auto-rotate' : 'تدوير تلقائي');
    }
    _bumpControls();
  }

  Future<void> _cycleFit() async {
    setState(() {
      if (_fit == BoxFit.contain) {
        _fit = BoxFit.cover;
        _flashHint(english ? 'Fill' : 'ملء');
      } else if (_fit == BoxFit.cover) {
        _fit = BoxFit.fill;
        _flashHint(english ? 'Stretch' : 'تمديد');
      } else {
        _fit = BoxFit.contain;
        _zoom = 1;
        _flashHint(english ? 'Fit' : 'احتواء');
      }
    });
    _bumpControls();
  }

  String get _speedLabel {
    final rate = _engine?.rate ?? 1.0;
    return '${rate == rate.roundToDouble() ? rate.toStringAsFixed(1) : rate}X';
  }

  // ── Sheets ──────────────────────────────────────────────────────────────

  Future<void> _openSheet(Future<void> Function() show) async {
    _sheetOpen = true;
    _hideTimer?.cancel();
    if (mounted) setState(() => _controlsVisible = true);
    try {
      await show();
    } finally {
      if (mounted) {
        setState(() => _sheetOpen = false);
        _bumpControls();
      }
    }
  }

  Future<void> _openSettings() => _openSheet(() async {
        final next = await showPlayerSheet<String>(
          context,
          builder: (_) => PlayerSettingsSheet(
            english: english,
            speed: _engine?.rate ?? 1.0,
            fit: _fit,
            audioLabel: _audioLabel,
            subtitleLabel: _subtitleLabel,
            hasEpisodes: widget.item.type == 'series' && _episodes.isNotEmpty,
            onSpeed: (value) {
              Navigator.of(context).pop('speed:${value.toString()}');
            },
            onFit: (fit) => Navigator.of(context).pop('fit:$fit'),
            onOpenAudio: () => Navigator.of(context).pop('audio'),
            onOpenSubtitles: () => Navigator.of(context).pop('subtitles'),
            onOpenEpisodes: () => Navigator.of(context).pop('episodes'),
          ),
        );
        if (!mounted || next == null) return;
        if (next.startsWith('speed:')) {
          final value = double.tryParse(next.substring(6));
          if (value != null) await _engine?.setRate(value);
        } else if (next.startsWith('fit:')) {
          final name = next.substring(4);
          setState(() {
            _fit = name == 'BoxFit.cover'
                ? BoxFit.cover
                : name == 'BoxFit.fill'
                    ? BoxFit.fill
                    : BoxFit.contain;
          });
        } else if (next == 'audio') {
          await _openAudioSheet();
        } else if (next == 'subtitles') {
          await _openSubtitlesSheet();
        } else if (next == 'episodes') {
          await _openEpisodesSheet();
        }
      });

  String get _audioLabel {
    final track = _engine?.selectedAudio;
    if (track == null || track.id == 'auto' || track.id.isEmpty) {
      return english ? 'Default' : 'افتراضي';
    }
    return (track.title?.isNotEmpty == true
            ? track.title!
            : track.language?.isNotEmpty == true
                ? track.language!
                : '${english ? 'Track' : 'مسار'} ${track.id}')
        .split('\n')
        .first;
  }

  String get _subtitleLabel {
    final track = _engine?.selectedSubtitle;
    if (track == null || track.id == 'no') {
      return english ? 'Off' : 'إيقاف';
    }
    if (track.id == 'auto' || track.id.isEmpty) {
      return english ? 'Auto' : 'تلقائي';
    }
    return (track.title?.isNotEmpty == true
            ? track.title!
            : track.language?.isNotEmpty == true
                ? track.language!
                : '${english ? 'Track' : 'مسار'} ${track.id}')
        .split('\n')
        .first;
  }

  Future<void> _openAudioSheet() => _openSheet(() async {
        final engine = _engine;
        if (engine == null) return;
        await showPlayerSheet<void>(
          context,
          builder: (_) => AudioTracksSheet(
            english: english,
            tracks: engine.audioTracks,
            selected: engine.selectedAudio,
            onPick: (track) => unawaited(engine.selectAudio(track)),
          ),
        );
      });

  List<Map<String, dynamic>> _externalSubRows = const [];

  Future<void> _loadExternalSubs() async {
    if (_externalSubRows.isNotEmpty) return;
    try {
      final app = context.read<AppState>();
      final subs = await app.catalogs
          .subtitles(widget.item.type, widget.videoId, app.addons);
      _externalSubRows = subs.where((sub) => sub['url'] is String).toList();
    } catch (_) {
      _externalSubRows = const [];
    }
  }

  Future<void> _openSubtitlesSheet() => _openSheet(() async {
        final engine = _engine;
        if (engine == null) return;
        await _loadExternalSubs();
        if (!mounted) return;
        final result = await showPlayerSheet<String>(
          context,
          builder: (_) => SubtitleTracksSheet(
            english: english,
            embedded: engine.subtitleTracks,
            external: _externalSubRows,
            selected: engine.selectedSubtitle,
            onPick: (track) {
              if (track.uri && track.id.isNotEmpty) {
                unawaited(engine.setSubtitleUri(track.id, title: track.title));
              } else {
                unawaited(engine.selectSubtitle(track));
              }
            },
            onOpenSettings: () => Navigator.of(context).pop('style-settings'),
          ),
        );
        if (!mounted) return;
        if (result == 'style-settings') {
          await _openSubtitleStyleSheet();
        }
      });

  /// Live-editing subtitle style/timing sheet (user request): every change is
  /// pushed to the engine immediately and persisted through AppState.
  Future<void> _openSubtitleStyleSheet() => _openSheet(() async {
        await showPlayerSheet<void>(
          context,
          builder: (_) => SubtitleStyleSheet(
            english: english,
            onApply: _applySubtitleValues,
          ),
        );
      });

  void _applySubtitleValues(Map<String, Object?> values) {
    final engineRef = _engine;
    if (engineRef == null) return;
    unawaited(engineRef.applySubtitleStyle(
      fontSize: (values['subFontSize'] as num?)?.toInt(),
      colorHex: values['subFontColor'] as String?,
      borderColorHex: values['subBorderColor'] as String?,
      borderSize: (values['subBorderSize'] as num?)?.toInt(),
      backgroundOpacity: (values['subBackgroundOpacity'] as num?)?.toDouble(),
      style: values['subStyle'] as String?,
      position: (values['subPos'] as num?)?.toInt(),
    ));
    unawaited(engineRef.setSubtitleDelayMs(
        (values['subtitleOffsetMs'] as num?)?.toInt() ?? 0));
  }

  Future<void> _openEpisodesSheet() => _openSheet(() async {
        if (_episodes.isEmpty) return;
        await showPlayerSheet<void>(
          context,
          builder: (_) => EpisodesSheet(
            english: english,
            episodes: _episodes,
            currentVideoId: widget.videoId,
            onPick: (episode) => unawaited(_switchEpisode(episode)),
          ),
        );
      });

  Future<void> _openStreamsSheet() => _openSheet(() async {
        if (widget.streams.isEmpty) return;
        await showPlayerSheet<void>(
          context,
          builder: (_) => StreamsSheet(
            english: english,
            streams: widget.streams,
            selectedIndex: _streamIndex,
            onPick: (stream) => unawaited(_switchStream(stream)),
          ),
        );
      });

  Future<void> _switchEpisode(Map<String, dynamic> episode) async {
    final app = context.read<AppState>();
    final episodeId = (episode['id'] ?? widget.item.id).toString();
    if (episodeId == widget.videoId) return;
    try {
      final streams =
          await app.catalogs.streams(widget.item.type, episodeId, app.addons);
      final playable = streams.where((stream) {
        if (stream['url'] != null) return true;
        if (stream['infoHash'] != null) {
          if (app.api.debridService != null) return true;
          return app.webSettings['p2pEnabled'] == true;
        }
        return false;
      }).toList();
      if (playable.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                english
                    ? 'No playable source for the next episode.'
                    : 'لا يوجد مصدر قابل للتشغيل للحلقة التالية.',
              ),
            ),
          );
        }
        return;
      }
      final stream = _bestStream(playable);
      final resolved = await _resolveForPlayback(app, stream);
      if (!mounted) return;
      if (resolved == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              english
                  ? 'Could not resolve the source. Try another stream.'
                  : 'تعذر تحضير المصدر. جرّب مصدراً آخر.',
            ),
          ),
        );
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => VideoPlayerPage(
            item: widget.item,
            url: resolved.url,
            streamName:
                (stream['title'] ?? stream['addonName'] ?? 'Noor').toString(),
            videoId: episodeId,
            season: (episode['season'] as num?)?.toInt(),
            episode: (episode['episode'] as num?)?.toInt(),
            headers: resolved.headers.isEmpty ? null : resolved.headers,
            torrent: resolved.torrent,
            streams: playable,
            streamIndex: playable.indexOf(stream),
          ),
          fullscreenDialog: true,
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  Map<String, dynamic> _bestStream(List<Map<String, dynamic>> list) {
    int score(Map<String, dynamic> s) {
      final t = ((s['name'] ?? s['title'] ?? '') as String).toUpperCase();
      var v = 0;
      if (t.contains('2160') || t.contains('4K')) v += 50;
      if (t.contains('1080')) v += 40;
      if (t.contains('720')) v += 25;
      if (t.contains('480')) v += 10;
      if (RegExp('HDR|DOLBY|DV ').hasMatch(t)) v += 5;
      if (t.contains('H265') || t.contains('HEVC')) v += 3;
      return v;
    }

    final sorted = [...list]..sort((a, b) => score(b).compareTo(score(a)));
    return sorted.first;
  }

  Future<_PlaybackResolution?> _resolveForPlayback(
    AppState app,
    Map<String, dynamic> stream,
  ) async {
    final url = stream['url']?.toString();
    final headers = <String, String>{};
    final bh = stream['behaviorHints'];
    if (bh is Map && bh['proxyHeaders'] is Map) {
      (bh['proxyHeaders'] as Map).forEach(
        (k, v) => headers[k.toString()] = v.toString(),
      );
    }
    if (url != null) {
      return _PlaybackResolution(
        url: url,
        headers: headers,
        torrent: null,
      );
    }
    final infoHash = stream['infoHash']?.toString();
    if (infoHash == null) return null;
    final filename =
        (stream['filename'] ?? stream['name'] ?? widget.filename ?? '')
            .toString();
    final filesize = (stream['size'] as num?)?.toInt();
    // Premium debrid first: instant direct link, zero buffering.
    if (app.api.debridService != null) {
      final direct = await app.api.resolveDebridTorrent(
        infoHash: infoHash,
        filename: filename,
        filesize: filesize,
      );
      if (direct != null) {
        return _PlaybackResolution(
            url: direct, headers: headers, torrent: null);
      }
    }
    // On-device torrent engine: sequential streaming via localhost server.
    try {
      final torrent = await TorrentService.instance.prepare(
        infoHash: infoHash,
        filename: filename,
        filesize: filesize,
        displayName: widget.item.name,
      );
      return _PlaybackResolution(
          url: torrent.url, headers: headers, torrent: torrent);
    } on TorrentException {
      return null;
    }
  }

  // ── Gestures ────────────────────────────────────────────────────────────

  void _handleDoubleTap(TapDownDetails details) {
    if (_locked) return;
    final width = MediaQuery.sizeOf(context).width;
    final backStep = _backStepSec;
    final forwardStep = _forwardStepSec;
    if (details.localPosition.dx < width * .34) {
      _showRipple(forward: false, seconds: backStep);
      unawaited(_seekBy(-backStep));
    } else if (details.localPosition.dx > width * .66) {
      _showRipple(forward: true, seconds: forwardStep);
      unawaited(_seekBy(forwardStep));
    } else {
      unawaited(_togglePlay());
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (_locked) return;
    _hideTimer?.cancel();
    final engine = _engine;
    _gestureModeStart(details.pointerCount);
    if (details.pointerCount >= 2) {
      _mode = _GestureMode.zoom;
      _zoomStart = _zoom;
      return;
    }
    if (engine == null || !engine.ready) return;
    _dragStartDx = details.localFocalPoint.dx;
    _dragAccumDx = 0;
    _positionAtDragStartMs = engine.position.inMilliseconds;
    _brightnessStart = null;
    _mode = _GestureMode.none;
  }

  void _gestureModeStart(int pointerCount) {
    // reset per-gesture HUD values
    _hudValue = 0;
    _hudDeltaSeconds = 0;
    _hudTargetMs = 0;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_locked || _mode == _GestureMode.none && details.pointerCount == 0) {
      return;
    }
    if (_mode == _GestureMode.zoom) {
      setState(() {
        _zoom = (_zoomStart * details.scale).clamp(1.0, 4.0);
        _hudValue = _zoom;
      });
      return;
    }
    final engine = _engine;
    if (engine == null || !engine.ready) return;
    final size = MediaQuery.sizeOf(context);

    // Axis lock on first significant movement.
    if (_mode == _GestureMode.none) {
      final dx = details.focalPointDelta.dx;
      final dy = details.focalPointDelta.dy;
      if (dx.abs() < 8 && dy.abs() < 8) return;
      if (dx.abs() >= dy.abs()) {
        _mode = _GestureMode.seek;
      } else if (_dragStartDx < size.width * .35) {
        _mode = _GestureMode.brightness;
      } else if (_dragStartDx > size.width * .65) {
        _mode = _GestureMode.volume;
      } else {
        _mode = _GestureMode.seek; // center: default to scrub
      }
    }

    switch (_mode) {
      case _GestureMode.seek:
        _dragAccumDx += details.focalPointDelta.dx;
        final durationMs = engine.duration.inMilliseconds;
        // Full screen width covers half the runtime — comfortable scrub rate.
        final deltaMs = (_dragAccumDx / size.width * durationMs * .5).round();
        setState(() {
          _hudDeltaSeconds = (deltaMs / 1000).round();
          _hudTargetMs =
              (_positionAtDragStartMs + deltaMs).clamp(0, durationMs).toInt();
        });
      case _GestureMode.brightness:
        unawaited(_updateBrightness(details.focalPointDelta.dy, size.height));
      case _GestureMode.volume:
        unawaited(_updateVolume(details.focalPointDelta.dy, size.height));
      case _GestureMode.zoom:
      case _GestureMode.none:
        break;
    }
  }

  Future<void> _updateBrightness(double dy, double height) async {
    try {
      _brightnessStart ??= await ScreenBrightness().application;
      final next = (_brightnessStart! - dy / height).clamp(0.0, 1.0);
      await ScreenBrightness().setApplicationScreenBrightness(next);
      if (mounted) setState(() => _hudValue = next);
    } catch (_) {
      // Platform refused (rare); HUD stays silent rather than lying.
      _mode = _GestureMode.none;
    }
  }

  Future<void> _updateVolume(double dy, double height) async {
    try {
      final current = await VolumeController.instance.getVolume();
      final next = (current - dy / height).clamp(0.0, 1.0);
      VolumeController.instance.showSystemUI = false;
      await VolumeController.instance.setVolume(next);
      if (mounted) setState(() => _hudValue = next);
    } catch (_) {
      _mode = _GestureMode.none;
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_mode == _GestureMode.seek && _hudTargetMs > 0) {
      unawaited(_engine?.seekTo(Duration(milliseconds: _hudTargetMs)));
    }
    _mode = _GestureMode.none;
    _hudValue = 0;
    _hudDeltaSeconds = 0;
    _hudTargetMs = 0;
    if (mounted) setState(() {});
    _bumpControls();
  }

  // ── Build ───────────────────────────────────────────────────────────────

  bool get _english => context.read<AppState>().english;
  bool get english => _english;

  @override
  void dispose() {
    _hideTimer?.cancel();
    _progressTimer?.cancel();
    _hintTimer?.cancel();
    _rippleTimer?.cancel();
    _torrentSub?.cancel();
    final torrent = widget.torrent;
    if (torrent != null) unawaited(torrent.stop());
    final engine = _engine;
    engine?.removeListener(_onEngineTick);
    unawaited(_saveProgress());
    engine?.dispose();
    unawaited(_restoreBrightness());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const []);
    super.dispose();
  }

  Future<void> _restoreBrightness() async {
    try {
      await ScreenBrightness().resetApplicationScreenBrightness();
    } catch (_) {
      // Nothing to restore.
    }
  }

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
    final ready = engine != null && engine.ready;
    final failed = engine?.failed ?? false;
    final duration = engine?.duration.inMilliseconds ?? 0;
    final position = engine?.position.inMilliseconds ?? 0;
    final nearEnd = duration > 0 && (duration - position) <= 30000 ||
        (duration > 0 && position / duration >= 0.95);
    final nextEpisode = widget.item.type == 'series'
        ? _episodeAt(_currentEpisodeIndex() + 1)
        : null;
    final prevEpisode = widget.item.type == 'series'
        ? _episodeAt(_currentEpisodeIndex() - 1)
        : null;
    final width = MediaQuery.sizeOf(context).width;
    final scale = width >= 768 ? 1.15 : 1.0;
    final railTopInset = 108.0 * scale;

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && !_stopScrobbled) {
          _scrobble('stop');
          _stopScrobbled = true;
          unawaited(_saveProgress());
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // The chrome follows the reference layout (LTR media convention);
        // Arabic strings still render correctly via bidi.
        body: Directionality(
          textDirection: TextDirection.ltr,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_locked) {
                _flashHint(english ? 'Controls locked' : 'التحكم مقفل');
              } else {
                _toggleControls();
              }
            },
            onDoubleTapDown: _handleDoubleTap,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Video surface (+ pinch zoom).
                if (engine != null && engine.ready)
                  ClipRect(
                    child: Transform.scale(
                      scale: _zoom,
                      child: PlayerVideoSurface(engine: engine, fit: _fit),
                    ),
                  )
                else if (failed)
                  _ErrorPanel(
                    message: engine?.errorMessage,
                    english: english,
                    onRetry: () {
                      final old = _engine;
                      old?.removeListener(_onEngineTick);
                      old?.dispose();
                      setState(() {
                        _controlsVisible = true;
                        _zoom = 1;
                      });
                      _createEngine();
                    },
                  )
                else
                  const Center(
                    child: CircularProgressIndicator(
                      color: HorseTheme.gold,
                      strokeWidth: 2,
                    ),
                  ),

                // Torrent streaming HUD (speed / peers / progress).
                if (widget.torrent != null && _torrentStatus != null)
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + 8,
                    left: 12,
                    child: _TorrentHud(
                      status: _torrentStatus!,
                      english: english,
                    ),
                  ),

                // Buffering spark.
                if (engine != null && engine.ready && engine.buffering)
                  const Center(
                    child: SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        color: Colors.white70,
                        strokeWidth: 2,
                      ),
                    ),
                  ),

                if (ready && !failed) ...[
                  // Chrome — fades together.
                  AnimatedOpacity(
                    opacity: _controlsVisible && !_locked ? 1 : 0,
                    duration: const Duration(milliseconds: 280),
                    child: IgnorePointer(
                      ignoring: !_controlsVisible || _locked,
                      child: Stack(
                        children: [
                          PlayerTopBar(
                            title: widget.item.name,
                            episodeTag: widget.item.type == 'series'
                                ? seasonEpisodeTag(
                                    widget.season, widget.episode)
                                : '',
                            onClose: _close,
                          ),
                          PlayerSideRail(
                            side: AxisSide.left,
                            topInset: railTopInset,
                            children: [
                              PlayerRailButton(
                                icon: _orientationIcon,
                                semanticLabel: 'Orientation',
                                onTap: () => unawaited(_cycleOrientation()),
                              ),
                              PlayerRailButton(
                                icon: Icons.aspect_ratio_rounded,
                                semanticLabel: 'Video fit',
                                onTap: () => unawaited(_cycleFit()),
                              ),
                              PlayerRailButton(
                                icon: Icons.lock_outline_rounded,
                                semanticLabel: 'Lock controls',
                                onTap: _lock,
                              ),
                              if (widget.item.type == 'series' &&
                                  _episodes.isNotEmpty)
                                PlayerRailButton(
                                  icon: Icons.format_list_bulleted_rounded,
                                  semanticLabel: 'Episodes',
                                  onTap: _openEpisodesSheet,
                                ),
                              PlayerSpeedPill(
                                label: _speedLabel,
                                semanticLabel: 'Playback speed',
                                onTap: _openSettings,
                              ),
                            ],
                          ),
                          PlayerBottomCluster(
                            durationMs: duration,
                            positionMs: position,
                            bufferedMs: engine.bufferedEnd.inMilliseconds,
                            isPlaying: engine.playing,
                            volume: engine.volume,
                            muted: engine.muted,
                            backStepSec: _backStepSec,
                            forwardStepSec: _forwardStepSec,
                            fullscreen: _fullscreen,
                            showRemaining: _showRemaining,
                            canPrev: prevEpisode != null,
                            canNext: nextEpisode != null,
                            scale: scale,
                            onPlayPause: () => unawaited(_togglePlay()),
                            onSkip: (s) => unawaited(_seekBy(s)),
                            onPrev: prevEpisode == null
                                ? null
                                : () => unawaited(_switchEpisode(prevEpisode)),
                            onNext: nextEpisode == null
                                ? null
                                : () => unawaited(_switchEpisode(nextEpisode)),
                            onVolumeChanged: (value) async {
                              await engine.setVolume(value);
                            },
                            onVolumeDragEnd: () => _bumpControls(),
                            onMuteToggle: () async {
                              await engine.toggleMute();
                              _bumpControls();
                            },
                            onToggleFullscreen: () =>
                                unawaited(_toggleFullscreen()),
                            onOpenStreams: widget.onSwitchStream == null ||
                                    widget.streams.isEmpty
                                ? null
                                : _openStreamsSheet,
                            onOpenSubtitles: _openSubtitlesSheet,
                            onOpenAudio: _openAudioSheet,
                            onToggleRemaining: () => setState(
                                () => _showRemaining = !_showRemaining),
                            onScrubStart: () {
                              _hideTimer?.cancel();
                              setState(() => _controlsVisible = true);
                            },
                            onScrubUpdate: (seconds) {},
                            onScrubEnd: (seconds) async {
                              await engine.seekTo(
                                Duration(
                                    milliseconds: (seconds * 1000).round()),
                              );
                              _bumpControls();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Center gesture HUDs.
                  if (_mode == _GestureMode.seek)
                    Center(
                      child: SeekHud(
                        deltaSeconds: _hudDeltaSeconds,
                        targetText: formatPlayerTime(
                          Duration(milliseconds: _hudTargetMs),
                        ),
                      ),
                    )
                  else if (_mode == _GestureMode.brightness)
                    Center(
                      child: VerticalHud(
                        icon: Icons.brightness_6_rounded,
                        label: english ? 'Brightness' : 'السطوع',
                        value: _hudValue,
                      ),
                    )
                  else if (_mode == _GestureMode.volume)
                    Center(
                      child: VerticalHud(
                        icon: Icons.volume_up_rounded,
                        label: english ? 'Volume' : 'الصوت',
                        value: _hudValue,
                      ),
                    )
                  else if (_mode == _GestureMode.zoom && _zoom > 1.01)
                    Center(child: ZoomHud(scale: _zoom)),

                  // Reset-zoom chip.
                  if (_zoom > 1.01 &&
                      _mode == _GestureMode.none &&
                      _controlsVisible)
                    Positioned(
                      top: railTopInset + 168,
                      right: 14,
                      child: Material(
                        color: Colors.black.withValues(alpha: .55),
                        borderRadius: BorderRadius.circular(999),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => setState(() => _zoom = 1),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.center_focus_strong_rounded,
                                    size: 14, color: Colors.white),
                                SizedBox(width: 6),
                                Text(
                                  '1×',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Lock pill — the only chrome while locked.
                  if (_locked)
                    Positioned(
                      bottom: 26,
                      left: 16,
                      child: Material(
                        color: Colors.black.withValues(alpha: .45),
                        borderRadius: BorderRadius.circular(999),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: _unlock,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            child: Icon(
                              Icons.lock_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Hint pill.
                  if (_hintVisible)
                    Center(child: LockHintHud(message: _lastHint)),

                  // Double-tap seek ripple (Task 124: animated ±N feedback),
                  // anchored to the tapped third of the screen.
                  if (_rippleVisible && !_locked)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Align(
                          alignment: _rippleForward
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 56,
                            ),
                            child: DoubleTapRipple(
                              key: ValueKey(_rippleKey),
                              forward: _rippleForward,
                              seconds: _rippleSeconds,
                              english: english,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Resume card.
                  if (!_locked && _resuming && (_resumePositionMs ?? 0) > 30000)
                    Positioned(
                      bottom: 180 * scale,
                      left: 16,
                      child: PlayerCardShell(
                        width: 340,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PlayerCardHeader(
                              icon: Icons.history_rounded,
                              label: english ? 'RESUME' : 'استئناف',
                              trailing: InkWell(
                                onTap: () => setState(() => _resuming = false),
                                child: const Icon(Icons.close_rounded,
                                    size: 17, color: Colors.white38),
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              english
                                  ? 'Resume from ${formatPlayerTime(Duration(milliseconds: _resumePositionMs ?? 0))}?'
                                  : 'استئناف من ${formatPlayerTime(Duration(milliseconds: _resumePositionMs ?? 0))}؟',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 11),
                            Row(
                              children: [
                                Expanded(
                                  child: PlayerPrimaryAction(
                                    label: english ? 'Resume' : 'استئناف',
                                    onPressed: () =>
                                        unawaited(_resumeFromSaved()),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: PlayerSecondaryAction(
                                    label:
                                        english ? 'Start over' : 'من البداية',
                                    onPressed: () async {
                                      setState(() {
                                        _resuming = false;
                                        _resumePositionMs = 0;
                                      });
                                      await _engine?.seekTo(Duration.zero);
                                      await _engine?.play();
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Up-Next card.
                  if (!_locked &&
                      nextEpisode != null &&
                      nearEnd &&
                      !_upNextDismissed &&
                      !_stopScrobbled &&
                      duration > 0)
                    Positioned(
                      bottom: 180 * scale,
                      right: 16,
                      child: PlayerCardShell(
                        width: 288,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PlayerCardHeader(
                              icon: Icons.skip_next_rounded,
                              label: english ? 'UP NEXT' : 'التالي',
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: HorseTheme.canvas,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: HorseTheme.line),
                                ),
                                child: Text(
                                  countdown(nearEnd, duration, position),
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              (nextEpisode['name'] ??
                                      nextEpisode['title'] ??
                                      'Episode')
                                  .toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (nextEpisode['season'] != null &&
                                nextEpisode['episode'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  'S${(nextEpisode['season'] as num).toInt()}:E${(nextEpisode['episode'] as num).toInt()}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: .54),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 11),
                            Row(
                              children: [
                                Expanded(
                                  child: PlayerPrimaryAction(
                                    label: english
                                        ? 'Next episode'
                                        : 'الحلقة التالية',
                                    onPressed: () => unawaited(
                                      _switchEpisode(nextEpisode),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                PlayerSecondaryAction(
                                  label: english ? 'Cancel' : 'إلغاء',
                                  onPressed: () =>
                                      setState(() => _upNextDismissed = true),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String countdown(bool nearEnd, int duration, int position) {
    final seconds = ((duration - position) / 1000).ceil().clamp(0, 30);
    final s = seconds.toString();
    final unit = english ? 's' : 'ث';
    return seconds > 0
        ? (english ? 'in $s$unit' : 'بعد $s$unit')
        : (english ? 'now' : 'الآن');
  }

  IconData get _orientationIcon {
    switch (_orientation) {
      case _OrientationMode.auto:
        return Icons.screen_rotation_rounded;
      case _OrientationMode.landscape:
        return Icons.screen_lock_landscape_rounded;
      case _OrientationMode.portrait:
        return Icons.screen_lock_portrait_rounded;
    }
  }
}

// ── Error panel ────────────────────────────────────────────────────────────

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.message,
    required this.english,
    required this.onRetry,
  });

  final String? message;
  final bool english;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 46,
                color: Color(0xFFFF8178),
              ),
              const SizedBox(height: 14),
              Text(
                english ? 'Playback error' : 'خطأ في التشغيل',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              if (message != null)
                Text(
                  message!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(english ? 'Try again' : 'إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
}

class _PlaybackResolution {
  const _PlaybackResolution({
    required this.url,
    required this.headers,
    required this.torrent,
  });

  final String url;
  final Map<String, String> headers;
  final PreparedTorrent? torrent;
}

class _TorrentHud extends StatelessWidget {
  const _TorrentHud({required this.status, required this.english});

  final TorrentStatus status;
  final bool english;

  String _speed(num bps) {
    if (bps >= 1024 * 1024) {
      return '${(bps / 1024 / 1024).toStringAsFixed(1)} MB/s';
    }
    if (bps >= 1024) return '${(bps / 1024).toStringAsFixed(0)} kB/s';
    return '${bps.toStringAsFixed(0)} B/s';
  }

  @override
  Widget build(BuildContext context) {
    final pct = (status.progress.clamp(0.0, 1.0) * 100).toStringAsFixed(1);
    final state = switch (status.state) {
      'downloading' => english ? 'Streaming' : 'بث',
      'finished' => english ? 'Completed' : 'مكتمل',
      'seeding' => english ? 'Seeding' : 'مشاركة',
      'paused' => english ? 'Paused' : 'متوقف',
      'checking' => english ? 'Checking' : 'فحص',
      _ => english ? 'Preparing' : 'تحضير',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 7,
            height: 7,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: Colors.white70,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$state · ↓ ${_speed(status.downloadRate)}'
            ' · P:${status.numPeers} S:${status.numSeeds} · $pct%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
