import 'package:noor_mobile/l10n/nova_strings.dart';
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

const _playerPreferences = <_Preference>[
  // Task 139: 'instantPlay' removed — watching ALWAYS lands on the sources
  // page now (user mandate); the legacy stored key stays harmless in prefs.
  _Preference(
      key: 'autoPlayNextEpisode',
      arabic: 'تشغيل الحلقة التالية تلقائيًا',
      english: 'Autoplay next episode',
      control: _Control.toggle),
  _Preference(
      key: 'resumePlayback',
      arabic: 'استئناف من آخر موضع',
      english: 'Resume playback',
      control: _Control.toggle),
  _Preference(
      key: 'resumePrompt',
      arabic: 'السؤال قبل الاستئناف',
      english: 'Ask before resuming',
      control: _Control.toggle),
  _Preference(
      key: 'playerConfirmLeave',
      arabic: 'تأكيد الخروج من المشغّل',
      english: 'Confirm before leaving',
      control: _Control.toggle),
  _Preference(
      key: 'seekBackStepSec',
      arabic: 'مقدار الرجوع',
      english: 'Seek backward step',
      control: _Control.select,
      suffix: 's',
      options: [
        _Option('5', '٥ ثوانٍ', '5 sec'),
        _Option('10', '١٠ ثوانٍ', '10 sec'),
        _Option('15', '١٥ ثانية', '15 sec'),
        _Option('30', '٣٠ ثانية', '30 sec')
      ]),
  _Preference(
      key: 'seekForwardStepSec',
      arabic: 'مقدار التقديم',
      english: 'Seek forward step',
      control: _Control.select,
      suffix: 's',
      options: [
        _Option('5', '٥ ثوانٍ', '5 sec'),
        _Option('10', '١٠ ثوانٍ', '10 sec'),
        _Option('15', '١٥ ثانية', '15 sec'),
        _Option('30', '٣٠ ثانية', '30 sec')
      ]),
  _Preference(
      key: 'defaultAudioLanguage',
      arabic: 'لغة الصوت المفضلة',
      english: 'Default audio language',
      control: _Control.select,
      options: [
        _Option('source', 'لغة المصدر', 'Source language'),
        _Option('ar', 'العربية', 'Arabic'),
        _Option('en', 'الإنجليزية', 'English'),
        _Option('ja', 'اليابانية', 'Japanese'),
        _Option('original', 'الصوت الأصلي', 'Original audio')
      ]),
  _Preference(
      key: 'preferredQuality',
      arabic: 'جودة المصدر المفضلة',
      english: 'Preferred source quality',
      control: _Control.select,
      options: [
        _Option('auto', 'تلقائي', 'Auto'),
        _Option('2160p', '4K', '4K'),
        _Option('1080p', '1080p', '1080p'),
        _Option('720p', '720p', '720p'),
        _Option('480p', '480p', '480p')
      ]),
  _Preference(
      key: 'videoFill',
      arabic: 'ملاءمة الفيديو',
      english: 'Video fit',
      control: _Control.select,
      options: [
        _Option('fit', 'احتواء', 'Fit'),
        _Option('fill', 'ملء الشاشة', 'Fill'),
        _Option('zoom', 'تكبير', 'Zoom')
      ]),
  _Preference(
      key: 'showQualityInfo',
      arabic: 'إظهار معلومات الجودة',
      english: 'Show quality information',
      control: _Control.toggle),
  _Preference(
      key: 'customPlaybackSpeeds',
      arabic: 'سرعات التشغيل',
      english: 'Playback speeds',
      control: _Control.multiple,
      options: [
        _Option('0.75', '0.75×', '0.75×'),
        _Option('1', '1×', '1×'),
        _Option('1.25', '1.25×', '1.25×'),
        _Option('1.5', '1.5×', '1.5×'),
        _Option('1.75', '1.75×', '1.75×'),
        _Option('2', '2×', '2×')
      ]),
  _Preference(
      key: 'pickerLayout',
      arabic: 'طريقة عرض المصادر',
      english: 'Stream picker layout',
      control: _Control.select,
      options: [
        _Option('stremio', 'تفصيلي', 'Detailed'),
        _Option('condensed', 'مختصر', 'Compact')
      ]),
  _Preference(
      key: 'streamSort',
      arabic: 'ترتيب المصادر',
      english: 'Stream sorting',
      control: _Control.select,
      options: [
        _Option('addon', 'حسب الإضافة', 'By add-on'),
        _Option('score', 'حسب الجودة', 'By quality')
      ]),
  _Preference(
      key: 'playableOnly',
      arabic: 'إخفاء المصادر غير المدعومة',
      english: 'Hide unsupported streams',
      control: _Control.toggle),
  _Preference(
      key: 'preferH264',
      arabic: 'تفضيل H.264',
      english: 'Prefer H.264',
      control: _Control.toggle),
  _Preference(
      key: 'p2pEnabled',
      arabic: 'مصادر التورنت عبر الخادم',
      english: 'Server torrent engine',
      control: _Control.toggle),
];

const _subtitlePreferences = <_Preference>[
  _Preference(
      key: 'preferredSubLangs',
      arabic: 'لغات الترجمة المفضلة',
      english: 'Preferred subtitle languages',
      control: _Control.multiple,
      options: [
        _Option('Arabic', 'العربية', 'Arabic'),
        _Option('English', 'الإنجليزية', 'English'),
        _Option('Japanese', 'اليابانية', 'Japanese'),
        _Option('French', 'الفرنسية', 'French'),
        _Option('Spanish', 'الإسبانية', 'Spanish')
      ]),
  _Preference(
      key: 'subtitleTranslationLanguage',
      arabic: 'لغة الترجمة المفضلة للمسار',
      english: 'Preferred subtitle track language',
      control: _Control.select,
      options: [
        _Option('off', 'حسب اللغات المفضلة', 'Use preferred languages'),
        _Option('ar', 'العربية', 'Arabic'),
        _Option('en', 'الإنجليزية', 'English'),
        _Option('ja', 'اليابانية', 'Japanese'),
        _Option('fr', 'الفرنسية', 'French'),
        _Option('es', 'الإسبانية', 'Spanish')
      ]),
  _Preference(
      key: 'subtitlesOffByDefault',
      arabic: 'إيقاف الترجمة تلقائيًا',
      english: 'Subtitles off by default',
      control: _Control.toggle),
  _Preference(
      key: 'subFontSize',
      arabic: 'حجم الترجمة',
      english: 'Subtitle size',
      control: _Control.slider,
      min: 14,
      max: 44,
      step: 2,
      suffix: ' px'),
  _Preference(
      key: 'subFontColor',
      arabic: 'لون النص',
      english: 'Text color',
      control: _Control.color),
  _Preference(
      key: 'subStyle',
      arabic: 'نمط الترجمة',
      english: 'Subtitle style',
      control: _Control.select,
      options: [
        _Option('shadow', 'ظل', 'Shadow'),
        _Option('outline', 'حد خارجي', 'Outline'),
        _Option('box', 'خلفية', 'Background')
      ]),
  _Preference(
      key: 'subBorderColor',
      arabic: 'لون الحد',
      english: 'Outline color',
      control: _Control.color),
  _Preference(
      key: 'subBorderSize',
      arabic: 'سماكة الحد',
      english: 'Outline size',
      control: _Control.slider,
      min: 0,
      max: 8,
      step: 1,
      suffix: ' px'),
  _Preference(
      key: 'subBackgroundOpacity',
      arabic: 'شفافية الخلفية',
      english: 'Background opacity',
      control: _Control.slider,
      min: 0,
      max: 1,
      step: .05),
  _Preference(
      key: 'subtitleOffsetMs',
      arabic: 'تقديم أو تأخير الترجمة',
      english: 'Subtitle offset',
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
