import 'package:nova_mobile/l10n/nova_strings.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/state/app_state.dart';
import '../../../core/theme/nova_theme.dart';
import '../../../shared/widgets/color_picker_dialog.dart';
import '../engine/playback_engine.dart';
import 'subtitle_overlay.dart' show SubtitleStyle;

/// Dark-glass bottom sheets used by the player (settings, episodes,
/// subtitle style). They belong to the app's design language; the on-video
/// chrome follows the cinematic reference, and the subtitle / audio /
/// source pickers live in the RIGHT-HALF side panel
/// (widgets/player_side_panel.dart, Task 139 user mandate).

/// Common subtitle language codes → native names (Task 124 mandate: the
/// subtitles window groups addon results by language). Unknown codes fall
/// back to the upper-cased code itself.
final Map<String, String> kSubtitleLanguageNames = {
  'ar': NovaStrings.lookup(false, 'arabicLanguage'),
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
  'ur': NovaStrings.lookup(false, 'urduLanguage'),
  'fa': NovaStrings.lookup(false, 'persianLanguage'),
  'he': NovaStrings.lookup(false, 'hebrewLanguage'),
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
  if (size.width >= 700 || size.width > size.height) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Theme.of(context).colorScheme.shadow.withValues(alpha: .32),
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(
                  Directionality.of(context) == TextDirection.rtl ? -.06 : .06,
                  0),
              end: Offset.zero,
            ).animate(curved),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Material(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerLow
                      .withValues(alpha: .98),
                  borderRadius: BorderRadius.circular(22),
                  clipBehavior: Clip.antiAlias,
                  elevation: 12,
                  shadowColor: Theme.of(context)
                      .colorScheme
                      .shadow
                      .withValues(alpha: .32),
                  child: SizedBox(
                    width: (size.width * .48).clamp(360.0, 560.0),
                    height: size.height - 32,
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
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    isScrollControlled: true,
    constraints: BoxConstraints(maxHeight: size.height * .86),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null,
    builder: builder,
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

  /// Full-height mode: the selection panels stretch to the host height so
  /// long lists scroll across the entire surface instead of stacking at
  /// the top.
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    // Compact geometry for short landscape phone screens (~360–412 dp tall):
    // smaller paddings, header and close target leave the list usable.
    final compact = MediaQuery.sizeOf(context).height < 520;
    final EdgeInsetsGeometry insets = expanded
        ? EdgeInsetsDirectional.fromSTEB(
            compact ? 14 : 18,
            compact ? 10 : 16,
            compact ? 14 : 18,
            compact ? 12 : 20,
          )
        : const EdgeInsetsDirectional.fromSTEB(18, 16, 18, 20);
    final header = Row(
      children: [
        Expanded(
            child: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge,
        )),
        if (headerAction != null) ...[
          headerAction!,
          SizedBox(width: 8),
        ],
        InkWell(
          customBorder: CircleBorder(),
          onTap: () => Navigator.of(context).pop(),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(
              LucideIcons.x,
              size: compact && expanded ? 17 : 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
          SizedBox(height: 14),
          footer!,
        ],
      ],
    );
    return SafeArea(
      child: expanded
          ? Padding(padding: insets, child: column)
          : ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .82,
              ),
              child: Padding(padding: insets, child: column),
            ),
    );
  }
}

// ── Settings ───────────────────────────────────────────────────────────────

// Task 141 (user mandate): the playback-settings picker joined the RIGHT-HALF
// side panels — PlayerSettingsPanelBody lives in
// widgets/player_side_panel.dart. The selection chips below are shared with
// the sheets that remain.

class SheetSelectChip extends StatelessWidget {
  const SheetSelectChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Material(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant)),
          child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Center(
                      child: Text(label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(
                                  color: selected
                                      ? Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant))))),
        ),
      );
}

// ── Track pickers ──────────────────────────────────────────────────────────

// The audio / subtitle / stream pickers moved to the RIGHT-HALF side panel
// (widgets/player_side_panel.dart, Task 139 user mandate): instant open,
// in-panel loading and a header refresh button. The playback settings
// joined them in Task 141 — only the episodes and subtitle-style
// sheets remain bottom sheets here.

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

/// Round ± stepper button shared by the subtitle style sheet's delay row.
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
        message: NovaStrings.lookup(english, 'message42'),
        child: InkWell(
          customBorder: CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
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
      title: NovaStrings.lookup(english, 'message43'),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: episodes.length,
        separatorBuilder: (_, __) => Divider(
            color: Theme.of(context).colorScheme.outlineVariant, height: 1),
        itemBuilder: (context, index) {
          final episode = episodes[index];
          final season = (episode['season'] as num?)?.toInt() ?? 0;
          final number = (episode['episode'] as num?)?.toInt() ?? 0;
          final name =
              (episode['name'] ?? episode['title'] ?? '').toString().trim();
          final id = (episode['id'] ?? '').toString();
          final isCurrent = id == currentVideoId;
          return ListTile(
            dense: false,
            selected: isCurrent,
            leading: Container(
              width: 44,
              alignment: Alignment.center,
              child: Text(
                number == 0 ? '$index' : '$number',
                style: TextStyle(
                  color: isCurrent
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            title: Text(
              name.isEmpty
                  ? (NovaStrings.lookup(english, 'message44', {'p0': number}))
                  : name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14),
            ),
            subtitle: season > 0
                ? Text(
                    NovaStrings.lookup(english, 'message45', {'p0': season}),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12),
                  )
                : null,
            trailing: isCurrent
                ? Icon(LucideIcons.play,
                    size: 20, color: Theme.of(context).colorScheme.primary)
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
    if (ms == 0) return NovaStrings.lookup(widget.english, 'message46');
    final abs = ms.abs();
    return ms < 0
        ? (NovaStrings.lookup(widget.english, 'message47', {'p0': abs}))
        : (NovaStrings.lookup(widget.english, 'message48', {'p0': abs}));
  }

  /// mpv sub-pos: 100 = bottom of the frame (default), 0 = top.
  String _posLabel(int pos) {
    if (pos >= 98) return NovaStrings.lookup(widget.english, 'message49');
    if (pos <= 2) return NovaStrings.lookup(widget.english, 'message50');
    if (pos >= 48 && pos <= 52) {
      return NovaStrings.lookup(widget.english, 'message51');
    }
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
    return LayoutBuilder(builder: (context, constraints) {
      final english = widget.english;
      final wide = constraints.maxWidth >= 700;
      final options = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _colorRow(
            icon: LucideIcons.type,
            label: NovaStrings.lookup(english, 'message52'),
            hex: _v['subFontColor']! as String,
            onPick: (hex) => _commit('subFontColor', hex),
          ),
          _sliderRow(
            label: NovaStrings.lookup(english, 'message53'),
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
            label: NovaStrings.lookup(english, 'message54'),
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
            icon: LucideIcons.paintBucket,
            label: NovaStrings.lookup(english, 'message55'),
            hex: _v['subBorderColor']! as String,
            onPick: (hex) => _commit('subBorderColor', hex),
          ),
          _sliderRow(
            label: NovaStrings.lookup(english, 'message56'),
            value: (_v['subBorderSize'] as int).toDouble(),
            min: 0,
            max: 8,
            divisions: 8,
            display: '${_v['subBorderSize']} px',
            onChanged: (v) => _preview('subBorderSize', v.round()),
            onChangeEnd: (v) => _commit('subBorderSize', v.round()),
          ),
          _sliderRow(
            label: NovaStrings.lookup(english, 'message57'),
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
            label: NovaStrings.lookup(english, 'message58'),
            value: (_v['subtitleOffsetMs'] as int).toDouble(),
            min: -5000,
            max: 5000,
            divisions: 40,
            display: _offsetLabel(_v['subtitleOffsetMs']! as int),
            onChanged: (v) => _preview('subtitleOffsetMs', v.round()),
            onChangeEnd: (v) => _commit('subtitleOffsetMs', v.round()),
          ),
          SizedBox(height: 6),
          Center(
            child: TextButton.icon(
              onPressed: _resetToDefaults,
              icon: Icon(LucideIcons.rotateCcw, size: 18),
              label: Text(
                NovaStrings.lookup(english, 'message59'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      );

      return SheetScaffold(
        title: NovaStrings.lookup(english, 'message60'),
        child: wide
            ? // Tablet (spec §0-ب): live preview beside the options.
            Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 230, child: _previewBox(widePreview: true)),
                  SizedBox(width: 16),
                  Expanded(
                    child: SingleChildScrollView(child: options),
                  ),
                ],
              )
            : SingleChildScrollView(
                // Phone: preview on top, options below (spec §0-ب).
                child: Column(children: [
                  _previewBox(),
                  const SizedBox(height: 24),
                  options
                ]),
              ),
      );
    });
  }

  Widget _posChips() {
    final english = widget.english;
    final pos = _v['subPos'] as int;
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 2, bottom: 4),
      child: Row(
        children: [
          for (final option in [
            (0, NovaStrings.lookup(english, 'message50')),
            (50, NovaStrings.lookup(english, 'message61')),
            (100, NovaStrings.lookup(english, 'message49')),
          ])
            Expanded(
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  end: option.$1 == 100 ? 0 : 6,
                ),
                child: SheetSelectChip(
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

  Widget _delayButtons() => Padding(
      padding: const EdgeInsetsDirectional.only(top: 16, bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(NovaStrings.lookup(widget.english, 'message62'),
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(children: [
          _DelayButton(
              english: widget.english,
              icon: LucideIcons.minus,
              onTap: () => _shiftDelay(-100)),
          Expanded(
              child: Text(_offsetLabel(_v['subtitleOffsetMs'] as int),
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.primary))),
          _DelayButton(
              english: widget.english,
              icon: LucideIcons.plus,
              onTap: () => _shiftDelay(100)),
        ]),
      ]));

  // ── Pieces ────────────────────────────────────────────────────────────────

  Widget _previewBox({bool widePreview = false}) {
    if (widePreview) return _previewBoxInner(height: 300);
    return _previewBoxInner(height: 96);
  }

  Widget _previewBoxInner({required double height}) {
    final text = NovaStrings.lookup(widget.english, 'message63');
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
          color: NovaColors.ink.withValues(alpha: opacity),
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
                color: NovaColors.ink.withValues(alpha: .9),
                blurRadius: 4,
                offset: Offset(2, 2),
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
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [NovaColors.graphite, NovaColors.ink],
        ),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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
        dense: false,
        leading: Icon(icon,
            size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
        title: Text(label,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
        trailing: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: _hex(hex),
            shape: BoxShape.circle,
            border: Border.all(
                color: Theme.of(context).colorScheme.outline, width: 1.5),
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
                Expanded(
                    child: Text(label,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w600))),
                const SizedBox(width: 12),
                Text(display,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
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
              activeColor: Theme.of(context).colorScheme.primary,
              inactiveColor: Theme.of(context).colorScheme.outlineVariant,
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
            Text(NovaStrings.lookup(widget.english, 'message64'),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Row(
              children: [
                for (final option in [
                  ('shadow', NovaStrings.lookup(widget.english, 'message65')),
                  ('outline', NovaStrings.lookup(widget.english, 'message66')),
                  ('box', NovaStrings.lookup(widget.english, 'message67')),
                ])
                  Expanded(
                    child: Padding(
                      padding: EdgeInsetsDirectional.only(
                          end: option.$1 == 'box' ? 0 : 6),
                      child: SheetSelectChip(
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
