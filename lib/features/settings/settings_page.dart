import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../core/state/app_state.dart';
import '../shell/noor_dock_tabs.dart';
import 'addons_page.dart';
import 'integrations_page.dart';
import 'stats_page.dart';
import 'settings_preferences_page.dart';
import 'settings_data_page.dart';
import 'settings_display_page.dart';
import 'settings_personalization_page.dart';
import 'widgets/settings_tiles.dart';

class _Destination {
  const _Destination(this.id, this.icon, this.title, this.description,
      this.keywords, this.page);
  final String id;
  final IconData icon;
  final String title, description, keywords;
  final Widget page;
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.onOpenLibrary});
  final VoidCallback? onOpenLibrary;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _query = '';
  String? _selected;
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<_Destination> _destinations(AppState app) => [
        _Destination(
            'account',
            LucideIcons.userRound,
            app.tr('message346'),
            app.tr('message452'),
            app.tr('settingsSearchAccountKeywords'),
            const SettingsDataPage(section: 'account')),
        _Destination(
            'playback',
            LucideIcons.play,
            app.tr('message453'),
            app.tr('message454'),
            app.tr('settingsSearchPlaybackKeywords'),
            const SettingsPreferencesPage(subtitles: false)),
        _Destination(
            'subtitles',
            LucideIcons.captions,
            app.tr('message7'),
            app.tr('message455'),
            app.tr('settingsSearchSubtitleKeywords'),
            const SettingsPreferencesPage(subtitles: true)),
        _Destination(
            'downloads',
            LucideIcons.download,
            app.tr('message345'),
            app.tr('message456'),
            app.tr('settingsSearchDownloadKeywords'),
            const SettingsDataPage(section: 'storage')),
        _Destination(
            'appearance',
            LucideIcons.palette,
            app.tr('appearance'),
            app.tr('message457'),
            app.tr('settingsSearchAppearanceKeywords'),
            const SettingsPersonalizationPage(section: 'appearance')),
        _Destination(
            'display',
            LucideIcons.layoutGrid,
            app.tr('message416'),
            app.tr('message458'),
            app.tr('settingsSearchDisplayKeywords'),
            const SettingsDisplayPage()),
        _Destination(
            'language',
            LucideIcons.languages,
            app.tr('language'),
            app.tr('message459'),
            app.tr('settingsSearchLanguageKeywords'),
            const SettingsPersonalizationPage(section: 'language')),
        _Destination(
            'notifications',
            LucideIcons.bell,
            app.tr('message460'),
            app.tr('message461'),
            app.tr('settingsSearchNotificationsKeywords'),
            const SettingsPersonalizationPage(section: 'notifications')),
        _Destination(
            'privacy',
            LucideIcons.shieldCheck,
            app.tr('message347'),
            app.tr('message462'),
            app.tr('settingsSearchPrivacyKeywords'),
            const SettingsDataPage(section: 'privacy')),
        _Destination(
            'addons',
            LucideIcons.puzzle,
            app.tr('message220'),
            app.tr('message463'),
            app.tr('settingsSearchAddonKeywords'),
            const AddonsPage()),
        _Destination(
            'services',
            LucideIcons.orbit,
            app.tr('message252'),
            app.tr('message464'),
            app.tr('settingsSearchServiceKeywords'),
            const IntegrationsPage()),
        _Destination(
            'kids',
            LucideIcons.smile,
            app.tr('message415'),
            app.tr('message465'),
            app.tr('settingsSearchKidsKeywords'),
            const SettingsDisplayPage(kidsOnly: true)),
        _Destination(
            'stats',
            LucideIcons.chartNoAxesCombined,
            app.tr('message466'),
            app.tr('message467'),
            app.tr('settingsSearchStatsKeywords'),
            const StatsPage()),
        _Destination(
            'about',
            LucideIcons.info,
            app.tr('message468'),
            app.tr('message469'),
            app.tr('settingsSearchAboutKeywords'),
            const SettingsAboutPage()),
      ];

  @override
  Widget build(BuildContext context) {
    context.select<AppState, bool>((app) => app.english);
    final app = context.read<AppState>();
    final destinations = _destinations(app);
    final query = _query.trim().toLowerCase();
    final results = destinations
        .where((d) => '${d.title} ${d.description} ${d.keywords}'
            .toLowerCase()
            .contains(query))
        .toList();
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1000;
      final selected = destinations.where((d) => d.id == _selected).firstOrNull;
      final menu = ListView(
          padding: EdgeInsetsDirectional.fromSTEB(
              wide ? 24 : 20,
              16,
              wide ? 24 : 20,
              widget.onOpenLibrary == null
                  ? 40
                  : glassDockContentClearance(context)),
          children: [
            SettingsPageIntro(
                title: app.tr('message470'), description: app.tr('message471')),
            TextField(
                controller: _search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                    hintText: app.tr('message472'),
                    prefixIcon: const Icon(LucideIcons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: app.tr('message473'),
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(LucideIcons.x)))),
            const SizedBox(height: 24),
            if (widget.onOpenLibrary != null && query.isEmpty)
              Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: 12),
                  child: SettingsTile(
                      icon: LucideIcons.bookmark,
                      title: app.tr('message474'),
                      onTap: widget.onOpenLibrary)),
            if (results.isEmpty)
              Padding(
                  padding: const EdgeInsets.all(24),
                  child: SettingsInfoBanner(
                      icon: LucideIcons.searchX,
                      message: app.tr('message475'))),
            for (final destination in results)
              Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: 4),
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                          color: wide && destination.id == _selected
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16)),
                      child: SettingsTile(
                          icon: destination.icon,
                          title: destination.title,
                          subtitle: wide ? null : destination.description,
                          onTap: () {
                            if (wide) {
                              setState(() => _selected = destination.id);
                            } else {
                              Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                      builder: (_) => destination.page));
                            }
                          }))),
          ]);
      return Scaffold(
          appBar: AppBar(title: Text(app.tr('settings'))),
          body: wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SizedBox(width: 340, child: menu),
                  const VerticalDivider(width: 1),
                  Expanded(
                      child: selected?.page ??
                          const SettingsPersonalizationPage(
                              section: 'appearance')),
                ])
              : Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: menu)));
    });
  }
}
