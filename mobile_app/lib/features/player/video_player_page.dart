import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/models/media_item.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';
import 'player_timeline.dart';

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
  final Map<String, dynamic>? nextEpisode;
  final bool recordProgress;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage>
    with WidgetsBindingObserver {
  late VideoPlayerController _controller;
  late final AppState _app;
  Timer? _hideTimer;
  Timer? _progressTimer;
  Timer? _feedbackTimer;
  bool _controlsVisible = true;
  bool _failed = false;
  bool _stopScrobbled = false;
  bool _completionScrobbled = false;
  bool _autoAdvanceStarted = false;
  bool _closing = false;
  bool _switchingEpisode = false;
  bool _isFullscreen = true;
  bool _preservePlayerOrientation = false;
  bool _wasPlayingBeforeBackground = false;
  bool _isSeeking = false;
  List<Map<String, dynamic>> _subtitleTracks = [];
  Map<String, dynamic>? _activeSubtitle;
  List<VideoAudioTrack> _audioTracks = [];
  double _playbackSpeed = 1;
  double _lastVolume = 1;
  Duration? _seekPreview;
  Duration _videoGestureStart = Duration.zero;
  double _videoGestureDelta = 0;
  String? _seekFeedback;
  String? _error;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _createController();
    _initialize();
    _scheduleHide();
    _progressTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _saveProgress(),
    );
  }

  void _createController() {
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller.addListener(_onVideoChanged);
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      final settings = _app.webSettings;
      final resumeEnabled = settings['resumePlayback'] != false;
      final resumeAt = resumeEnabled ? widget.initialPositionMs ?? 0 : 0;
      var shouldResume = resumeAt > 0;
      if (shouldResume && settings['resumePrompt'] == true && mounted) {
        shouldResume = await _askToResume(resumeAt);
      }
      if (shouldResume && resumeAt > 0) {
        final end = _controller.value.duration.inMilliseconds;
        await _controller.seekTo(
          Duration(
            milliseconds: resumeAt.clamp(0, end).toInt(),
          ),
        );
      }
      _controller.setCaptionOffset(
        Duration(
            milliseconds: (settings['subtitleOffsetMs'] as num?)?.toInt() ?? 0),
      );
      await _controller.play();
      unawaited(_loadPlaybackTracks());
      _scrobble('start');
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadPlaybackTracks() async {
    await _loadAudioTracks();
    await _loadSubtitleTracks();
    if (_app.webSettings['subtitlesOffByDefault'] != true &&
        _subtitleTracks.isNotEmpty) {
      final preferred = _preferredSubtitle();
      if (preferred != null) {
        await _activateSubtitle(preferred, showError: false);
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_wasPlayingBeforeBackground && _controller.value.isInitialized) {
        _wasPlayingBeforeBackground = false;
        unawaited(_controller.play());
        _scheduleHide();
      }
      return;
    }

    _hideTimer?.cancel();
    if (_controller.value.isInitialized) {
      _wasPlayingBeforeBackground = _controller.value.isPlaying;
      if (_wasPlayingBeforeBackground) unawaited(_controller.pause());
      unawaited(_saveProgress());
    }
    if (mounted && !_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
  }

  Future<bool> _askToResume(int milliseconds) async {
    final english = _app.english;
    final minutes = (milliseconds / 60000).floor();
    final seconds = ((milliseconds ~/ 1000) % 60).toString().padLeft(2, '0');
    final resume = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(english ? 'Resume playback?' : 'استئناف المشاهدة؟'),
        content: Text(english
            ? 'Continue from $minutes:$seconds?'
            : 'متابعة المشاهدة من $minutes:$seconds؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(english ? 'Start over' : 'من البداية')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(english ? 'Resume' : 'استئناف')),
        ],
      ),
    );
    return resume == true;
  }

  Future<void> _loadAudioTracks() async {
    if (!_controller.isAudioTrackSupportAvailable()) return;
    try {
      _audioTracks = await _controller.getAudioTracks();
      final preference =
          (_app.webSettings['defaultAudioLanguage'] ?? 'source').toString();
      if (preference == 'source') return;
      final matching = _audioTracks.where((track) {
        final haystack =
            '${track.language ?? ''} ${track.label ?? ''}'.toLowerCase();
        return haystack.contains(preference.toLowerCase());
      }).firstOrNull;
      if (matching != null) await _controller.selectAudioTrack(matching.id);
    } catch (_) {
      // Some media backends do not expose track selection for every stream.
    }
  }

  Future<void> _loadSubtitleTracks() async {
    try {
      _subtitleTracks = await _app.catalogs.subtitles(
        widget.item.type,
        widget.videoId,
        _app.addons,
      );
    } catch (_) {
      _subtitleTracks = [];
    }
  }

  Map<String, dynamic>? _preferredSubtitle() {
    final target =
        (_app.webSettings['subtitleTranslationLanguage'] ?? 'off').toString();
    final languages = <String>[
      if (target != 'off') _normalizedLanguage(target),
      ...((_app.webSettings['preferredSubLangs'] as List? ?? const [])
          .map((entry) => _normalizedLanguage(entry.toString()))),
    ];
    for (final language in languages) {
      final track = _subtitleTracks.where((entry) {
        final code = _normalizedLanguage(
          (entry['lang'] ?? entry['language'] ?? '').toString(),
        );
        return code == language ||
            code.startsWith('$language-') ||
            code.startsWith('${language}_');
      }).firstOrNull;
      if (track != null) return track;
    }
    return _subtitleTracks.firstOrNull;
  }

  Future<void> _activateSubtitle(
    Map<String, dynamic>? track, {
    bool showError = true,
  }) async {
    try {
      if (track == null) {
        await _controller.setClosedCaptionFile(null);
        if (mounted) setState(() => _activeSubtitle = null);
        return;
      }
      final url = Uri.tryParse(track['url'].toString());
      if (url == null || !url.hasScheme) {
        throw const FormatException('Invalid subtitle URL');
      }
      final contents = await _app.api.proxyText(url.toString());
      final extension = url.path.toLowerCase();
      final file = extension.endsWith('.srt')
          ? SubRipCaptionFile(contents)
          : WebVTTCaptionFile(contents);
      await _controller.setClosedCaptionFile(Future.value(file));
      _controller.setCaptionOffset(
        Duration(
            milliseconds:
                (_app.webSettings['subtitleOffsetMs'] as num?)?.toInt() ?? 0),
      );
      if (mounted) setState(() => _activeSubtitle = track);
    } catch (error) {
      if (showError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(_app.english
                  ? 'Could not load this subtitle track.'
                  : 'تعذر تحميل مسار الترجمة.')),
        );
      }
    }
  }

  Future<void> _showSubtitlePicker() async {
    _hideTimer?.cancel();
    final selected = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      backgroundColor: HorseTheme.surface,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(_app.english ? 'Subtitles' : 'الترجمة')),
            ListTile(
              leading: Icon(_activeSubtitle == null
                  ? Icons.check_rounded
                  : Icons.subtitles_off_outlined),
              title: Text(_app.english ? 'Off' : 'إيقاف'),
              onTap: () =>
                  Navigator.pop(context, <String, dynamic>{'__off': true}),
            ),
            for (final track in _subtitleTracks)
              ListTile(
                leading: Icon(identical(track, _activeSubtitle)
                    ? Icons.check_rounded
                    : Icons.subtitles_outlined),
                title: Text((track['lang'] ?? track['language'] ?? 'Unknown')
                    .toString()),
                subtitle: Text(
                    '${track['addonName'] ?? ''} ${track['label'] ?? ''}'
                        .trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(context, track),
              ),
          ],
        ),
      ),
    );
    if (mounted) _scheduleHide();
    if (selected == null) return;
    await _activateSubtitle(selected['__off'] == true ? null : selected);
  }

  Future<void> _showAudioPicker() async {
    if (_audioTracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_app.english
                ? 'No selectable audio tracks are available.'
                : 'لا توجد مسارات صوت يمكن اختيارها.')),
      );
      return;
    }
    _hideTimer?.cancel();
    final selected = await showModalBottomSheet<VideoAudioTrack>(
      context: context,
      backgroundColor: HorseTheme.surface,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
                title:
                    Text(_app.english ? 'Audio tracks' : 'المسارات الصوتية')),
            for (final track in _audioTracks)
              ListTile(
                leading: Icon(track.isSelected
                    ? Icons.check_rounded
                    : Icons.audiotrack_rounded),
                title: Text(track.label ?? track.language ?? track.id),
                subtitle: track.language == null ? null : Text(track.language!),
                onTap: () => Navigator.pop(context, track),
              ),
          ],
        ),
      ),
    );
    if (mounted) _scheduleHide();
    if (selected != null) {
      try {
        await _controller.selectAudioTrack(selected.id);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(_app.english
                    ? 'This stream cannot switch audio tracks.'
                    : 'لا يمكن تبديل المسار الصوتي لهذا المصدر.')),
          );
        }
      }
    }
  }

  Future<void> _showSpeedPicker() async {
    _hideTimer?.cancel();
    final configured =
        (_app.webSettings['customPlaybackSpeeds'] as List? ?? const [])
            .map((entry) => (entry as num).toDouble())
            .toList();
    final speeds = configured.isEmpty ? [0.75, 1, 1.25, 1.5, 2] : configured;
    final selected = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: HorseTheme.surface,
      builder: (context) => SafeArea(
        child: Wrap(
          alignment: WrapAlignment.center,
          children: [
            for (final speed in speeds)
              ChoiceChip(
                label: Text('$speed×'),
                selected: _playbackSpeed == speed,
                onSelected: (_) => Navigator.pop(context, speed),
              ),
          ],
        ),
      ),
    );
    if (mounted) _scheduleHide();
    if (selected != null) {
      try {
        await _controller.setPlaybackSpeed(selected);
        if (mounted) setState(() => _playbackSpeed = selected);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(_app.english
                    ? 'Playback speed is not supported by this stream.'
                    : 'سرعة التشغيل غير مدعومة في هذا المصدر.')),
          );
        }
      }
    }
  }

  void _onVideoChanged() {
    if (!mounted) return;
    final value = _controller.value;
    if (!value.isPlaying) {
      _hideTimer?.cancel();
      _controlsVisible = true;
    }
    if (value.isCompleted && !_completionScrobbled) {
      _completionScrobbled = true;
      _stopScrobbled = true;
      _scrobble('stop');
      if (_app.webSettings['autoPlayNextEpisode'] == true &&
          widget.nextEpisode != null) {
        unawaited(_playNextEpisode());
      }
    }
    if (value.hasError) {
      setState(() {
        _failed = true;
        _error = value.errorDescription;
      });
    } else {
      setState(() {});
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_controller.value.isInitialized ||
        !_controller.value.isPlaying ||
        _isSeeking) {
      return;
    }
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller.value.isPlaying && !_isSeeking) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    if (!_controller.value.isPlaying) {
      setState(() => _controlsVisible = true);
      return;
    }
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  Future<void> _seek(Duration offset) async {
    if (!_controller.value.isInitialized ||
        _controller.value.duration <= Duration.zero) {
      return;
    }
    final duration = _controller.value.duration;
    final target = _controller.value.position + offset;
    await _controller.seekTo(
      Duration(
        milliseconds:
            target.inMilliseconds.clamp(0, duration.inMilliseconds).toInt(),
      ),
    );
    _showSeekFeedback(offset);
    _scheduleHide();
  }

  Future<void> _togglePlayback() async {
    try {
      if (_controller.value.isPlaying) {
        await _controller.pause();
        _scrobble('pause');
      } else {
        await _controller.play();
        _scrobble('start');
      }
      _scheduleHide();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_app.english
                ? 'Playback could not be changed.'
                : 'تعذر تغيير حالة التشغيل.'),
          ),
        );
      }
    }
  }

  void _showSeekFeedback(Duration offset) {
    _feedbackTimer?.cancel();
    final sign = offset.isNegative ? '−' : '+';
    _seekFeedback = '$sign${formatPlayerTime(offset.abs())}';
    if (mounted) setState(() {});
    _feedbackTimer = Timer(const Duration(milliseconds: 850), () {
      if (!mounted) return;
      setState(() => _seekFeedback = null);
    });
  }

  void _startVideoSeek(DragStartDetails details) {
    if (!_controller.value.isInitialized ||
        _controller.value.duration <= Duration.zero) {
      return;
    }
    _hideTimer?.cancel();
    _videoGestureStart = _controller.value.position;
    _videoGestureDelta = 0;
    _isSeeking = true;
    _seekPreview = _videoGestureStart;
    _controlsVisible = true;
    setState(() {});
  }

  void _updateVideoSeek(DragUpdateDetails details) {
    if (!_isSeeking) return;
    _videoGestureDelta += details.delta.dx;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final shiftMs = (_videoGestureDelta / screenWidth * 180000).round();
    final durationMs = _controller.value.duration.inMilliseconds;
    final position = Duration(
      milliseconds: (_videoGestureStart.inMilliseconds + shiftMs)
          .clamp(0, durationMs)
          .toInt(),
    );
    setState(() {
      _seekPreview = position;
      final offset = position - _videoGestureStart;
      final sign = offset.isNegative ? '−' : '+';
      _seekFeedback = '$sign${formatPlayerTime(offset.abs())}';
    });
  }

  Future<void> _finishVideoSeek(DragEndDetails details) async {
    if (!_isSeeking) return;
    final target = _seekPreview;
    _isSeeking = false;
    _videoGestureDelta = 0;
    if (target != null && target != _videoGestureStart) {
      try {
        await _controller.seekTo(target);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_app.english
                  ? 'Could not seek in this stream.'
                  : 'تعذر تغيير موضع التشغيل في هذا المصدر.'),
            ),
          );
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _seekPreview = null;
      _seekFeedback = null;
    });
    _scheduleHide();
  }

  Future<void> _finishTimelineSeek(double milliseconds) async {
    try {
      await _controller.seekTo(Duration(milliseconds: milliseconds.round()));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_app.english
                ? 'Could not seek in this stream.'
                : 'تعذر تغيير موضع التشغيل في هذا المصدر.'),
          ),
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _isSeeking = false;
      _seekPreview = null;
    });
    _scheduleHide();
  }

  Future<void> _toggleMute({bool scheduleHide = true}) async {
    final current = _controller.value.volume;
    final target = current > 0.001 ? 0.0 : _lastVolume.clamp(0.1, 1.0);
    if (current > 0.001) _lastVolume = current;
    try {
      await _controller.setVolume(target);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_app.english
                ? 'Volume control is unavailable for this stream.'
                : 'التحكم بالصوت غير متاح لهذا المصدر.'),
          ),
        );
      }
    }
    if (scheduleHide) _scheduleHide();
  }

  Future<void> _showVolumePicker() async {
    _hideTimer?.cancel();
    var selectedVolume = _controller.value.volume;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: HorseTheme.surface,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Row(
                children: [
                  IconButton(
                    tooltip: _app.english ? 'Mute' : 'كتم',
                    onPressed: () async {
                      await _toggleMute(scheduleHide: false);
                      selectedVolume = _controller.value.volume;
                      setSheetState(() {});
                    },
                    icon: Icon(selectedVolume <= 0.001
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded),
                  ),
                  Expanded(
                    child: Slider(
                      value: selectedVolume.clamp(0.0, 1.0),
                      onChanged: (value) async {
                        selectedVolume = value;
                        if (value > 0.001) _lastVolume = value;
                        setSheetState(() {});
                        try {
                          await _controller.setVolume(value);
                        } catch (_) {
                          selectedVolume = _controller.value.volume;
                          setSheetState(() {});
                        }
                      },
                    ),
                  ),
                  Text('${(selectedVolume * 100).round()}%'),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (mounted) _scheduleHide();
  }

  Future<void> _toggleFullscreen() async {
    final next = !_isFullscreen;
    setState(() => _isFullscreen = next);
    await SystemChrome.setPreferredOrientations(
      next
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const <DeviceOrientation>[],
    );
    await SystemChrome.setEnabledSystemUIMode(
      next ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    if (!mounted) return;
    _scheduleHide();
  }

  Future<void> _showAspectPicker() async {
    _hideTimer?.cancel();
    final current = (_app.webSettings['videoFill'] ?? 'fit').toString();
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: HorseTheme.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(_app.english ? 'Video fit' : 'ملاءمة الفيديو'),
            ),
            for (final option in const ['fit', 'fill', 'zoom'])
              ListTile(
                leading: Icon(option == current
                    ? Icons.check_rounded
                    : Icons.crop_rounded),
                title: Text(_aspectLabel(option)),
                onTap: () => Navigator.pop(context, option),
              ),
          ],
        ),
      ),
    );
    if (mounted) _scheduleHide();
    if (selected != null) await _app.setSetting('videoFill', selected);
  }

  String _aspectLabel(String option) {
    if (_app.english) {
      return switch (option) {
        'fill' => 'Fill',
        'zoom' => 'Zoom',
        _ => 'Fit',
      };
    }
    return switch (option) {
      'fill' => 'ملء الشاشة',
      'zoom' => 'تكبير',
      _ => 'احتواء',
    };
  }

  Future<void> _showPlayerSettings() async {
    _hideTimer?.cancel();
    final action = await showModalBottomSheet<_PlayerSettingAction>(
      context: context,
      backgroundColor: HorseTheme.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(_app.english ? 'Player settings' : 'إعدادات المشغل'),
            ),
            ListTile(
              leading: const Icon(Icons.speed_rounded),
              title: Text(_app.english ? 'Playback speed' : 'سرعة التشغيل'),
              trailing: Text('$_playbackSpeed×'),
              onTap: () => Navigator.pop(context, _PlayerSettingAction.speed),
            ),
            ListTile(
              leading: const Icon(Icons.crop_rounded),
              title: Text(_app.english ? 'Video fit' : 'ملاءمة الفيديو'),
              trailing: Text(_aspectLabel(
                  (_app.webSettings['videoFill'] ?? 'fit').toString())),
              onTap: () => Navigator.pop(context, _PlayerSettingAction.aspect),
            ),
            if (_subtitleTracks.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.subtitles_outlined),
                title: Text(_app.english ? 'Subtitles' : 'الترجمة'),
                onTap: () =>
                    Navigator.pop(context, _PlayerSettingAction.subtitles),
              ),
            if (_audioTracks.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.audiotrack_rounded),
                title: Text(_app.english ? 'Audio tracks' : 'المسارات الصوتية'),
                onTap: () => Navigator.pop(context, _PlayerSettingAction.audio),
              ),
          ],
        ),
      ),
    );
    if (mounted) _scheduleHide();
    if (!mounted) return;
    switch (action) {
      case _PlayerSettingAction.speed:
        await _showSpeedPicker();
      case _PlayerSettingAction.aspect:
        await _showAspectPicker();
      case _PlayerSettingAction.subtitles:
        await _showSubtitlePicker();
      case _PlayerSettingAction.audio:
        await _showAudioPicker();
      case null:
        break;
    }
  }

  Future<void> _playNextEpisode() async {
    if (_autoAdvanceStarted) return;
    _autoAdvanceStarted = true;
    final next = widget.nextEpisode;
    if (next == null) return;
    await _startEpisode(next, automatic: true);
  }

  Map<String, dynamic>? _episodeAt(int offset) {
    final videos = widget.item.videos;
    final index = videos.indexWhere(
      (video) => video['id']?.toString() == widget.videoId,
    );
    if (index < 0) return offset > 0 ? widget.nextEpisode : null;
    final target = index + offset;
    if (target >= 0 && target < videos.length) return videos[target];
    return offset > 0 ? widget.nextEpisode : null;
  }

  Future<void> _showEpisodePicker() async {
    final episodes = widget.item.videos;
    if (episodes.isEmpty) return;
    _hideTimer?.cancel();
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: HorseTheme.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520, maxWidth: 620),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: episodes.length,
            itemBuilder: (context, index) {
              final episode = episodes[index];
              final active = episode['id']?.toString() == widget.videoId;
              final season = (episode['season'] as num?)?.toInt();
              final number = (episode['episode'] as num?)?.toInt();
              final english = _app.english;
              return ListTile(
                leading: Icon(active
                    ? Icons.graphic_eq_rounded
                    : Icons.play_circle_outline_rounded),
                title: Text(
                  (episode['title'] ??
                          (english
                              ? 'Episode ${number ?? index + 1}'
                              : 'الحلقة ${number ?? index + 1}'))
                      .toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: season == null || number == null
                    ? null
                    : Text(english
                        ? 'Season $season · Episode $number'
                        : 'الموسم $season · الحلقة $number'),
                trailing: active ? const Icon(Icons.check_rounded) : null,
                onTap: active
                    ? () => Navigator.pop(context)
                    : () => Navigator.pop(context, episode),
              );
            },
          ),
        ),
      ),
    );
    if (mounted) _scheduleHide();
    if (selected != null) await _startEpisode(selected);
  }

  Future<void> _startEpisode(
    Map<String, dynamic> episode, {
    bool automatic = false,
  }) async {
    if (_switchingEpisode) return;
    _switchingEpisode = true;
    if (mounted && !automatic) setState(() {});
    try {
      final id = (episode['id'] ?? '').toString();
      if (id.isEmpty) throw const FormatException('Episode has no id');
      final streams =
          await _app.catalogs.streams(widget.item.type, id, _app.addons);
      final candidates = _rankStreams(streams);
      final nextStream = candidates
          .where((stream) =>
              stream['url'] is String &&
              (stream['url'] as String).startsWith('http'))
          .firstOrNull;
      if (nextStream == null) throw StateError('No playable episode stream');
      if (!mounted) return;
      final hints =
          (nextStream['behaviorHints'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
      final signedUrl = await _app.api.signMediaUrl(
        nextStream['url'] as String,
        proxyHeaders: (hints['proxyHeaders'] as Map?)?.cast<String, dynamic>(),
        filename: (hints['filename'] ?? nextStream['title']) as String?,
      );
      if (!mounted) return;
      if (!_stopScrobbled) _scrobble('stop');
      _stopScrobbled = true;
      await _saveProgress();
      if (!mounted) return;
      _preservePlayerOrientation = true;
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => VideoPlayerPage(
            item: widget.item,
            url: signedUrl,
            streamName: (nextStream['title'] ??
                    nextStream['addonName'] ??
                    widget.streamName)
                .toString(),
            videoId: id,
            season: (episode['season'] as num?)?.toInt(),
            episode: (episode['episode'] as num?)?.toInt(),
            nextEpisode: _nextFromCatalog(id),
            recordProgress: widget.recordProgress,
          ),
          fullscreenDialog: true,
        ),
      );
    } catch (_) {
      if (mounted) {
        _switchingEpisode = false;
        _preservePlayerOrientation = false;
        if (automatic) _autoAdvanceStarted = false;
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_app.english
                ? 'Could not load a playable stream for this episode.'
                : 'تعذر العثور على مصدر تشغيل لهذه الحلقة.'),
          ),
        );
      }
    }
  }

  Map<String, dynamic>? _nextFromCatalog(String currentId) {
    final videos = widget.item.videos;
    final index =
        videos.indexWhere((video) => video['id']?.toString() == currentId);
    return index >= 0 && index + 1 < videos.length ? videos[index + 1] : null;
  }

  List<Map<String, dynamic>> _rankStreams(List<Map<String, dynamic>> streams) {
    final preferred =
        (_app.webSettings['preferredQuality'] ?? 'auto').toString();
    final sorted = [...streams];
    if (preferred != 'auto' || _app.webSettings['streamSort'] == 'score') {
      int quality(Map<String, dynamic> stream) {
        final title = '${stream['title'] ?? ''} ${stream['name'] ?? ''}';
        final match = RegExp(r'(2160|1080|720|480)p?', caseSensitive: false)
            .firstMatch(title);
        final value = int.tryParse(match?.group(1) ?? '') ?? 0;
        final preference = int.tryParse(preferred.replaceAll('p', ''));
        return preference == null
            ? value
            : (value == preference ? 10000 + value : value);
      }

      sorted.sort((a, b) => quality(b).compareTo(quality(a)));
    }
    return sorted;
  }

  Future<void> _saveProgress() async {
    if (!widget.recordProgress || !_controller.value.isInitialized) return;
    final value = _controller.value;
    await _app.recordPlayback(
      widget.item,
      positionMs: value.position.inMilliseconds,
      durationMs: value.duration.inMilliseconds,
      videoId: widget.videoId,
      season: widget.season,
      episode: widget.episode,
    );
  }

  void _scrobble(String action) {
    if (!widget.recordProgress) return;
    final imdbId = widget.item.id;
    if (!RegExp(r'^tt\d+$').hasMatch(imdbId)) return;
    final value = _controller.value;
    final duration = value.duration.inMilliseconds;
    final progress =
        duration <= 0 ? 0.0 : value.position.inMilliseconds / duration * 100;
    final type = widget.item.type == 'series' ? 'episode' : 'movie';
    for (final service in const ['trakt', 'simkl']) {
      final link = _app.linkedServices[service];
      final linkId = link?['linkId']?.toString();
      if (linkId == null || linkId.isEmpty) continue;
      unawaited(
        _app.api.scrobbleLinkedService(
          service: service,
          linkId: linkId,
          action: action,
          progress: progress,
          imdbId: imdbId,
          type: type,
          season: type == 'episode' ? widget.season : null,
          episode: type == 'episode' ? widget.episode : null,
        ),
      );
    }
  }

  Future<void> _close() async {
    if (_closing) return;
    if (_app.webSettings['playerConfirmLeave'] == true) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_app.english ? 'Leave playback?' : 'مغادرة المشغّل؟'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(_app.english ? 'Stay' : 'البقاء')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(_app.english ? 'Leave' : 'مغادرة')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _closing = true);
    if (!_stopScrobbled) _scrobble('stop');
    _stopScrobbled = true;
    await _saveProgress();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _progressTimer?.cancel();
    _feedbackTimer?.cancel();
    _controller.removeListener(_onVideoChanged);
    unawaited(_saveProgress());
    unawaited(_controller.dispose());
    if (!_preservePlayerOrientation) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(const []);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final english = context.watch<AppState>().english;
    final value = _controller.value;
    return PopScope(
      canPop: _closing || _app.webSettings['playerConfirmLeave'] != true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          if (!_stopScrobbled) _scrobble('stop');
          _stopScrobbled = true;
          unawaited(_saveProgress());
        } else {
          unawaited(_close());
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxHeight < 440 || constraints.maxWidth < 560;
            return Stack(
              fit: StackFit.expand,
              children: [
                if (value.isInitialized && !_failed)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleControls,
                    onDoubleTapDown: (details) {
                      final width = MediaQuery.sizeOf(context).width;
                      if (details.localPosition.dx < width * .34) {
                        _seek(const Duration(seconds: -10));
                      } else if (details.localPosition.dx > width * .66) {
                        _seek(const Duration(seconds: 10));
                      }
                    },
                    onHorizontalDragStart: _startVideoSeek,
                    onHorizontalDragUpdate: _updateVideoSeek,
                    onHorizontalDragEnd: _finishVideoSeek,
                    child: _buildVideo(value.aspectRatio),
                  )
                else if (_failed)
                  _PlaybackError(
                    message: _error,
                    english: english,
                    onRetry: () {
                      final previous = _controller;
                      previous.removeListener(_onVideoChanged);
                      unawaited(previous.dispose());
                      setState(() {
                        _failed = false;
                        _error = null;
                        _completionScrobbled = false;
                      });
                      _createController();
                      _initialize();
                    },
                  )
                else
                  const Center(
                    child: CircularProgressIndicator(
                      color: HorseTheme.gold,
                      strokeWidth: 2,
                    ),
                  ),
                if (value.isInitialized && value.isBuffering && !_failed)
                  const Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0x77000000),
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox.square(
                          dimension: 26,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!_failed && value.caption.text.isNotEmpty)
                  _CaptionOverlay(
                    text: value.caption.text,
                    settings: _app.webSettings,
                    bottom: _controlsVisible ? 112 : 38,
                  ),
                IgnorePointer(
                  ignoring: !_controlsVisible || _failed || _switchingEpisode,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible && !_failed ? 1 : 0,
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    child: _buildControls(
                      value: value,
                      english: english,
                      compact: compact,
                    ),
                  ),
                ),
                if (_seekFeedback != null && !_failed)
                  Center(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .62),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 10),
                          child: Text(
                            _seekFeedback!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_switchingEpisode && !_autoAdvanceStarted)
                  const Center(
                    child: CircularProgressIndicator(color: HorseTheme.gold),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildControls({
    required VideoPlayerValue value,
    required bool english,
    required bool compact,
  }) {
    final videos = widget.item.videos;
    final hasEpisodeContext = widget.season != null || widget.episode != null;
    final previousEpisode = hasEpisodeContext ? _episodeAt(-1) : null;
    final nextEpisode = hasEpisodeContext ? _episodeAt(1) : null;
    final horizontalPadding = compact ? 12.0 : 26.0;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xB8000000),
            Colors.transparent,
            Colors.transparent,
            Color(0xC9000000),
          ],
          stops: [0, .25, .64, 1],
        ),
      ),
      child: SafeArea(
        child: Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: compact ? 4 : 14,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      _playerIconButton(
                        icon: Icons.arrow_back_rounded,
                        label: english ? 'Back' : 'رجوع',
                        onPressed: _close,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: compact ? 14 : 16,
                              ),
                            ),
                            if (!compact || hasEpisodeContext)
                              Text(
                                _app.webSettings['showQualityInfo'] == true
                                    ? '${_episodeLabel(english)} · ${widget.streamName}'
                                    : _episodeLabel(english),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .72),
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (hasEpisodeContext && videos.length > 1)
                        _playerIconButton(
                          icon: Icons.playlist_play_rounded,
                          label: english ? 'Episodes' : 'الحلقات',
                          onPressed: _showEpisodePicker,
                        ),
                      _playerIconButton(
                        icon: _activeSubtitle == null
                            ? Icons.subtitles_outlined
                            : Icons.closed_caption_rounded,
                        label: english ? 'Subtitles' : 'الترجمة',
                        onPressed: _showSubtitlePicker,
                      ),
                      _playerIconButton(
                        icon: Icons.tune_rounded,
                        label: english ? 'Player settings' : 'إعدادات المشغل',
                        onPressed: _showPlayerSettings,
                      ),
                    ],
                  ),
                  const Spacer(),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (hasEpisodeContext)
                          _playerIconButton(
                            icon: Icons.skip_previous_rounded,
                            label:
                                english ? 'Previous episode' : 'الحلقة السابقة',
                            onPressed: previousEpisode == null
                                ? null
                                : () => _startEpisode(previousEpisode),
                            size: compact ? 22 : 26,
                          ),
                        _playerIconButton(
                          icon: Icons.replay_10_rounded,
                          label: english ? 'Back 10 seconds' : 'رجوع 10 ثوانٍ',
                          onPressed: () => _seek(Duration(
                            seconds:
                                -((_app.webSettings['seekBackStepSec'] as num?)
                                        ?.toInt() ??
                                    10),
                          )),
                          size: compact ? 24 : 28,
                        ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .42),
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: Colors.white70, width: 1.5),
                            boxShadow: const [
                              BoxShadow(color: Colors.black38, blurRadius: 18),
                            ],
                          ),
                          child: IconButton(
                            tooltip: value.isPlaying
                                ? (english ? 'Pause' : 'إيقاف مؤقت')
                                : (english ? 'Play' : 'تشغيل'),
                            onPressed: _togglePlayback,
                            iconSize: compact ? 34 : 42,
                            padding: EdgeInsets.all(compact ? 8 : 12),
                            constraints: BoxConstraints.tightFor(
                              width: compact ? 58 : 70,
                              height: compact ? 58 : 70,
                            ),
                            color: Colors.white,
                            icon: Icon(
                              value.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _playerIconButton(
                          icon: Icons.forward_10_rounded,
                          label:
                              english ? 'Forward 10 seconds' : 'تقديم 10 ثوانٍ',
                          onPressed: () => _seek(Duration(
                            seconds: ((_app.webSettings['seekForwardStepSec']
                                        as num?)
                                    ?.toInt() ??
                                10),
                          )),
                          size: compact ? 24 : 28,
                        ),
                        if (hasEpisodeContext)
                          _playerIconButton(
                            icon: Icons.skip_next_rounded,
                            label: english ? 'Next episode' : 'الحلقة التالية',
                            onPressed: nextEpisode == null
                                ? null
                                : () => _startEpisode(nextEpisode),
                            size: compact ? 22 : 26,
                          ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  PlayerTimeline(
                    position: _seekPreview ?? value.position,
                    duration: value.duration,
                    buffered: value.buffered,
                    onSeekStart: (target) {
                      _hideTimer?.cancel();
                      setState(() {
                        _isSeeking = true;
                        _seekPreview = target;
                      });
                    },
                    onSeekPreview: (target) =>
                        setState(() => _seekPreview = target),
                    onSeekEnd: (target) => _finishTimelineSeek(
                      target.inMilliseconds.toDouble(),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      _playerIconButton(
                        icon: value.volume <= .001
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        label: value.volume <= .001
                            ? (english ? 'Unmute' : 'إلغاء كتم الصوت')
                            : (english ? 'Mute' : 'كتم الصوت'),
                        onPressed: _toggleMute,
                      ),
                      _playerIconButton(
                        icon: Icons.graphic_eq_rounded,
                        label: english ? 'Volume' : 'مستوى الصوت',
                        onPressed: _showVolumePicker,
                      ),
                      const Spacer(),
                      _playerTextButton(
                        label: '$_playbackSpeed×',
                        tooltip: english ? 'Playback speed' : 'سرعة التشغيل',
                        onPressed: _showSpeedPicker,
                      ),
                      _playerIconButton(
                        icon: Icons.fit_screen_rounded,
                        label: english ? 'Video fit' : 'ملاءمة الفيديو',
                        onPressed: _showAspectPicker,
                      ),
                      _playerIconButton(
                        icon: _isFullscreen
                            ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded,
                        label: _isFullscreen
                            ? (english ? 'Exit fullscreen' : 'إنهاء ملء الشاشة')
                            : (english ? 'Fullscreen' : 'ملء الشاشة'),
                        onPressed: _toggleFullscreen,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _playerIconButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    double size = 22,
  }) {
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      iconSize: size,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      style: IconButton.styleFrom(
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white38,
        backgroundColor: const Color(0x33101010),
        shape: const CircleBorder(),
      ),
      icon: Icon(icon),
    );
  }

  Widget _playerTextButton({
    required String label,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildVideo(double aspectRatio) {
    final fit = (_app.webSettings['videoFill'] ?? 'fit').toString();
    if (fit == 'fit') {
      return Center(
        child: AspectRatio(
            aspectRatio: aspectRatio, child: VideoPlayer(_controller)),
      );
    }
    final screen = MediaQuery.sizeOf(context);
    final width = math.max(screen.width, screen.height * aspectRatio);
    final height = width / aspectRatio;
    return SizedBox.expand(
      child: ClipRect(
        child: Center(
          child: Transform.scale(
            scale: fit == 'zoom' ? 1.12 : 1,
            child: SizedBox(
                width: width, height: height, child: VideoPlayer(_controller)),
          ),
        ),
      ),
    );
  }

  String _episodeLabel(bool english) {
    if (widget.season == null || widget.episode == null) {
      return widget.streamName;
    }
    return english
        ? 'Season ${widget.season} · Episode ${widget.episode}'
        : 'الموسم ${widget.season} · الحلقة ${widget.episode}';
  }
}

enum _PlayerSettingAction { speed, aspect, subtitles, audio }

class _CaptionOverlay extends StatelessWidget {
  const _CaptionOverlay(
      {required this.text, required this.settings, required this.bottom});

  final String text;
  final Map<String, dynamic> settings;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final fontColor =
        _captionColor(settings['subFontColor']?.toString() ?? '#FFFFFF');
    final outlineColor =
        _captionColor(settings['subBorderColor']?.toString() ?? '#000000');
    final borderSize = (settings['subBorderSize'] as num?)?.toDouble() ?? 0;
    final style = settings['subStyle']?.toString() ?? 'shadow';
    final opacity =
        (settings['subBackgroundOpacity'] as num?)?.toDouble() ?? .35;
    final List<Shadow> shadows = style == 'outline'
        ? <Shadow>[
            for (var x = -1; x <= 1; x++)
              for (var y = -1; y <= 1; y++)
                if (x != 0 || y != 0)
                  Shadow(
                      color: outlineColor,
                      offset: Offset(x * borderSize, y * borderSize),
                      blurRadius: 0),
          ]
        : style == 'shadow'
            ? const [
                Shadow(color: Colors.black, offset: Offset(1, 2), blurRadius: 4)
              ]
            : <Shadow>[];
    return PositionedDirectional(
      start: 22,
      end: 22,
      bottom: bottom,
      child: IgnorePointer(
        child: Center(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * .88,
            ),
            padding: EdgeInsets.symmetric(
                horizontal: 10, vertical: style == 'box' ? 5 : 1),
            decoration: style == 'box'
                ? BoxDecoration(
                    color: Colors.black.withValues(alpha: opacity),
                    borderRadius: BorderRadius.circular(5))
                : null,
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: fontColor,
                fontSize: (settings['subFontSize'] as num?)?.toDouble() ?? 28,
                height: 1.15,
                fontWeight: FontWeight.w600,
                shadows: shadows,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

String _normalizedLanguage(String language) {
  final normalized = language.trim().toLowerCase();
  return switch (normalized) {
    'arabic' || 'ara' => 'ar',
    'english' || 'eng' => 'en',
    'japanese' || 'jpn' => 'ja',
    'french' || 'fra' || 'fre' => 'fr',
    'spanish' || 'spa' => 'es',
    _ => normalized,
  };
}

Color _captionColor(String value) {
  final digits = value.replaceFirst('#', '');
  final parsed = int.tryParse(digits, radix: 16) ?? 0xFFFFFF;
  return Color(0xFF000000 | parsed);
}

class _PlaybackError extends StatelessWidget {
  const _PlaybackError({
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
                color: Color(0xFFE88178),
              ),
              const SizedBox(height: 14),
              Text(
                english
                    ? 'This source could not be played'
                    : 'تعذر تشغيل هذا المصدر',
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
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(english ? 'Try again' : 'إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
}
