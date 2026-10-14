/// Full-screen source picker (user mandate, Task 118): tapping an episode —
/// or the "Available streams" action — opens a PAGE listing every stream
/// from every enabled add-on (already fetched in parallel, deduped and
/// ranked by the detail page), with a filter field to flip through them.
/// Picking a source hands it back to the detail page, which resolves it and
/// drives the live prepare-progress sheet below before entering the player.
library;

import 'package:flutter/material.dart';

import '../../core/models/media_item.dart';
import '../../core/theme/horse_theme.dart';
import '../../core/torrent/torrent_models.dart';
import '../../shared/widgets/glass_navigation.dart';

/// The full-screen sources page. Pushed over the detail page; completes with
/// the chosen stream map (`Navigator.pop(context, stream)`).
class SourcesPage extends StatefulWidget {
  const SourcesPage({
    super.key,
    required this.item,
    required this.video,
    required this.streams,
    required this.english,
  });

  final MediaItem item;

  /// The tapped episode (null for movies) — shown as the page subtitle.
  final Map<String, dynamic>? video;

  /// All playable-considered streams for this video, already ranked.
  final List<Map<String, dynamic>> streams;
  final bool english;

  @override
  State<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends State<SourcesPage> {
  String _query = '';

  bool _isDirect(Map<String, dynamic> stream) {
    final url = stream['url'];
    return url is String && url.startsWith('http');
  }

  bool _isTorrent(Map<String, dynamic> stream) =>
      !_isDirect(stream) && stream['infoHash'] is String;

  @override
  Widget build(BuildContext context) {
    final english = widget.english;
    final video = widget.video;
    final season = (video?['season'] as num?)?.toInt();
    final episode = (video?['episode'] as num?)?.toInt();
    final episodeName = (video?['name'] ?? video?['title'])?.toString();
    final subtitle = video == null
        ? (english ? 'Movie' : 'فيلم')
        : [
            'S$season:E$episode',
            if (episodeName != null && episodeName.isNotEmpty) episodeName,
          ].join(' · ');

    final query = _query.trim().toLowerCase();
    final streams = query.isEmpty
        ? widget.streams
        : widget.streams
            .where((stream) => '${stream['title'] ?? ''} '
                    '${stream['name'] ?? ''} '
                    '${stream['addonName'] ?? ''}'
                .toLowerCase()
                .contains(query))
            .toList(growable: false);

    final addons = <String>{
      for (final stream in widget.streams)
        if (stream['addonName'] is String) stream['addonName'] as String,
    };

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 20, 0),
              child: Row(
                children: [
                  // Same liquid-glass family as the search + detail back
                  // buttons (Task 118 chrome consistency).
                  GlassSearchButton(
                    size: 40,
                    tooltip: english ? 'Back' : 'رجوع',
                    icon: english
                        ? Icons.arrow_back_rounded
                        : Icons.arrow_forward_rounded,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          english ? 'Sources' : 'المصادر',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: HorseTheme.ink,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: HorseTheme.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 4),
              child: Text(
                english
                    ? '${widget.streams.length} sources from ${addons.length} '
                        '${addons.length == 1 ? 'add-on' : 'add-ons'}'
                    : '${widget.streams.length} مصدر من ${addons.length} '
                        '${addons.length == 1 ? 'إضافة' : 'إضافات'}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: HorseTheme.muted,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 4),
              child: TextField(
                onChanged: (value) => setState(() => _query = value),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  hintText: english ? 'Filter sources…' : 'تصفية المصادر…',
                  filled: true,
                  fillColor: HorseTheme.raised.withValues(alpha: .7),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
            Expanded(
              child: streams.isEmpty
                  ? Center(
                      child: Text(
                        english ? 'No matching sources' : 'لا مصادر مطابقة',
                        style: const TextStyle(
                          fontSize: 14,
                          color: HorseTheme.muted,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      itemCount: streams.length,
                      itemBuilder: (context, index) => _SourceRow(
                        stream: streams[index],
                        index: index,
                        english: english,
                        condensed:
                            widget.streams.length > 12, // web pickerLayout
                        onTap: _isDirect(streams[index]) ||
                                _isTorrent(streams[index])
                            ? () => Navigator.of(context).pop(streams[index])
                            : null,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One source row — ranked position badge, quality title, add-on origin,
/// torrent/direct glyph. Disabled rows (neither URL nor infoHash) dim.
class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.stream,
    required this.index,
    required this.english,
    required this.condensed,
    required this.onTap,
  });

  final Map<String, dynamic> stream;
  final int index;
  final bool english;
  final bool condensed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final url = stream['url'];
    final direct = url is String && url.startsWith('http');
    final torrent = !direct && stream['infoHash'] is String;
    final playable = direct || torrent;
    final title = (stream['title'] ??
            stream['name'] ??
            stream['description'] ??
            (playable ? 'HTTP stream' : 'Torrent stream'))
        .toString()
        .split('\n')
        .first;
    final addon =
        (stream['addonName'] ?? (english ? 'Add-on' : 'إضافة')).toString();
    final kind = torrent
        ? (english ? 'Torrent source' : 'مصدر تورنت')
        : playable
            ? (english ? 'Direct stream' : 'بث مباشر')
            : (english ? 'Unsupported source' : 'مصدر غير مدعوم');

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: Material(
        color: HorseTheme.raised.withValues(alpha: onTap == null ? .30 : .70),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: condensed ? 8 : 12,
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: onTap == null
                        ? Colors.white.withValues(alpha: .04)
                        : HorseTheme.gold.withValues(alpha: .16),
                    border: Border.all(
                      color: onTap == null
                          ? HorseTheme.line
                          : HorseTheme.gold.withValues(alpha: .35),
                    ),
                  ),
                  child: onTap == null
                      ? Icon(
                          Icons.cloud_off_rounded,
                          size: 16,
                          color: HorseTheme.muted,
                        )
                      : Icon(
                          torrent
                              ? Icons.bolt_rounded
                              : Icons.play_arrow_rounded,
                          size: 18,
                          color: HorseTheme.gold,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: condensed ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: condensed ? 13 : 14,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                          color:
                              onTap == null ? HorseTheme.muted : HorseTheme.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$addon · $kind',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: HorseTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: HorseTheme.muted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Live stream-preparation sheet (Task 118): while a torrent source is being
/// prepared, this modal shows the REAL download percentage (1%, 2%, …),
/// speed, peers/seeds and engine state streamed from the torrent engine —
/// replacing the old indeterminate spinner. The detail page drives
/// [status] and closes the dialog when the stream is ready (or after its
/// fallback timeout, since the local stream server can serve mid-download).
class StreamPrepareDialog extends StatelessWidget {
  const StreamPrepareDialog({
    super.key,
    required this.english,
    required this.status,
    required this.onCancel,
  });

  final bool english;

  /// null = indeterminate phase (debrid API round-trip / engine metadata
  /// fetch); non-null = live engine status with a real percentage.
  final ValueNotifier<TorrentStatus?> status;
  final VoidCallback onCancel;

  static String _stateLabel(TorrentStatus? status, bool english) {
    final state = status?.state;
    return switch (state) {
      'downloading' => english ? 'Downloading…' : 'جارٍ التحميل…',
      'checking' => english ? 'Checking…' : 'جارٍ الفحص…',
      'finished' || 'seeding' => english ? 'Ready' : 'جاهز',
      'paused' => english ? 'Paused' : 'متوقف مؤقتاً',
      _ => english ? 'Preparing the stream…' : 'جارٍ تجهيز المصدر…',
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: HorseTheme.surface,
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      content: SizedBox(
        width: 320,
        child: ValueListenableBuilder<TorrentStatus?>(
          valueListenable: status,
          builder: (context, snapshot, _) {
            final progress = snapshot?.progress ?? 0.0;
            final hasPercent = snapshot != null;
            final rateMbps =
                snapshot == null ? 0.0 : snapshot.downloadRate / (1024 * 1024);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _stateLabel(snapshot, english),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: hasPercent ? progress.clamp(0.0, 1.0) : null,
                    minHeight: 6,
                    backgroundColor: HorseTheme.raised,
                    valueColor: const AlwaysStoppedAnimation(HorseTheme.gold),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (hasPercent) ...[
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          '${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: HorseTheme.gold,
                            fontFeatures: [],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Text(
                        english
                            ? 'A portion is buffered before playback starts.'
                            : 'يُجهَّز جزء من الحلقة قبل بدء التشغيل.',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: HorseTheme.muted,
                        ),
                      ),
                    ),
                  ],
                ),
                if (hasPercent) ...[
                  const SizedBox(height: 8),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      '↓ ${rateMbps.toStringAsFixed(2)} MB/s'
                      ' · P:${snapshot.numPeers} S:${snapshot.numSeeds}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: HorseTheme.muted,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: Text(english ? 'Cancel' : 'إلغاء',
              style: TextStyle(color: scheme.onSurface.withValues(alpha: .8))),
        ),
      ],
    );
  }
}
