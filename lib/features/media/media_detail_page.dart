import 'package:nova_mobile/l10n/nova_strings.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/featured_artwork.dart';
import '../../core/models/media_item.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';
import '../../core/torrent/torrent_models.dart';
import '../../core/torrent/torrent_service.dart';
import '../../shared/widgets/media_rail.dart';
import '../../shared/widgets/noor_toast.dart';
import '../../shared/widgets/nova_parental_gate.dart';
import '../anime/anime_tracker_sheet.dart';
import '../library/custom_list_picker.dart';
import '../player/stream_headers.dart';
import '../player/video_player_page.dart';
import '../shell/noor_dock_tabs.dart' show glassDockContentClearance;
import 'detail_hero.dart';
import 'episode_data.dart';
import 'episode_views.dart';
import 'sources_page.dart';
import 'stream_loading.dart';
import '../home/widgets/cinematic_cover_scroll.dart';
import '../home/widgets/async_media_section.dart';
import '../../core/downloads/download_manager.dart';

/// Cinematic detail page — the Flutter replica of the Harbor web DetailView:
/// fixed glass back pill over a full-bleed hero (phone card variant < 700px /
/// wide band ≥ 700px), start-aligned content column (single-line meta row,
/// provider ratings, synopsis, CTA + expandable glass menu + lists circle,
/// cast & crew), the rebuilt episodes system, the similar rail and the
/// TMDB-enriched artwork — all fail-soft and RTL-mirrored.
///
/// The playback machinery (streams → rank → instant-play/source sheet →
/// debrid/torrent resolve → player) is byte-for-byte the previous contract;
/// only the presentation around it changed.
class MediaDetailPage extends StatefulWidget {
  const MediaDetailPage({
    super.key,
    required this.item,
    this.resumeVideoId,
    this.resumePositionMs,
    this.kidsMode = false,
  });
  final MediaItem item;
  final bool kidsMode;

  /// Continue-watching handoff: the video to resume (series episode id, or
  /// the movie's own id) and the playback position in milliseconds.
  final String? resumeVideoId;
  final int? resumePositionMs;

  @override
  State<MediaDetailPage> createState() => _MediaDetailPageState();
}

class _MediaDetailPageState extends State<MediaDetailPage> {
  late Future<MediaItem?> _detail;
  FeaturedArtwork? _art;
  MediaItem? _enrichedItem;
  int _detailGeneration = 0;
  bool _loadingStreams = false;

  /// Episodes subsystem state (season/sort/view) — Task 118. Created lazily
  /// on the first populated build; the page listens so season/sort/view
  /// toggles rebuild ONLY the episodes slivers, never the hero or shell.
  EpisodesController? _episodes;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _detail = _loadDetail(app);
    _loadFeaturedArtwork(app);
  }

  @override
  void dispose() {
    _episodes?.removeListener(_onEpisodesChanged);
    _episodes?.dispose();
    super.dispose();
  }

  void _onEpisodesChanged() {
    if (mounted) setState(() {});
  }

  /// TMDB textless backdrop + transparent logo (in-memory cached inside the
  /// repository). Fails soft with a timeout: the page renders instantly from
  /// the item's own fields and enriches when the art arrives.
  Future<void> _loadFeaturedArtwork(AppState app) async {
    final item = widget.item;
    if (!RegExp(r'^tt\d+$').hasMatch(item.id)) return;
    try {
      final artwork = await app.catalogs
          .featuredArtwork(
            item,
            // Task 122-d: TMDB text/genre/overview and the logo/image-language
            // pick follow the CONTENT language (was the legacy UI-less
            // TMDB-locale fallback + the UI language). The repository
            // normalizes uiLanguage to its primary subtag for the
            // include_image_language list and logo preference (en/null
            // fallback chain unchanged).
            language: app.contentTmdbLocale,
            region: app.webSettings['region']?.toString() ?? 'US',
            uiLanguage: app.contentTmdbLocale,
          )
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() => _art = artwork);
    } catch (_) {
      // Featured art is a bonus — the hero keeps the addon artwork.
    }
  }

  Future<MediaItem?> _loadDetail(AppState app) async {
    final generation = ++_detailGeneration;
    final item =
        await app.catalogs.detail(widget.item.type, widget.item.id, app.addons);
    if (item != null && app.webSettings['tmdbEnabled'] != false) {
      unawaited(app.catalogs
          .detailEnrichment(item,
              language: app.contentTmdbLocale,
              region: app.webSettings['region']?.toString() ?? 'US')
          .then((enriched) {
        if (mounted && generation == _detailGeneration) {
          setState(() => _enrichedItem = enriched);
        }
      }).catchError((Object _) {}));
    }
    return item;
  }

  void _reloadDetail() {
    final app = context.read<AppState>();
    setState(() {
      _enrichedItem = null;
      _detail = _loadDetail(app);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final english = app.english;
    final media = MediaQuery.of(context);
    final isWide = media.size.width >= 700;
    return Scaffold(
      body: FutureBuilder<MediaItem?>(
        future: _detail,
        builder: (context, snapshot) {
          final done = snapshot.connectionState != ConnectionState.waiting;
          final failed = done && (snapshot.hasError || !snapshot.hasData);
          // The warm item renders instantly; the skeleton only exists for
          // degenerate hand-offs with no title at all (the web always shows
          // a skeleton because it never has a warm item).
          final showSkeleton = !failed && widget.item.name.isEmpty;
          return Stack(
            children: [
              if (showSkeleton)
                const Positioned.fill(child: DetailLoadingSkeleton())
              else if (failed && widget.item.name.isEmpty)
                Positioned.fill(
                  child: _ErrorView(
                    english: english,
                    message: snapshot.error?.toString() ??
                        (NovaStrings.lookup(english, 'message172')),
                    onRetry: _reloadDetail,
                  ),
                )
              else
                Positioned.fill(
                  child: _buildContent(
                    context,
                    app,
                    item: _enrichedItem ?? snapshot.data ?? widget.item,
                    english: english,
                    isWide: isWide,
                    viewportSize: media.size,
                    refreshFailed: failed,
                  ),
                ),
              // Fixed chrome — visible in every state, over everything.
              DetailBackPill(english: english),
            ],
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Page content
  // -------------------------------------------------------------------------

  Widget _buildContent(
    BuildContext context,
    AppState app, {
    required MediaItem item,
    required bool english,
    required bool isWide,
    required Size viewportSize,
    bool refreshFailed = false,
  }) {
    final videos = sortEpisodes(item.videos);
    final resume = _resolveResume(app, item, videos);
    final defaultVideo = _defaultVideo(videos);
    final backdrop = _art?.landscape ?? item.background;
    final logo = _art?.logo ?? item.logo;

    // Episodes controller sync (Task 118): created lazily on the first
    // populated build, refreshed with the freshest item/entries/settings on
    // every rebuild — then laid out as TRUE slivers of this scroll view
    // (one unified scroll position; the old nested 68vh scroller used to
    // swallow drags at its edge and strand the page).
    List<Widget> episodeSlivers = const [];
    if (item.type == 'series' && item.videos.isNotEmpty) {
      final entries = app.history
          .where((entry) => entry.item.id == item.id)
          .toList(growable: false);
      final savedView = app.webSettings['episodesView']?.toString() ?? 'auto';
      if (_episodes == null) {
        _episodes = EpisodesController(
          item: item,
          entries: entries,
          savedView: savedView,
        )..addListener(_onEpisodesChanged);
      } else {
        _episodes!.update(item: item, entries: entries, savedView: savedView);
      }
      episodeSlivers = buildEpisodeSlivers(
        controller: _episodes!,
        english: english,
        isWide: isWide,
        contentWidth: viewportSize.width - (isWide ? 68.0 : 40.0),
        blurUnwatched: app.webSettings['blurEpisodeThumbnails'] == true,
        ratingsEnabled: app.webSettings['ratingsEnabled'] != false,
        onViewChange: (view) {
          // Local toggle first (instant, no AppState round-trip), then a
          // fire-and-forget persist for the next visit.
          _episodes!.setView(view);
          unawaited(app.setSetting('episodesView', view));
        },
        onPlay: (video) => _play(item, video: video),
      );
    }

    final gutter = isWide ? 40.0 : 24.0;
    final heroHeight = (viewportSize.height * (isWide ? .65 : .60))
            .clamp(360.0, 640.0) +
        (MediaQuery.textScalerOf(context).scale(16) - 16).clamp(0.0, 32.0) * 4;
    return CinematicCoverScroll(
      storageKey: PageStorageKey('detail-${item.id}'),
      heroHeight: heroHeight,
      heroBuilder: (contentVisibility) => DetailHero(
          item: item,
          backdropUrl: backdrop,
          logoUrl: logo,
          isWide: isWide,
          viewportHeight: viewportSize.height,
          viewportWidth: viewportSize.width,
          contentVisibility: contentVisibility),
      slivers: [
        SliverToBoxAdapter(
            child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(gutter, 24, gutter, 32),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (refreshFailed) ...[
              Text(NovaStrings.lookup(english, 'message173'),
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              TextButton(
                  onPressed: _reloadDetail,
                  child: Text(NovaStrings.lookup(english, 'message174'))),
              const SizedBox(height: 16),
            ],
            DetailMetaRow(item: item, isWide: true),
            const SizedBox(height: 20),
            DetailActionRow(
              english: english,
              isWide: true,
              inList: app.contains(item),
              showTrackAnime: item.hasAnimeIds &&
                  (app.linkedServices['anilist']?['linked'] == true ||
                      app.linkedServices['mal']?['linked'] == true),
              primaryLabel: resume.isResume
                  ? (item.type == 'series'
                      ? (NovaStrings.lookup(english, 'message175',
                          {'p0': resume.season, 'p1': resume.episode}))
                      : (NovaStrings.lookup(english, 'message176')))
                  : (NovaStrings.lookup(english, 'message177')),
              primaryIsResume: resume.isResume,
              loading: _loadingStreams,
              onPrimaryPressed: () => _play(item,
                  video: resume.video ?? defaultVideo,
                  resumePositionMs: resume.positionMs),
              onToggleWatchlist: () => unawaited(app.toggleWatchlist(item)),
              onOpenStreams: () =>
                  _play(item, video: resume.video ?? defaultVideo),
              onTrackAnime: () =>
                  unawaited(showAnimeTrackerSheet(context, item)),
              onShare: () => unawaited(_share(item, english)),
              onAddToList: () => unawaited(showCustomListPicker(context, item)),
              onDownload: widget.kidsMode
                  ? null
                  : () => unawaited(
                      _download(item, video: resume.video ?? defaultVideo)),
            ),
            const SizedBox(height: 16),
            _ProviderRatings(item: item, startAligned: true),
            if (item.description?.isNotEmpty == true) ...[
              const SizedBox(height: 32),
              Text(NovaStrings.lookup(english, 'message178'),
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              DetailSynopsis(
                  description: item.description!,
                  isWide: isWide,
                  viewportWidth: viewportSize.width),
            ],
          ]),
        )),
        if (episodeSlivers.isNotEmpty)
          SliverPadding(
              padding: EdgeInsetsDirectional.fromSTEB(gutter, 0, gutter, 32),
              sliver: SliverMainAxisGroup(slivers: episodeSlivers)),
        SliverToBoxAdapter(
            child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(gutter, 8, gutter, 32),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            DetailCastCrew(item: item, english: english),
            DetailProduction(item: item, english: english),
          ]),
        )),
        // The fact table is deliberately immediately before similar titles.
        SliverToBoxAdapter(
            child: Padding(
                padding: EdgeInsetsDirectional.fromSTEB(gutter, 0, gutter, 0),
                child: DetailFactsTable(item: item, english: english))),
        SliverToBoxAdapter(
            child: _SimilarTitles(item: item, kidsMode: widget.kidsMode)),
        SliverToBoxAdapter(
            child: SizedBox(height: glassDockContentClearance(context))),
      ],
    );
  }

  Future<void> _download(MediaItem item, {Map<String, dynamic>? video}) async {
    final app = context.read<AppState>();
    final id = video?['id']?.toString() ?? item.id;
    final picked = await Navigator.of(context)
        .push<Map<String, dynamic>>(MaterialPageRoute(
            builder: (_) => SourcesPage(
                  item: item,
                  video: video,
                  english: app.english,
                  downloadMode: true,
                  loader: () async => (await loadRankedSources(
                          app: app, item: item, videoId: id))
                      .where((source) =>
                          source['url'] is String &&
                          (source['url'] as String).startsWith('http'))
                      .toList(),
                )));
    if (picked == null || !mounted) return;
    final title = video == null
        ? item.name
        : '${item.name} · S${video['season']}:E${video['episode']}';
    try {
      final source = parsePlaybackSource(picked);
      if (source == null) return;
      await DownloadManager.instance
          .enqueue(url: source.url, title: title, headers: source.headers);
      if (mounted) {
        NoorToast.show(context, NovaStrings.lookup(app.english, 'message179'));
      }
    } catch (_) {
      if (mounted) {
        NoorToast.show(context, NovaStrings.lookup(app.english, 'message180'),
            error: true);
      }
    }
  }

  /// Resolves the primary CTA's resume target from the constructor hand-off
  /// (continue-watching) and this title's newest history entry.
  _ResumePlan _resolveResume(
    AppState app,
    MediaItem item,
    List<Map<String, dynamic>> videos,
  ) {
    final entry = app.history.where((h) => h.item.id == item.id).firstOrNull;
    final progress = entry != null && entry.durationMs > 0
        ? entry.positionMs / entry.durationMs
        : 0.0;

    if (item.type == 'series') {
      Map<String, dynamic>? video;
      int? position;
      if (widget.resumeVideoId != null) {
        video = videos
            .where((v) => v['id']?.toString() == widget.resumeVideoId)
            .firstOrNull;
        if (video != null) position = widget.resumePositionMs;
      }
      if (video == null &&
          entry != null &&
          entry.season != null &&
          entry.episode != null &&
          progress < 0.92) {
        video = videos
            .where((v) =>
                (v['season'] as num?)?.toInt() == entry.season &&
                (v['episode'] as num?)?.toInt() == entry.episode)
            .firstOrNull;
        if (video != null && entry.positionMs > 0) position = entry.positionMs;
      }
      if (video == null) return const _ResumePlan();
      final season = (video['season'] as num?)?.toInt() ?? entry?.season ?? 1;
      final episode =
          (video['episode'] as num?)?.toInt() ?? entry?.episode ?? 1;
      return _ResumePlan(
          video: video,
          positionMs: position,
          isResume: true,
          season: season,
          episode: episode);
    }

    // Movie: the CW hand-off or an in-progress history entry resumes.
    final cwResume =
        widget.resumeVideoId != null && (widget.resumePositionMs ?? 0) > 0;
    final historyResume =
        entry != null && entry.positionMs > 0 && progress < 0.92;
    if (cwResume || historyResume) {
      final position = widget.resumePositionMs ?? entry?.positionMs ?? 0;
      return _ResumePlan(
          positionMs: position > 0 ? position : null, isResume: true);
    }
    return const _ResumePlan();
  }

  Map<String, dynamic>? _defaultVideo(List<Map<String, dynamic>> videos) {
    for (final video in videos) {
      if (((video['season'] as num?)?.toInt() ?? 0) > 0) return video;
    }
    return videos.firstOrNull;
  }

  Future<void> _share(MediaItem item, bool english) async {
    if (widget.kidsMode &&
        (!await NovaParentalGate.verify(context) || !mounted)) {
      return;
    }
    try {
      await SharePlus.instance.share(ShareParams(text: item.name));
    } catch (_) {
      // No share sheet on this platform — fall back to the clipboard.
      try {
        await Clipboard.setData(ClipboardData(text: item.name));
        if (mounted) {
          NoorToast.show(
            context,
            NovaStrings.lookup(english, 'message181'),
          );
        }
      } catch (_) {
        // Clipboard unavailable too — nothing else to do.
      }
    }
  }

  // -------------------------------------------------------------------------
  // Playback machinery (unchanged contract — moved, not rewritten)
  // -------------------------------------------------------------------------

  Future<void> _play(
    MediaItem item, {
    Map<String, dynamic>? video,
    int? resumePositionMs,
  }) async {
    final app = context.read<AppState>();
    final english = app.english;
    final episode = video;
    // Task 139 (user mandate): watch / episode taps land DIRECTLY on the
    // sources page — the streams are fetched INSIDE it (spinner + refresh
    // button next to the search bar) and only the picked stream is
    // resolved afterwards. The old instant-play auto-pick is gone: the
    // user always chooses the source.
    final id = (episode?['id'] as String?) ?? item.id;
    final picked = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => SourcesPage(
          item: item,
          video: episode,
          english: english,
          loader: () => loadRankedSources(app: app, item: item, videoId: id),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _launchStream(
      item: item,
      episode: episode,
      stream: picked,
      resumePositionMs: resumePositionMs,
    );
  }

  /// Resolves the chosen stream (direct URL / debrid / on-device torrent)
  /// and pushes the player — the playback contract carried over unchanged
  /// from the old inline-sheet flow, now fed by the sources page.
  Future<void> _launchStream({
    required MediaItem item,
    required Map<String, dynamic>? episode,
    required Map<String, dynamic> stream,
    required int? resumePositionMs,
  }) async {
    final id = (episode?['id'] as String?) ?? item.id;
    final chosenStream = stream;
    setState(() => _loadingStreams = true);
    PreparedTorrent? prepared;
    Map<String, String>? directHeaders;
    try {
      final hints =
          (chosenStream['behaviorHints'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
      final filename = (hints['filename'] ?? chosenStream['title'])?.toString();
      final String url;
      final direct = parsePlaybackSource(chosenStream);
      // Task 128: addons increasingly return magnet: URIs in the url field —
      // they resolve through debrid/engine (trackers preserved), never mpv.
      final magnetUrl = (direct?.url ?? '').toLowerCase().startsWith('magnet:')
          ? direct!.url
          : null;
      if (direct != null &&
          magnetUrl == null &&
          direct.url.startsWith('http')) {
        // Direct HTTP sources play as-is; the player attaches the source's
        // headers (pipe syntax / proxyHeaders flat or nested / legacy
        // headers — all normalized by parsePlaybackSource, Task 127).
        url = direct.url;
        directHeaders = direct.headers.isEmpty ? null : direct.headers;
      } else {
        // Task 142: the shared TorrentStreamHints extraction (info-hash from
        // the stream or the magnet, Torrentio `sources` trackers, `fileIdx`,
        // behaviorHints filename, declared size) — identical to the in-player
        // source resolver, pinned by torrent_stream_hints_test.dart.
        final torrentHints = TorrentStreamHints.fromStream(
          chosenStream,
          magnetUri: magnetUrl,
          fallbackName: item.name,
        );
        final resolved = await _resolveTorrentStream(
          displayName: item.name,
          infoHash: torrentHints.infoHash,
          filename: torrentHints.filename,
          filesize: torrentHints.filesize,
          magnet: magnetUrl,
          trackers: torrentHints.trackers,
          fileIndex: torrentHints.fileIndex,
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
            headers: directHeaders,
            filename: filename,
            torrent: prepared,
            streamName:
                (chosenStream['title'] ?? chosenStream['addonName'] ?? 'NOVA')
                    .toString(),
            videoId: id,
            season: (episode?['season'] as num?)?.toInt(),
            episode: (episode?['episode'] as num?)?.toInt(),
            initialPositionMs: resumePositionMs ??
                (widget.resumeVideoId == episode?['id']
                    ? widget.resumePositionMs
                    : null),
            // Task 139: hand the player the picked stream row — the
            // skip-intro/outro + Up-Next resolver reads the CURRENT
            // stream's metadata (behaviorHints etc.), and before this the
            // player never saw any stream row at all.
            streams: [chosenStream],
            streamIndex: 0,
          ),
          fullscreenDialog: true,
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _loadingStreams = false);
      if (mounted) {
        // Task 128: friendly, actionable message instead of the raw
        // `TorrentException(metadata_timeout): …` toast.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              torrentFriendlyMessage(
                error,
                english: context.read<AppState>().english,
              ),
            ),
          ),
        );
      }
    }
  }

  /// Resolves an infoHash stream through the connected Debrid service first
  /// and the on-device torrent engine second (Task 118). The player opens as
  /// soon as the local endpoint is bound and buffers missing pieces while the
  /// torrent downloads; it does not wait for an arbitrary file percentage.
  /// Returns `null` after showing a bilingual explanation when no resolution
  /// path exists (or the user cancels).
  Future<({String url, PreparedTorrent? torrent})?> _resolveTorrentStream({
    required String displayName,
    required String infoHash,
    required String? filename,
    required int? filesize,
    String? magnet,
    List<String> trackers = const <String>[],
    int? fileIndex,
  }) async {
    final app = context.read<AppState>();
    final api = app.api;
    final english = app.english;
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
    var dialogOpen = true;
    // null = indeterminate phase (debrid round-trip / metadata fetch);
    // non-null = live engine status with a real percentage.
    final status = ValueNotifier<TorrentStatus?>(null);
    Future<void> closeDialog() async {
      if (dialogOpen) {
        dialogOpen = false;
        navigator.pop();
      }
    }

    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StreamPrepareDialog(
        english: english,
        status: status,
        onCancel: () {
          cancelled = true;
          unawaited(closeDialog());
        },
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
        magnet: magnet,
        filename: filename,
        filesize: filesize,
        displayName: displayName,
        trackers: trackers,
        fileIndex: fileIndex,
      );
      if (cancelled) {
        // The user backed out while the engine was preparing the stream.
        unawaited(prepared.stop());
        unawaited(TorrentService.instance.remove(prepared.infoHash));
        return null;
      }
      // prepare() has already bound the loopback HTTP server. Transfer control
      // to mpv now; waiting for torrent.ready here can strand the user on this
      // dialog when the swarm downloads out of order. The HTTP server waits
      // for each requested piece and mpv owns buffering from this point on.
      if (cancelled) {
        unawaited(prepared.stop());
        unawaited(TorrentService.instance.remove(prepared.infoHash));
        return null;
      }
      return (url: prepared.url, torrent: prepared);
    } finally {
      await closeDialog();
      status.dispose();
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
              ? (NovaStrings.lookup(english, 'message182'))
              : (NovaStrings.lookup(english, 'message183')),
        ),
      ),
    );
  }
}

/// The primary CTA's resolved target: which video to play, the resume
/// position, and whether the label reads "Resume" (with S:E for series).
class _ResumePlan {
  const _ResumePlan({
    this.video,
    this.positionMs,
    this.isResume = false,
    this.season = 1,
    this.episode = 1,
  });

  final Map<String, dynamic>? video;
  final int? positionMs;
  final bool isResume;
  final int season;
  final int episode;
}

/// Centered danger card with retry — shown when the detail fetch fails or
/// comes back empty (web `titleNotFound` state). The back pill stays.
class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.english,
    required this.message,
    required this.onRetry,
  });

  final bool english;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        20,
        MediaQuery.paddingOf(context).top + 88,
        20,
        24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 576),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.error.withValues(alpha: .40)),
              color: scheme.error.withValues(alpha: .10),
            ),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: scheme.error, height: 1.5),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            label: Text(NovaStrings.lookup(english, 'message120')),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------------
// Provider ratings (engine unchanged — chips restyled to the web recipe)
// -------------------------------------------------------------------------

class _ProviderRatings extends StatefulWidget {
  const _ProviderRatings({required this.item, required this.startAligned});

  final MediaItem item;

  /// Wide layouts align the chips to the column start; phones center them.
  final bool startAligned;

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
        ? item.releaseInfo!.substring(0, item.releaseInfo!.length.clamp(0, 4))
        : null;
    final imdb = RegExp(r'^tt\d+$').hasMatch(item.id) ? item.id : null;
    final anime =
        item.genres.any((genre) => genre.toLowerCase() == 'animation') &&
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
            padding: const EdgeInsetsDirectional.fromSTEB(0, 2, 0, 0),
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 76,
                    height: 26,
                    decoration: BoxDecoration(
                        color: NovaColors.ink.withValues(alpha: .30),
                        borderRadius: BorderRadius.circular(999)),
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
        return Align(
          alignment: widget.startAligned
              ? AlignmentDirectional.centerStart
              : AlignmentDirectional.topCenter,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 0),
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
      _ => provider.isEmpty
          ? (NovaStrings.lookup(english, 'message184'))
          : provider,
    };
    final display = (rating['display'] ?? '').toString();
    final scale = (rating['originalScale'] ?? '/10').toString();
    final votes = rating['votes'] is num ? (rating['votes'] as num).toInt() : 0;
    final url = Uri.tryParse((rating['url'] ?? '').toString());
    final color = Theme.of(context).colorScheme.secondary;
    return Semantics(
      button: url?.hasScheme == true,
      label: '$label $display $scale',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: url?.hasScheme == true
            ? () async {
                if (context.read<AppState>().kidsSession &&
                    (!await NovaParentalGate.verify(context) ||
                        !context.mounted)) {
                  return;
                }
                await launchUrl(url!);
              }
            : null,
        child: Container(
          // Task 136 (perf): the blur-6 backdrop is retired — a row of these
          // rating chips sat over the scrolling artwork and each re-blurred
          // its backdrop every frame; the .55 fill keeps the same contrast.
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            border:
                Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(999)),
                child: Text(label,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSecondary,
                        fontSize: 9,
                        fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 6),
              Text(display,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600)),
              if (scale != '/10')
                Text(scale == '%' ? '' : scale,
                    style: TextStyle(
                        fontSize: 10, color: NovaTheme.of(context).muted)),
              if (votes > 0) ...[
                const SizedBox(width: 4),
                Text(_compactVotes(votes),
                    style: TextStyle(
                        fontSize: 10, color: NovaTheme.of(context).muted)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SimilarTitles extends StatefulWidget {
  const _SimilarTitles({required this.item, this.kidsMode = false});
  final MediaItem item;
  final bool kidsMode;

  @override
  State<_SimilarTitles> createState() => _SimilarTitlesState();
}

class _SimilarTitlesState extends State<_SimilarTitles> {
  Future<List<MediaItem>>? _similar;
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
      // Task 122-d: recommendations follow the content-language TMDB locale
      // (was the legacy UI-less fallback, always 'en-US').
      app.contentTmdbLocale,
      app.webSettings['region'],
    ].join('|');
    if (signature != _requestSignature) {
      _requestSignature = signature;
      final language = app.contentTmdbLocale;
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
            .where((item) =>
                !widget.kidsMode ||
                const {
                  'g',
                  'pg',
                  'tv-y',
                  'tv-y7',
                  'tv-g',
                  'tv-pg',
                  'u',
                  '0',
                  '6',
                  '7'
                }.contains(item.certification?.trim().toLowerCase()))
            .take(14)
            .toList();
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return RailLoadingSkeleton(
              title: NovaStrings.lookup(app.english, 'message185'));
        }
        if (items.isEmpty) {
          return Padding(
              padding: const EdgeInsets.all(24),
              child: Text(NovaStrings.lookup(app.english, 'message186'),
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)));
        }
        return Padding(
          padding: const EdgeInsetsDirectional.only(top: 32, bottom: 22),
          child: MediaRail(
            title: NovaStrings.lookup(app.english, 'message185'),
            items: items,
            onTap: (item) => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) =>
                      MediaDetailPage(item: item, kidsMode: widget.kidsMode)),
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
