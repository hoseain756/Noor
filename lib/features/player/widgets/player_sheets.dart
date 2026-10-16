import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/state/app_state.dart';
import '../../../core/theme/horse_theme.dart';
import '../../../shared/widgets/color_picker_dialog.dart';
import '../engine/playback_engine.dart';
import 'subtitle_overlay.dart' show SubtitleStyle;

/// Dark-glass bottom sheets used by the player (settings, tracks, episodes,
/// streams). They belong to the app's design language; only the on-video
/// chrome follows the cinematic reference.

/// Common subtitle language codes → native names (Task 124 mandate: the
/// subtitles window groups addon results by language). Unknown codes fall
/// back to the upper-cased code itself.
const Map<String, String> kSubtitleLanguageNames = {
  'ar': 'العربية',
  'en': 'English',
  'es': 'Español',
  'fr': 'Français',
  'de': 'Deutsch',
  'it': 'Italiano',
  'pt': 'Português',
  'pt-BR': 'Português (Brasil)',
  'ru': 'Русский',
  'tr': 'Türkçe',
  'hi': 'हिन्दी',
  'ur': 'اردو',
  'fa': 'فارسی',
  'he': 'עברית',
  'ja': '日本語',
  'ko': '한국어',
  'zh': '中文',
  'id': 'Bahasa Indonesia',
  'ms': 'Bahasa Melayu',
  'th': 'ไทย',
  'vi': 'Tiếng Việt',
  'nl': 'Nederlands',
  'pl': 'Polski',
  'sv': 'Svenska',
  'no': 'Norsk',
  'da': 'Dansk',
  'fi': 'Suomi',
  'el': 'Ελληνικά',
  'uk': 'Українська',
  'cs': 'Čeština',
  'ro': 'Română',
  'hu': 'Magyar',
  'sw': 'Kiswahili',
};

String subtitleLanguageName(String code) {
  final key = code.trim();
  if (key.isEmpty) return '';
  return kSubtitleLanguageNames[key] ??
      kSubtitleLanguageNames[key.split('-').first] ??
      key.toUpperCase();
}

/// Player sheet host (spec §0-ب): phones get a full-width bottom sheet at
/// ~66% height; tablets (width ≥ 900) get a floating ~400px side panel
/// anchored to the directional END so the video stays visible.
Future<T?> showPlayerSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  final size = MediaQuery.sizeOf(context);
  if (size.width >= 900) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Player panel',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, .06),
              end: Offset.zero,
            ).animate(curved),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Material(
                  color: HorseTheme.raised.withValues(alpha: .98),
                  borderRadius: BorderRadius.circular(22),
                  clipBehavior: Clip.antiAlias,
                  elevation: 12,
                  shadowColor: Colors.black54,
                  child: SizedBox(
                    width: 400,
                    height: size.height * .86,
                    child: builder(dialogContext),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: HorseTheme.raised,
    isScrollControlled: true,
    constraints: BoxConstraints(maxHeight: size.height * .66),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: builder,
  );
}

/// Full-screen selection panel host (workstream A1): the subtitle, audio and
/// source pickers fill the ENTIRE screen on every device — width and height,
/// background extending behind the system bars while the content itself
/// respects the safe areas (SheetScaffold's SafeArea).
///
/// Implemented as a modal bottom sheet at 100% height on purpose: it gives
/// us Flutter's own drag-down-to-dismiss machinery, which already resolves
/// the swipe-vs-list-scroll conflict (dismiss only when the inner list is at
/// the top or the drag starts on non-scrolling chrome) — the exact behavior
/// the spec mandates, battle-tested instead of hand-rolled. A visible close
/// button lives in the sheet header; the video pauses for the panel's
/// lifetime (player page side) and resumes only if it was playing.
Future<T?> showPlayerFullScreenSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  final size = MediaQuery.sizeOf(context);
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: HorseTheme.raised,
    barrierColor: Colors.black54,
    isScrollControlled: true,
    useSafeArea: false,
    enableDrag: true,
    isDismissible: true,
    // Full-bleed panel: no top radius, no height cap.
    shape: const RoundedRectangleBorder(),
    constraints: BoxConstraints(maxWidth: size.width, maxHeight: size.height),
    builder: (sheetContext) => SizedBox(
      height: size.height,
      width: size.width,
      child: Material(color: HorseTheme.raised, child: builder(sheetContext)),
    ),
  );
}

class SheetScaffold extends StatelessWidget {
  const SheetScaffold({
    super.key,
    required this.title,
    required this.child,
    this.footer,
    this.headerAction,
    this.expanded = false,
  });

  final String title;
  final Widget child;
  final Widget? footer;

  /// Optional action icon shown at the top of the sheet next to the title
  /// (e.g. the subtitle-settings shortcut inside the subtitles sheet).
  final Widget? headerAction;

  /// Full-screen mode (workstream A1): the selection panels fill the whole
  /// host — the column stretches to the panel height so long lists scroll
  /// across the entire surface instead of stacking at the top.
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    // Compact geometry for short landscape phone screens (~360–412 dp tall):
    // smaller paddings, header and close target leave the list usable.
    final compact = MediaQuery.sizeOf(context).height < 520;
    final EdgeInsets insets = expanded
        ? EdgeInsets.fromLTRB(
            compact ? 14 : 18,
            compact ? 10 : 16,
            compact ? 14 : 18,
            compact ? 12 : 20,
          )
        : const EdgeInsets.fromLTRB(18, 16, 18, 20);
    final header = Row(
      children: [
        Text(
          title,
          style: compact && expanded
              ? Theme.of(context).textTheme.titleMedium
              : Theme.of(context).textTheme.titleLarge,
        ),
        const Spacer(),
        if (headerAction != null) ...[
          headerAction!,
          const SizedBox(width: 8),
        ],
        InkWell(
          customBorder: const CircleBorder(),
          onTap: () => Navigator.of(context).pop(),
          child: SizedBox(
            width: compact && expanded ? 30 : 34,
            height: compact && expanded ? 30 : 34,
            child: Icon(
              Icons.close_rounded,
              size: compact && expanded ? 17 : 18,
              color: Colors.white54,
            ),
          ),
        ),
      ],
    );
    final column = Column(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        SizedBox(height: compact && expanded ? 10 : 14),
        expanded ? Expanded(child: child) : Flexible(child: child),
        if (footer != null) ...[
          const SizedBox(height: 14),
          footer!,
        ],
      ],
    );
    return SafeArea(
      child: expanded
          ? Padding(padding: insets, child: column)
          : ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .72,
              ),
              child: Padding(padding: insets, child: column),
            ),
    );
  }
}

// ── Settings ───────────────────────────────────────────────────────────────

class PlayerSettingsSheet extends StatelessWidget {
  const PlayerSettingsSheet({
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
    final entries = [
      _SheetEntry(
        icon: Icons.graphic_eq_rounded,
        label: english ? 'Audio track' : 'المسار الصوتي',
        value: audioLabel,
        onTap: onOpenAudio,
      ),
      _SheetEntry(
        icon: Icons.subtitles_outlined,
        label: english ? 'Subtitles' : 'الترجمة',
        value: subtitleLabel,
        onTap: onOpenSubtitles,
      ),
      if (hasEpisodes)
        _SheetEntry(
          icon: Icons.format_list_bulleted_rounded,
          label: english ? 'Episodes' : 'الحلقات',
          value: '',
          onTap: onOpenEpisodes,
        ),
    ];

    return SheetScaffold(
      title: english ? 'Playback settings' : 'إعدادات التشغيل',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel(english ? 'Speed' : 'السرعة'),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 2.6,
              children: [
                for (final value in _speeds)
                  _SelectChip(
                    label: '${value == 1.0 ? '1' : value}×',
                    selected: (speed - value).abs() < .01,
                    onTap: () => onSpeed(value),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _SectionLabel(english ? 'Video fit' : 'ملاءمة الفيديو'),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 2.2,
              children: [
                _SelectChip(
                  label: english ? 'Fit' : 'احتواء',
                  selected: fit == BoxFit.contain,
                  onTap: () => onFit(BoxFit.contain),
                ),
                _SelectChip(
                  label: english ? 'Fill' : 'ملء',
                  selected: fit == BoxFit.cover,
                  onTap: () => onFit(BoxFit.cover),
                ),
                _SelectChip(
                  label: english ? 'Stretch' : 'تمديد',
                  selected: fit == BoxFit.fill,
                  onTap: () => onFit(BoxFit.fill),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final entry in entries)
              _EntryTile(
                icon: entry.icon,
                label: entry.label,
                value: entry.value,
                onTap: entry.onTap,
              ),
          ],
        ),
      ),
    );
  }
}

class _SheetEntry {
  const _SheetEntry({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: .8,
        ),
      );
}

class _SelectChip extends StatelessWidget {
  const _SelectChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected
            ? HorseTheme.gold.withValues(alpha: .18)
            : Colors.white.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? HorseTheme.gold : Colors.white70,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      );
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: Icon(icon, size: 20, color: Colors.white70),
        title: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        subtitle: value.isEmpty
            ? null
            : Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          size: 20,
          color: Colors.white24,
        ),
        onTap: onTap,
      );
}

// ── Track pickers ──────────────────────────────────────────────────────────

class AudioTracksSheet extends StatefulWidget {
  const AudioTracksSheet({
    super.key,
    required this.english,
    required this.tracks,
    required this.selected,
    required this.onPick,
    required this.delayMs,
    required this.onDelayChanged,
    this.expanded = false,
  });

  final bool english;
  final List<AudioTrack> tracks;
  final AudioTrack selected;
  final ValueChanged<AudioTrack> onPick;

  /// Current audio delay (ms) — persisted via AppState.webSettings.
  final int delayMs;
  final ValueChanged<int> onDelayChanged;

  /// Full-screen host flag (workstream A1) — stretches the panel.
  final bool expanded;

  @override
  State<AudioTracksSheet> createState() => _AudioTracksSheetState();
}

class _AudioTracksSheetState extends State<AudioTracksSheet> {
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

  /// Spec §5: track info line — language name · codec · channels.
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

  /// Group the embedded tracks by their language tag (the dub window
  /// mirrors the subtitles window's language organization).
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
    return SheetScaffold(
      title: widget.english ? 'Audio track / dub' : 'المسار الصوتي / الدبلاج',
      expanded: widget.expanded,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: widget.tracks.isEmpty
                ? _EmptyNote(
                    widget.english
                        ? 'No selectable audio tracks in this stream. Dubs may '
                            'be available as separate sources.'
                        : 'لا توجد مسارات صوتية قابلة للاختيار في هذا المصدر. '
                            'قد يتوفر الدبلاج ضمن مصادر أخرى.',
                  )
                : ListView.separated(
                    shrinkWrap: true,
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
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
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
                              onTap: () {
                                widget.onPick(track);
                                Navigator.of(context).pop();
                              },
                            ),
                        ],
                      );
                    },
                  ),
          ),
          // Audio delay (spec §5): ±100 ms buttons, like the subtitle offset.
          const Divider(color: HorseTheme.line, height: 1),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 18,
                  color: Colors.white54,
                ),
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
                _DelayButton(
                  icon: Icons.remove_rounded,
                  english: widget.english,
                  onTap: () => _shift(-100),
                ),
                Container(
                  constraints: const BoxConstraints(minWidth: 96),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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
                _DelayButton(
                  icon: Icons.add_rounded,
                  english: widget.english,
                  onTap: () => _shift(100),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Round ± stepper button shared by the audio/subtitle delay controls.
class _DelayButton extends StatelessWidget {
  const _DelayButton({
    required this.icon,
    required this.onTap,
    required this.english,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool english;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: english ? '±100 ms' : '±100 ms',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 20, color: Colors.white70),
          ),
        ),
      );
}

/// A selectable subtitle row model: external addon subtitles carry their raw
/// language code + source addon; embedded mpv tracks carry track info.
class SubtitleChoice {
  const SubtitleChoice({
    required this.track,
    required this.groupKey,
    required this.title,
    this.subtitle,
  });

  final SubtitleTrack track;
  final String groupKey; // language code, or 'embedded'
  final String title;
  final String? subtitle;
}

/// Task 124 mandate: the subtitles window fetches from every addon across
/// ALL languages (done lazily by the page), then presents them grouped by
/// language — tapping a language chip shows only that language's results —
/// with a live search field on top.
class SubtitleTracksSheet extends StatefulWidget {
  const SubtitleTracksSheet({
    super.key,
    required this.english,
    required this.embedded,
    required this.external,
    required this.selected,
    required this.onPick,
    this.onOpenSettings,
    this.expanded = false,
  });

  final bool english;

  /// mpv-embedded subtitle tracks (inside the file itself).
  final List<SubtitleTrack> embedded;

  /// Raw addon subtitle rows: url / lang / label / addonName.
  final List<Map<String, dynamic>> external;

  final SubtitleTrack selected;
  final ValueChanged<SubtitleTrack> onPick;

  /// When set, a tuning icon appears at the top of the sheet (user request:
  /// subtitle style/timing settings reachable from the player subtitles
  /// section, not only from the app settings page).
  final VoidCallback? onOpenSettings;

  /// Full-screen host flag (workstream A1) — stretches the panel.
  final bool expanded;

  @override
  State<SubtitleTracksSheet> createState() => _SubtitleTracksSheetState();
}

class _SubtitleTracksSheetState extends State<SubtitleTracksSheet> {
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
    // Arabic first (the app's primary language), then alphabetical by
    // native name, embedded section last.
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

  /// Spec §4: expandable language list. While searching, all matching
  /// groups auto-expand; otherwise the default group (Arabic when present)
  /// starts open until the user toggles sections themselves.
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
                Icons.expand_more_rounded,
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
            ? Icons.radio_button_checked
            : (choice.track.uri
                ? Icons.cloud_download_outlined
                : Icons.radio_button_off),
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
      onTap: () {
        widget.onPick(choice.track);
        Navigator.of(context).pop();
      },
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

    return SheetScaffold(
      title: widget.english ? 'Subtitles' : 'الترجمة',
      expanded: widget.expanded,
      headerAction: widget.onOpenSettings == null
          ? null
          : Tooltip(
              message: widget.english ? 'Subtitle settings' : 'إعدادات الترجمة',
              child: IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: widget.onOpenSettings,
                icon: const Icon(Icons.tune_rounded,
                    size: 22, color: HorseTheme.gold),
              ),
            ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search — filters by title / language / addon instantly.
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, size: 16),
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
                borderSide:
                    const BorderSide(color: HorseTheme.gold, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Divider(color: HorseTheme.line, height: 14),
          Flexible(
            child: totalVisible == 0
                ? _EmptyNote(
                    query.isEmpty
                        ? (widget.english
                            ? 'No subtitles found for this title.'
                            : 'لم يتم العثور على ترجمات لهذا العمل.')
                        : (widget.english
                            ? 'No matches for your search.'
                            : 'لا توجد نتائج مطابقة لبحثك.'),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      // The persistent "Off" row leads the list (spec §4).
                      ListTile(
                        dense: true,
                        selected: offSelected,
                        leading: Icon(
                          offSelected
                              ? Icons.radio_button_checked
                              : Icons.subtitles_off_outlined,
                          size: 20,
                          color: offSelected ? HorseTheme.gold : Colors.white38,
                        ),
                        title: Text(
                          widget.english ? 'Off' : 'إيقاف',
                          style: const TextStyle(fontSize: 14),
                        ),
                        onTap: () {
                          widget.onPick(off);
                          Navigator.of(context).pop();
                        },
                      ),
                      const Divider(color: HorseTheme.line, height: 1),
                      // Expandable language sections (spec §4): tapping a
                      // language shows only that language's subtitles.
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
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 26),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white38, fontSize: 13),
        ),
      );
}

// ── Episodes ───────────────────────────────────────────────────────────────

class EpisodesSheet extends StatelessWidget {
  const EpisodesSheet({
    super.key,
    required this.english,
    required this.episodes,
    required this.currentVideoId,
    required this.onPick,
  });

  final bool english;
  final List<Map<String, dynamic>> episodes;
  final String currentVideoId;
  final ValueChanged<Map<String, dynamic>> onPick;

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: english ? 'Episodes' : 'الحلقات',
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: episodes.length,
        separatorBuilder: (_, __) =>
            const Divider(color: HorseTheme.line, height: 1),
        itemBuilder: (context, index) {
          final episode = episodes[index];
          final season = (episode['season'] as num?)?.toInt() ?? 0;
          final number = (episode['episode'] as num?)?.toInt() ?? 0;
          final name =
              (episode['name'] ?? episode['title'] ?? '').toString().trim();
          final id = (episode['id'] ?? '').toString();
          final isCurrent = id == currentVideoId;
          return ListTile(
            dense: true,
            selected: isCurrent,
            leading: Container(
              width: 44,
              alignment: Alignment.center,
              child: Text(
                number == 0 ? '$index' : '$number',
                style: TextStyle(
                  color: isCurrent ? HorseTheme.gold : Colors.white54,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            title: Text(
              name.isEmpty
                  ? (english ? 'Episode $number' : 'الحلقة $number')
                  : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: season > 0
                ? Text(
                    english ? 'S$season' : 'الموسم $season',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  )
                : null,
            trailing: isCurrent
                ? const Icon(Icons.play_arrow_rounded,
                    size: 20, color: HorseTheme.gold)
                : null,
            onTap: isCurrent
                ? null
                : () {
                    Navigator.of(context).pop();
                    onPick(episode);
                  },
          );
        },
      ),
    );
  }
}

// ── Streams ────────────────────────────────────────────────────────────────

class StreamsSheet extends StatelessWidget {
  const StreamsSheet({
    super.key,
    required this.english,
    required this.streams,
    required this.selectedIndex,
    required this.onPick,
    this.expanded = false,
  });

  final bool english;
  final List<Map<String, dynamic>> streams;
  final int selectedIndex;
  final ValueChanged<Map<String, dynamic>> onPick;

  /// Full-screen host flag (workstream A1) — stretches the panel.
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: english ? 'Choose a stream' : 'اختر مصدر التشغيل',
      expanded: expanded,
      child: ListView.separated(
        shrinkWrap: true,
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
          final isSelected = index == selectedIndex;
          return ListTile(
            dense: true,
            selected: isSelected,
            leading: Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.play_circle_outline_rounded,
              color: isSelected ? HorseTheme.gold : HorseTheme.muted,
              size: 22,
            ),
            title: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: Text(
              stream['addonName']?.toString() ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            onTap: isSelected
                ? null
                : () {
                    Navigator.of(context).pop();
                    onPick(stream);
                  },
          );
        },
      ),
    );
  }
}

// ── Subtitle style & timing (live-editing, user request) ──────────────────

/// In-player subtitle settings: text color, size, style (shadow / outline /
/// background), outline color + thickness, background opacity and the
/// timing offset (advance / delay). Every change is applied to the running
/// engine immediately (live preview over the video) and persisted on commit.
class SubtitleStyleSheet extends StatefulWidget {
  const SubtitleStyleSheet({
    super.key,
    required this.english,
    required this.onApply,
  });

  final bool english;

  /// Receives the full current values map so the player can re-apply the
  /// style (and timing) to the engine on every change.
  final ValueChanged<Map<String, Object?>> onApply;

  @override
  State<SubtitleStyleSheet> createState() => _SubtitleStyleSheetState();
}

class _SubtitleStyleSheetState extends State<SubtitleStyleSheet> {
  late final Map<String, Object?> _v = _fromSettings();

  /// Cloud-synced settings may deliver numbers as JSON strings; the strict
  /// `as num?` cast used to THROW and take the whole sheet down with it.
  /// Tolerant parse mirrors SubtitleStyle's own numeric handling.
  static num? _numOf(Object? raw) {
    if (raw is num) return raw;
    if (raw is String) return num.tryParse(raw.trim());
    return null;
  }

  Map<String, Object?> _fromSettings() {
    final st = context.read<AppState>().webSettings;
    int intVal(String key, int fallback) =>
        _numOf(st[key])?.toInt() ?? fallback;
    double doubleVal(String key, double fallback) =>
        _numOf(st[key])?.toDouble() ?? fallback;
    return <String, Object?>{
      'subFontSize': intVal('subFontSize', 28),
      'subFontColor': (st['subFontColor'] as String?) ?? '#FFFFFF',
      'subStyle': (st['subStyle'] as String?) ?? 'shadow',
      'subBorderColor': (st['subBorderColor'] as String?) ?? '#000000',
      'subBorderSize': intVal('subBorderSize', 0),
      'subBackgroundOpacity': doubleVal('subBackgroundOpacity', .35),
      'subPos': intVal('subPos', 100),
      'subtitleOffsetMs': intVal('subtitleOffsetMs', 0),
    };
  }

  void _preview(String key, Object? value) {
    setState(() => _v[key] = value);
    widget.onApply(Map<String, Object?>.of(_v));
  }

  void _commit(String key, Object? value) {
    _preview(key, value);
    final app = context.read<AppState>();
    unawaited(app.setSetting(key, value));
  }

  Color _hex(String raw) {
    final hex = raw.trim().replaceFirst('#', '');
    final parsed = int.tryParse(hex, radix: 16) ?? 0xFFFFFF;
    return Color(0xFF000000 | parsed);
  }

  String _offsetLabel(int ms) {
    if (ms == 0) return widget.english ? 'No offset' : 'بدون إزاحة';
    final abs = ms.abs();
    return ms < 0
        ? (widget.english ? 'Ahead $abs ms' : 'تقديم $abs ms')
        : (widget.english ? 'Delay $abs ms' : 'تأخير $abs ms');
  }

  /// mpv sub-pos: 100 = bottom of the frame (default), 0 = top.
  String _posLabel(int pos) {
    if (pos >= 98) return widget.english ? 'Bottom' : 'أسفل';
    if (pos <= 2) return widget.english ? 'Top' : 'أعلى';
    if (pos >= 48 && pos <= 52) return widget.english ? 'Middle' : 'منتصف';
    return '$pos%';
  }

  static const Map<String, Object?> _defaults = <String, Object?>{
    'subFontSize': 28,
    'subFontColor': '#FFFFFF',
    'subStyle': 'shadow',
    'subBorderColor': '#000000',
    'subBorderSize': 0,
    'subBackgroundOpacity': .35,
    'subPos': 100,
    'subtitleOffsetMs': 0,
  };

  /// Spec §4: "إعادة للافتراضي" — restore every value and commit it.
  void _resetToDefaults() {
    setState(() => _v.addAll(Map<String, Object?>.of(_defaults)));
    widget.onApply(Map<String, Object?>.of(_v));
    final app = context.read<AppState>();
    for (final entry in _defaults.entries) {
      unawaited(app.setSetting(entry.key, entry.value));
    }
  }

  void _shiftDelay(int delta) {
    final next =
        (((_v['subtitleOffsetMs'] as int) + delta).clamp(-5000, 5000)).toInt();
    _preview('subtitleOffsetMs', next);
    _commit('subtitleOffsetMs', next);
  }

  @override
  Widget build(BuildContext context) {
    final english = widget.english;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final options = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _colorRow(
          icon: Icons.format_color_text_rounded,
          label: english ? 'Text color' : 'لون النص',
          hex: _v['subFontColor']! as String,
          onPick: (hex) => _commit('subFontColor', hex),
        ),
        _sliderRow(
          label: english ? 'Subtitle size' : 'حجم الترجمة',
          value: (_v['subFontSize'] as int).toDouble(),
          min: 14,
          max: 44,
          divisions: 15,
          display: '${_v['subFontSize']} px',
          onChanged: (v) => _preview('subFontSize', v.round()),
          onChangeEnd: (v) => _commit('subFontSize', v.round()),
        ),
        // Position: quick chips + fine slider (spec §4: أعلى/وسط/أسفل +
        // رفع وخفض دقيق).
        _posChips(),
        _sliderRow(
          label: english ? 'Fine position' : 'رفع وخفض دقيق',
          value: (_v['subPos'] as int).toDouble(),
          min: 0,
          max: 100,
          divisions: 20,
          display: _posLabel(_v['subPos'] as int),
          onChanged: (v) => _preview('subPos', v.round()),
          onChangeEnd: (v) => _commit('subPos', v.round()),
        ),
        _styleChips(),
        _colorRow(
          icon: Icons.format_color_fill_rounded,
          label: english ? 'Outline color' : 'لون الحد',
          hex: _v['subBorderColor']! as String,
          onPick: (hex) => _commit('subBorderColor', hex),
        ),
        _sliderRow(
          label: english ? 'Outline thickness' : 'سماكة الحد',
          value: (_v['subBorderSize'] as int).toDouble(),
          min: 0,
          max: 8,
          divisions: 8,
          display: '${_v['subBorderSize']} px',
          onChanged: (v) => _preview('subBorderSize', v.round()),
          onChangeEnd: (v) => _commit('subBorderSize', v.round()),
        ),
        _sliderRow(
          label: english ? 'Background opacity' : 'شفافية الخلفية',
          value: _v['subBackgroundOpacity']! as double,
          min: 0,
          max: 1,
          divisions: 20,
          display:
              '${((_v['subBackgroundOpacity']! as double) * 100).round()}%',
          onChanged: (v) => _preview('subBackgroundOpacity', v),
          onChangeEnd: (v) => _commit('subBackgroundOpacity', v),
        ),
        // Timing offset: ±100 ms buttons (spec §4) + coarse slider.
        _delayButtons(),
        _sliderRow(
          label: english ? 'Coarse timing' : 'ضبط تقريبي',
          value: (_v['subtitleOffsetMs'] as int).toDouble(),
          min: -5000,
          max: 5000,
          divisions: 40,
          display: _offsetLabel(_v['subtitleOffsetMs']! as int),
          onChanged: (v) => _preview('subtitleOffsetMs', v.round()),
          onChangeEnd: (v) => _commit('subtitleOffsetMs', v.round()),
        ),
        const SizedBox(height: 6),
        Center(
          child: TextButton.icon(
            onPressed: _resetToDefaults,
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: Text(
              english ? 'Reset to defaults' : 'إعادة للافتراضي',
              style: const TextStyle(
                color: HorseTheme.gold,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );

    return SheetScaffold(
      title: english ? 'Subtitle settings' : 'إعدادات الترجمة',
      child: wide
          ? // Tablet (spec §0-ب): live preview beside the options.
          Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 230, child: _previewBox(widePreview: true)),
                const SizedBox(width: 16),
                Expanded(
                  child: SingleChildScrollView(child: options),
                ),
              ],
            )
          : SingleChildScrollView(
              // Phone: preview on top, options below (spec §0-ب).
              child: options,
            ),
    );
  }

  Widget _posChips() {
    final english = widget.english;
    final pos = _v['subPos'] as int;
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 2, bottom: 4),
      child: Row(
        children: [
          for (final option in [
            (0, english ? 'Top' : 'أعلى'),
            (50, english ? 'Middle' : 'وسط'),
            (100, english ? 'Bottom' : 'أسفل'),
          ])
            Expanded(
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  end: option.$1 == 100 ? 0 : 6,
                ),
                child: _SelectChip(
                  label: option.$2,
                  selected: (pos - option.$1).abs() <= 2,
                  onTap: () {
                    _preview('subPos', option.$1);
                    _commit('subPos', option.$1);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _delayButtons() {
    final ms = _v['subtitleOffsetMs'] as int;
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 4, bottom: 2),
      child: Row(
        children: [
          Text(
            widget.english ? 'Timing offset' : 'تقديم أو تأخير الترجمة',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          _DelayButton(
            english: widget.english,
            icon: Icons.remove_rounded,
            onTap: () => _shiftDelay(-100),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 92),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: HorseTheme.line),
            ),
            child: Text(
              _offsetLabel(ms),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: HorseTheme.gold,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _DelayButton(
            english: widget.english,
            icon: Icons.add_rounded,
            onTap: () => _shiftDelay(100),
          ),
        ],
      ),
    );
  }

  // ── Pieces ────────────────────────────────────────────────────────────────

  Widget _previewBox({bool widePreview = false}) {
    if (widePreview) return _previewBoxInner(height: 300);
    return _previewBoxInner(height: 96);
  }

  Widget _previewBoxInner({required double height}) {
    final text =
        widget.english ? 'Subtitle sample — Noor' : 'مثال نص الترجمة — Noor';
    final fontSize = ((_v['subFontSize']! as int).clamp(12, 26)).toDouble();
    final color = _hex(_v['subFontColor']! as String);
    final borderColor = _hex(_v['subBorderColor']! as String);
    final style = _v['subStyle']! as String;
    final opacity = (_v['subBackgroundOpacity']! as double).clamp(0.0, 1.0);
    final stroke =
        ((_v['subBorderSize']! as int) * 1.5).clamp(1.0, 7.0).toDouble();

    Widget content;
    switch (style) {
      case 'box':
        content = Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          color: Colors.black.withValues(alpha: opacity),
          child: Text(
            text,
            style: TextStyle(
              fontSize: fontSize,
              color: color,
              fontFamily: SubtitleStyle.subtitleFontFamily,
            ),
          ),
        );
        break;
      case 'outline':
        content = Stack(
          alignment: Alignment.center,
          children: [
            Text(
              text,
              style: TextStyle(
                fontSize: fontSize,
                fontFamily: SubtitleStyle.subtitleFontFamily,
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = stroke
                  ..color = borderColor,
              ),
            ),
            Text(
              text,
              style: TextStyle(
                fontSize: fontSize,
                color: color,
                fontFamily: SubtitleStyle.subtitleFontFamily,
              ),
            ),
          ],
        );
        break;
      default: // shadow
        content = Text(
          text,
          style: TextStyle(
            fontSize: fontSize,
            color: color,
            fontFamily: SubtitleStyle.subtitleFontFamily,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: .9),
                blurRadius: 4,
                offset: const Offset(2, 2),
              ),
            ],
          ),
        );
    }

    final pos = (_v['subPos']! as int).clamp(0, 100);
    // Map mpv sub-pos (0=top .. 100=bottom) onto the preview box.
    final vertical = Alignment(0, (pos / 50.0) - 1.0);
    return Container(
      height: height,
      width: double.infinity,
      alignment: vertical,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF43494C), Color(0xFF14171A)],
        ),
        border: Border.all(color: HorseTheme.line),
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: content),
      ),
    );
  }

  Widget _colorRow({
    required IconData icon,
    required String label,
    required String hex,
    required ValueChanged<String> onPick,
  }) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: Icon(icon, size: 20, color: Colors.white70),
        title: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        trailing: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: _hex(hex),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24, width: 1.5),
          ),
        ),
        onTap: () async {
          final picked = await showNoorColorPicker(
            context,
            initialHex: hex,
            title: label,
            english: widget.english,
          );
          if (picked != null && mounted) onPick(picked);
        },
      );

  Widget _sliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) =>
      Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(display,
                    style: const TextStyle(
                        color: HorseTheme.gold,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ],
            ),
            Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              label: display,
              activeColor: HorseTheme.gold,
              inactiveColor: Colors.white12,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ],
        ),
      );

  Widget _styleChips() => Padding(
        padding: const EdgeInsetsDirectional.only(top: 2, bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.english ? 'Subtitle style' : 'نمط الترجمة',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final option in [
                  ('shadow', widget.english ? 'Shadow' : 'ظل'),
                  ('outline', widget.english ? 'Outline' : 'حد خارجي'),
                  ('box', widget.english ? 'Background' : 'خلفية'),
                ])
                  Expanded(
                    child: Padding(
                      padding: EdgeInsetsDirectional.only(
                          end: option.$1 == 'box' ? 0 : 6),
                      child: _SelectChip(
                        label: option.$2,
                        selected: _v['subStyle'] == option.$1,
                        onTap: () => _commit('subStyle', option.$1),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
}
