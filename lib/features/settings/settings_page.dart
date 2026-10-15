import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/app_state.dart';
import '../../core/sync/noor_sync.dart';
import '../../core/theme/horse_theme.dart';
import '../shell/noor_dock_tabs.dart';
import 'addons_page.dart';
import 'integrations_page.dart';
import 'stats_page.dart';
import 'settings_preferences_page.dart';
import 'settings_data_page.dart';
import 'settings_display_page.dart';
import 'widgets/settings_tiles.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, this.onOpenLibrary});

  final VoidCallback? onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    // Task 122-c F4: scoped selects — this overview tile list reads ONLY
    // these six derived fields, so unrelated notifies no longer rebuild it.
    final (
      english,
      addonCount,
      serviceCount,
      watchedCount,
      syncOn,
      savedCount,
    ) = context.select<AppState, (bool, int, int, int, bool, int)>((app) => (
          app.english,
          app.addons.length,
          app.linkedServices.length + (app.api.debridService == null ? 0 : 1),
          app.watchedCount,
          app.webSettings['cloudSyncEnabled'] != false,
          app.watchlist.length,
        ));
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      appBar: AppBar(
        title: Text(english ? 'Settings' : 'الإعدادات'),
        centerTitle: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              width >= 700 ? 32 : 20,
              10,
              width >= 700 ? 32 : 20,
              onOpenLibrary == null ? 36 : glassDockContentClearance(context),
            ),
            children: [
              Text(
                english ? 'Your Noor' : 'تطبيق Noor',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                english
                    ? 'A focused player and catalog for your add-ons.'
                    : 'كتالوج ومشغّل بسيط يعملان مع إضافاتك.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: HorseTheme.muted),
              ),
              if (onOpenLibrary != null) ...[
                const SizedBox(height: 16),
                SettingsTile(
                  icon: Icons.video_library_outlined,
                  title: english ? 'My library' : 'مكتبتي',
                  subtitle: english
                      ? 'Continue watching and saved titles'
                      : 'متابعة المشاهدة والعناوين المحفوظة',
                  onTap: onOpenLibrary,
                ),
              ],
              const SizedBox(height: 24),
              SettingsSectionTitle(title: english ? 'Playback' : 'التشغيل'),
              SettingsTile(
                icon: Icons.tune_rounded,
                title: english ? 'Player settings' : 'إعدادات المشغّل',
                subtitle: english
                    ? 'Audio, quality, resume, and playback behavior'
                    : 'الصوت والجودة والاستئناف وسلوك التشغيل',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const SettingsPreferencesPage(subtitles: false),
                  ),
                ),
              ),
              SettingsTile(
                icon: Icons.closed_caption_outlined,
                title:
                    english ? 'Subtitles and translation' : 'الترجمة واللغات',
                subtitle: english
                    ? 'Languages, style, size, and timing'
                    : 'اللغات والنمط والحجم والتوقيت',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const SettingsPreferencesPage(subtitles: true),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              SettingsSectionTitle(title: english ? 'Add-ons' : 'الإضافات'),
              SettingsTile(
                icon: Icons.extension_rounded,
                title: english ? 'Installed add-ons' : 'الإضافات المثبتة',
                subtitle: english
                    ? '$addonCount installed · catalogs and streams'
                    : '$addonCount مثبتة · كتالوجات وبث',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AddonsPage()),
                ),
              ),
              SettingsTile(
                icon: Icons.hub_outlined,
                title: english ? 'Connected services' : 'الخدمات المرتبطة',
                subtitle: english
                    ? '$serviceCount connected · Trakt, Simkl, Debrid'
                    : '$serviceCount متصلة · Trakt وSimkl وDebrid',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const IntegrationsPage(),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              SettingsSectionTitle(title: english ? 'Sync' : 'المزامنة'),
              const _SyncPanel(),
              const SizedBox(height: 22),
              SettingsSectionTitle(title: english ? 'App' : 'التطبيق'),
              SettingsTile(
                icon: Icons.dashboard_customize_outlined,
                title: english ? 'Catalog and display' : 'الكتالوج والمظهر',
                subtitle: english
                    ? 'Home rows, posters, Kids, and episode layouts'
                    : 'صفوف الرئيسية والملصقات والأطفال وعرض الحلقات',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsDisplayPage(),
                  ),
                ),
              ),
              // Task 122-c: the hidden language Switch became an explicit
              // dropdown — native labels in both UI languages, same tile
              // geometry (icon/title/subtitle unchanged).
              SettingsTile(
                icon: Icons.language_rounded,
                title: english ? 'Language' : 'اللغة',
                trailing: SettingsLanguageDropdown(
                  value: english ? 'en' : 'ar',
                  items: const [
                    DropdownMenuItem(value: 'ar', child: Text('العربية')),
                    DropdownMenuItem(value: 'en', child: Text('English')),
                  ],
                  onChanged: (value) =>
                      context.read<AppState>().setLanguage(value == 'en'),
                ),
              ),
              SettingsTile(
                icon: Icons.palette_outlined,
                title: english ? 'Noor design' : 'تصميم Noor',
                subtitle: english
                    ? 'The signature dark and bronze look'
                    : 'الهوية الداكنة والذهبية المعتمدة',
                trailing: const Icon(
                  Icons.lock_outline_rounded,
                  size: 18,
                  color: HorseTheme.muted,
                ),
                onTap: null,
              ),
              const SizedBox(height: 22),
              SettingsSectionTitle(title: english ? 'Usage' : 'الإحصائيات'),
              SettingsTile(
                icon: Icons.query_stats_rounded,
                title: english ? 'Viewing statistics' : 'إحصائيات المشاهدة',
                subtitle: english
                    ? '$watchedCount recent plays'
                    : '$watchedCount مشاهدة مسجلة',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const StatsPage()),
                ),
              ),
              const SizedBox(height: 22),
              SettingsSectionTitle(
                  title: english ? 'Data and privacy' : 'البيانات والخصوصية'),
              SettingsTile(
                icon: Icons.privacy_tip_outlined,
                title: english ? 'Data and privacy' : 'البيانات والخصوصية',
                subtitle: english
                    ? 'Cloud sync ${syncOn ? 'on' : 'off'} · $savedCount saved titles'
                    : 'المزامنة ${syncOn ? 'مفعّلة' : 'متوقفة'} · $savedCount عنوان محفوظ',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const SettingsDataPage()),
                ),
              ),
              const SizedBox(height: 22),
              SettingsSectionTitle(title: english ? 'About' : 'حول التطبيق'),
              SettingsTile(
                icon: Icons.info_outline_rounded,
                title: english ? 'About Noor' : 'حول Noor',
                subtitle: english
                    ? 'Version, license, and acknowledgements'
                    : 'الإصدار والترخيص والإسناد',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const SettingsAboutPage()),
                ),
              ),
              const SizedBox(height: 26),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncPanel extends StatefulWidget {
  const _SyncPanel();

  @override
  State<_SyncPanel> createState() => _SyncPanelState();
}

class _SyncPanelState extends State<_SyncPanel> {
  bool _busy = false;
  DateTime? _lastSync;

  @override
  void initState() {
    super.initState();
    _loadLastSync();
  }

  Future<void> _loadLastSync() async {
    final last = await NoorSyncService.instance
        .lastSyncAt(NoorSyncService.bucketSettings);
    if (mounted) setState(() => _lastSync = last);
  }

  Future<void> _syncNow() async {
    final app = context.read<AppState>();
    final english = app.english;
    setState(() => _busy = true);
    final ok = await app.syncNow();
    await _loadLastSync();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? (english ? 'Sync complete.' : 'تمت المزامنة.')
              : (english
                  ? 'Sync failed — check your connection.'
                  : 'تعذّرت المزامنة — تحقّق من الاتصال.'),
        ),
      ),
    );
  }

  String _formatLastSync(bool english) {
    final last = _lastSync;
    if (last == null) return english ? 'Never' : 'لم تتم بعد';
    final local = last.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    final clock = '${two(local.hour)}:${two(local.minute)}';
    return english
        ? '${local.year}-${two(local.month)}-${two(local.day)} $clock'
        : '${local.day}/${local.month}/${local.year} · $clock';
  }

  @override
  Widget build(BuildContext context) {
    final (english, shortId) = context.select<AppState, (bool, String)>((app) {
      final id = app.deviceId ?? '';
      return (
        app.english,
        id.length >= 8 ? id.substring(0, 8) : (id.isEmpty ? '—' : id),
      );
    });
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: HorseTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: HorseTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sync_rounded, color: HorseTheme.gold, size: 20),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  english ? 'Noor Sync' : 'مزامنة Noor',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.tonal(
                onPressed: _busy ? null : _syncNow,
                child: _busy
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(english ? 'Sync now' : 'مزامنة الآن'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            english
                ? 'Accountless device sync'
                : 'بدون حساب — مزامنة عبر معرّف الجهاز',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Text(
            english
                ? 'Device $shortId · Last sync: ${_formatLastSync(english)}'
                : 'الجهاز $shortId · آخر مزامنة: ${_formatLastSync(english)}',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: HorseTheme.muted),
          ),
        ],
      ),
    );
  }
}
