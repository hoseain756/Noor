import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/data/cache_reset_service.dart';
import '../../core/state/app_state.dart';
import '../../core/sync/noor_sync.dart';
import '../../core/theme/horse_theme.dart';
import '../../core/torrent/torrent_service.dart';
import '../../core/version.dart';
import '../../shared/widgets/noor_toast.dart';
import 'widgets/settings_tiles.dart';

class SettingsDataPage extends StatelessWidget {
  const SettingsDataPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Task 122-c F4: the page reads only the UI language + the two counts
    // shown in the row subtitles; callbacks use context.read below.
    final (english, savedCount, historyCount) =
        context.select<AppState, (bool, int, int)>((app) => (
              app.english,
              app.watchlist.length,
              app.history.length,
            ));
    final app = context.read<AppState>();
    return Scaffold(
      appBar: AppBar(
          title: Text(english ? 'Data and privacy' : 'البيانات والخصوصية')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 36),
            children: [
              _SupabaseSyncCard(app: app),
              const _TorrentDownloadsCard(),
              const _CacheResetCard(),
              _DataRow(
                icon: Icons.download_outlined,
                title: english ? 'Export backup' : 'تصدير نسخة احتياطية',
                detail: english
                    ? '$savedCount saved titles · $historyCount history records'
                    : '$savedCount عنوان محفوظ · $historyCount سجل مشاهدة',
                onTap: () async {
                  await Clipboard.setData(
                      ClipboardData(text: await app.exportLocalData()));
                  if (!context.mounted) return;
                  NoorToast.show(
                    context,
                    english
                        ? 'Backup copied as JSON.'
                        : 'تم نسخ النسخة الاحتياطية بصيغة JSON.',
                  );
                },
              ),
              _DataRow(
                icon: Icons.restore_rounded,
                title: english ? 'Restore backup' : 'استعادة نسخة احتياطية',
                detail: english
                    ? 'Paste a Noor mobile JSON backup to restore this device.'
                    : 'الصق نسخة Noor الاحتياطية بصيغة JSON لاستعادتها على هذا الجهاز.',
                onTap: () => _restoreBackup(context, app),
              ),
              _DataRow(
                icon: Icons.history_toggle_off_rounded,
                title: english ? 'Clear viewing history' : 'مسح سجل المشاهدة',
                detail: english ? '$historyCount records' : '$historyCount سجل',
                destructive: true,
                onTap: () => _confirm(
                  context,
                  title:
                      english ? 'Clear viewing history?' : 'مسح سجل المشاهدة؟',
                  body: english
                      ? 'This also removes your Continue Watching progress.'
                      : 'سيؤدي هذا أيضًا إلى إزالة تقدم «متابعة المشاهدة».',
                  onConfirm: app.clearHistory,
                ),
              ),
              _DataRow(
                icon: Icons.delete_outline_rounded,
                title: english
                    ? 'Clear library and history'
                    : 'مسح المكتبة والسجل',
                detail: english
                    ? 'Remove saved titles and playback records from this device.'
                    : 'إزالة العناوين المحفوظة وسجلات التشغيل من هذا الجهاز.',
                destructive: true,
                onTap: () => _confirm(
                  context,
                  title: english ? 'Clear your library?' : 'مسح مكتبتك؟',
                  body: english
                      ? 'Your add-ons stay installed on this device.'
                      : 'ستبقى الإضافات مثبتة على هذا الجهاز.',
                  onConfirm: app.clearLibraryData,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                english
                    ? 'Provider API credentials are kept on this device and excluded from cloud sync.'
                    : 'تُحفظ مفاتيح الخدمات على هذا الجهاز ولا تدخل ضمن المزامنة السحابية.',
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

  Future<void> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required Future<void> Function() onConfirm,
  }) async {
    final english = context.read<AppState>().english;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(english ? 'Cancel' : 'إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(english ? 'Clear' : 'مسح')),
        ],
      ),
    );
    if (accepted == true) await onConfirm();
  }
}

class _SupabaseSyncCard extends StatefulWidget {
  const _SupabaseSyncCard({required this.app});
  final AppState app;

  @override
  State<_SupabaseSyncCard> createState() => _SupabaseSyncCardState();
}

class _SupabaseSyncCardState extends State<_SupabaseSyncCard> {
  bool _busy = false;
  final Map<String, DateTime?> _lastSync = {};

  @override
  void initState() {
    super.initState();
    _loadLastSync();
  }

  Future<void> _loadLastSync() async {
    for (final bucket in NoorSyncService.buckets) {
      _lastSync[bucket] = await NoorSyncService.instance.lastSyncAt(bucket);
    }
    if (mounted) setState(() {});
  }

  Future<void> _syncNow() async {
    final english = widget.app.english;
    setState(() => _busy = true);
    final ok = await widget.app.syncNow();
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

  String _bucketLabel(String bucket, bool english) => switch (bucket) {
        NoorSyncService.bucketSettings => english ? 'Settings' : 'الإعدادات',
        NoorSyncService.bucketLibrary =>
          english ? 'Continue watching' : 'متابعة المشاهدة',
        NoorSyncService.bucketLists => english ? 'Lists' : 'القوائم',
        NoorSyncService.bucketWatchlist => english ? 'Watchlist' : 'المحفوظات',
        NoorSyncService.bucketHistory => english ? 'History' : 'السجل',
        NoorSyncService.bucketAddons => english ? 'Add-ons' : 'الإضافات',
        _ => bucket,
      };

  String _format(DateTime? last, bool english) {
    if (last == null) return english ? 'Never' : 'لم تتم بعد';
    final local = last.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    // Task 122-c F4: scoped select — the sync card reads only the UI
    // language, the cloud-sync flag and the short device id.
    final (english, enabled, shortId) =
        context.select<AppState, (bool, bool, String)>((app) {
      final id = app.deviceId ?? '';
      return (
        app.english,
        app.webSettings['cloudSyncEnabled'] != false,
        id.length >= 8 ? id.substring(0, 8) : (id.isEmpty ? '—' : id),
      );
    });
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
              const Icon(Icons.cloud_sync_outlined,
                  color: HorseTheme.gold, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  english
                      ? 'Cloud sync (Supabase)'
                      : 'مزامنة سحابية (Supabase)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              SettingsOptimisticSwitch(
                value: enabled,
                onChanged: (value) => context
                    .read<AppState>()
                    .setSetting('cloudSyncEnabled', value),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            english
                ? 'Accountless device sync · Device $shortId'
                : 'بدون حساب — مزامنة عبر معرّف الجهاز · الجهاز $shortId',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (enabled)
            ...NoorSyncService.buckets.map(
              (bucket) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _bucketLabel(bucket, english),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      _format(_lastSync[bucket], english),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: HorseTheme.muted),
                    ),
                  ],
                ),
              ),
            ),
          if (!enabled)
            Text(
              english
                  ? 'Sync is off — data stays on this device only.'
                  : 'المزامنة متوقفة — ستبقى البيانات على هذا الجهاز فقط.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.tonal(
              onPressed: _busy ? null : _syncNow,
              child: _busy
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(english ? 'Sync now' : 'مزامنة الآن'),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _restoreBackup(BuildContext context, AppState app) async {
  final english = app.english;
  final backup = await showDialog<String>(
    context: context,
    builder: (_) => _RestoreBackupDialog(english: english),
  );
  if (backup != null && context.mounted) {
    try {
      await app.restoreLocalData(backup);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(english ? 'Backup restored.' : 'تمت استعادة النسخة.'),
        ));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString().replaceFirst('FormatException: ', '')),
        ));
      }
    }
  }
}

/// Lists the on-disk torrent downloads (`<docs>/torrents/<hash>/`) with
/// their sizes and offers per-torrent / clear-all deletion.
class _TorrentDownloadsCard extends StatefulWidget {
  const _TorrentDownloadsCard();

  @override
  State<_TorrentDownloadsCard> createState() => _TorrentDownloadsCardState();
}

class _TorrentEntry {
  _TorrentEntry({required this.hash, required this.size, required this.files});

  final String hash;
  final int size;
  final int files;
}

class _TorrentDownloadsCardState extends State<_TorrentDownloadsCard> {
  List<_TorrentEntry>? _entries;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    final entries = <_TorrentEntry>[];
    try {
      final docs = await getApplicationDocumentsDirectory();
      final root = Directory('${docs.path}/torrents');
      if (await root.exists()) {
        await for (final dir in root.list()) {
          if (dir is! Directory) continue;
          var size = 0;
          var files = 0;
          await for (final entity in dir.list(
            recursive: true,
            followLinks: false,
          )) {
            if (entity is File) {
              try {
                size += await entity.length();
                files += 1;
              } catch (_) {
                // File vanished mid-scan — ignore.
              }
            }
          }
          entries.add(
            _TorrentEntry(
              hash: dir.uri.pathSegments.where((s) => s.isNotEmpty).last,
              size: size,
              files: files,
            ),
          );
        }
      }
    } catch (_) {
      // Storage scan failed — show the empty state rather than an error.
    }
    entries.sort((a, b) => b.size.compareTo(a.size));
    if (mounted) setState(() => _entries = entries);
  }

  Future<void> _delete(_TorrentEntry entry) async {
    setState(() => _busy = true);
    try {
      try {
        await TorrentService.instance.remove(entry.hash, deleteFiles: true);
      } catch (_) {
        // Not in the engine anymore — just clean the disk below.
      }
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/torrents/${entry.hash}');
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // Best effort; rescan below reflects what actually remains.
    }
    if (mounted) {
      setState(() => _busy = false);
      await _scan();
    }
  }

  Future<void> _clearAll() async {
    final entries = _entries;
    if (entries == null || entries.isEmpty) return;
    setState(() => _busy = true);
    for (final entry in entries) {
      try {
        await TorrentService.instance.remove(entry.hash, deleteFiles: true);
      } catch (_) {
        // Ignore engine misses.
      }
      try {
        final docs = await getApplicationDocumentsDirectory();
        final dir = Directory('${docs.path}/torrents/${entry.hash}');
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {
        // Best effort.
      }
    }
    if (mounted) {
      setState(() => _busy = false);
      await _scan();
    }
  }

  static String _formatSize(int bytes) {
    if (bytes <= 0) return '—';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    final exp = math.min(
      (math.log(bytes) / math.log(1024)).floor(),
      units.length - 1,
    );
    final value = bytes / math.pow(1024, exp);
    final text = value >= 100 || exp <= 1
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$text ${units[exp]}';
  }

  @override
  Widget build(BuildContext context) {
    // Task 122-c F4: this card only localizes itself — entries are local
    // scan state, so the UI language is the only AppState read.
    final english = context.select<AppState, bool>((app) => app.english);
    final entries = _entries;
    final total = entries?.fold<int>(0, (sum, e) => sum + e.size) ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HorseTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HorseTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: HorseTheme.gold, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  english ? 'Torrent downloads' : 'تنزيلات التورنت',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (entries != null && entries.isNotEmpty)
                TextButton(
                  onPressed: _busy ? null : _clearAll,
                  child: Text(
                    english ? 'Clear all' : 'حذف الكل',
                    style: const TextStyle(color: Color(0xFFE0705A)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            entries == null
                ? (english ? 'Checking storage…' : 'جارٍ فحص التخزين…')
                : entries.isEmpty
                    ? (english
                        ? 'Nothing on disk — streamed torrents can be kept for instant resume.'
                        : 'لا شيء على القرص — التورنتات المشاهدة تُحفظ للاستئناف الفوري.')
                    : (english
                        ? '${entries.length} torrent(s) · ${_formatSize(total)} on disk'
                        : '${entries.length} تورنت · ${_formatSize(total)} على القرص'),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: HorseTheme.muted),
          ),
          if (entries != null && entries.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.hash.length > 18
                                  ? '${entry.hash.substring(0, 18)}…'
                                  : entry.hash,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontFamily: 'monospace',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_formatSize(entry.size)} · ${entry.files} ${english ? 'files' : 'ملف'}',
                              style: const TextStyle(
                                color: HorseTheme.muted,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: english ? 'Delete' : 'حذف',
                        onPressed:
                            _busy ? null : () => unawaited(_delete(entry)),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 20,
                          color: Color(0xFFE0705A),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

class _RestoreBackupDialog extends StatefulWidget {
  const _RestoreBackupDialog({required this.english});
  final bool english;

  @override
  State<_RestoreBackupDialog> createState() => _RestoreBackupDialogState();
}

class _RestoreBackupDialogState extends State<_RestoreBackupDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.english ? 'Restore backup' : 'استعادة النسخة'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: _controller,
            minLines: 5,
            maxLines: 10,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              hintText:
                  widget.english ? 'Paste backup JSON' : 'الصق نص JSON هنا',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(widget.english ? 'Cancel' : 'إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: Text(widget.english ? 'Restore' : 'استعادة'),
          ),
        ],
      );
}

/// Cache auto-reset card (user request): pick the interval at which the app
/// resets its transient storage (default 12 h — torrent temp files + image
/// cache) and run a reset right now. Lives next to the torrent downloads
/// card because that is the payload being cleaned.
class _CacheResetCard extends StatelessWidget {
  const _CacheResetCard();

  // (hours, arabic, english)
  static const List<(int, String, String)> _choices = [
    (0, 'إيقاف', 'Off'),
    (1, 'كل ساعة', 'Every hour'),
    (3, 'كل 3 ساعات', 'Every 3 hours'),
    (6, 'كل 6 ساعات', 'Every 6 hours'),
    (12, 'كل 12 ساعة', 'Every 12 hours'),
    (24, 'كل 24 ساعة', 'Every 24 hours'),
    (48, 'كل 48 ساعة', 'Every 48 hours'),
  ];

  static String _labelFor(int hours, bool english) {
    for (final (value, arabic, eng) in _choices) {
      if (value == hours) return english ? eng : arabic;
    }
    final fallback = _choices.firstWhere(
      (choice) => choice.$1 == CacheResetService.defaultHours,
    );
    return english ? fallback.$3 : fallback.$2;
  }

  @override
  Widget build(BuildContext context) {
    final (english, hours) = context.select<AppState, (bool, int)>(
      (app) => (
        app.english,
        CacheResetService.hoursFromSettings(app.webSettings),
      ),
    );
    final detail = hours <= 0
        ? (english
            ? 'Automatic reset is off — clear manually from this screen.'
            : 'إعادة التعيين التلقائية معطّلة — يمكنك المسح يدويًا من هذه الشاشة.')
        : (english
            ? 'Torrent temp files and the image cache are reset ${_labelFor(hours, true).toLowerCase()}.'
            : 'تُعاد تعيين ملفات التورنت المؤقتة وذاكرة الصور ${_labelFor(hours, false)}');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: HorseTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: const BorderSide(color: HorseTheme.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: () => unawaited(_openSheet(context)),
          minVerticalPadding: 10,
          leading:
              const Icon(Icons.auto_delete_outlined, color: HorseTheme.gold),
          title: Text(english
              ? 'Reset temporary storage'
              : 'إعادة تعيين الذاكرة المؤقتة'),
          subtitle: Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: Text(
            _labelFor(hours, english),
            style: const TextStyle(color: HorseTheme.gold),
          ),
        ),
      ),
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    final app = context.read<AppState>();
    final english = app.english;
    final current = CacheResetService.hoursFromSettings(app.webSettings);
    var busy = false;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: HorseTheme.surface,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 4),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    english
                        ? 'Reset temporary storage'
                        : 'إعادة تعيين الذاكرة المؤقتة',
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 10),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    english
                        ? 'Clears downloaded torrent temp files and the image '
                            'cache when the interval elapses. The torrent '
                            'currently streaming is never touched.'
                        : 'تمسح ملفات التورنت المؤقتة وذاكرة الصور عند انتهاء '
                            'المدة المحددة، ولا تُمس ملفات التورنت الذي يُبث الآن.',
                    style: Theme.of(sheetContext)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: HorseTheme.muted),
                  ),
                ),
              ),
              for (final (hours, arabic, label) in _choices)
                ListTile(
                  leading: Icon(
                    current == hours
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color:
                        current == hours ? HorseTheme.gold : HorseTheme.muted,
                  ),
                  title: Text(english ? label : arabic),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    unawaited(app.setSetting('cacheResetHours', hours));
                  },
                ),
              const Divider(height: 8),
              ListTile(
                enabled: !busy,
                leading: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: HorseTheme.gold,
                        ),
                      )
                    : const Icon(
                        Icons.cleaning_services_rounded,
                        color: HorseTheme.gold,
                      ),
                title: Text(english ? 'Reset now' : 'إعادة التعيين الآن'),
                onTap: busy
                    ? null
                    : () async {
                        setSheetState(() => busy = true);
                        final freed =
                            await CacheResetService.instance.performReset();
                        if (!sheetContext.mounted) return;
                        Navigator.pop(sheetContext);
                        if (!context.mounted) return;
                        final megs = freed / (1024 * 1024);
                        NoorToast.show(
                          context,
                          megs >= 0.1
                              ? (english
                                  ? 'Cache cleared — ${megs.toStringAsFixed(1)} MB freed.'
                                  : 'تم مسح الذاكرة المؤقتة — تم تحرير ${megs.toStringAsFixed(1)} م.ب.')
                              : (english
                                  ? 'Cache cleared — nothing to free.'
                                  : 'تم مسح الذاكرة المؤقتة — لا يوجد ما يُحرَّر.'),
                        );
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.icon,
    required this.title,
    required this.detail,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: HorseTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: HorseTheme.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            onTap: onTap,
            minVerticalPadding: 10,
            leading: Icon(icon,
                color: destructive ? HorseTheme.danger : HorseTheme.gold),
            title: Text(title,
                style: TextStyle(
                    color: destructive ? const Color(0xFFFFA29B) : null)),
            subtitle:
                Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing:
                const Icon(Icons.chevron_left_rounded, color: HorseTheme.muted),
          ),
        ),
      );
}

class SettingsAboutPage extends StatelessWidget {
  const SettingsAboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final english = context.select<AppState, bool>((app) => app.english);
    return Scaffold(
      appBar: AppBar(title: Text(english ? 'About Noor' : 'حول Noor')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: HorseTheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: HorseTheme.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Noor',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    // Task 137: on-device build verification — the exact
                    // pubspec version, so "did the update reach me?" is
                    // answerable in two taps (Settings → حول Noor).
                    Text(
                      english
                          ? 'Version $noorVersionLabel'
                          : 'الإصدار $noorVersionLabel',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: HorseTheme.gold),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      english
                          ? 'An independent, open-source media center for the Stremio add-on protocol. Noor is not affiliated with Stremio, does not host or ship media, and users install their own add-ons.'
                          : 'مركز وسائط مستقل ومفتوح المصدر لبروتوكول إضافات Stremio. لا يرتبط Noor بـ Stremio ولا يستضيف أو يوزّع محتوى؛ ويثبّت المستخدم إضافاته بنفسه.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      english
                          ? 'MIT licensed. Attribution: Harbor desktop project.'
                          : 'مرخّص بموجب MIT. الإسناد: مشروع Harbor لسطح المكتب.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: HorseTheme.muted),
                    ),
                    const SizedBox(height: 12),
                    const SelectableText('github.com/harborstremio/harbor'),
                    const Divider(height: 28),
                    Text(
                      english
                          ? 'Movie metadata and images may be provided by TMDB.'
                          : 'قد تُقدَّم بيانات الأفلام وصورها عبر TMDB.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: HorseTheme.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
