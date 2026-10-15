import 'dart:async';
import 'dart:ui' show ImageFilter;

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
import '../anime/anime_tracker_sheet.dart';
import '../library/custom_list_picker.dart';
import '../player/video_player_page.dart';
import '../shell/noor_dock_tabs.dart' show glassDockContentClearance;
import 'detail_hero.dart';
import 'episode_data.dart';
import 'episode_views.dart';
import 'sources_page.dart';

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
  });
  final MediaItem item;

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
  bool _loadingStreams = false;

  /// Episodes subsystem state (season/sort/view) — Task 118. Created lazily
  /// on the first populated build; the page listens so season/sort/view
  /// toggles rebuild ONLY the episodes slivers, never the hero or shell.
  EpisodesController? _episodes;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _detail = app.catalogs.detail(widget.item.type, widget.item.id, app.addons);
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

  void _reloadDetail() {
    final app = context.read<AppState>();
    setState(() {
      _detail =
          app.catalogs.detail(widget.item.type, widget.item.id, app.addons);
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
              else if (failed)
                Positioned.fill(
                  child: _ErrorView(
                    english: english,
                    message: snapshot.error?.toString() ??
                        (english
                            ? 'Title not found. It may not be in Cinemeta or your addons.'
                            : 'لم يتم العثور على العنوان. قد لا يكون موجوداً في Cinemeta أو في إضافاتك.'),
                    onRetry: _reloadDetail,
                  ),
                )
              else
                Positioned.fill(
                  child: _buildContent(
                    context,
                    app,
                    item: snapshot.data ?? widget.item,
                    english: english,
                    isWide: isWide,
                    viewportSize: media.size,
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

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _buildHeroAndColumn(
            context,
            app,
            item: item,
            english: english,
            isWide: isWide,
            viewportSize: viewportSize,
            backdrop: backdrop,
            logo: logo,
            resume: resume,
            defaultVideo: defaultVideo,
          ),
        ),
        ...episodeSlivers,
        SliverToBoxAdapter(child: _SimilarTitles(item: item)),
        if (item.type == 'movie' &&
            item.genres.isEmpty &&
            (item.description == null || item.description!.isEmpty))
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  isWide ? 34 : 20, 32, isWide ? 34 : 20, 0),
              child: Align(
                alignment: isWide
                    ? AlignmentDirectional.centerStart
                    : AlignmentDirectional.topCenter,
                child: Text(
                  english
                      ? 'Press Watch Now to fetch playback sources…'
                      : 'اضغط مشاهدة لجلب مصادر التشغيل…',
                  style: const TextStyle(fontSize: 12, color: HorseTheme.muted),
                ),
              ),
            ),
          ),
        // Dock clearance (was a flat SizedBox(height: 108) — bug fix).
        SliverToBoxAdapter(
          child: SizedBox(height: glassDockContentClearance(context)),
        ),
      ],
    );
  }

  /// Hero + overlapping content column. The column is laid out in normal
  /// flow with a top offset of `heroHeight − overlap`; the hero paints
  /// behind it as a positioned child of the same Stack.
  Widget _buildHeroAndColumn(
    BuildContext context,
    AppState app, {
    required MediaItem item,
    required bool english,
    required bool isWide,
    required Size viewportSize,
    required String? backdrop,
    required String? logo,
    required _ResumePlan resume,
    required Map<String, dynamic>? defaultVideo,
  }) {
    final vh = viewportSize.height;
    final vw = viewportSize.width;
    final heroHeight =
        isWide ? (vh * 0.52).clamp(360.0, 680.0) : (vw - 32) * 11 / 16 + 72;
    final overlap = isWide ? (vh * 0.14).clamp(96.0, 168.0) : 0.0;

    Widget column = Column(
      crossAxisAlignment:
          isWide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        if (isWide) ...[
          DetailColumnTitle(
            logoUrl: logo,
            title: item.name,
            isWide: true,
            viewportWidth: vw,
          ),
          const SizedBox(height: 8),
        ] else
          const SizedBox(height: 16),
        DetailMetaRow(item: item, isWide: isWide),
        const SizedBox(height: 8),
        _ProviderRatings(item: item, startAligned: isWide),
        if (item.description != null && item.description!.isNotEmpty) ...[
          const SizedBox(height: 16),
          DetailSynopsis(
            description: item.description!,
            isWide: isWide,
            viewportWidth: vw,
          ),
        ],
        const SizedBox(height: 24),
        DetailActionRow(
          english: english,
          isWide: isWide,
          inList: app.contains(item),
          showTrackAnime: item.hasAnimeIds &&
              (app.linkedServices['anilist']?['linked'] == true ||
                  app.linkedServices['mal']?['linked'] == true),
          primaryLabel: resume.isResume
              ? (item.type == 'series'
                  ? (english
                      ? 'Resume S${resume.season}:E${resume.episode}'
                      : 'متابعة S${resume.season}:E${resume.episode}')
                  : (english ? 'Resume' : 'متابعة'))
              : (english ? 'Watch Now' : 'مشاهدة'),
          primaryIsResume: resume.isResume,
          loading: _loadingStreams,
          onPrimaryPressed: () => _play(
            item,
            video: resume.video ?? defaultVideo,
            resumePositionMs: resume.positionMs,
          ),
          onToggleWatchlist: () => unawaited(app.toggleWatchlist(item)),
          onOpenStreams: () => _play(
            item,
            video: resume.video ?? defaultVideo,
            forceSourceSheet: true,
          ),
          onTrackAnime: () => unawaited(showAnimeTrackerSheet(context, item)),
          onShare: () => unawaited(_share(item, english)),
          onAddToList: () => unawaited(showCustomListPicker(context, item)),
        ),
        if (item.director.isNotEmpty || item.cast.isNotEmpty) ...[
          const SizedBox(height: 32),
          DetailCastCrew(item: item, english: english, centered: !isWide),
        ],
      ],
    );
    column = SizedBox(width: double.infinity, child: column);
    if (isWide) {
      column = vw >= 840
          ? ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: column,
            )
          : FractionallySizedBox(
              widthFactor: 0.7,
              alignment: AlignmentDirectional.centerStart,
              child: column,
            );
    }
    column = Padding(
      padding: EdgeInsets.symmetric(horizontal: isWide ? 34 : 20),
      child: column,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: heroHeight,
          child: DetailHero(
            item: item,
            backdropUrl: backdrop,
            logoUrl: logo,
            isWide: isWide,
            viewportHeight: vh,
            viewportWidth: vw,
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: heroHeight - overlap),
          child: column,
        ),
      ],
    );
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
    try {
      await SharePlus.instance.share(ShareParams(text: item.name));
    } catch (_) {
      // No share sheet on this platform — fall back to the clipboard.
      try {
        await Clipboard.setData(ClipboardData(text: item.name));
        if (mounted) {
          NoorToast.show(
            context,
            english ? 'Link copied to clipboard' : 'تم نسخ الرابط',
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
    bool forceSourceSheet = false,
    int? resumePositionMs,
  }) async {
    final app = context.read<AppState>();
    final english = app.english;
    final episode = video;
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
    Map<String, dynamic>? selected;
    // "Available streams" in the menu always forces the source sheet —
    // instant-play never auto-picks from that entry (web contract).
    if (!forceSourceSheet && app.webSettings['instantPlay'] == true) {
      selected = streams.where(_isPlayableStream).firstOrNull;
    }
    if (selected != null) {
      await _launchStream(
        item: item,
        episode: episode,
        stream: selected,
        resumePositionMs: resumePositionMs,
      );
      return;
    }
    // Full-screen sources page (Task 118 user mandate): tapping an episode —
    // or "Available streams" — surfaces EVERY source from EVERY enabled
    // add-on on a browsable page with a filter field, instead of the cramped
    // bottom sheet. Picking one hands the stream back for resolution.
    final picked = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => SourcesPage(
          item: item,
          video: episode,
          streams: streams,
          english: english,
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
    try {
      final rawUrl = chosenStream['url'] as String?;
      final hints =
          (chosenStream['behaviorHints'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
      final proxyHeaders = (hints['proxyHeaders'] as Map?)
          ?.map((key, value) => MapEntry(key.toString(), value.toString()));
      final filename = (hints['filename'] ?? chosenStream['title'])?.toString();
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
            streamName:
                (chosenStream['title'] ?? chosenStream['addonName'] ?? 'Noor')
                    .toString(),
            videoId: id,
            season: (episode?['season'] as num?)?.toInt(),
            episode: (episode?['episode'] as num?)?.toInt(),
            nextEpisode: _nextEpisode(item.videos, episode),
            initialPositionMs: resumePositionMs ??
                (widget.resumeVideoId == episode?['id']
                    ? widget.resumePositionMs
                    : null),
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
  /// and the on-device torrent engine second (Task 118): the modal shows the
  /// LIVE download percentage streamed from the engine (1%, 2%, …) instead
  /// of a bare spinner, and the player opens as soon as the head pieces are
  /// down (20s fallback — the local stream server serves mid-download).
  /// Returns `null` after showing a bilingual explanation when no resolution
  /// path exists (or the user cancels).
  Future<({String url, PreparedTorrent? torrent})?> _resolveTorrentStream({
    required String displayName,
    required String infoHash,
    required String? filename,
    required int? filesize,
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
    StreamSubscription<TorrentStatus>? sub;
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
      // Live progress phase (Task 118): pump engine events into the dialog
      // and hand off to the player the moment the head pieces land.
      final ready = Completer<void>();
      sub = prepared.statusStream.listen(
        (event) {
          status.value = event;
          if (event.ready && !ready.isCompleted) ready.complete();
        },
        onDone: () {
          if (!ready.isCompleted) ready.complete();
        },
      );
      try {
        await ready.future.timeout(const Duration(seconds: 20));
      } on TimeoutException {
        // Proceed anyway — the StreamServer stall-wait serves the remainder
        // while the player buffers.
      }
      await sub.cancel();
      sub = null;
      if (cancelled) {
        unawaited(prepared.stop());
        unawaited(TorrentService.instance.remove(prepared.infoHash));
        return null;
      }
      return (url: prepared.url, torrent: prepared);
    } finally {
      await sub?.cancel();
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

  /// Next episode in canonical (season, episode) order — the sorted list
  /// fixes the old bug where addon order leaked into Up-Next.
  Map<String, dynamic>? _nextEpisode(
    List<Map<String, dynamic>> videos,
    Map<String, dynamic>? current,
  ) {
    final sorted = sortEpisodes(videos);
    final index = sorted.indexWhere((video) => video['id'] == current?['id']);
    return index >= 0 && index + 1 < sorted.length ? sorted[index + 1] : null;
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
      padding: EdgeInsets.fromLTRB(
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
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(english ? 'Retry' : 'إعادة المحاولة'),
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
                        color: Colors.black.withValues(alpha: .30),
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
        borderRadius: BorderRadius.circular(999),
        onTap: url?.hasScheme == true ? () => unawaited(launchUrl(url!)) : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .30),
                border: Border.all(color: Colors.white.withValues(alpha: .08)),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                        color: color, borderRadius: BorderRadius.circular(999)),
                    child: Text(label,
                        style: TextStyle(
                            color: provider == 'imdb'
                                ? Colors.black
                                : Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(width: 6),
                  Text(display,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600)),
                  if (scale != '/10')
                    Text(scale == '%' ? '' : scale,
                        style: const TextStyle(
                            fontSize: 10, color: HorseTheme.muted)),
                  if (votes > 0) ...[
                    const SizedBox(width: 4),
                    Text(_compactVotes(votes),
                        style: const TextStyle(
                            fontSize: 10, color: HorseTheme.muted)),
                  ],
                ],
              ),
            ),
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
      // Task 122-d: recommendations follow the content-language TMDB locale
      // (was the legacy UI-less fallback, always 'en-US').
      app.contentTmdbLocale,
      app.webSettings['region'],
    ].join('|');
    if (signature != _requestSignature) {
      _requestSignature = signature;
      _genre = genre;
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
            .take(14)
            .toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsetsDirectional.only(top: 32, bottom: 22),
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
