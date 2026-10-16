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

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/horse_theme.dart';
import '../engine/playback_engine.dart';
import 'player_sheets.dart'
    show SheetSelectChip, SubtitleChoice, subtitleLanguageName;

/// Which picker the side panel currently hosts.
enum PlayerPanelKind { audio, subtitles, streams, settings }

/// Panel width: exactly HALF the screen, clamped for readability — narrow
/// landscape phones never go below 300dp, large tablets never past 640dp.
double playerPanelWidth(double screenWidth) =>
    (screenWidth * .5).clamp(300.0, 640.0);

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
    final compact = MediaQuery.sizeOf(context).height < 520;
    final insets = MediaQuery.paddingOf(context);
    return Material(
      color: HorseTheme.raised,
      elevation: 14,
      shadowColor: Colors.black54,
      child: Padding(
        // Task 140 (user mandate): ZERO horizontal chrome padding — the body
        // (search field, list rows, header icons) stretches flush to BOTH
        // panel edges. The LEFT inset is always dropped (the edge is at
        // mid-screen — a landscape camera cutout on the display's left side
        // must never open a phantom strip here); top / right / bottom keep
        // their real system insets so content never sits under the punch
        // hole or gesture areas when the phone is rotated the other way.
        padding: EdgeInsets.fromLTRB(
          0,
          insets.top + (compact ? 10 : 14),
          insets.right,
          insets.bottom + (compact ? 10 : 14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: compact
                        ? Theme.of(context).textTheme.titleMedium
                        : Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (headerAction != null) ...[
                  headerAction!,
                  const SizedBox(width: 4),
                ],
                if (onRefresh != null) ...[
                  _PanelIconButton(
                    icon: LucideIcons.refreshCw,
                    spinning: refreshing,
                    semanticLabel: english ? 'Refresh' : 'تحديث',
                    onTap: refreshing ? null : onRefresh,
                  ),
                  const SizedBox(width: 4),
                ],
                _PanelIconButton(
                  icon: LucideIcons.x,
                  semanticLabel: english ? 'Close' : 'إغلاق',
                  onTap: onClose,
                ),
              ],
            ),
            SizedBox(height: compact ? 8 : 12),
            Expanded(child: child),
          ],
        ),
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
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 32,
            height: 32,
            child: spinning
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: HorseTheme.gold,
                    ),
                  )
                : Icon(icon, size: 18, color: Colors.white70),
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
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const SizedBox(
            width: 32,
            height: 32,
            child: Icon(LucideIcons.settings2, size: 18, color: Colors.white70),
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
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
      );
}

/// Panel-body loading spinner (gold, small — visible to the user INSIDE the
/// panel, never blocking the whole screen).
class PanelLoading extends StatelessWidget {
  const PanelLoading({super.key});

  @override
  Widget build(BuildContext context) => const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            color: HorseTheme.gold,
            strokeWidth: 2,
          ),
        ),
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
      return widget.english ? 'Track ${track.id}' : 'مسار ${track.id}';
    }
    return parts.join(' · ');
  }

  String _info(AudioTrack track) {
    final parts = <String>[
      if (track.language?.isNotEmpty == true)
        subtitleLanguageName(track.language!),
      if (track.codec?.isNotEmpty == true) track.codec!.toUpperCase(),
      if (track.channelscount != null)
        '${track.channelscount}${widget.english ? 'ch' : ' قنوات'}',
    ];
    return parts.join(' · ');
  }

  Map<String, List<AudioTrack>> get _groups {
    final groups = <String, List<AudioTrack>>{};
    for (final track in widget.tracks) {
      final code = (track.language ?? '').trim();
      final key =
          code.isEmpty ? (widget.english ? 'default' : 'افتراضي') : code;
      groups.putIfAbsent(key, () => []).add(track);
    }
    return groups;
  }

  String _groupTitle(String code) {
    if (code == 'default' || code == 'افتراضي') {
      return widget.english ? 'Default' : 'افتراضي';
    }
    final name = subtitleLanguageName(code);
    return name.isEmpty ? code : '$name · $code';
  }

  String _delayLabel(int ms) {
    if (ms == 0) return widget.english ? 'No delay' : 'بدون تأخير';
    final abs = ms.abs();
    return ms < 0
        ? (widget.english ? 'Ahead $abs ms' : 'تقديم $abs ms')
        : (widget.english ? 'Delay $abs ms' : 'تأخير $abs ms');
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups.entries.toList();
    if (widget.tracks.isEmpty) {
      return _PanelNote(
        widget.english
            ? 'No selectable audio tracks in this stream. Dubs may be '
                'available as separate sources.'
            : 'لا توجد مسارات صوتية قابلة للاختيار في هذا المصدر. '
                'قد يتوفر الدبلاج ضمن مصادر أخرى.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView.separated(
            itemCount: groups.length,
            separatorBuilder: (_, __) =>
                const Divider(color: HorseTheme.line, height: 1),
            itemBuilder: (context, index) {
              final entry = groups[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
                    child: Text(
                      _groupTitle(entry.key),
                      style: const TextStyle(
                        color: HorseTheme.gold,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .5,
                      ),
                    ),
                  ),
                  for (final track in entry.value)
                    ListTile(
                      dense: true,
                      selected: track.id == widget.selected.id,
                      leading: Icon(
                        track.id == widget.selected.id
                            ? LucideIcons.circleDot
                            : LucideIcons.circle,
                        size: 20,
                        color: track.id == widget.selected.id
                            ? HorseTheme.gold
                            : Colors.white38,
                      ),
                      title: Text(
                        _label(track),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: _info(track).isEmpty
                          ? null
                          : Text(
                              _info(track),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 12),
                            ),
                      onTap: () => widget.onPick(track),
                    ),
                ],
              );
            },
          ),
        ),
        const Divider(color: HorseTheme.line, height: 1),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              const Icon(LucideIcons.timer, size: 18, color: Colors.white54),
              const SizedBox(width: 8),
              Text(
                widget.english ? 'Audio delay' : 'تأخير الصوت',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _StepperButton(
                icon: LucideIcons.minus,
                onTap: () => _shift(-100),
              ),
              Container(
                constraints: const BoxConstraints(minWidth: 96),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: HorseTheme.line),
                ),
                child: Text(
                  _delayLabel(_delayMs),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: HorseTheme.gold,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _StepperButton(
                icon: LucideIcons.plus,
                onTap: () => _shift(100),
              ),
            ],
          ),
        ),
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
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 20, color: Colors.white70),
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
                    : (widget.english
                        ? 'Track ${track.id}'
                        : 'مسار ${track.id}'))
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
                ? (widget.english ? 'Addon subtitle' : 'ترجمة إضافة')
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
      return widget.english ? 'In this file' : 'داخل الملف';
    }
    if (key == 'all') {
      return widget.english ? 'Unknown language' : 'لغة غير معروفة';
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
        padding: const EdgeInsets.fromLTRB(6, 9, 6, 7),
        child: Row(
          children: [
            AnimatedRotation(
              turns: open ? 0 : -.25,
              duration: const Duration(milliseconds: 160),
              child: const Icon(
                LucideIcons.chevronDown,
                size: 18,
                color: HorseTheme.gold,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _groupTitle(key),
                style: const TextStyle(
                  color: HorseTheme.gold,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .4,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: HorseTheme.line),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white54,
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
      dense: true,
      selected: isSelected,
      leading: Icon(
        isSelected
            ? LucideIcons.circleDot
            : (choice.track.uri
                ? LucideIcons.cloudDownload
                : LucideIcons.circle),
        size: 20,
        color: isSelected ? HorseTheme.gold : Colors.white38,
      ),
      title: Text(
        choice.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: choice.subtitle?.isEmpty != true
          ? Text(
              choice.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
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
            prefixIcon: const Icon(LucideIcons.search, size: 20),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(LucideIcons.x, size: 16),
                    onPressed: () {
                      _search.clear();
                      setState(() {});
                    },
                  ),
            hintText:
                widget.english ? 'Search subtitles…' : 'ابحث في الترجمات…',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: HorseTheme.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: HorseTheme.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: HorseTheme.gold, width: 1.4),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Divider(color: HorseTheme.line, height: 14),
        Expanded(
          child: widget.loadingExternal
              ? const PanelLoading()
              : totalVisible == 0
                  ? _PanelNote(
                      query.isEmpty
                          ? (widget.english
                              ? 'No subtitles found for this title.'
                              : 'لم يتم العثور على ترجمات لهذا العمل.')
                          : (widget.english
                              ? 'No matches for your search.'
                              : 'لا توجد نتائج مطابقة لبحثك.'),
                    )
                  : ListView(
                      children: [
                        ListTile(
                          dense: true,
                          selected: offSelected,
                          leading: Icon(
                            offSelected
                                ? LucideIcons.circleDot
                                : LucideIcons.captionsOff,
                            size: 20,
                            color:
                                offSelected ? HorseTheme.gold : Colors.white38,
                          ),
                          title: Text(
                            widget.english ? 'Off' : 'إيقاف',
                            style: const TextStyle(fontSize: 14),
                          ),
                          onTap: () => widget.onPick(off),
                        ),
                        const Divider(color: HorseTheme.line, height: 1),
                        for (final entry in visibleGroups.entries) ...[
                          _languageHeader(entry.key, entry.value.length),
                          if (_isOpen(entry.key, visibleGroups))
                            ...entry.value.map(_choiceRow),
                          const Divider(color: HorseTheme.line, height: 1),
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
class StreamsPanelBody extends StatelessWidget {
  const StreamsPanelBody({
    super.key,
    required this.english,
    required this.streams,
    required this.currentStream,
    required this.onPick,
  });

  final bool english;
  final List<Map<String, dynamic>> streams;

  /// The currently playing stream map — highlighted when present in the list.
  final Map<String, dynamic>? currentStream;
  final ValueChanged<Map<String, dynamic>> onPick;

  bool _isDirect(Map<String, dynamic> stream) =>
      stream['url'] is String && (stream['url'] as String).startsWith('http');

  bool _isPlayable(Map<String, dynamic> stream) =>
      _isDirect(stream) || stream['infoHash'] is String;

  @override
  Widget build(BuildContext context) {
    if (streams.isEmpty) {
      return _PanelNote(
        english
            ? 'No sources available for this title yet — try the refresh '
                'button.'
            : 'لا توجد مصادر متاحة لهذا العمل بعد — جرّب زر التحديث.',
      );
    }
    return ListView.separated(
      itemCount: streams.length,
      separatorBuilder: (_, __) =>
          const Divider(color: HorseTheme.line, height: 1),
      itemBuilder: (context, index) {
        final stream = streams[index];
        final title = (stream['title'] ??
                stream['name'] ??
                stream['description'] ??
                'Stream')
            .toString()
            .split('\n')
            .first;
        // Highlight by identity AND by content: a refreshed list re-creates
        // every row, so the currently-playing source must still light up
        // (same url / infoHash ⇒ same stream).
        final current = currentStream;
        final isSelected = identical(stream, current) ||
            (current != null &&
                stream['url'] == current['url'] &&
                stream['infoHash'] == current['infoHash']);
        final playable = _isPlayable(stream);
        return ListTile(
          dense: true,
          selected: isSelected,
          enabled: playable,
          leading: Icon(
            isSelected ? LucideIcons.circleDot : LucideIcons.circlePlay,
            color: isSelected
                ? HorseTheme.gold
                : (playable ? HorseTheme.muted : Colors.white24),
            size: 22,
          ),
          title: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              color: playable ? null : Colors.white24,
            ),
          ),
          subtitle: Text(
            stream['addonName']?.toString() ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          onTap: playable ? () => onPick(stream) : null,
        );
      },
    );
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
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
          child: Text(
            english ? 'Speed' : 'السرعة',
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: .8,
            ),
          ),
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 2.6,
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
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
          child: Text(
            english ? 'Video fit' : 'ملاءمة الفيديو',
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: .8,
            ),
          ),
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 2.2,
          padding: EdgeInsets.zero,
          children: [
            SheetSelectChip(
              label: english ? 'Fit' : 'احتواء',
              selected: fit == BoxFit.contain,
              onTap: () => onFit(BoxFit.contain),
            ),
            SheetSelectChip(
              label: english ? 'Fill' : 'ملء',
              selected: fit == BoxFit.cover,
              onTap: () => onFit(BoxFit.cover),
            ),
            SheetSelectChip(
              label: english ? 'Stretch' : 'تمديد',
              selected: fit == BoxFit.fill,
              onTap: () => onFit(BoxFit.fill),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ListTile(
          dense: true,
          leading: const Icon(LucideIcons.audioLines,
              size: 20, color: Colors.white70),
          title: Text(
            english ? 'Audio track' : 'المسار الصوتي',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          subtitle: Text(
            audioLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          trailing: const Icon(
            LucideIcons.chevronRight,
            size: 20,
            color: Colors.white24,
          ),
          onTap: onOpenAudio,
        ),
        ListTile(
          dense: true,
          leading:
              const Icon(LucideIcons.captions, size: 20, color: Colors.white70),
          title: Text(
            english ? 'Subtitles' : 'الترجمة',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          subtitle: Text(
            subtitleLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          trailing: const Icon(
            LucideIcons.chevronRight,
            size: 20,
            color: Colors.white24,
          ),
          onTap: onOpenSubtitles,
        ),
        if (hasEpisodes)
          ListTile(
            dense: true,
            leading: const Icon(
              LucideIcons.listVideo,
              size: 20,
              color: Colors.white70,
            ),
            title: Text(
              english ? 'Episodes' : 'الحلقات',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            trailing: const Icon(
              LucideIcons.chevronRight,
              size: 20,
              color: Colors.white24,
            ),
            onTap: onOpenEpisodes,
          ),
      ],
    );
  }
}
