import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';

class SettingsDisplayPage extends StatelessWidget {
  const SettingsDisplayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final english = app.english;
    final settings = app.webSettings;
    final radius = (settings['posterRadius'] as num?)?.toDouble() ?? 12;
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
                title: english ? 'Home' : 'الرئيسية',
                children: [
                  _SelectRow(
                    title: english ? 'Home layout' : 'تخطيط الرئيسية',
                    value: (settings['homeMode'] ?? 'harbor').toString(),
                    options: {
                      'harbor': english ? 'Featured' : 'المميز',
                      'classic': english ? 'Compact' : 'مختصر',
                    },
                    onChanged: (value) => app.setSetting('homeMode', value),
                  ),
                  _ToggleRow(
                    title: english
                        ? 'Show all add-on catalogs'
                        : 'عرض كل كتالوجات الإضافات',
                    value: settings['homeShowAllAddonRows'] == true,
                    onChanged: (value) =>
                        app.setSetting('homeShowAllAddonRows', value),
                  ),
                  _ToggleRow(
                    title: english
                        ? 'Hide watched titles in catalogs'
                        : 'إخفاء العناوين المشاهدة من الكتالوجات',
                    value: settings['hideWatchedInCatalogs'] == true,
                    onChanged: (value) =>
                        app.setSetting('hideWatchedInCatalogs', value),
                  ),
                  _ToggleRow(
                    title: english
                        ? 'Hide anime from Home catalogs'
                        : 'إخفاء الأنمي من كتالوجات الرئيسية',
                    value: (settings['hideContent'] as Map?)?['anime'] == true,
                    onChanged: (value) {
                      final hide = Map<String, dynamic>.from(
                          settings['hideContent'] as Map? ?? const {});
                      app.setSetting('hideContent', {...hide, 'anime': value});
                    },
                  ),
                  _ToggleRow(
                    title: english
                        ? 'Hide adult-rated titles from Home'
                        : 'إخفاء العناوين المصنفة للكبار من الرئيسية',
                    value: (settings['hideContent'] as Map?)?['adult'] == true,
                    onChanged: (value) {
                      final hide = Map<String, dynamic>.from(
                          settings['hideContent'] as Map? ?? const {});
                      app.setSetting('hideContent', {...hide, 'adult': value});
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _PreferenceCard(
                title: english ? 'Posters' : 'الملصقات',
                children: [
                  _ToggleRow(
                    title: english ? 'Show rating badge' : 'إظهار تقييم الملصق',
                    value: settings['showImdbBadge'] != false,
                    onChanged: (value) =>
                        app.setSetting('showImdbBadge', value),
                  ),
                  _ToggleRow(
                    title: english
                        ? 'Hide poster titles'
                        : 'إخفاء عناوين الملصقات',
                    value: settings['hidePosterTitles'] == true,
                    onChanged: (value) =>
                        app.setSetting('hidePosterTitles', value),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(3, 12, 3, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(english
                            ? 'Poster corner radius'
                            : 'استدارة زوايا الملصق'),
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
                          onChangeEnd: (value) =>
                              app.setSetting('posterRadius', value.round()),
                        ),
                      ],
                    ),
                  ),
                  _ToggleRow(
                    title: english
                        ? 'Blur unwatched episode stills'
                        : 'تمويه صور الحلقات غير المشاهدة',
                    value: settings['blurEpisodeThumbnails'] == true,
                    onChanged: (value) =>
                        app.setSetting('blurEpisodeThumbnails', value),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _PreferenceCard(
                title: english ? 'Kids and library' : 'الأطفال والمكتبة',
                children: [
                  _SelectRow(
                    title: english ? 'Kids poster size' : 'حجم ملصقات الأطفال',
                    value: (settings['kidsCardSize'] ?? 'medium').toString(),
                    options: {
                      'large': english ? 'Large' : 'كبير',
                      'medium': english ? 'Medium' : 'متوسط',
                      'small': english ? 'Small' : 'صغير',
                    },
                    onChanged: (value) => app.setSetting('kidsCardSize', value),
                  ),
                  _SelectRow(
                    title: english ? 'Library sort' : 'ترتيب المكتبة',
                    value: (settings['librarySort'] ?? 'recent').toString(),
                    options: {
                      'recent': english ? 'Recently added' : 'الأحدث إضافة',
                      'title': english ? 'Title' : 'العنوان',
                      'year': english ? 'Year' : 'السنة',
                    },
                    onChanged: (value) => app.setSetting('librarySort', value),
                  ),
                  _SelectRow(
                    title: english ? 'Episode layout' : 'عرض الحلقات',
                    value: (settings['episodesView'] ?? 'auto').toString(),
                    options: {
                      'auto': english ? 'Automatic' : 'تلقائي',
                      'list': english ? 'List' : 'قائمة',
                      'grid': english ? 'Cards' : 'بطاقات',
                    },
                    onChanged: (value) => app.setSetting('episodesView', value),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _PreferenceCard(
                title: english ? 'Navigation' : 'التنقل',
                children: [
                  _ToggleRow(
                    title: english
                        ? 'Auto-hide navigation while scrolling'
                        : 'إخفاء شريط التنقل أثناء التمرير',
                    value: settings['dockAutoHide'] != false,
                    onChanged: (value) => app.setSetting('dockAutoHide', value),
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

class _ToggleRow extends StatelessWidget {
  const _ToggleRow(
      {required this.title, required this.value, required this.onChanged});
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
        contentPadding: const EdgeInsetsDirectional.only(start: 3, end: 0),
        title: Text(title),
        value: value,
        activeThumbColor: HorseTheme.gold,
        onChanged: onChanged,
      );
}

class _SelectRow extends StatelessWidget {
  const _SelectRow(
      {required this.title,
      required this.value,
      required this.options,
      required this.onChanged});
  final String title;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(3, 10, 3, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            // The dropdown itself shows the selected value — no repeated
            // muted copy of it above (user request: no duplicates).
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
