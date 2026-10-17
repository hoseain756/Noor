import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../core/state/app_state.dart';
import 'navigation_bar_style_page.dart';
import 'widgets/settings_tiles.dart';

class SettingsPersonalizationPage extends StatelessWidget {
  const SettingsPersonalizationPage({super.key, required this.section});
  final String section;
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final title = switch (section) {
      'language' => app.tr('language'),
      'notifications' => app.tr('message460'),
      _ => app.tr('message476'),
    };
    return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 48),
              children: [
                SettingsPageIntro(
                    title: title,
                    description: section == 'language'
                        ? app.tr('message477')
                        : section == 'notifications'
                            ? app.tr('message478')
                            : app.tr('message479'),
                    icon: section == 'language'
                        ? LucideIcons.languages
                        : section == 'notifications'
                            ? LucideIcons.bell
                            : LucideIcons.palette),
                if (section == 'language') ...[
                  SettingsContentSection(
                      title: app.tr('message480'),
                      children: [
                        RadioGroup<bool>(
                            groupValue: app.english,
                            onChanged: (value) =>
                                app.setLanguage(value ?? true),
                            child: Column(children: [
                              RadioListTile<bool>(
                                  value: true,
                                  title: Text(app.tr('englishLanguage')),
                                  subtitle: Text(app.tr('message481'))),
                              RadioListTile<bool>(
                                  value: false,
                                  title: Text(app.tr('arabicLanguage')),
                                  subtitle: Text(app.tr('message482'))),
                            ])),
                      ]),
                  SettingsContentSection(
                      title: app.tr('message483'),
                      children: [
                        Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(app.tr('message484')),
                                  const SizedBox(height: 12),
                                  SettingsLanguageDropdown(
                                      value: AppState.kContentLanguages
                                              .containsKey(app.contentLanguage)
                                          ? app.contentLanguage
                                          : 'en',
                                      expanded: true,
                                      items: AppState.kContentLanguages.entries
                                          .map((e) => DropdownMenuItem(
                                              value: e.key,
                                              child: Text(e.value)))
                                          .toList(),
                                      onChanged: (value) => app.setSetting(
                                          'contentLanguage', value)),
                                ])),
                      ]),
                ] else if (section == 'notifications') ...[
                  SettingsInfoBanner(
                      icon: LucideIcons.bellOff, message: app.tr('message485')),
                ] else ...[
                  SettingsContentSection(
                      title: app.tr('message486'),
                      children: [
                        RadioGroup<String>(
                            groupValue: (app.webSettings['themeMode'] ?? 'dark')
                                .toString(),
                            onChanged: (value) =>
                                app.setSetting('themeMode', value),
                            child: Column(children: [
                              for (final mode in ['dark', 'light', 'system'])
                                RadioListTile<String>(
                                    value: mode,
                                    title: Text(switch (mode) {
                                      'dark' => app.tr('message487'),
                                      'light' => app.tr('message488'),
                                      _ => app.tr('message489')
                                    }),
                                    secondary: Icon(switch (mode) {
                                      'dark' => LucideIcons.moon,
                                      'light' => LucideIcons.sun,
                                      _ => LucideIcons.monitor
                                    })),
                            ])),
                        SettingsTile(
                            icon: LucideIcons.layoutGrid,
                            title: app.tr('navigationBarStyle'),
                            subtitle: app.tr('navigationBarStyleSubtitle'),
                            onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                    builder: (_) =>
                                        const NavigationBarStylePage()))),
                      ]),
                  SettingsContentSection(
                      title: app.tr('message490'),
                      children: [
                        SettingsOptimisticSwitchTile(
                            title: Text(app.tr('message491')),
                            subtitle: Text(app.tr('message492')),
                            value: app.webSettings['reduceMotion'] == true,
                            onChanged: (v) =>
                                app.setSetting('reduceMotion', v)),
                        SettingsOptimisticSwitchTile(
                            title: Text(app.tr('message493')),
                            subtitle: Text(app.tr('message494')),
                            value:
                                app.webSettings['reduceTransparency'] == true,
                            onChanged: (v) =>
                                app.setSetting('reduceTransparency', v)),
                      ]),
                  SettingsInfoBanner(
                      icon: LucideIcons.accessibility,
                      message: app.tr('message495')),
                ],
              ]),
        )));
  }
}
