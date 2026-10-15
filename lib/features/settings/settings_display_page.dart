import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';
import 'widgets/settings_tiles.dart';

class SettingsDisplayPage extends StatelessWidget {
  const SettingsDisplayPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Task 122-c F4: the page subscribes ONLY to the UI language (titles,
    // card headers, footer). Every row selects its own `webSettings` value,
    // so a settings change rebuilds exactly one row instead of the page.
    final english = context.select<AppState, bool>((app) => app.english);
    return Scaffold(
      appBar: AppBar(
        title: Text(english ? 'Catalog and display' : 'الكتالوج والمظهر'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 36),
            children: [
              _PreferenceCard(
                title: english ? 'Language' : 'اللغة',
                children: [
                  _ContentLanguageRow(
                    title: english ? 'Content language' : 'لغة المحتوى',
                    subtitle: english
                        ? 'Posters, synopses & episode titles (TMDB & supporting addons)'
                        : 'الملصقات والقصص وعناوين الحلقات (TMDB والإضافات الداعمة)',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _PreferenceCard(
                title: english ? 'Home' : 'الرئيسية',
                children: [
                  _SettingSelect(
                    settingKey: 'homeMode',
                    fallback: 'harbor',
                    title: english ? 'Home layout' : 'تخطيط الرئيسية',
                    options: {
                      'harbor': english ? 'Featured' : 'المميز',
                      'classic': english ? 'Compact' : 'مختصر',
                    },
                  ),
                  _SettingToggle(
                    settingKey: 'homeShowAllAddonRows',
                    title: english
                        ? 'Show all add-on catalogs'
                        : 'عرض كل كتالوجات الإضافات',
                  ),
                  _SettingToggle(
                    settingKey: 'hideWatchedInCatalogs',
                    title: english
                        ? 'Hide watched titles in catalogs'
                        : 'إخفاء العناوين المشاهدة من الكتالوجات',
                  ),
                  _HideContentToggle(
                    kind: 'anime',
                    title: english
                        ? 'Hide anime from Home catalogs'
                        : 'إخفاء الأنمي من كتالوجات الرئيسية',
                  ),
                  _HideContentToggle(
                    kind: 'adult',
                    title: english
                        ? 'Hide adult-rated titles from Home'
                        : 'إخفاء العناوين المصنفة للكبار من الرئيسية',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _PreferenceCard(
                title: english ? 'Posters' : 'الملصقات',
                children: [
                  _SettingToggle(
                    settingKey: 'showImdbBadge',
                    onWhenAbsent: true,
                    title: english ? 'Show rating badge' : 'إظهار تقييم الملصق',
                  ),
                  _SettingToggle(
                    settingKey: 'hidePosterTitles',
                    title: english
                        ? 'Hide poster titles'
                        : 'إخفاء عناوين الملصقات',
                  ),
                  const _PosterRadiusRow(),
                  _SettingToggle(
                    settingKey: 'blurEpisodeThumbnails',
                    title: english
                        ? 'Blur unwatched episode stills'
                        : 'تمويه صور الحلقات غير المشاهدة',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _PreferenceCard(
                title: english ? 'Kids and library' : 'الأطفال والمكتبة',
                children: [
                  _SettingSelect(
                    settingKey: 'kidsCardSize',
                    fallback: 'medium',
                    title: english ? 'Kids poster size' : 'حجم ملصقات الأطفال',
                    options: {
                      'large': english ? 'Large' : 'كبير',
                      'medium': english ? 'Medium' : 'متوسط',
                      'small': english ? 'Small' : 'صغير',
                    },
                  ),
                  _SettingSelect(
                    settingKey: 'librarySort',
                    fallback: 'recent',
                    title: english ? 'Library sort' : 'ترتيب المكتبة',
                    options: {
                      'recent': english ? 'Recently added' : 'الأحدث إضافة',
                      'title': english ? 'Title' : 'العنوان',
                      'year': english ? 'Year' : 'السنة',
                    },
                  ),
                  _SettingSelect(
                    settingKey: 'episodesView',
                    fallback: 'auto',
                    title: english ? 'Episode layout' : 'عرض الحلقات',
                    options: {
                      'auto': english ? 'Automatic' : 'تلقائي',
                      'list': english ? 'List' : 'قائمة',
                      'grid': english ? 'Cards' : 'بطاقات',
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _PreferenceCard(
                title: english ? 'Navigation' : 'التنقل',
                children: [
                  _SettingToggle(
                    settingKey: 'dockAutoHide',
                    onWhenAbsent: true,
                    title: english
                        ? 'Auto-hide navigation while scrolling'
                        : 'إخفاء شريط التنقل أثناء التمرير',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                english
                    ? 'Noor keeps its signature dark and bronze colors. Browser-only options such as desktop side-rail order are not available on mobile.'
                    : 'يحافظ Noor على ألوانه الداكنة والذهبية. خيارات المتصفح الخاصة مثل ترتيب الشريط الجانبي المكتبي غير متاحة على الجوال.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: HorseTheme.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadiusSlider extends StatefulWidget {
  const _RadiusSlider({required this.value, required this.onChangeEnd});
  final double value;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_RadiusSlider> createState() => _RadiusSliderState();
}

class _RadiusSliderState extends State<_RadiusSlider> {
  late double _value = widget.value;

  @override
  void didUpdateWidget(covariant _RadiusSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _value = widget.value;
  }

  @override
  Widget build(BuildContext context) => Slider(
        value: _value.clamp(0, 28),
        min: 0,
        max: 28,
        divisions: 14,
        label: '${_value.round()} px',
        onChanged: (value) => setState(() => _value = value),
        onChangeEnd: widget.onChangeEnd,
      );
}

/// Task 122-c: content-language row — a [_SelectRow] reading ONLY
/// [AppState.contentLanguage] via context.select. The 11 options are the
/// static [AppState.kContentLanguages] native labels, shown natively in
/// BOTH UI languages (a content language may differ from the UI one).
class _ContentLanguageRow extends StatelessWidget {
  const _ContentLanguageRow({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final language =
        context.select<AppState, String>((app) => app.contentLanguage);
    final options = AppState.kContentLanguages;
    return _SelectRow(
      title: title,
      subtitle: subtitle,
      themedDropdown: true,
      value: options.containsKey(language) ? language : options.keys.first,
      options: options,
      onChanged: (next) =>
          context.read<AppState>().setSetting('contentLanguage', next),
    );
  }
}

/// Task 122-c F4: self-subscribing toggle row bound to one `webSettings`
/// bool key (`== true` semantics, or `!= false` with [onWhenAbsent]) —
/// renders through the optimistic switch tile so taps paint instantly.
class _SettingToggle extends StatelessWidget {
  const _SettingToggle({
    required this.settingKey,
    required this.title,
    this.onWhenAbsent = false,
  });
  final String settingKey;
  final String title;
  final bool onWhenAbsent;

  @override
  Widget build(BuildContext context) {
    final value = context.select<AppState, bool>((app) {
      final raw = app.webSettings[settingKey];
      return onWhenAbsent ? raw != false : raw == true;
    });
    return SettingsOptimisticSwitchTile(
      contentPadding: const EdgeInsetsDirectional.only(start: 3, end: 0),
      title: Text(title),
      value: value,
      onChanged: (next) =>
          context.read<AppState>().setSetting(settingKey, next),
    );
  }
}

/// Self-subscribing toggle row over the `hideContent` map (`anime`/`adult`).
class _HideContentToggle extends StatelessWidget {
  const _HideContentToggle({required this.kind, required this.title});
  final String kind;
  final String title;

  @override
  Widget build(BuildContext context) {
    final value = context.select<AppState, bool>(
        (app) => (app.webSettings['hideContent'] as Map?)?[kind] == true);
    return SettingsOptimisticSwitchTile(
      contentPadding: const EdgeInsetsDirectional.only(start: 3, end: 0),
      title: Text(title),
      value: value,
      onChanged: (next) {
        final app = context.read<AppState>();
        final hide = Map<String, dynamic>.from(
            app.webSettings['hideContent'] as Map? ?? const {});
        app.setSetting('hideContent', {...hide, kind: next});
      },
    );
  }
}

/// Self-subscribing select row bound to one `webSettings` string key with
/// a fallback ([_SelectRow]'s rendering is unchanged for these rows).
class _SettingSelect extends StatelessWidget {
  const _SettingSelect({
    required this.settingKey,
    required this.fallback,
    required this.title,
    required this.options,
  });
  final String settingKey;
  final String fallback;
  final String title;
  final Map<String, String> options;

  @override
  Widget build(BuildContext context) {
    final value = context.select<AppState, String>(
        (app) => (app.webSettings[settingKey] ?? fallback).toString());
    return _SelectRow(
      title: title,
      value: value,
      options: options,
      onChanged: (next) =>
          context.read<AppState>().setSetting(settingKey, next),
    );
  }
}

/// Task 122-c F4: poster-radius block lifted out of the page build —
/// selects (english, radius) so only this block rebuilds on its change.
class _PosterRadiusRow extends StatelessWidget {
  const _PosterRadiusRow();

  @override
  Widget build(BuildContext context) {
    final (english, radius) =
        context.select<AppState, (bool, double)>((app) => (
              app.english,
              (app.webSettings['posterRadius'] as num?)?.toDouble() ?? 12,
            ));
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(3, 12, 3, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(english ? 'Poster corner radius' : 'استدارة زوايا الملصق'),
          const SizedBox(height: 3),
          Text(
            '${radius.round()} px',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: HorseTheme.muted),
          ),
          _RadiusSlider(
            value: radius,
            onChangeEnd: (value) => context
                .read<AppState>()
                .setSetting('posterRadius', value.round()),
          ),
        ],
      ),
    );
  }
}

class _PreferenceCard extends StatelessWidget {
  const _PreferenceCard({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
        color: HorseTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: HorseTheme.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(3, 8, 3, 6),
                child: Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: HorseTheme.gold)),
              ),
              ...children,
            ],
          ),
        ),
      );
}

class _SelectRow extends StatelessWidget {
  const _SelectRow({
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.subtitle,
    this.themedDropdown = false,
  });
  final String title;
  final String? subtitle;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  /// Task 122-c: render the shared [SettingsLanguageDropdown] (gold/muted,
  /// no underline) instead of the plain dropdown — used by the new
  /// content-language row so the two language dropdowns look alike. The
  /// default keeps the original dropdown byte-for-byte.
  final bool themedDropdown;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(3, 10, 3, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: HorseTheme.muted),
              ),
            ],
            // The dropdown itself shows the selected value — no repeated
            // muted copy of it above (user request: no duplicates).
            if (themedDropdown)
              SettingsLanguageDropdown(
                expanded: true,
                value: options.containsKey(value) ? value : options.keys.first,
                items: options.entries
                    .map((entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ))
                    .toList(),
                onChanged: onChanged,
              )
            else
              DropdownButton<String>(
                value: options.containsKey(value) ? value : options.keys.first,
                isExpanded: true,
                items: options.entries
                    .map((entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ))
                    .toList(),
                onChanged: (next) {
                  if (next != null) onChanged(next);
                },
              ),
          ],
        ),
      );
}
