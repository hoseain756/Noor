/// Full-screen source picker (user mandate, Task 118; Task 123 upgrade):
/// tapping an episode — or the "Available streams" action — opens a PAGE
/// listing every stream from every enabled add-on (already fetched in
/// parallel, deduped and ranked by the detail page), with a text filter AND
/// a glass filter bar (quality buckets, torrent-vs-direct, per-add-on picker
/// and sort by seeds/size/quality). Each row leads with the add-on's own
/// icon in a rounded square (start-aligned, so it flips right/left with the
/// UI language), the stream title beside it and a facts line below it
/// (quality · seeds · size · codec). Picking a source hands it back to the
/// detail page, which resolves it and drives the live prepare-progress
/// sheet below before entering the player.
library;

import 'package:flutter/material.dart';

import '../../core/models/media_item.dart';
import '../../core/theme/horse_theme.dart';
import '../../core/torrent/torrent_models.dart';
import '../../shared/widgets/app_state_message.dart';
import '../../shared/widgets/glass_navigation.dart';
import '../../shared/widgets/image_decode.dart';
import 'detail_glass.dart';

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

  /// Selected quality bucket (exact parsed height): null = any.
  int? _minHeight;

  /// Selected source kind: null = any, 'torrent' or 'direct'.
  String? _kind;

  /// Selected add-on (exact [stream['addonName']]): null = all.
  String? _addon;

  /// Sort mode: 0 = detail-page rank (as delivered), 1 = seeds, 2 = size,
  /// 3 = quality (then seeds).
  int _sort = 0;

  /// Parsed facts per stream — [widget.streams] never mutates during the
  /// page's lifetime (it is delivered once by the detail page), so parse
  /// lazily once and reuse for every filter/sort pass.
  late final List<_SourceFacts> _facts = [
    for (final stream in widget.streams) _SourceFacts.parse(stream),
  ];

  /// First-appearance-ordered add-on stats: name → (count, iconUrl).
  late final Map<String, (int, String?)> _addonStats = () {
    final stats = <String, (int, String?)>{};
    for (final stream in widget.streams) {
      final name = stream['addonName']?.toString() ?? '';
      if (name.isEmpty) continue;
      final current = stats[name] ?? (0, null);
      stats[name] = (
        current.$1 + 1,
        current.$2 ?? stream['addonIcon']?.toString(),
      );
    }
    return stats;
  }();

  bool _isDirect(Map<String, dynamic> stream) {
    final url = stream['url'];
    return url is String && url.startsWith('http');
  }

  bool _isTorrent(Map<String, dynamic> stream) =>
      !_isDirect(stream) && stream['infoHash'] is String;

  /// Indices into [widget.streams] that survive the text query + chips,
  /// ordered by the active sort (rank order = original index order kept).
  List<int> _visibleIndices(String query) {
    var indices = List<int>.generate(widget.streams.length, (i) => i);
    if (query.isNotEmpty) {
      bool matches(int i) {
        final s = widget.streams[i];
        return '${s['title'] ?? ''} '
                '${s['name'] ?? ''} '
                '${s['description'] ?? ''} '
                '${s['addonName'] ?? ''}'
            .toLowerCase()
            .contains(query);
      }

      indices = indices.where(matches).toList(growable: false);
    }
    if (_minHeight != null) {
      indices = indices
          .where((i) => _facts[i].height == _minHeight)
          .toList(growable: false);
    }
    if (_kind != null) {
      indices = indices
          .where((i) =>
              _kind == 'torrent' ? _facts[i].isTorrent : _facts[i].isDirect)
          .toList(growable: false);
    }
    if (_addon != null) {
      indices = indices
          .where((i) =>
              (widget.streams[i]['addonName']?.toString() ?? '') == _addon)
          .toList(growable: false);
    }
    int desc(int? a, int? b) => (b ?? -1).compareTo(a ?? -1);
    switch (_sort) {
      case 1:
        indices.sort((a, b) => desc(_facts[a].seeds, _facts[b].seeds));
      case 2:
        indices.sort((a, b) => desc(_facts[a].sizeBytes, _facts[b].sizeBytes));
      case 3:
        indices.sort((a, b) {
          final byHeight = desc(_facts[a].height, _facts[b].height);
          if (byHeight != 0) return byHeight;
          return desc(_facts[a].seeds, _facts[b].seeds);
        });
    }
    return indices;
  }

  String _sortLabel(int index, bool english) => switch (index) {
        1 => english ? 'Seeds' : 'البذور',
        2 => english ? 'Size' : 'الحجم',
        3 => english ? 'Quality' : 'الجودة',
        _ => english ? 'Best' : 'الأفضل',
      };

  Future<void> _openSortMenu() async {
    final box = _sortKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    final picked = await showGlassMenu<int>(
      context: context,
      anchor: anchor,
      width: 216,
      builder: (close) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < 4; i++)
            InkWell(
              onTap: () => close(i),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: i == _sort
                          ? const Icon(Icons.check_rounded,
                              size: 16, color: HorseTheme.gold)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _sortLabel(i, widget.english),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: HorseTheme.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _sort = picked);
  }

  Future<void> _openAddonMenu() async {
    if (_addonStats.isEmpty) return;
    final box = _addonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    final english = widget.english;
    final names = _addonStats.keys.toList(growable: false);
    final picked = await showGlassMenu<int>(
      context: context,
      anchor: anchor,
      width: 280,
      maxHeight: 420,
      builder: (close) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i <= names.length; i++)
            InkWell(
              onTap: () => close(i),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: i == 0
                          ? null
                          : _AddonIcon(
                              icon: _addonStats[names[i - 1]]!.$2,
                              name: names[i - 1],
                              radius: 6,
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        i == 0
                            ? (english ? 'All add-ons' : 'كل الإضافات')
                            : names[i - 1],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: (_addon == null && i == 0) ||
                                  (_addon != null &&
                                      i > 0 &&
                                      names[i - 1] == _addon)
                              ? HorseTheme.gold
                              : HorseTheme.ink,
                        ),
                      ),
                    ),
                    if (i > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${_addonStats[names[i - 1]]!.$1}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: HorseTheme.muted,
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: (i == 0 && _addon == null) ||
                              (i > 0 && names[i - 1] == _addon)
                          ? const Icon(Icons.check_rounded,
                              size: 16, color: HorseTheme.gold)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _addon = picked == 0 ? null : names[picked - 1]);
  }

  final GlobalKey _sortKey = GlobalKey();
  final GlobalKey _addonKey = GlobalKey();

  /// One compact glass chip in the filter bar. [key] anchors the glass
  /// dropdown menus opened from the sort/add-on chips.
  Widget _chip({
    Key? key,
    required String label,
    required bool selected,
    IconData? icon,
    VoidCallback? onTap,
  }) {
    return GlassPillSurface(
      key: key,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 38,
            padding: const EdgeInsetsDirectional.fromSTEB(13, 0, 15, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: 15,
                      color: selected ? HorseTheme.gold : HorseTheme.muted),
                  const SizedBox(width: 7),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? HorseTheme.gold : HorseTheme.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterBar(bool english) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.fromSTEB(20, 1, 20, 1),
        children: [
          _chip(
            key: _sortKey,
            label: _sortLabel(_sort, english),
            icon: Icons.swap_vert_rounded,
            selected: _sort != 0,
            onTap: _openSortMenu,
          ),
          const SizedBox(width: 8),
          _chip(
            key: _addonKey,
            label: _addon ??
                (english
                    ? 'Add-ons · ${_addonStats.length}'
                    : 'الإضافات · ${_addonStats.length}'),
            icon: Icons.extension_rounded,
            selected: _addon != null,
            onTap: _openAddonMenu,
          ),
          const SizedBox(width: 8),
          for (final bucket in const <(int?, String)>[
            (null, 'any'),
            (2160, '4K'),
            (1080, '1080p'),
            (720, '720p'),
            (480, '480p'),
          ]) ...[
            _chip(
              label: bucket.$2 == 'any'
                  ? (english ? 'Any quality' : 'كل الجودات')
                  : bucket.$2,
              selected: _minHeight == bucket.$1,
              onTap: () => setState(() => _minHeight = bucket.$1),
            ),
            const SizedBox(width: 8),
          ],
          _chip(
            label: english ? 'Torrents' : 'تورنت',
            icon: Icons.bolt_rounded,
            selected: _kind == 'torrent',
            onTap: () =>
                setState(() => _kind = _kind == 'torrent' ? null : 'torrent'),
          ),
          const SizedBox(width: 8),
          _chip(
            label: english ? 'Direct' : 'مباشر',
            icon: Icons.play_arrow_rounded,
            selected: _kind == 'direct',
            onTap: () =>
                setState(() => _kind = _kind == 'direct' ? null : 'direct'),
          ),
        ],
      ),
    );
  }

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
    final visible = _visibleIndices(query);
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
            if (widget.streams.isNotEmpty) ...[
              const SizedBox(height: 6),
              _filterBar(english),
            ],
            Expanded(
              child: visible.isEmpty
                  ? AppStateMessage(
                      icon: widget.streams.isEmpty
                          ? Icons.cloud_off_rounded
                          : Icons.filter_alt_off_rounded,
                      message: widget.streams.isEmpty
                          ? (english
                              ? 'No sources available for this title yet'
                              : 'لا توجد مصادر متاحة لهذا العمل بعد')
                          : (english
                              ? 'No matching sources'
                              : 'لا مصادر مطابقة'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final i = visible[index];
                        final stream = widget.streams[i];
                        return _SourceRow(
                          stream: stream,
                          facts: _facts[i],
                          english: english,
                          condensed:
                              widget.streams.length > 12, // web pickerLayout
                          onTap: _isDirect(stream) || _isTorrent(stream)
                              ? () => Navigator.of(context).pop(stream)
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Parsed facts extracted from a Stremio stream map's free-form
/// title/name/description text (Torrentio-style "👤 25 💾 4.37 GB ⚙️ HEVC"
/// and the compact "S:85" variants). Pure + additive: when nothing matches,
/// every field stays null and the row simply renders fewer facts.
class _SourceFacts {
  _SourceFacts({
    this.height = 0,
    this.qualityLabel,
    this.seeds,
    this.sizeBytes,
    this.codec,
    required this.isTorrent,
    required this.isDirect,
  });

  final int height;
  final String? qualityLabel;
  final int? seeds;

  /// Size in bytes when a "4.37 GB"-style token is present (binary
  /// multipliers — only used for relative sorting/labels).
  final int? sizeBytes;
  final String? codec;
  final bool isTorrent;
  final bool isDirect;

  static final RegExp _heightRe = RegExp(
    r'(2160|1080|720|480|360)p?',
    caseSensitive: false,
  );
  static final RegExp _fourKRe = RegExp(r'\b4k\b', caseSensitive: false);
  static final List<RegExp> _seedRes = [
    RegExp(r'👤\s*(\d+)'),
    RegExp(r'⬆\s*(\d+)'),
    RegExp(r'\bS:\s*(\d+)'),
    RegExp(r'(\d+)\s*seed', caseSensitive: false),
    RegExp(r'seeds?\s*[:\-]\s*(\d+)', caseSensitive: false),
  ];
  static final RegExp _sizeRe = RegExp(
    r'(\d+(?:[.,]\d+)?)\s*(TB|GB|MB|KB)\b',
    caseSensitive: false,
  );

  factory _SourceFacts.parse(Map<String, dynamic> stream) {
    final url = stream['url'];
    final isDirect = url is String && url.startsWith('http');
    final isTorrent = !isDirect && stream['infoHash'] is String;
    final text = '${stream['title'] ?? ''}\n'
        '${stream['name'] ?? ''}\n'
        '${stream['description'] ?? ''}';

    var height = 0;
    if (_fourKRe.hasMatch(text)) {
      height = 2160;
    } else {
      height = int.tryParse(_heightRe.firstMatch(text)?.group(1) ?? '') ?? 0;
    }
    final qualityLabel =
        height == 0 ? null : (height == 2160 ? '4K' : '${height}p');

    int? seeds;
    for (final re in _seedRes) {
      final match = re.firstMatch(text);
      if (match != null) {
        seeds = int.tryParse(match.group(1) ?? '');
        if (seeds != null) break;
      }
    }

    int? sizeBytes;
    final sizeMatch = _sizeRe.firstMatch(text);
    if (sizeMatch != null) {
      final value = double.tryParse(
        (sizeMatch.group(1) ?? '').replaceFirst(',', '.'),
      );
      if (value != null) {
        final unit = (sizeMatch.group(2) ?? '').toUpperCase();
        const multipliers = {
          'KB': 1024,
          'MB': 1024 * 1024,
          'GB': 1024 * 1024 * 1024,
          'TB': 1024 * 1024 * 1024 * 1024,
        };
        sizeBytes = (value * multipliers[unit]!).round();
      }
    }

    final lower = text.toLowerCase();
    final String? codec = lower.contains('av1')
        ? 'AV1'
        : lower.contains('x265') ||
                lower.contains('h265') ||
                lower.contains('hevc')
            ? 'HEVC'
            : lower.contains('x264') ||
                    lower.contains('h264') ||
                    lower.contains('avc')
                ? 'H.264'
                : null;

    return _SourceFacts(
      height: height,
      qualityLabel: qualityLabel,
      seeds: seeds,
      sizeBytes: sizeBytes,
      codec: codec,
      isTorrent: isTorrent,
      isDirect: isDirect,
    );
  }

  String get sizeLabel {
    final bytes = sizeBytes;
    if (bytes == null) return '';
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(bytes % (1024 * 1024 * 1024) == 0 ? 0 : 1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}

/// The add-on's own icon in a rounded square — start-aligned so it sits on
/// the right in RTL (Arabic) and on the left in LTR (English) automatically.
/// Falls back to the add-on's initial letter on a gold tile; a small
/// cloud-off badge marks rows no playback path supports.
class _AddonBadge extends StatelessWidget {
  const _AddonBadge({
    required this.icon,
    required this.name,
    required this.playable,
    required this.condensed,
  });

  final String? icon;
  final String name;
  final bool playable;
  final bool condensed;

  @override
  Widget build(BuildContext context) {
    final size = condensed ? 38.0 : 44.0;
    final initial = name.trim().isEmpty
        ? '?'
        : String.fromCharCode(name.trim().runes.first).toUpperCase();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: playable
                  ? HorseTheme.gold.withValues(alpha: .12)
                  : Colors.white.withValues(alpha: .04),
              border: Border.all(
                color: playable
                    ? HorseTheme.gold.withValues(alpha: .35)
                    : HorseTheme.line,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: icon != null
                  ? Image.network(
                      icon!,
                      fit: BoxFit.cover,
                      width: size,
                      height: size,
                      // Task 136: decode at the 38/44px badge size.
                      cacheWidth: imageCacheWidth(context, size),
                      errorBuilder: (_, __, ___) => _fallback(initial),
                    )
                  : _fallback(initial),
            ),
          ),
          if (!playable)
            Positioned.directional(
              textDirection: Directionality.of(context),
              end: -2,
              bottom: -2,
              child: Container(
                width: 15,
                height: 15,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: HorseTheme.surface,
                ),
                child: const Icon(
                  Icons.cloud_off_rounded,
                  size: 9,
                  color: HorseTheme.muted,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _fallback(String initial) => SizedBox.expand(
        child: ColoredBox(
          color: HorseTheme.gold.withValues(alpha: .10),
          child: Center(
            child: Text(
              initial,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: HorseTheme.gold,
              ),
            ),
          ),
        ),
      );
}

/// Tiny add-on icon for the picker menu (same image pipeline, no badge).
class _AddonIcon extends StatelessWidget {
  const _AddonIcon({
    required this.icon,
    required this.name,
    this.radius = 11,
  });

  final String? icon;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty
        ? '?'
        : String.fromCharCode(name.trim().runes.first).toUpperCase();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        color: HorseTheme.gold.withValues(alpha: .12),
        child: icon != null
            ? Image.network(
                icon!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                // Task 136: decode at the tiny picker-icon size.
                cacheWidth: imageCacheWidth(context, 24),
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: HorseTheme.gold,
                    ),
                  ),
                ),
              )
            : Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: HorseTheme.gold,
                  ),
                ),
              ),
      ),
    );
  }
}

/// One source row (Task 123 redesign): add-on icon square leads (flips with
/// the language), title beside it, facts line below (kind · quality pill ·
/// seeds · size · codec). Disabled rows (neither URL nor infoHash) dim.
class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.stream,
    required this.facts,
    required this.english,
    required this.condensed,
    required this.onTap,
  });

  final Map<String, dynamic> stream;
  final _SourceFacts facts;
  final bool english;
  final bool condensed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final playable = facts.isDirect || facts.isTorrent;
    final title = (stream['title'] ??
            stream['name'] ??
            stream['description'] ??
            (playable ? 'HTTP stream' : 'Torrent stream'))
        .toString()
        .split('\n')
        .first;
    final addonName =
        (stream['addonName'] ?? (english ? 'Add-on' : 'إضافة')).toString();
    final addonIcon = stream['addonIcon']?.toString();

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
                _AddonBadge(
                  icon: addonIcon,
                  name: addonName,
                  playable: playable,
                  condensed: condensed,
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
                      SizedBox(height: condensed ? 3 : 5),
                      Wrap(
                        spacing: 7,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                facts.isTorrent
                                    ? Icons.bolt_rounded
                                    : facts.isDirect
                                        ? Icons.play_arrow_rounded
                                        : Icons.cloud_off_rounded,
                                size: 13,
                                color: onTap == null
                                    ? HorseTheme.muted
                                    : facts.isTorrent
                                        ? HorseTheme.gold
                                        : HorseTheme.success,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                facts.isTorrent
                                    ? (english ? 'Torrent' : 'تورنت')
                                    : facts.isDirect
                                        ? (english ? 'Direct' : 'مباشر')
                                        : (english
                                            ? 'Unsupported'
                                            : 'غير مدعوم'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: onTap == null
                                      ? HorseTheme.muted
                                      : HorseTheme.muted,
                                ),
                              ),
                            ],
                          ),
                          if (facts.qualityLabel != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: HorseTheme.gold.withValues(
                                      alpha: onTap == null ? .18 : .45),
                                ),
                              ),
                              child: Text(
                                facts.qualityLabel!,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: onTap == null
                                      ? HorseTheme.muted
                                      : HorseTheme.gold,
                                ),
                              ),
                            ),
                          if (facts.seeds != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.groups_rounded,
                                  size: 13,
                                  color: onTap == null
                                      ? HorseTheme.muted
                                      : facts.seeds! > 0
                                          ? HorseTheme.success
                                          : HorseTheme.muted,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '${facts.seeds}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: onTap == null
                                        ? HorseTheme.muted
                                        : facts.seeds! > 0
                                            ? HorseTheme.success
                                            : HorseTheme.muted,
                                  ),
                                ),
                              ],
                            ),
                          if (facts.sizeLabel.isNotEmpty)
                            Text(
                              facts.sizeLabel,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: HorseTheme.muted,
                              ),
                            ),
                          if (facts.codec != null)
                            Text(
                              facts.codec!,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: .3,
                                color: HorseTheme.muted,
                              ),
                            ),
                        ],
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
