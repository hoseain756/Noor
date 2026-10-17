import 'package:nova_mobile/l10n/nova_strings.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/app_state.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../shared/widgets/color_picker_dialog.dart';
import 'widgets/settings_tiles.dart';

enum _Control { toggle, select, multiple, slider, color }

class _Option {
  const _Option(this.value, this.arabic, this.english);
  final String value;
  final String arabic;
  final String english;
}

class _Preference {
  const _Preference({
    required this.key,
    required this.arabic,
    required this.english,
    required this.control,
    this.options = const [],
    this.min = 0,
    this.max = 100,
    this.step = 1,
    this.suffix = '',
  });

  final String key;
  final String arabic;
  final String english;
  final _Control control;
  final List<_Option> options;
  final double min;
  final double max;
  final double step;
  final String suffix;
}

final _playerPreferences = <_Preference>[
  // Task 139: 'instantPlay' removed — watching ALWAYS lands on the sources
  // page now (user mandate); the legacy stored key stays harmless in prefs.
  _Preference(
      key: 'autoPlayNextEpisode',
      arabic: NovaStrings.lookup(false, 'message728'),
      english: NovaStrings.lookup(true, 'message728'),
      control: _Control.toggle),
  _Preference(
      key: 'resumePlayback',
      arabic: NovaStrings.lookup(false, 'message729'),
      english: NovaStrings.lookup(true, 'message729'),
      control: _Control.toggle),
  _Preference(
      key: 'resumePrompt',
      arabic: NovaStrings.lookup(false, 'message730'),
      english: NovaStrings.lookup(true, 'message730'),
      control: _Control.toggle),
  _Preference(
      key: 'playerConfirmLeave',
      arabic: NovaStrings.lookup(false, 'message731'),
      english: NovaStrings.lookup(true, 'message731'),
      control: _Control.toggle),
  _Preference(
      key: 'seekBackStepSec',
      arabic: NovaStrings.lookup(false, 'message732'),
      english: NovaStrings.lookup(true, 'message732'),
      control: _Control.select,
      suffix: 's',
      options: [
        _Option('5', NovaStrings.lookup(false, 'message733'),
            NovaStrings.lookup(true, 'message733')),
        _Option('10', NovaStrings.lookup(false, 'message734'),
            NovaStrings.lookup(true, 'message734')),
        _Option('15', NovaStrings.lookup(false, 'message735'),
            NovaStrings.lookup(true, 'message735')),
        _Option('30', NovaStrings.lookup(false, 'message736'),
            NovaStrings.lookup(true, 'message736'))
      ]),
  _Preference(
      key: 'seekForwardStepSec',
      arabic: NovaStrings.lookup(false, 'message737'),
      english: NovaStrings.lookup(true, 'message737'),
      control: _Control.select,
      suffix: 's',
      options: [
        _Option('5', NovaStrings.lookup(false, 'message733'),
            NovaStrings.lookup(true, 'message733')),
        _Option('10', NovaStrings.lookup(false, 'message734'),
            NovaStrings.lookup(true, 'message734')),
        _Option('15', NovaStrings.lookup(false, 'message735'),
            NovaStrings.lookup(true, 'message735')),
        _Option('30', NovaStrings.lookup(false, 'message736'),
            NovaStrings.lookup(true, 'message736'))
      ]),
  _Preference(
      key: 'defaultAudioLanguage',
      arabic: NovaStrings.lookup(false, 'message738'),
      english: NovaStrings.lookup(true, 'message738'),
      control: _Control.select,
      options: [
        _Option('source', NovaStrings.lookup(false, 'message739'),
            NovaStrings.lookup(true, 'message739')),
        _Option('ar', NovaStrings.lookup(false, 'arabicLanguage'),
            NovaStrings.lookup(true, 'arabicLanguage')),
        _Option('en', NovaStrings.lookup(false, 'message740'),
            NovaStrings.lookup(true, 'message740')),
        _Option('ja', NovaStrings.lookup(false, 'message741'),
            NovaStrings.lookup(true, 'message741')),
        _Option('original', NovaStrings.lookup(false, 'message742'),
            NovaStrings.lookup(true, 'message742'))
      ]),
  _Preference(
      key: 'preferredQuality',
      arabic: NovaStrings.lookup(false, 'message743'),
      english: NovaStrings.lookup(true, 'message743'),
      control: _Control.select,
      options: [
        _Option('auto', NovaStrings.lookup(false, 'message5'),
            NovaStrings.lookup(true, 'message5')),
        _Option('2160p', NovaStrings.lookup(false, 'message744'),
            NovaStrings.lookup(true, 'message744')),
        _Option('1080p', NovaStrings.lookup(false, 'message745'),
            NovaStrings.lookup(true, 'message745')),
        _Option('720p', NovaStrings.lookup(false, 'message746'),
            NovaStrings.lookup(true, 'message746')),
        _Option('480p', NovaStrings.lookup(false, 'message747'),
            NovaStrings.lookup(true, 'message747'))
      ]),
  _Preference(
      key: 'videoFill',
      arabic: NovaStrings.lookup(false, 'message83'),
      english: NovaStrings.lookup(true, 'message83'),
      control: _Control.select,
      options: [
        _Option('fit', NovaStrings.lookup(false, 'message84'),
            NovaStrings.lookup(true, 'message84')),
        _Option('fill', NovaStrings.lookup(false, 'message748'),
            NovaStrings.lookup(true, 'message748')),
        _Option('zoom', NovaStrings.lookup(false, 'message749'),
            NovaStrings.lookup(true, 'message749'))
      ]),
  _Preference(
      key: 'showQualityInfo',
      arabic: NovaStrings.lookup(false, 'message750'),
      english: NovaStrings.lookup(true, 'message750'),
      control: _Control.toggle),
  _Preference(
      key: 'customPlaybackSpeeds',
      arabic: NovaStrings.lookup(false, 'message751'),
      english: NovaStrings.lookup(true, 'message751'),
      control: _Control.multiple,
      options: [
        _Option('0.75', NovaStrings.lookup(false, 'message752'),
            NovaStrings.lookup(true, 'message752')),
        _Option('1', NovaStrings.lookup(false, 'message753'),
            NovaStrings.lookup(true, 'message753')),
        _Option('1.25', NovaStrings.lookup(false, 'message754'),
            NovaStrings.lookup(true, 'message754')),
        _Option('1.5', NovaStrings.lookup(false, 'message755'),
            NovaStrings.lookup(true, 'message755')),
        _Option('1.75', NovaStrings.lookup(false, 'message756'),
            NovaStrings.lookup(true, 'message756')),
        _Option('2', NovaStrings.lookup(false, 'message757'),
            NovaStrings.lookup(true, 'message757'))
      ]),
  _Preference(
      key: 'pickerLayout',
      arabic: NovaStrings.lookup(false, 'message758'),
      english: NovaStrings.lookup(true, 'message758'),
      control: _Control.select,
      options: [
        _Option('stremio', NovaStrings.lookup(false, 'message759'),
            NovaStrings.lookup(true, 'message759')),
        _Option('condensed', NovaStrings.lookup(false, 'message424'),
            NovaStrings.lookup(true, 'message424'))
      ]),
  _Preference(
      key: 'streamSort',
      arabic: NovaStrings.lookup(false, 'message760'),
      english: NovaStrings.lookup(true, 'message760'),
      control: _Control.select,
      options: [
        _Option('addon', NovaStrings.lookup(false, 'message761'),
            NovaStrings.lookup(true, 'message761')),
        _Option('score', NovaStrings.lookup(false, 'message762'),
            NovaStrings.lookup(true, 'message762'))
      ]),
  _Preference(
      key: 'playableOnly',
      arabic: NovaStrings.lookup(false, 'message763'),
      english: NovaStrings.lookup(true, 'message763'),
      control: _Control.toggle),
  _Preference(
      key: 'preferH264',
      arabic: NovaStrings.lookup(false, 'message764'),
      english: NovaStrings.lookup(true, 'message764'),
      control: _Control.toggle),
  _Preference(
      key: 'p2pEnabled',
      arabic: NovaStrings.lookup(false, 'message765'),
      english: NovaStrings.lookup(true, 'message765'),
      control: _Control.toggle),
];

final _subtitlePreferences = <_Preference>[
  _Preference(
      key: 'preferredSubLangs',
      arabic: NovaStrings.lookup(false, 'message766'),
      english: NovaStrings.lookup(true, 'message766'),
      control: _Control.multiple,
      options: [
        _Option('Arabic', NovaStrings.lookup(false, 'arabicLanguage'),
            NovaStrings.lookup(true, 'arabicLanguage')),
        _Option('English', NovaStrings.lookup(false, 'message740'),
            NovaStrings.lookup(true, 'message740')),
        _Option('Japanese', NovaStrings.lookup(false, 'message741'),
            NovaStrings.lookup(true, 'message741')),
        _Option('French', NovaStrings.lookup(false, 'message767'),
            NovaStrings.lookup(true, 'message767')),
        _Option('Spanish', NovaStrings.lookup(false, 'message768'),
            NovaStrings.lookup(true, 'message768'))
      ]),
  _Preference(
      key: 'subtitleTranslationLanguage',
      arabic: NovaStrings.lookup(false, 'message769'),
      english: NovaStrings.lookup(true, 'message769'),
      control: _Control.select,
      options: [
        _Option('off', NovaStrings.lookup(false, 'message770'),
            NovaStrings.lookup(true, 'message770')),
        _Option('ar', NovaStrings.lookup(false, 'arabicLanguage'),
            NovaStrings.lookup(true, 'arabicLanguage')),
        _Option('en', NovaStrings.lookup(false, 'message740'),
            NovaStrings.lookup(true, 'message740')),
        _Option('ja', NovaStrings.lookup(false, 'message741'),
            NovaStrings.lookup(true, 'message741')),
        _Option('fr', NovaStrings.lookup(false, 'message767'),
            NovaStrings.lookup(true, 'message767')),
        _Option('es', NovaStrings.lookup(false, 'message768'),
            NovaStrings.lookup(true, 'message768'))
      ]),
  _Preference(
      key: 'subtitlesOffByDefault',
      arabic: NovaStrings.lookup(false, 'message771'),
      english: NovaStrings.lookup(true, 'message771'),
      control: _Control.toggle),
  _Preference(
      key: 'subFontSize',
      arabic: NovaStrings.lookup(false, 'message53'),
      english: NovaStrings.lookup(true, 'message53'),
      control: _Control.slider,
      min: 14,
      max: 44,
      step: 2,
      suffix: ' px'),
  _Preference(
      key: 'subFontColor',
      arabic: NovaStrings.lookup(false, 'message52'),
      english: NovaStrings.lookup(true, 'message52'),
      control: _Control.color),
  _Preference(
      key: 'subStyle',
      arabic: NovaStrings.lookup(false, 'message64'),
      english: NovaStrings.lookup(true, 'message64'),
      control: _Control.select,
      options: [
        _Option('shadow', NovaStrings.lookup(false, 'message65'),
            NovaStrings.lookup(true, 'message65')),
        _Option('outline', NovaStrings.lookup(false, 'message66'),
            NovaStrings.lookup(true, 'message66')),
        _Option('box', NovaStrings.lookup(false, 'message67'),
            NovaStrings.lookup(true, 'message67'))
      ]),
  _Preference(
      key: 'subBorderColor',
      arabic: NovaStrings.lookup(false, 'message55'),
      english: NovaStrings.lookup(true, 'message55'),
      control: _Control.color),
  _Preference(
      key: 'subBorderSize',
      arabic: NovaStrings.lookup(false, 'message772'),
      english: NovaStrings.lookup(true, 'message772'),
      control: _Control.slider,
      min: 0,
      max: 8,
      step: 1,
      suffix: ' px'),
  _Preference(
      key: 'subBackgroundOpacity',
      arabic: NovaStrings.lookup(false, 'message57'),
      english: NovaStrings.lookup(true, 'message57'),
      control: _Control.slider,
      min: 0,
      max: 1,
      step: .05),
  _Preference(
      key: 'subtitleOffsetMs',
      arabic: NovaStrings.lookup(false, 'message773'),
      english: NovaStrings.lookup(true, 'message773'),
      control: _Control.slider,
      min: -5000,
      max: 5000,
      step: 250,
      suffix: ' ms'),
];

class SettingsPreferencesPage extends StatelessWidget {
  const SettingsPreferencesPage({super.key, required this.subtitles});
  final bool subtitles;
  @override
  Widget build(BuildContext context) {
    context.select<AppState, bool>((app) => app.english);
    final app = context.read<AppState>();
    final rows = subtitles ? _subtitlePreferences : _playerPreferences;
    final groups = subtitles
        ? <String, List<String>>{
            app.tr('message496'): [
              'preferredSubLangs',
              'subtitleTranslationLanguage',
              'subtitlesOffByDefault'
            ],
            app.tr('message497'): [
              'subFontSize',
              'subFontColor',
              'subStyle',
              'subBorderColor',
              'subBorderSize',
              'subBackgroundOpacity'
            ],
            app.tr('message498'): ['subtitleOffsetMs'],
          }
        : <String, List<String>>{
            app.tr('message499'): [
              'autoPlayNextEpisode',
              'resumePlayback',
              'resumePrompt',
              'playerConfirmLeave'
            ],
            app.tr('message500'): [
              'defaultAudioLanguage',
              'preferredQuality',
              'videoFill',
              'showQualityInfo'
            ],
            app.tr('message501'): [
              'seekBackStepSec',
              'seekForwardStepSec',
              'customPlaybackSpeeds'
            ],
            app.tr('message502'): [
              'pickerLayout',
              'streamSort',
              'playableOnly',
              'preferH264',
              'p2pEnabled'
            ],
          };
    return Scaffold(
      appBar: AppBar(
          title: Text(subtitles ? app.tr('message7') : app.tr('message453'))),
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView(
                padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 48),
                children: [
                  SettingsPageIntro(
                      title: subtitles
                          ? app.tr('message503')
                          : app.tr('message504'),
                      description: subtitles
                          ? app.tr('message505')
                          : app.tr('message506'),
                      icon: subtitles
                          ? LucideIcons.captions
                          : LucideIcons.circlePlay),
                  for (final group in groups.entries)
                    SettingsContentSection(
                        title: group.key,
                        children: group.value
                            .map((key) => _PreferenceTile(
                                item: rows.firstWhere((row) => row.key == key)))
                            .toList()),
                  SettingsInfoBanner(
                      message: subtitles
                          ? app.tr('message507')
                          : app.tr('message508')),
                ],
              ))),
    );
  }
}

class _PreferenceTile extends StatelessWidget {
  const _PreferenceTile({required this.item});
  final _Preference item;

  @override
  Widget build(BuildContext context) {
    // Task 122-c F4: per-tile scoped select (english + this key's value) —
    // one tile rebuilds per change instead of the whole page.
    final (english, value) = context.select<AppState, (bool, dynamic)>(
        (app) => (app.english, app.webSettings[item.key]));
    final title = english ? item.english : item.arabic;
    final trailing = switch (item.control) {
      _Control.toggle => SettingsOptimisticSwitch(
          value: value == true,
          onChanged: (next) =>
              context.read<AppState>().setSetting(item.key, next),
        ),
      _Control.select => _valueButton(context, value, english),
      _Control.multiple => _valueButton(context, value, english),
      _Control.slider => _valueButton(context, value, english),
      _Control.color => _colorValue(context, value?.toString() ?? '#FFFFFF'),
    };
    if (item.control == _Control.toggle) {
      return SettingsOptimisticSwitchTile(
          title: Text(title),
          value: value == true,
          onChanged: (next) =>
              context.read<AppState>().setSetting(item.key, next));
    }
    return InkWell(
        onTap: () => _edit(context, item, value),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 16, 18),
          child: Row(children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  if (item.control != _Control.color)
                    Text(_formatValue(item, value, english),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.secondary)),
                ])),
            if (item.control == _Control.color) trailing,
            const SizedBox(width: 16),
            Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? LucideIcons.chevronLeft
                    : LucideIcons.chevronRight,
                size: 18),
          ]),
        ));
  }

  Widget _valueButton(BuildContext context, dynamic value, bool english) =>
      TextButton(
        onPressed: () => _edit(context, item, value),
        child: Text(_formatValue(item, value, english),
            textAlign: TextAlign.end,
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
      );

  Widget _colorValue(BuildContext context, String value) {
    final color = _parseColor(value);
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant, width: 1.5),
      ),
    );
  }

  Future<void> _edit(
      BuildContext context, _Preference item, dynamic current) async {
    final app = context.read<AppState>();
    final english = app.english;
    if (item.control == _Control.select) {
      final selected = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Theme.of(context).colorScheme.surface,
        showDragHandle: true,
        isScrollControlled: true,
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(english ? item.english : item.arabic,
                      style: Theme.of(context).textTheme.titleLarge)),
              for (final option in item.options)
                ListTile(
                  leading: Icon(
                    current?.toString() == option.value
                        ? LucideIcons.circleDot
                        : LucideIcons.circle,
                    color: current?.toString() == option.value
                        ? Theme.of(context).colorScheme.secondary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  title: Text(english ? option.english : option.arabic),
                  onTap: () => Navigator.pop(context, option.value),
                ),
            ],
          ),
        ),
      );
      if (selected != null) {
        await app.setSetting(item.key, _typedValue(item.key, selected));
      }
      return;
    }
    if (item.control == _Control.multiple) {
      final currentValues =
          (current as List? ?? const []).map((e) => e.toString()).toSet();
      final selected = await showDialog<Set<String>>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(english ? item.english : item.arabic),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final option in item.options)
                    CheckboxListTile(
                      value: currentValues.contains(option.value),
                      title: Text(english ? option.english : option.arabic),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (checked) => setState(() {
                        if (checked == true) {
                          currentValues.add(option.value);
                        } else {
                          currentValues.remove(option.value);
                        }
                      }),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(NovaStrings.lookup(english, 'cancel'))),
              FilledButton(
                  onPressed: () => Navigator.pop(context, currentValues),
                  child: Text(NovaStrings.lookup(english, 'save')))
            ],
          ),
        ),
      );
      if (selected != null) {
        await app.setSetting(
            item.key,
            item.key == 'customPlaybackSpeeds'
                ? selected.map(double.parse).toList()
                : selected.toList());
      }
      return;
    }
    if (item.control == _Control.slider) {
      var sliderValue = (current as num?)?.toDouble() ?? item.min;
      final next = await showDialog<double>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(english ? item.english : item.arabic),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Slider(
                    value: sliderValue.clamp(item.min, item.max),
                    min: item.min,
                    max: item.max,
                    divisions: ((item.max - item.min) / item.step).round(),
                    label: _shownNumber(sliderValue, item),
                    onChanged: (next) => setState(() => sliderValue = next)),
                Text(_shownNumber(sliderValue, item)),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(NovaStrings.lookup(english, 'cancel'))),
              FilledButton(
                  onPressed: () => Navigator.pop(context, sliderValue),
                  child: Text(NovaStrings.lookup(english, 'save')))
            ],
          ),
        ),
      );
      if (next != null) {
        await app.setSetting(
            item.key, item.key == 'subBackgroundOpacity' ? next : next.round());
      }
      return;
    }
    if (item.control == _Control.color) {
      // Full picker: wheel + hex code + presets (user request).
      final picked = await showNoorColorPicker(
        context,
        initialHex: current?.toString() ?? '#FFFFFF',
        title: english ? item.english : item.arabic,
        english: english,
      );
      if (picked != null) {
        await app.setSetting(item.key, picked);
      }
    }
  }
}

String _formatValue(_Preference item, dynamic value, bool english) {
  if (value is List) {
    if (value.isEmpty) return NovaStrings.lookup(english, 'message509');
    return value.map((entry) {
      final option = item.options
          .where((entryOption) => entryOption.value == entry.toString())
          .firstOrNull;
      return option == null
          ? entry.toString()
          : (english ? option.english : option.arabic);
    }).join(' · ');
  }
  final option = item.options
      .where((entry) => entry.value == value?.toString())
      .firstOrNull;
  if (option != null) return english ? option.english : option.arabic;
  if (item.control == _Control.slider && value is num) {
    return _shownNumber(value.toDouble(), item);
  }
  return value?.toString() ?? (NovaStrings.lookup(english, 'message2'));
}

String _shownNumber(double value, _Preference item) {
  final shown = item.key == 'subBackgroundOpacity'
      ? '${(value * 100).round()}%'
      : value.round().toString();
  return '$shown${item.suffix}';
}

dynamic _typedValue(String key, String raw) => switch (key) {
      'seekBackStepSec' || 'seekForwardStepSec' => int.parse(raw),
      _ => raw,
    };

Color _parseColor(String value) {
  final normalized = value.replaceFirst('#', '');
  final parsed = int.tryParse(normalized, radix: 16) ?? 0xFFFFFF;
  return Color(0xFF000000 | parsed);
}
