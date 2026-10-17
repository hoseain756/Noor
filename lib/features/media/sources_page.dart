/// Task 139 (user mandate): tapping an episode / the watch CTA opens THIS
/// page directly — the streams are fetched INSIDE the page (spinner in
/// front of the user) and a refresh button sits next to the search bar so
/// the list can be re-fetched in place. A pre-fetched `streams` list is
/// still accepted (legacy callers) — when `loader` is provided it wins.
library;

import 'package:noor_mobile/l10n/nova_strings.dart';
import 'package:noor_mobile/shared/widgets/nova_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../core/state/app_state.dart';
import '../../shared/widgets/shimmer_box.dart';

import '../../core/models/media_item.dart';
import '../../core/theme/horse_theme.dart';
import '../../core/torrent/torrent_models.dart';
import '../../shared/widgets/app_state_message.dart';
import '../../shared/widgets/image_decode.dart';
import 'detail_glass.dart';

/// The full-screen sources page. Pushed over the detail page; completes with
/// the chosen stream map (`Navigator.pop(context, stream)`).
class SourcesPage extends StatefulWidget {
  const SourcesPage({
    super.key,
    required this.item,
    required this.video,
    this.streams = const [],
    this.loader,
    required this.english,
    this.downloadMode = false,
  });

  final MediaItem item;

  /// The tapped episode (null for movies) — shown as the page subtitle.
  final Map<String, dynamic>? video;

  /// Pre-fetched playable-considered streams (legacy feed-only callers).
  final List<Map<String, dynamic>> streams;

  /// Task 139: when supplied, the page fetches its own list — the user
  /// watches the loading happen HERE, and the header refresh button
  /// re-runs it in place. Takes precedence over [streams].
  final Future<List<Map<String, dynamic>>> Function()? loader;
  final bool english;
  final bool downloadMode;

  @override
  State<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends State<SourcesPage> {
  String _query = '';
  bool _loadFailed = false;

  /// The live list: seeded from [SourcesPage.streams], or fetched through
  /// [SourcesPage.loader] (initial load + every refresh press).
  List<Map<String, dynamic>> _streams = const [];

  /// True only for the FIRST load through the loader (full-page spinner);
  /// refreshes keep the old list visible and just spin the button.
  bool _initialLoading = false;

  /// True while a loader round-trip is in flight (spins the refresh icon).
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    final loader = widget.loader;
    if (loader != null) {
      _streams = const [];
      _initialLoading = true;
      _runLoader(loader);
    } else {
      _streams = widget.streams;
    }
  }

  Future<void> _runLoader(
    Future<List<Map<String, dynamic>>> Function() loader,
  ) async {
    setState(() {
      _refreshing = true;
      _loadFailed = false;
    });
    List<Map<String, dynamic>> streams;
    try {
      streams = await loader();
    } catch (_) {
      _loadFailed = true;
      streams = _streams; // refreshable empty state — never a crash
    }
    if (!mounted) return;
    setState(() {
      _streams = streams;
      _initialLoading = false;
      _refreshing = false;
      _facts = _parseFacts();
      _addonStats = _computeAddonStats();
      // A fresh list invalidates a missing add-on filter silently — keep
      // the query/sort as-is (they re-filter the new list naturally).
      if (_addon != null &&
          !streams.any((s) => (s['addonName']?.toString() ?? '') == _addon)) {
        _addon = null;
      }
    });
  }

  void _refresh() {
    final loader = widget.loader;
    if (loader == null || _refreshing) return;
    _runLoader(loader);
  }

  /// Selected quality bucket (exact parsed height): null = any.
  int? _minHeight;

  /// Selected source kind: null = any, 'torrent' or 'direct'.
  String? _kind;

  /// Selected add-on (exact [stream['addonName']]): null = all.
  String? _addon;

  /// Sort mode: 0 = detail-page rank (as delivered), 1 = seeds, 2 = size,
  /// 3 = quality (then seeds).
  int _sort = 0;

  /// Parsed facts per stream — recomputed whenever [_streams] is replaced
  /// (initial loader result or a refresh), reused for every filter/sort
  /// pass in between.
  late List<_SourceFacts> _facts = _parseFacts();

  List<_SourceFacts> _parseFacts() => [
        for (final stream in _streams) _SourceFacts.parse(stream),
      ];

  /// First-appearance-ordered add-on stats: name → (count, iconUrl).
  late Map<String, (int, String?)> _addonStats = _computeAddonStats();

  Map<String, (int, String?)> _computeAddonStats() {
    final stats = <String, (int, String?)>{};
    for (final stream in _streams) {
      final name = stream['addonName']?.toString() ?? '';
      if (name.isEmpty) continue;
      final current = stats[name] ?? (0, null);
      stats[name] = (
        current.$1 + 1,
        current.$2 ?? stream['addonIcon']?.toString(),
      );
    }
    return stats;
  }

  bool _isDirect(Map<String, dynamic> stream) {
    final url = stream['url'];
    return url is String && url.startsWith('http');
  }

  bool _isTorrent(Map<String, dynamic> stream) =>
      !_isDirect(stream) && stream['infoHash'] is String;

  /// Indices into [_streams] that survive the text query + chips,
  /// ordered by the active sort (rank order = original index order kept).
  List<int> _visibleIndices(String query) {
    var indices = List<int>.generate(_streams.length, (i) => i);
    if (query.isNotEmpty) {
      bool matches(int i) {
        final s = _streams[i];
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
          .where((i) => (_streams[i]['addonName']?.toString() ?? '') == _addon)
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
        1 => NovaStrings.lookup(english, 'message187'),
        2 => NovaStrings.lookup(english, 'message188'),
        3 => NovaStrings.lookup(english, 'message189'),
        _ => NovaStrings.lookup(english, 'message190'),
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
                          ? Icon(LucideIcons.check,
                              size: 16, color: NovaTheme.of(context).gold)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _sortLabel(i, widget.english),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: NovaTheme.of(context).ink,
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
                            ? (NovaStrings.lookup(english, 'message191'))
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
                              ? NovaTheme.of(context).gold
                              : NovaTheme.of(context).ink,
                        ),
                      ),
                    ),
                    if (i > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${_addonStats[names[i - 1]]!.$1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: NovaTheme.of(context).muted,
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: (i == 0 && _addon == null) ||
                              (i > 0 && names[i - 1] == _addon)
                          ? Icon(LucideIcons.check,
                              size: 16, color: NovaTheme.of(context).gold)
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
                      color: selected
                          ? NovaTheme.of(context).gold
                          : NovaTheme.of(context).muted),
                  const SizedBox(width: 7),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? NovaTheme.of(context).gold
                        : NovaTheme.of(context).muted,
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
            icon: LucideIcons.arrowDownUp,
            selected: _sort != 0,
            onTap: _openSortMenu,
          ),
          const SizedBox(width: 8),
          _chip(
            key: _addonKey,
            label: _addon ??
                (NovaStrings.lookup(
                    english, 'message192', {'p0': _addonStats.length})),
            icon: LucideIcons.puzzle,
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
                  ? (NovaStrings.lookup(english, 'message193'))
                  : bucket.$2,
              selected: _minHeight == bucket.$1,
              onTap: () => setState(() => _minHeight = bucket.$1),
            ),
            const SizedBox(width: 8),
          ],
          _chip(
            label: NovaStrings.lookup(english, 'message194'),
            icon: LucideIcons.zap,
            selected: _kind == 'torrent',
            onTap: () =>
                setState(() => _kind = _kind == 'torrent' ? null : 'torrent'),
          ),
          const SizedBox(width: 8),
          _chip(
            label: NovaStrings.lookup(english, 'message195'),
            icon: LucideIcons.play,
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
    final english = context.watch<AppState?>()?.english ?? widget.english;
    final scheme = Theme.of(context).colorScheme;
    final video = widget.video;
    final season = (video?['season'] as num?)?.toInt();
    final episode = (video?['episode'] as num?)?.toInt();
    final episodeName = (video?['name'] ?? video?['title'])?.toString();
    final subtitle = video == null
        ? (NovaStrings.lookup(english, 'message128'))
        : [
            'S$season:E$episode',
            if (episodeName?.isNotEmpty == true) episodeName!
          ].join(' · ');
    final visible = _visibleIndices(_query.trim().toLowerCase());
    final addons = <String>{
      for (final stream in _streams)
        if (stream['addonName'] is String) stream['addonName'] as String
    };
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.downloadMode
              ? (NovaStrings.lookup(english, 'message196'))
              : (NovaStrings.lookup(english, 'message197')))),
      body: SafeArea(
          top: false,
          child: LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 840;
            final controls = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.item.name,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(subtitle,
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, height: 1.5)),
                  const SizedBox(height: 24),
                  Text(NovaStrings.lookup(english, 'message198'),
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  TextField(
                      onChanged: (value) => setState(() => _query = value),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                          prefixIcon: const Icon(LucideIcons.search),
                          hintText: NovaStrings.lookup(english, 'message199'),
                          suffixIcon: widget.loader == null
                              ? null
                              : _refreshing
                                  ? const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: SizedBox.square(
                                          dimension: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2)))
                                  : IconButton(
                                      tooltip: NovaStrings.lookup(
                                          english, 'message200'),
                                      icon: const Icon(LucideIcons.refreshCw),
                                      onPressed: _refresh))),
                  if (_streams.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _filterBar(english)
                  ],
                  const SizedBox(height: 16),
                  Text(
                      NovaStrings.lookup(english, 'message201',
                          {'p0': visible.length, 'p1': addons.length}),
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  if (widget.downloadMode) ...[
                    const SizedBox(height: 8),
                    Text(NovaStrings.lookup(english, 'message202'),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant))
                  ],
                  if (_loadFailed) ...[
                    const SizedBox(height: 16),
                    Text(NovaStrings.lookup(english, 'message203'),
                        style: TextStyle(color: scheme.error)),
                    TextButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(LucideIcons.refreshCw),
                        label: Text(NovaStrings.lookup(english, 'message174'))),
                  ],
                ]);
            final resultSliver = _initialLoading
                ? SliverList.builder(
                    itemCount: 6,
                    itemBuilder: (_, __) => const Padding(
                        padding: EdgeInsetsDirectional.only(bottom: 16),
                        child: ShimmerBox(height: 112)))
                : visible.isEmpty
                    ? SliverFillRemaining(
                        hasScrollBody: false,
                        child: AppStateMessage(
                            icon: _loadFailed
                                ? LucideIcons.wifiOff
                                : LucideIcons.searchX,
                            message: _loadFailed
                                ? (NovaStrings.lookup(english, 'message204'))
                                : _streams.isEmpty
                                    ? (NovaStrings.lookup(
                                        english, 'message205'))
                                    : (NovaStrings.lookup(
                                        english, 'message206'))))
                    : SliverList.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final i = visible[index];
                          final stream = _streams[i];
                          return _SourceRow(
                              stream: stream,
                              facts: _facts[i],
                              english: english,
                              condensed: false,
                              onTap: _isDirect(stream) || _isTorrent(stream)
                                  ? () => Navigator.of(context).pop(stream)
                                  : null);
                        });
            if (wide)
              return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                        width: 320,
                        child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: controls)),
                    VerticalDivider(width: 1, color: scheme.outlineVariant),
                    Expanded(
                        child: CustomScrollView(slivers: [
                      SliverPadding(
                          padding: const EdgeInsets.all(24),
                          sliver: resultSliver)
                    ])),
                  ]);
            return CustomScrollView(slivers: [
              SliverToBoxAdapter(
                  child: Padding(
                      padding: const EdgeInsets.all(24), child: controls)),
              SliverPadding(
                  padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 24),
                  sliver: resultSliver),
            ]);
          })),
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
    final isTenBit =
        RegExp(r'10\s*[-_.]?\s*bit|main10|\bp10\b').hasMatch(lower);
    final String? codec = lower.contains('av1')
        ? (isTenBit ? 'AV1 10-bit' : 'AV1')
        : lower.contains('x265') ||
                lower.contains('h265') ||
                lower.contains('hevc')
            ? (isTenBit ? 'HEVC 10-bit' : 'HEVC')
            : lower.contains('x264') ||
                    lower.contains('h264') ||
                    lower.contains('avc')
                ? (isTenBit ? 'H.264 10-bit' : 'H.264')
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
        color: NovaTheme.of(context).gold.withValues(alpha: .12),
        child: icon != null
            ? NovaNetworkImage(
                icon!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                // Task 136: decode at the tiny picker-icon size.
                cacheWidth: imageCacheWidth(context, 24),
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    initial,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: NovaTheme.of(context).gold,
                    ),
                  ),
                ),
              )
            : Center(
                child: Text(
                  initial,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: NovaTheme.of(context).gold,
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
  const _SourceRow(
      {required this.stream,
      required this.facts,
      required this.english,
      required this.condensed,
      required this.onTap});
  final Map<String, dynamic> stream;
  final _SourceFacts facts;
  final bool english, condensed;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = (stream['title'] ??
            stream['name'] ??
            stream['description'] ??
            (NovaStrings.lookup(english, 'message207')))
        .toString()
        .split('\n')
        .first;
    final addon =
        (stream['addonName'] ?? (NovaStrings.lookup(english, 'message208')))
            .toString();
    final kind = facts.isTorrent
        ? (NovaStrings.lookup(english, 'message209'))
        : facts.isDirect
            ? (NovaStrings.lookup(english, 'message195'))
            : (NovaStrings.lookup(english, 'message210'));
    return Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 16),
        child: Material(
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: scheme.outlineVariant)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
              onTap: onTap,
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          SizedBox.square(
                              dimension: 24,
                              child: _AddonIcon(
                                  icon: stream['addonIcon']?.toString(),
                                  name: addon,
                                  radius: 8)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(addon,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(color: scheme.primary))),
                          if (facts.qualityLabel != null)
                            Container(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    8, 4, 8, 4),
                                decoration: BoxDecoration(
                                    color: scheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(8)),
                                child: Text(facts.qualityLabel!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                            color: scheme.onPrimaryContainer))),
                        ]),
                        const SizedBox(height: 12),
                        Text(title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                    height: 1.5,
                                    color: onTap == null
                                        ? scheme.onSurfaceVariant
                                        : scheme.onSurface)),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                              child: Wrap(
                                  spacing: 12,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                Text(kind,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                            color: scheme.onSurfaceVariant)),
                                if (facts.sizeLabel.isNotEmpty)
                                  Text(facts.sizeLabel,
                                      textDirection: TextDirection.ltr,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                if (facts.codec != null)
                                  Text(facts.codec!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                if (facts.seeds != null)
                                  Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(LucideIcons.users,
                                            size: 14,
                                            color: scheme.onSurfaceVariant),
                                        const SizedBox(width: 4),
                                        Text('${facts.seeds}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall)
                                      ]),
                              ])),
                          if (onTap != null)
                            Icon(LucideIcons.play,
                                color: scheme.primary, size: 24),
                        ]),
                      ]))),
        ));
  }
}

/// Stream-preparation sheet shown while metadata and the local HTTP endpoint
/// are being prepared. Once the endpoint is bound, playback takes over and
/// waits for the requested pieces itself; a whole-file percentage is not a
/// prerequisite for opening the player.
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
      'downloading' => NovaStrings.lookup(english, 'message211'),
      'checking' => NovaStrings.lookup(english, 'message212'),
      'finished' || 'seeding' => NovaStrings.lookup(english, 'message213'),
      'paused' => NovaStrings.lookup(english, 'message214'),
      _ => NovaStrings.lookup(english, 'message215'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(LucideIcons.clapperboard, size: 32, color: scheme.primary),
      title: Text(NovaStrings.lookup(english, 'message216')),
      content: SizedBox(
          width: 360,
          child: ValueListenableBuilder<TorrentStatus?>(
              valueListenable: status,
              builder: (context, snapshot, _) {
                final progress = snapshot?.progress.clamp(0.0, 1.0);
                return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_stateLabel(snapshot, english),
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 20),
                      LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(8)),
                      const SizedBox(height: 16),
                      Text(NovaStrings.lookup(english, 'message217'),
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, height: 1.6)),
                      if (snapshot != null) ...[
                        const SizedBox(height: 20),
                        Wrap(spacing: 16, runSpacing: 8, children: [
                          Text('${((progress ?? 0) * 100).round()}%',
                              textDirection: TextDirection.ltr,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(color: scheme.primary)),
                          Text(
                              '${(snapshot.downloadRate / (1024 * 1024)).toStringAsFixed(2)} MB/s',
                              textDirection: TextDirection.ltr,
                              style: Theme.of(context).textTheme.bodyMedium),
                        ]),
                      ],
                    ]);
              })),
      actions: [
        TextButton(
            onPressed: onCancel,
            child: Text(NovaStrings.lookup(english, 'cancel')))
      ],
    );
  }
}
