/// Task 139 (user mandate): the player's subtitle / audio / source pickers
/// no longer take the whole screen — each opens as a RIGHT-HALF panel
/// (50% of the screen width, full height) the INSTANT its button is pressed,
/// shows its loading state inside the panel itself, and carries a refresh
/// button in the header so the lists can be re-fetched in place.
/// Task 141: the playback-settings picker joined them — same chrome, same
/// instant open, same full-height right half.
///
/// Panels are in-page overlays (not routes): opening is a single setState —
/// zero route-transition delay — and the video pauses for the panel's
/// lifetime, resuming only if it was playing before (workstream A1 semantics
/// preserved). The PAGE owns the data loading (spinner + refresh state live
/// in the panel header); these bodies render lists and UI-local state.
/// Icons are Lucide across the whole player surface.
///
/// Task 140 (user mandate — "لا فراغات"): the panel's LEFT edge sits at
/// MID-SCREEN, so the screen's left system inset (a landscape camera cutout
/// reported on the display's left edge) must NEVER be applied there — the
/// old SafeArea injected it and opened a ~40dp phantom dead strip inside
/// every panel. Content now stretches flush to the mid-screen edge with zero
/// horizontal chrome padding; only the panel's REAL screen edges (top /
/// right / bottom) keep their system insets.
library;

import 'package:noor_mobile/l10n/nova_strings.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../engine/playback_engine.dart';
import '../../../shared/widgets/shimmer_box.dart';
import 'player_sheets.dart'
    show SheetSelectChip, SubtitleChoice, subtitleLanguageName;

/// Which picker the side panel currently hosts.
enum PlayerPanelKind { audio, subtitles, streams, settings }

/// Panel width: exactly HALF the screen, clamped for readability — narrow
/// landscape phones never go below 300dp, large tablets never past 640dp.
double playerPanelWidth(double screenWidth) =>
    (screenWidth * .48).clamp(360.0, 560.0).clamp(0.0, screenWidth);

/// The chrome every picker panel shares: header (title · optional action ·
/// refresh · close) over a body. [onRefresh] is supplied whenever the
/// body's data can actually be re-fetched; [refreshing] spins the button.
class PlayerSidePanel extends StatelessWidget {
  const PlayerSidePanel({
    super.key,
    required this.title,
    required this.english,
    required this.onClose,
    required this.child,
    this.onRefresh,
    this.refreshing = false,
    this.headerAction,
  });

  final String title;
  final bool english;
  final VoidCallback onClose;
  final Widget child;
  final VoidCallback? onRefresh;
  final bool refreshing;
  final Widget? headerAction;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final portrait = size.width < 600 && size.height > size.width;
    final scheme = Theme.of(context).colorScheme;
    final padding = MediaQuery.paddingOf(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Material(
      color: scheme.surface,
      elevation: 12,
      shadowColor: scheme.shadow.withValues(alpha: .24),
      borderRadius: portrait
          ? const BorderRadiusDirectional.vertical(top: Radius.circular(28))
          : BorderRadius.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
            24,
            portrait ? 12 : padding.top + 16,
            24 +
                (portrait
                    ? 0
                    : rtl
                        ? padding.left
                        : padding.right),
            padding.bottom + 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (portrait) ...[
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(4)))),
            const SizedBox(height: 16)
          ],
          Row(children: [
            Expanded(
                child: Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge)),
            _PanelIconButton(
                icon: LucideIcons.x,
                semanticLabel: NovaStrings.lookup(english, 'close'),
                onTap: onClose),
          ]),
          if (headerAction != null || onRefresh != null)
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (headerAction != null) headerAction!,
              if (onRefresh != null)
                _PanelIconButton(
                    icon: LucideIcons.refreshCw,
                    spinning: refreshing,
                    semanticLabel: NovaStrings.lookup(english, 'message68'),
                    onTap: refreshing ? null : onRefresh),
            ]),
          const SizedBox(height: 16),
          Expanded(child: child),
        ]),
      ),
    );
  }
}

class _PanelIconButton extends StatelessWidget {
  const _PanelIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.spinning = false,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;
  final bool spinning;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semanticLabel,
        child: InkWell(
          customBorder: CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: spinning
                ? Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
                : Icon(icon,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
}

/// Public panel-header icon button — used by the page to put the subtitle
/// STYLE/TIMING shortcut (settings icon) in the panel header.
class PanelSettingsButton extends StatelessWidget {
  const PanelSettingsButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Subtitle style & timing',
        child: InkWell(
          customBorder: CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(LucideIcons.settings2,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
}

/// Centered note for empty panel states.
class _PanelNote extends StatelessWidget {
  const _PanelNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13),
          ),
        ),
      );
}

/// Panel-body loading spinner (gold, small — visible to the user INSIDE the
/// panel, never blocking the whole screen).
class PanelLoading extends StatelessWidget {
  const PanelLoading({super.key});

  @override
  Widget build(BuildContext context) => ListView.separated(
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (_, __) => const ShimmerBox(height: 72),
      );
}

// ── Audio tracks ───────────────────────────────────────────────────────────

/// Audio / dub picker body — embedded mpv tracks grouped by language, plus
/// the ±100 ms audio-delay stepper. Picking keeps the panel open so the user
/// can audition tracks; the change applies to the engine instantly.
class AudioTracksPanelBody extends StatefulWidget {
  const AudioTracksPanelBody({
    super.key,
    required this.english,
    required this.tracks,
    required this.selected,
    required this.onPick,
    required this.delayMs,
    required this.onDelayChanged,
  });

  final bool english;
  final List<AudioTrack> tracks;
  final AudioTrack selected;
  final ValueChanged<AudioTrack> onPick;

  /// Current audio delay (ms) — persisted via AppState.webSettings.
  final int delayMs;
  final ValueChanged<int> onDelayChanged;

  @override
  State<AudioTracksPanelBody> createState() => _AudioTracksPanelBodyState();
}

class _AudioTracksPanelBodyState extends State<AudioTracksPanelBody> {
  late int _delayMs = widget.delayMs;

  void _shift(int delta) {
    final next = (_delayMs + delta).clamp(-10000, 10000);
    setState(() => _delayMs = next);
    widget.onDelayChanged(next);
  }

  String _label(AudioTrack track) {
    final parts = <String>[
      if (track.title?.isNotEmpty == true) track.title!,
    ];
    if (parts.isEmpty) {
      return NovaStrings.lookup(widget.english, 'message69', {'p0': track.id});
    }
    return parts.join(' · ');
  }

  String _info(AudioTrack track) {
    final parts = <String>[
      if (track.language?.isNotEmpty == true)
        subtitleLanguageName(track.language!),
      if (track.codec?.isNotEmpty == true) track.codec!.toUpperCase(),
      if (track.channelscount != null)
        '${track.channelscount}${NovaStrings.lookup(widget.english, 'message70')}',
    ];
    return parts.join(' · ');
  }

  Map<String, List<AudioTrack>> get _groups {
    final groups = <String, List<AudioTrack>>{};
    for (final track in widget.tracks) {
      final code = (track.language ?? '').trim();
      final key = code.isEmpty
          ? (NovaStrings.lookup(widget.english, 'message71'))
          : code;
      groups.putIfAbsent(key, () => []).add(track);
    }
    return groups;
  }

  String _groupTitle(String code) {
    if (code == 'default' || code == 'افتراضي') {
      return NovaStrings.lookup(widget.english, 'message2');
    }
    final name = subtitleLanguageName(code);
    return name.isEmpty ? code : '$name · $code';
  }

  String _delayLabel(int ms) {
    if (ms == 0) return NovaStrings.lookup(widget.english, 'message72');
    final abs = ms.abs();
    return ms < 0
        ? (NovaStrings.lookup(widget.english, 'message47', {'p0': abs}))
        : (NovaStrings.lookup(widget.english, 'message48', {'p0': abs}));
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups.entries.toList();
    if (widget.tracks.isEmpty) {
      return _PanelNote(
        NovaStrings.lookup(widget.english, 'message73'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView.separated(
            itemCount: groups.length,
            separatorBuilder: (_, __) => Divider(
                color: Theme.of(context).colorScheme.outlineVariant, height: 1),
            itemBuilder: (context, index) {
              final entry = groups[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(4, 8, 4, 2),
                    child: Text(
                      _groupTitle(entry.key),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .5,
                      ),
                    ),
                  ),
                  for (final track in entry.value)
                    ListTile(
                      dense: false,
                      selected: track.id == widget.selected.id,
                      leading: Icon(
                        track.id == widget.selected.id
                            ? LucideIcons.circleDot
                            : LucideIcons.circle,
                        size: 20,
                        color: track.id == widget.selected.id
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      title: Text(
                        _label(track),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14),
                      ),
                      subtitle: _info(track).isEmpty
                          ? null
                          : Text(
                              _info(track),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  fontSize: 12),
                            ),
                      onTap: () => widget.onPick(track),
                    ),
                ],
              );
            },
          ),
        ),
        Divider(color: Theme.of(context).colorScheme.outlineVariant, height: 1),
        Padding(
            padding: const EdgeInsetsDirectional.only(top: 16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(NovaStrings.lookup(widget.english, 'message74'),
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(children: [
                _StepperButton(
                    icon: LucideIcons.minus, onTap: () => _shift(-100)),
                Expanded(
                    child: Text(_delayLabel(_delayMs),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w700))),
                _StepperButton(
                    icon: LucideIcons.plus, onTap: () => _shift(100)),
              ]),
            ])),
      ],
    );
  }
}

/// Round ± stepper button shared by the panel delay controls.
class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        customBorder: CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon,
              size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
}

// ── Subtitles ──────────────────────────────────────────────────────────────

/// Subtitle picker body: embedded mpv tracks + addon subtitles (fetched by
/// the page — the spinner is visible INSIDE the panel), search field,
/// expandable language groups and the persistent "Off" row. Picking applies
/// immediately without closing the panel.
class SubtitleTracksPanelBody extends StatefulWidget {
  const SubtitleTracksPanelBody({
    super.key,
    required this.english,
    required this.embedded,
    required this.selected,
    required this.onPick,
    required this.external,
    required this.loadingExternal,
    this.onOpenSettings,
  });

  final bool english;

  /// mpv-embedded subtitle tracks (inside the file itself).
  final List<SubtitleTrack> embedded;

  final SubtitleTrack selected;
  final ValueChanged<SubtitleTrack> onPick;

  /// Raw addon subtitle rows (url / lang / label / addonName), loaded by the
  /// page on panel open and on the header refresh button.
  final List<Map<String, dynamic>> external;
  final bool loadingExternal;

  /// Subtitle style/timing shortcut (tune icon in the panel header).
  final VoidCallback? onOpenSettings;

  @override
  State<SubtitleTracksPanelBody> createState() =>
      _SubtitleTracksPanelBodyState();
}

class _SubtitleTracksPanelBodyState extends State<SubtitleTracksPanelBody> {
  final _search = TextEditingController();
  final Set<String> _expanded = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<SubtitleChoice> get _choices {
    final choices = <SubtitleChoice>[];
    for (final track in widget.embedded) {
      if (track.id == 'no' || track.id == 'auto') continue;
      choices.add(SubtitleChoice(
        track: track,
        groupKey: 'embedded',
        title: (track.title?.isNotEmpty == true
                ? track.title!
                : track.language?.isNotEmpty == true
                    ? subtitleLanguageName(track.language!)
                    : (NovaStrings.lookup(
                        widget.english, 'message69', {'p0': track.id})))
            .split('\n')
            .first,
        subtitle: [
          if (track.language?.isNotEmpty == true)
            subtitleLanguageName(track.language!),
          if (track.codec?.isNotEmpty == true) track.codec!.toUpperCase(),
        ].join(' · '),
      ));
    }
    for (final row in widget.external) {
      final url = row['url']?.toString() ?? '';
      if (url.isEmpty) continue;
      final lang = (row['lang'] ?? '').toString().trim();
      final label = (row['label'] ?? '').toString().trim();
      final addon = (row['addonName'] ?? '').toString().trim();
      final name = subtitleLanguageName(lang);
      choices.add(SubtitleChoice(
        track: SubtitleTrack.uri(url, title: label.isEmpty ? lang : label),
        groupKey: lang.isEmpty ? 'all' : lang,
        title: label.isEmpty
            ? (lang.isEmpty
                ? (NovaStrings.lookup(widget.english, 'message75'))
                : name)
            : label,
        subtitle: [
          if (addon.isNotEmpty) addon,
          if (lang.isNotEmpty) name,
        ].join(' · '),
      ));
    }
    return choices;
  }

  Map<String, List<SubtitleChoice>> get _groups {
    final groups = <String, List<SubtitleChoice>>{};
    for (final choice in _choices) {
      groups.putIfAbsent(choice.groupKey, () => []).add(choice);
    }
    int rank(String key) {
      if (key == 'ar') return 0;
      if (key == 'embedded') return 2;
      return 1;
    }

    final keys = groups.keys.toList()
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        if (byRank != 0) return byRank;
        return subtitleLanguageName(a)
            .toLowerCase()
            .compareTo(subtitleLanguageName(b).toLowerCase());
      });
    return {for (final key in keys) key: groups[key]!};
  }

  bool _matches(SubtitleChoice choice, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return choice.title.toLowerCase().contains(q) ||
        (choice.subtitle ?? '').toLowerCase().contains(q) ||
        choice.groupKey.toLowerCase().contains(q) ||
        subtitleLanguageName(choice.groupKey).toLowerCase().contains(q);
  }

  String _groupTitle(String key) {
    if (key == 'embedded') {
      return NovaStrings.lookup(widget.english, 'message76');
    }
    if (key == 'all') {
      return NovaStrings.lookup(widget.english, 'message77');
    }
    final name = subtitleLanguageName(key);
    return name.isEmpty ? key : '$name · $key';
  }

  bool _isOpen(String key, Map<String, List<SubtitleChoice>> groups) {
    if (_search.text.trim().isNotEmpty) return true;
    if (_expanded.contains(key)) return true;
    return _expanded.isEmpty &&
        groups.keys.isNotEmpty &&
        key == groups.keys.first;
  }

  Widget _languageHeader(String key, int count) {
    final open = _search.text.trim().isNotEmpty || _expanded.contains(key);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() {
        open ? _expanded.remove(key) : _expanded.add(key);
      }),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(6, 9, 6, 7),
        child: Row(
          children: [
            AnimatedRotation(
              turns: open ? 0 : -.25,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              child: Icon(
                LucideIcons.chevronDown,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                _groupTitle(key),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .4,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: .06),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choiceRow(SubtitleChoice choice) {
    final isSelected = choice.track.id == widget.selected.id;
    return ListTile(
      dense: false,
      selected: isSelected,
      leading: Icon(
        isSelected
            ? LucideIcons.circleDot
            : (choice.track.uri
                ? LucideIcons.cloudDownload
                : LucideIcons.circle),
        size: 20,
        color: isSelected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: Text(
        choice.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 14),
      ),
      subtitle: choice.subtitle?.isEmpty != true
          ? Text(
              choice.subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12),
            )
          : null,
      onTap: () => widget.onPick(choice.track),
    );
  }

  @override
  Widget build(BuildContext context) {
    final off = SubtitleTrack.no();
    final offSelected = widget.selected.id == off.id;
    final groups = _groups;
    final query = _search.text.trim();
    final visibleGroups = <String, List<SubtitleChoice>>{};
    for (final entry in groups.entries) {
      final rows = entry.value.where((c) => _matches(c, query)).toList();
      if (rows.isNotEmpty) visibleGroups[entry.key] = rows;
    }
    final totalVisible =
        visibleGroups.values.fold<int>(0, (sum, rows) => sum + rows.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: Icon(LucideIcons.search, size: 20),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(LucideIcons.x, size: 16),
                    onPressed: () {
                      _search.clear();
                      setState(() {});
                    },
                  ),
            hintText: NovaStrings.lookup(widget.english, 'message78'),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary, width: 1.4),
            ),
          ),
        ),
        SizedBox(height: 10),
        Divider(
            color: Theme.of(context).colorScheme.outlineVariant, height: 14),
        Expanded(
          child: widget.loadingExternal
              ? PanelLoading()
              : totalVisible == 0
                  ? _PanelNote(
                      query.isEmpty
                          ? (NovaStrings.lookup(widget.english, 'message79'))
                          : (NovaStrings.lookup(widget.english, 'message80')),
                    )
                  : ListView(
                      children: [
                        ListTile(
                          dense: false,
                          selected: offSelected,
                          leading: Icon(
                            offSelected
                                ? LucideIcons.circleDot
                                : LucideIcons.captionsOff,
                            size: 20,
                            color: offSelected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                          ),
                          title: Text(
                            NovaStrings.lookup(widget.english, 'message4'),
                            style: TextStyle(fontSize: 14),
                          ),
                          onTap: () => widget.onPick(off),
                        ),
                        Divider(
                            color: Theme.of(context).colorScheme.outlineVariant,
                            height: 1),
                        for (final entry in visibleGroups.entries) ...[
                          _languageHeader(entry.key, entry.value.length),
                          if (_isOpen(entry.key, visibleGroups))
                            ...entry.value.map(_choiceRow),
                          Divider(
                              color:
                                  Theme.of(context).colorScheme.outlineVariant,
                              height: 1),
                        ],
                      ],
                    ),
        ),
      ],
    );
  }
}

// ── Streams ────────────────────────────────────────────────────────────────

/// Source picker body: renders the stream list handed in by the page (the
/// page owns loading + refresh; the spinner lives INSIDE the panel). Rows
/// that no playback path supports stay visible but disabled. Picking hands
/// the stream back for resolution — never a silent auto-pick.
class StreamsPanelBody extends StatefulWidget {
  const StreamsPanelBody(
      {super.key,
      required this.english,
      required this.streams,
      required this.currentStream,
      required this.onPick});
  final bool english;
  final List<Map<String, dynamic>> streams;
  final Map<String, dynamic>? currentStream;
  final ValueChanged<Map<String, dynamic>> onPick;
  @override
  State<StreamsPanelBody> createState() => _StreamsPanelBodyState();
}

class _StreamsPanelBodyState extends State<StreamsPanelBody> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final streams = widget.streams
        .where((stream) =>
            '${stream['title']} ${stream['name']} ${stream['addonName']}'
                .toLowerCase()
                .contains(_query.trim().toLowerCase()))
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
              prefixIcon: const Icon(LucideIcons.search),
              hintText: NovaStrings.lookup(widget.english, 'message677'))),
      const SizedBox(height: 16),
      Text(
          NovaStrings.lookup(
              widget.english, 'message678', {'p0': streams.length}),
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: scheme.onSurfaceVariant)),
      const SizedBox(height: 8),
      Expanded(
          child: streams.isEmpty
              ? _PanelNote(NovaStrings.lookup(widget.english, 'message81'))
              : ListView.separated(
                  itemCount: streams.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final stream = streams[index];
                    final playable = stream['url'] is String &&
                            (stream['url'] as String).startsWith('http') ||
                        stream['infoHash'] is String;
                    final current = widget.currentStream;
                    final selected = identical(stream, current) ||
                        current != null &&
                            stream['url'] == current['url'] &&
                            stream['infoHash'] == current['infoHash'];
                    return ListTile(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                              color: selected
                                  ? scheme.primary
                                  : scheme.outlineVariant)),
                      tileColor: selected
                          ? scheme.primaryContainer
                          : scheme.surfaceContainerLow,
                      contentPadding: const EdgeInsets.all(16),
                      selected: selected,
                      enabled: playable,
                      leading: Icon(
                          selected ? LucideIcons.circleCheck : LucideIcons.play,
                          color: selected
                              ? scheme.primary
                              : scheme.onSurfaceVariant),
                      title: Text(
                          (stream['title'] ?? stream['name'] ?? '')
                              .toString()
                              .split('\n')
                              .first,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      subtitle: Padding(
                          padding: const EdgeInsetsDirectional.only(top: 8),
                          child: Text(stream['addonName']?.toString() ?? '',
                              style:
                                  TextStyle(color: scheme.onSurfaceVariant))),
                      onTap: playable ? () => widget.onPick(stream) : null,
                    );
                  })),
    ]);
  }
}

// ── Playback settings ──────────────────────────────────────────────────────

/// Playback-settings body (Task 141 user mandate): the player's settings now
/// open as the SAME right-half panel as the subtitle picker — instant,
/// in-page, full height — instead of a bottom-sheet route. Speed and video
/// fit apply LIVE with the panel staying open (same contract as picking
/// audio tracks); the audio / subtitles entries hand the panel over in
/// place, and episodes keeps its dense bottom sheet.
class PlayerSettingsPanelBody extends StatelessWidget {
  const PlayerSettingsPanelBody({
    super.key,
    required this.english,
    required this.speed,
    required this.fit,
    required this.audioLabel,
    required this.subtitleLabel,
    required this.hasEpisodes,
    required this.onSpeed,
    required this.onFit,
    required this.onOpenAudio,
    required this.onOpenSubtitles,
    required this.onOpenEpisodes,
  });

  final bool english;
  final double speed;
  final BoxFit fit;
  final String audioLabel;
  final String subtitleLabel;
  final bool hasEpisodes;
  final ValueChanged<double> onSpeed;
  final ValueChanged<BoxFit> onFit;
  final VoidCallback onOpenAudio;
  final VoidCallback onOpenSubtitles;
  final VoidCallback onOpenEpisodes;

  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 4),
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(4, 2, 4, 0),
          child: Text(
            NovaStrings.lookup(english, 'message82'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: .8,
            ),
          ),
        ),
        SizedBox(height: 8),
        GridView.count(
          crossAxisCount:
              MediaQuery.textScalerOf(context).scale(16) > 24 ? 2 : 3,
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 1.6,
          padding: EdgeInsets.zero,
          children: [
            for (final value in _speeds)
              SheetSelectChip(
                label: '${value == 1.0 ? '1' : value}×',
                selected: (speed - value).abs() < .01,
                onTap: () => onSpeed(value),
              ),
          ],
        ),
        SizedBox(height: 16),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 0),
          child: Text(
            NovaStrings.lookup(english, 'message83'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: .8,
            ),
          ),
        ),
        SizedBox(height: 8),
        GridView.count(
          crossAxisCount:
              MediaQuery.textScalerOf(context).scale(16) > 24 ? 2 : 3,
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 1.6,
          padding: EdgeInsets.zero,
          children: [
            SheetSelectChip(
              label: NovaStrings.lookup(english, 'message84'),
              selected: fit == BoxFit.contain,
              onTap: () => onFit(BoxFit.contain),
            ),
            SheetSelectChip(
              label: NovaStrings.lookup(english, 'message85'),
              selected: fit == BoxFit.cover,
              onTap: () => onFit(BoxFit.cover),
            ),
            SheetSelectChip(
              label: NovaStrings.lookup(english, 'message86'),
              selected: fit == BoxFit.fill,
              onTap: () => onFit(BoxFit.fill),
            ),
          ],
        ),
        SizedBox(height: 8),
        ListTile(
          dense: false,
          leading: Icon(LucideIcons.audioLines,
              size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
          title: Text(
            NovaStrings.lookup(english, 'message87'),
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
          ),
          subtitle: Text(
            audioLabel,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12),
          ),
          trailing: Icon(
            LucideIcons.chevronRight,
            size: 20,
            color: Theme.of(context).colorScheme.outline,
          ),
          onTap: onOpenAudio,
        ),
        ListTile(
          dense: false,
          leading: Icon(LucideIcons.captions,
              size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
          title: Text(
            NovaStrings.lookup(english, 'message7'),
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
          ),
          subtitle: Text(
            subtitleLabel,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12),
          ),
          trailing: Icon(
            LucideIcons.chevronRight,
            size: 20,
            color: Theme.of(context).colorScheme.outline,
          ),
          onTap: onOpenSubtitles,
        ),
        if (hasEpisodes)
          ListTile(
            dense: false,
            leading: Icon(
              LucideIcons.listVideo,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            title: Text(
              NovaStrings.lookup(english, 'message43'),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
            ),
            trailing: Icon(
              LucideIcons.chevronRight,
              size: 20,
              color: Theme.of(context).colorScheme.outline,
            ),
            onTap: onOpenEpisodes,
          ),
      ],
    );
  }
}
