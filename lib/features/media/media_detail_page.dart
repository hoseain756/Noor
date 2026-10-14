import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/media_item.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';
import '../../core/torrent/torrent_models.dart';
import '../../core/torrent/torrent_service.dart';
import '../../shared/widgets/media_rail.dart';
import '../library/custom_list_picker.dart';
import 'episode_views.dart';
import '../player/video_player_page.dart';

class MediaDetailPage extends StatefulWidget {
  const MediaDetailPage({
    super.key,
    required this.item,
    this.resumeVideoId,
    this.resumePositionMs,
  });
  final MediaItem item;
  final String? resumeVideoId;
  final int? resumePositionMs;

  @override
  State<MediaDetailPage> createState() => _MediaDetailPageState();
}

class _MediaDetailPageState extends State<MediaDetailPage> {
  late Future<MediaItem?> _detail;
  Map<String, dynamic>? _selectedVideo;
  bool _loadingStreams = false;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _detail = app.catalogs.detail(widget.item.type, widget.item.id, app.addons);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final english = app.english;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final savedEpisodeView =
        app.webSettings['episodesView']?.toString() ?? 'auto';
    final episodeCards =
        savedEpisodeView == 'grid' || (savedEpisodeView == 'auto' && wide);
    final watchedEpisodeIds = app.history
        .where((entry) =>
            entry.item.id == widget.item.id &&
            entry.videoId != null &&
            entry.durationMs > 0 &&
            entry.positionMs >= entry.durationMs - 120000)
        .map((entry) => entry.videoId!)
        .toSet();
    void toggleEpisodeView() {
      unawaited(app.setSetting('episodesView', episodeCards ? 'list' : 'grid'));
    }

    return Scaffold(
      body: FutureBuilder<MediaItem?>(
        future: _detail,
        builder: (context, snapshot) {
          final item = snapshot.data ?? widget.item;
          final videos = item.videos;
          final resumeMatches = videos.where(
            (video) => video['id'] == widget.resumeVideoId,
          );
          _selectedVideo ??= resumeMatches.isNotEmpty
              ? resumeMatches.first
              : _defaultVideo(videos);
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: HorseTheme.canvas,
                title: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                actions: [
                  IconButton(
                    tooltip: english ? 'Add to collection' : 'أضف إلى قائمة',
                    onPressed: () => showCustomListPicker(context, item),
                    icon: const Icon(Icons.playlist_add_rounded),
                  ),
                  IconButton(
                    tooltip: english ? 'My list' : 'قائمتي',
                    onPressed: () => app.toggleWatchlist(item),
                    icon: Icon(
                      app.contains(item)
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      color: app.contains(item) ? HorseTheme.gold : null,
                    ),
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    wide ? 34 : 20,
                    8,
                    wide ? 34 : 20,
                    30,
                  ),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Poster(item: item, width: 250),
                            const SizedBox(width: 30),
                            Expanded(
                              child: _Description(
                                item: item,
                                videos: videos,
                                selectedVideo: _selectedVideo,
                                episodeCards: episodeCards,
                                watchedEpisodeIds: watchedEpisodeIds,
                                blurUnwatchedEpisodes:
                                    app.webSettings['blurEpisodeThumbnails'] ==
                                        true,
                                onToggleEpisodeView: toggleEpisodeView,
                                onSelectVideo: (v) =>
                                    setState(() => _selectedVideo = v),
                                loading: _loadingStreams,
                                onPlay: () => _play(item),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _Poster(item: item, width: 128),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _CompactInfo(
                                    item: item,
                                    english: english,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _Description(
                              item: item,
                              videos: videos,
                              selectedVideo: _selectedVideo,
                              episodeCards: episodeCards,
                              watchedEpisodeIds: watchedEpisodeIds,
                              blurUnwatchedEpisodes:
                                  app.webSettings['blurEpisodeThumbnails'] ==
                                      true,
                              onToggleEpisodeView: toggleEpisodeView,
                              onSelectVideo: (v) =>
                                  setState(() => _selectedVideo = v),
                              loading: _loadingStreams,
                              onPlay: () => _play(item),
                              compact: true,
                            ),
                          ],
                        ),
                ),
              ),
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    _ProviderRatings(item: item),
                    _SimilarTitles(item: item),
                    const SizedBox(height: 108),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Map<String, dynamic>? _defaultVideo(List<Map<String, dynamic>> videos) {
    if (videos.isEmpty) return null;
    for (final video in videos) {
      final season = (video['season'] as num?)?.toInt() ?? 0;
      if (season > 0) return video;
    }
    return videos.first;
  }

  Future<void> _play(MediaItem item) async {
    final app = context.read<AppState>();
    final episode = _selectedVideo;
    final id = (episode?['id'] as String?) ?? item.id;
    setState(() => _loadingStreams = true);
    List<Map<String, dynamic>> streams;
    try {
      streams = await app.catalogs.streams(item.type, id, app.addons);
    } catch (_) {
      streams = [];
    }
    if (!mounted) return;
    setState(() => _loadingStreams = false);
    if (streams.isEmpty) {
      final english = app.english;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(english ? 'No streams found' : 'لم يتم العثور على مصادر'),
          content: Text(
            english
                ? 'Install a stream add-on from Settings, then try again.'
                : 'ثبّت إضافة بث من الإعدادات ثم أعد المحاولة.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(english ? 'Close' : 'إغلاق'),
            ),
          ],
        ),
      );
      return;
    }
    if (app.webSettings['playableOnly'] == true) {
      streams = streams.where(_isPlayableStream).toList();
    }
    // Torrent sources stay available when a Debrid service is connected or
    // the device itself can run the torrent engine.
    final debridConfigured = app.api.debridService != null;
    final p2pAllowed = app.webSettings['p2pEnabled'] != false;
    var torrentSourcesAllowed = debridConfigured;
    if (!torrentSourcesAllowed && p2pAllowed) {
      try {
        torrentSourcesAllowed = await TorrentService.instance.isSupported;
      } catch (_) {
        torrentSourcesAllowed = false;
      }
      if (!mounted) return;
    }
    if (!torrentSourcesAllowed) {
      streams = streams.where((stream) => stream['url'] is String).toList();
    }
    streams = _rankStreams(streams, app.webSettings);
    final english = app.english;
    Map<String, dynamic>? selected;
    if (app.webSettings['instantPlay'] == true) {
      selected = streams.where(_isPlayableStream).firstOrNull;
    }
    selected ??= await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: HorseTheme.surface,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                english ? 'Choose a source' : 'اختر مصدر التشغيل',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .58,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: streams.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: HorseTheme.line),
                  itemBuilder: (context, index) {
                    final stream = streams[index];
                    final url = stream['url'] as String?;
                    final direct = url != null && url.startsWith('http');
                    final torrent = !direct && stream['infoHash'] is String;
                    final playable = direct || torrent;
                    final title = (stream['title'] ??
                            stream['name'] ??
                            stream['description'] ??
                            (playable ? 'HTTP stream' : 'Torrent stream'))
                        .toString()
                        .split('\n')
                        .first;
                    return ListTile(
                      dense: app.webSettings['pickerLayout'] == 'condensed',
                      enabled: playable,
                      leading: Icon(
                        playable
                            ? Icons.play_circle_outline_rounded
                            : Icons.cloud_off_rounded,
                        color: playable ? HorseTheme.gold : HorseTheme.muted,
                      ),
                      title: Text(
                        title,
                        maxLines: app.webSettings['pickerLayout'] == 'condensed'
                            ? 1
                            : 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: app.webSettings['pickerLayout'] == 'condensed'
                          ? null
                          : Text(
                              '${stream['addonName'] ?? (english ? 'Add-on' : 'إضافة')}${torrent ? (english ? ' · Torrent source' : ' · مصدر تورنت') : (playable ? '' : (english ? ' · Unsupported source' : ' · مصدر غير مدعوم'))}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      onTap: playable
                          ? () => Navigator.pop(context, stream)
                          : null,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final chosenStream = selected;
    setState(() => _loadingStreams = true);
    PreparedTorrent? prepared;
    try {
      final rawUrl = chosenStream['url'] as String?;
      final hints =
          (chosenStream['behaviorHints'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
      final proxyHeaders = (hints['proxyHeaders'] as Map?)
          ?.map((key, value) => MapEntry(key.toString(), value.toString()));
      final filename =
          (hints['filename'] ?? chosenStream['title'])?.toString();
      final String url;
      if (rawUrl != null && rawUrl.startsWith('http')) {
        // Direct HTTP sources play as-is; the player attaches the source's
        // proxy headers itself. No server-side signing is involved anymore.
        url = rawUrl;
      } else {
        final infoHash =
            (chosenStream['infoHash'] ?? '').toString().toLowerCase();
        final sizeCandidate = chosenStream['fileSize'] ?? hints['videoSize'];
        final filesize = sizeCandidate is num ? sizeCandidate.toInt() : null;
        final resolved = await _resolveTorrentStream(
          displayName: item.name,
          infoHash: infoHash,
          filename: filename,
          filesize: filesize,
          english: english,
        );
        if (!mounted) return;
        if (resolved == null) {
          setState(() => _loadingStreams = false);
          return;
        }
        url = resolved.url;
        prepared = resolved.torrent;
      }
      if (!mounted) return;
      setState(() => _loadingStreams = false);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VideoPlayerPage(
            item: item,
            url: url,
            headers: proxyHeaders,
            filename: filename,
            torrent: prepared,
            streamName: (chosenStream['title'] ??
                    chosenStream['addonName'] ??
                    'Noor')
                .toString(),
            videoId: id,
            season: (episode?['season'] as num?)?.toInt(),
            episode: (episode?['episode'] as num?)?.toInt(),
            nextEpisode: _nextEpisode(item.videos, episode),
            initialPositionMs: widget.resumeVideoId == episode?['id']
                ? widget.resumePositionMs
                : null,
          ),
          fullscreenDialog: true,
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _loadingStreams = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  /// Resolves an infoHash stream through the connected Debrid service first
  /// and the on-device torrent engine second. A cancellable progress dialog
  /// covers the whole preparation. Returns `null` after showing a bilingual
  /// explanation when no resolution path exists (or the user cancels).
  Future<({String url, PreparedTorrent? torrent})?> _resolveTorrentStream({
    required String displayName,
    required String infoHash,
    required String? filename,
    required int? filesize,
    required bool english,
  }) async {
    final app = context.read<AppState>();
    final api = app.api;
    final debridConfigured = api.debridService != null;
    var engineSupported = false;
    if (!debridConfigured) {
      try {
        engineSupported = await TorrentService.instance.isSupported;
      } catch (_) {
        engineSupported = false;
      }
      if (!engineSupported) {
        // Neither path exists on this device — explain the requirement.
        _showNoTorrentPathMessage(english);
        return null;
      }
    }
    if (!mounted) return null;
    final navigator = Navigator.of(context, rootNavigator: true);
    var cancelled = false;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: HorseTheme.surface,
        content: Row(
          children: [
            const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                english ? 'Preparing the stream…' : 'جارٍ تجهيز المصدر…',
                style: Theme.of(dialogContext).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelled = true;
              Navigator.of(dialogContext).pop();
            },
            child: Text(english ? 'Cancel' : 'إلغاء'),
          ),
        ],
      ),
    ));
    try {
      if (debridConfigured) {
        final url = await api.resolveDebridTorrent(
          infoHash: infoHash,
          filename: filename,
          filesize: filesize,
        );
        if (cancelled) return null;
        if (url != null && url.isNotEmpty) {
          return (url: url, torrent: null);
        }
        // The debrid service could not resolve this torrent (not cached,
        // quota, network…). Degrade to the on-device engine when possible.
        try {
          engineSupported = await TorrentService.instance.isSupported;
        } catch (_) {
          engineSupported = false;
        }
        if (cancelled) return null;
        if (!engineSupported) {
          _showNoTorrentPathMessage(english, debridFailed: true);
          return null;
        }
      }
      final prepared = await TorrentService.instance.prepare(
        infoHash: infoHash,
        filename: filename,
        filesize: filesize,
        displayName: displayName,
      );
      if (cancelled) {
        // The user backed out while the engine was preparing the stream.
        unawaited(prepared.stop());
        unawaited(TorrentService.instance.remove(prepared.infoHash));
        return null;
      }
      return (url: prepared.url, torrent: prepared);
    } finally {
      if (!cancelled) navigator.pop();
    }
  }

  /// Bilingual SnackBar explaining that torrent playback needs either a
  /// connected Debrid service or a device with the built-in torrent engine.
  void _showNoTorrentPathMessage(bool english, {bool debridFailed = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          debridFailed
              ? (english
                  ? 'The Debrid service could not resolve this torrent and this device has no built-in torrent engine.'
                  : 'تعذّرت خدمة Debrid حل هذا التورنت، وهذا الجهاز لا يدعم محرك التورنت المدمج.')
              : (english
                  ? 'Torrent streaming needs a Debrid service (Real-Debrid / AllDebrid / TorBox) or a device with the built-in torrent engine.'
                  : 'البث عبر التورنت يحتاج خدمة Debrid (Real-Debrid / AllDebrid / TorBox) أو جهازًا يدعم محرك التورنت المدمج.'),
        ),
      ),
    );
  }

  bool _isPlayableStream(Map<String, dynamic> stream) {
    final url = stream['url'];
    return (url is String && url.startsWith('http')) ||
        stream['infoHash'] is String;
  }

  List<Map<String, dynamic>> _rankStreams(
    List<Map<String, dynamic>> streams,
    Map<String, dynamic> settings,
  ) {
    final preferred = (settings['preferredQuality'] ?? 'auto').toString();
    final preferH264 = settings['preferH264'] == true;
    if (preferred == 'auto' &&
        settings['streamSort'] != 'score' &&
        !preferH264) {
      return streams;
    }
    final ranked = [...streams];
    int quality(Map<String, dynamic> stream) {
      final text = '${stream['title'] ?? ''} ${stream['name'] ?? ''}';
      final match = RegExp(r'(2160|1080|720|480)p?', caseSensitive: false)
          .firstMatch(text);
      final height = int.tryParse(match?.group(1) ?? '') ?? 0;
      final target = int.tryParse(preferred.replaceAll('p', ''));
      final codec = text.toLowerCase();
      final codecPreference = preferH264
          ? (codec.contains('x265') || codec.contains('hevc')
              ? -100000
              : 100000)
          : 0;
      return target == null
          ? codecPreference + height
          : codecPreference + (height == target ? 10000 + height : height);
    }

    ranked.sort((a, b) => quality(b).compareTo(quality(a)));
    return ranked;
  }

  Map<String, dynamic>? _nextEpisode(
    List<Map<String, dynamic>> videos,
    Map<String, dynamic>? current,
  ) {
    final index = videos.indexWhere((video) => video['id'] == current?['id']);
    return index >= 0 && index + 1 < videos.length ? videos[index + 1] : null;
  }
}

class _Description extends StatelessWidget {
  const _Description({
    required this.item,
    required this.videos,
    required this.selectedVideo,
    required this.episodeCards,
    required this.watchedEpisodeIds,
    required this.blurUnwatchedEpisodes,
    required this.onToggleEpisodeView,
    required this.onSelectVideo,
    required this.loading,
    required this.onPlay,
    this.compact = false,
  });
  final MediaItem item;
  final List<Map<String, dynamic>> videos;
  final Map<String, dynamic>? selectedVideo;
  final bool episodeCards;
  final Set<String> watchedEpisodeIds;
  final bool blurUnwatchedEpisodes;
  final VoidCallback onToggleEpisodeView;
  final ValueChanged<Map<String, dynamic>> onSelectVideo;
  final bool loading;
  final VoidCallback onPlay;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final english = context.watch<AppState>().english;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact) ...[
          _CompactInfo(item: item, english: english),
          const SizedBox(height: 18),
        ],
        if (item.description != null && item.description!.isNotEmpty)
          Text(
            item.description!,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.white70, height: 1.6),
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final genre in item.genres.take(6))
              Chip(
                label: Text(genre),
                visualDensity: VisualDensity.compact,
                side: const BorderSide(color: HorseTheme.line),
                backgroundColor: HorseTheme.surface,
              ),
          ],
        ),
        if (videos.isNotEmpty) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  english ? 'Episodes' : 'الحلقات',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: episodeCards
                    ? (english ? 'Switch to list view' : 'عرض الحلقات كقائمة')
                    : (english ? 'Switch to card view' : 'عرض الحلقات كبطاقات'),
                onPressed: onToggleEpisodeView,
                icon: Icon(
                  episodeCards
                      ? Icons.view_list_rounded
                      : Icons.grid_view_rounded,
                  color: HorseTheme.gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          if (episodeCards)
            EpisodeGrid(
              episodes: videos.take(60).toList(),
              selectedId: selectedVideo?['id']?.toString(),
              english: english,
              watchedEpisodeIds: watchedEpisodeIds,
              blurUnwatched: blurUnwatchedEpisodes,
              onSelected: onSelectVideo,
            )
          else
            EpisodeList(
              episodes: videos.take(60).toList(),
              selectedId: selectedVideo?['id']?.toString(),
              english: english,
              watchedEpisodeIds: watchedEpisodeIds,
              blurUnwatched: blurUnwatchedEpisodes,
              onSelected: onSelectVideo,
            ),
        ],
        const SizedBox(height: 22),
        SizedBox(
          width: compact ? double.infinity : 260,
          child: FilledButton.icon(
            onPressed: loading ? null : onPlay,
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow_rounded),
            label: Text(
              loading
                  ? (english ? 'Finding streams…' : 'جارٍ البحث عن مصادر…')
                  : (english ? 'Find a stream' : 'ابحث عن مصدر تشغيل'),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          english
              ? 'Playback uses your selected add-on source.'
              : 'يعتمد التشغيل على مصدر الإضافة التي تختارها.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _CompactInfo extends StatelessWidget {
  const _CompactInfo({required this.item, required this.english});
  final MediaItem item;
  final bool english;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.name,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 8,
            runSpacing: 5,
            children: [
              if (item.releaseInfo != null) _MetaBadge(item.releaseInfo!),
              _MetaBadge(
                item.type == 'series'
                    ? (english ? 'Series' : 'مسلسل')
                    : (english ? 'Movie' : 'فيلم'),
              ),
              if (item.rating != null)
                _MetaBadge('★ ${item.rating}', color: HorseTheme.gold),
            ],
          ),
        ],
      );
}

class _MetaBadge extends StatelessWidget {
  const _MetaBadge(this.text, {this.color = HorseTheme.muted});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: HorseTheme.surface,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: HorseTheme.line),
        ),
        child: Text(
          text,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600),
        ),
      );
}

class _Poster extends StatelessWidget {
  const _Poster({required this.item, required this.width});
  final MediaItem item;
  final double width;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: width,
          child: AspectRatio(
            aspectRatio: .68,
            child: item.poster == null
                ? const ColoredBox(
                    color: HorseTheme.raised,
                    child: Icon(
                      Icons.movie_outlined,
                      size: 38,
                      color: HorseTheme.gold,
                    ),
                  )
                : Image.network(
                    item.poster!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const ColoredBox(
                      color: HorseTheme.raised,
                      child: Icon(
                        Icons.movie_outlined,
                        size: 38,
                        color: HorseTheme.gold,
                      ),
                    ),
                  ),
          ),
        ),
      );
}

class _ProviderRatings extends StatefulWidget {
  const _ProviderRatings({required this.item});
  final MediaItem item;

  @override
  State<_ProviderRatings> createState() => _ProviderRatingsState();
}

class _ProviderRatingsState extends State<_ProviderRatings> {
  Future<Map<String, dynamic>>? _ratings;
  bool? _enabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled =
        context.read<AppState>().webSettings['ratingsEnabled'] != false;
    if (_enabled != enabled) {
      _enabled = enabled;
      _ratings = enabled &&
              (widget.item.type == 'movie' || widget.item.type == 'series')
          ? _loadRatings()
          : null;
    }
  }

  Future<Map<String, dynamic>> _loadRatings() async {
    final item = widget.item;
    final year = item.releaseInfo?.isNotEmpty == true
        ? item.releaseInfo!
            .substring(0, item.releaseInfo!.length.clamp(0, 4))
        : null;
    final imdb = RegExp(r'^tt\d+$').hasMatch(item.id) ? item.id : null;
    final anime = item.genres.any((genre) => genre.toLowerCase() == 'animation') &&
        (item.originCountry ?? '').toLowerCase().contains('japan');
    final data = await context.read<AppState>().api.ratingsGet(
          type: item.type == 'series' ? 'series' : 'movie',
          title: item.name,
          year: year,
          imdb: imdb,
          anime: anime,
        );
    return data is Map
        ? Map<String, dynamic>.from(data)
        : const <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.webSettings['ratingsEnabled'] == false || _ratings == null) {
      return const SizedBox.shrink();
    }
    final english = app.english;
    return FutureBuilder<Map<String, dynamic>>(
      future: _ratings,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 2, 20, 16),
            child: Wrap(
              spacing: 7,
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 76,
                    height: 28,
                    decoration: BoxDecoration(
                        color: HorseTheme.raised,
                        borderRadius: BorderRadius.circular(24)),
                  ),
              ],
            ),
          );
        }
        final ratings = _ratingRows(snapshot.data ?? const <String, dynamic>{});
        if (ratings.isEmpty) return const SizedBox.shrink();
        final preferred =
            (app.webSettings['ratingsProviders'] as List? ?? const [])
                .map((value) => value.toString())
                .toList();
        ratings.sort((a, b) {
          final aOrder = preferred.indexOf(a['provider']?.toString() ?? '');
          final bOrder = preferred.indexOf(b['provider']?.toString() ?? '');
          return (aOrder < 0 ? 999 : aOrder)
              .compareTo(bOrder < 0 ? 999 : bOrder);
        });
        return Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 20),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final rating in ratings)
                  _RatingChip(rating: rating, english: english),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RatingChip extends StatelessWidget {
  const _RatingChip({required this.rating, required this.english});
  final Map<String, dynamic> rating;
  final bool english;

  @override
  Widget build(BuildContext context) {
    final provider = (rating['provider'] ?? '').toString().toLowerCase();
    final label = switch (provider) {
      'imdb' => 'IMDb',
      'rotten' => 'RT',
      'metacritic' => 'Metacritic',
      'tmdb' => 'TMDB',
      'trakt' => 'Trakt',
      'mdblist' => 'MDBList',
      'anilist' => 'AniList',
      'mal' => 'MAL',
      'kitsu' => 'Kitsu',
      _ => provider.isEmpty ? (english ? 'Rating' : 'تقييم') : provider,
    };
    final display = (rating['display'] ?? '').toString();
    final scale = (rating['originalScale'] ?? '/10').toString();
    final votes = rating['votes'] is num ? (rating['votes'] as num).toInt() : 0;
    final url = Uri.tryParse((rating['url'] ?? '').toString());
    final color = switch (provider) {
      'imdb' => const Color(0xFFFFC107),
      'tmdb' => const Color(0xFF01B4E4),
      'trakt' || 'rotten' => const Color(0xFFDA3545),
      'metacritic' => const Color(0xFF21A366),
      'anilist' => const Color(0xFF7B61FF),
      'mal' => const Color(0xFF2E66A8),
      _ => HorseTheme.gold,
    };
    return Semantics(
      button: url?.hasScheme == true,
      label: '$label $display $scale',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: url?.hasScheme == true ? () => unawaited(launchUrl(url!)) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .32),
            border: Border.all(color: HorseTheme.line),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(12)),
                child: Text(label,
                    style: TextStyle(
                        color: provider == 'imdb' ? Colors.black : Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 6),
              Text(display,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700)),
              if (scale != '/10')
                Text(scale == '%' ? '' : scale,
                    style:
                        const TextStyle(fontSize: 10, color: HorseTheme.muted)),
              if (votes > 0) ...[
                const SizedBox(width: 4),
                Text(_compactVotes(votes),
                    style:
                        const TextStyle(fontSize: 10, color: HorseTheme.muted)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SimilarTitles extends StatefulWidget {
  const _SimilarTitles({required this.item});
  final MediaItem item;

  @override
  State<_SimilarTitles> createState() => _SimilarTitlesState();
}

class _SimilarTitlesState extends State<_SimilarTitles> {
  Future<List<MediaItem>>? _similar;
  String? _genre;
  String? _requestSignature;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final genre = widget.item.genres
        .where((value) => value.trim().isNotEmpty)
        .firstOrNull;
    final app = context.read<AppState>();
    final signature = [
      widget.item.id,
      genre,
      app.webSettings['tmdbEnabled'],
      app.webSettings['tmdbLanguage'],
      app.webSettings['region'],
    ].join('|');
    if (signature != _requestSignature) {
      _requestSignature = signature;
      _genre = genre;
      final language = app.webSettings['tmdbLanguage']?.toString() ?? 'en-US';
      final region = app.webSettings['region']?.toString() ?? 'US';
      final fallback = genre == null
          ? Future.value(const <MediaItem>[])
          : app.catalogs
              .catalog(widget.item.type, 'top', extras: {'genre': genre});
      _similar = app.webSettings['tmdbEnabled'] == false
          ? fallback
          : app.catalogs
              .tmdbRecommendations(
                widget.item,
                language: language,
                region: region,
              )
              .then((items) => items.isNotEmpty ? items : fallback);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final future = _similar;
    if (future == null) return const SizedBox.shrink();
    return FutureBuilder<List<MediaItem>>(
      future: future,
      builder: (context, snapshot) {
        final items = (snapshot.data ?? const <MediaItem>[])
            .where((item) => item.id != widget.item.id)
            .take(14)
            .toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 22),
          child: MediaRail(
            title: app.english
                ? (_genre == null
                    ? 'Recommended for you'
                    : 'More like this · $_genre')
                : (_genre == null ? 'مقترح لك' : 'أعمال مشابهة · $_genre'),
            items: items,
            onTap: (item) => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => MediaDetailPage(item: item)),
            ),
          ),
        );
      },
    );
  }
}

String _compactVotes(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).round()}K';
  return '$value';
}

/// Converts the consolidated ratings payload into chip rows. The payload maps
/// provider keys to `{rating, votes}` objects; providers can be missing or
/// null when their rating is unavailable for the title.
List<Map<String, dynamic>> _ratingRows(Map<String, dynamic> data) {
  const providers = <String, String>{
    'imdb': 'imdb',
    'rottenTomatoes': 'rotten',
    'metacritic': 'metacritic',
    'tmdb': 'tmdb',
    'trakt': 'trakt',
    'mdblist': 'mdblist',
  };
  const percentProviders = {'rottenTomatoes', 'mdblist'};
  const scales = <String, String>{
    'imdb': '/10',
    'rottenTomatoes': '%',
    'metacritic': '/100',
    'tmdb': '/10',
    'trakt': '/10',
    'mdblist': '%',
  };
  final rows = <Map<String, dynamic>>[];
  for (final entry in providers.entries) {
    final value = data[entry.key];
    if (value is! Map) continue;
    final row = Map<String, dynamic>.from(value);
    final rating = _parseRating(row['rating']);
    if (rating == null) continue;
    final votes = row['votes'] is num ? (row['votes'] as num).toInt() : 0;
    final percent = percentProviders.contains(entry.key);
    rows.add(<String, dynamic>{
      'provider': entry.value,
      'display': percent
          ? '${rating.round()}%'
          : rating % 1 == 0
              ? rating.toInt().toString()
              : rating.toStringAsFixed(1),
      'originalScale': scales[entry.key],
      if (votes > 0) 'votes': votes,
    });
  }
  return rows;
}

double? _parseRating(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    final cleaned = value.trim().replaceAll('%', '');
    return double.tryParse(cleaned);
  }
  return null;
}
