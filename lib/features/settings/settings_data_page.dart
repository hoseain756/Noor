import 'package:noor_mobile/l10n/nova_strings.dart';
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
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/torrent/torrent_service.dart';
import '../../core/version.dart';
import '../../shared/widgets/noor_toast.dart';
import 'widgets/settings_tiles.dart';
import '../downloads/downloads_page.dart';

class SettingsDataPage extends StatelessWidget {
  const SettingsDataPage({super.key, this.section = 'all'});
  final String section;

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
          title: Text(section == 'storage'
              ? app.tr('message345')
              : section == 'account'
                  ? app.tr('message346')
                  : app.tr('message347'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 48),
            children: [
              SettingsPageIntro(
                  title: section == 'storage'
                      ? app.tr('message348')
                      : section == 'account'
                          ? app.tr('message349')
                          : app.tr('message350'),
                  description: section == 'storage'
                      ? app.tr('message351')
                      : section == 'account'
                          ? app.tr('message352')
                          : app.tr('message353'),
                  icon: section == 'storage'
                      ? LucideIcons.hardDrive
                      : section == 'account'
                          ? LucideIcons.cloud
                          : LucideIcons.shieldCheck),
              if (section == 'account' || section == 'all')
                _SupabaseSyncCard(app: app),
              if (section == 'storage' || section == 'all') ...[
                SettingsTile(
                    icon: LucideIcons.download,
                    title: app.tr('downloads'),
                    subtitle: app.tr('downloadIntro'),
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const DownloadsPage()))),
                const _TorrentDownloadsCard(),
                const _CacheResetCard(),
              ],
              if (section == 'privacy' || section == 'all') ...[
                _DataRow(
                  icon: LucideIcons.download,
                  title: NovaStrings.lookup(english, 'message354'),
                  detail: NovaStrings.lookup(english, 'message355',
                      {'p0': savedCount, 'p1': historyCount}),
                  onTap: () async {
                    await Clipboard.setData(
                        ClipboardData(text: await app.exportLocalData()));
                    if (!context.mounted) return;
                    NoorToast.show(
                      context,
                      NovaStrings.lookup(english, 'message356'),
                    );
                  },
                ),
                _DataRow(
                  icon: LucideIcons.rotateCcw,
                  title: NovaStrings.lookup(english, 'message357'),
                  detail: NovaStrings.lookup(english, 'message358'),
                  onTap: () => _restoreBackup(context, app),
                ),
                _DataRow(
                  icon: LucideIcons.history,
                  title: NovaStrings.lookup(english, 'message359'),
                  detail: NovaStrings.lookup(
                      english, 'message360', {'p0': historyCount}),
                  destructive: true,
                  onTap: () => _confirm(
                    context,
                    title: NovaStrings.lookup(english, 'message361'),
                    body: NovaStrings.lookup(english, 'message362'),
                    onConfirm: app.clearHistory,
                  ),
                ),
                _DataRow(
                  icon: LucideIcons.trash2,
                  title: NovaStrings.lookup(english, 'message363'),
                  detail: NovaStrings.lookup(english, 'message364'),
                  destructive: true,
                  onTap: () => _confirm(
                    context,
                    title: NovaStrings.lookup(english, 'message365'),
                    body: NovaStrings.lookup(english, 'message366'),
                    onConfirm: app.clearLibraryData,
                  ),
                ),
              ],
              SizedBox(height: 24),
              Text(
                NovaStrings.lookup(english, 'message367'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
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
              child: Text(NovaStrings.lookup(english, 'cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(NovaStrings.lookup(english, 'message368'))),
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
              ? (NovaStrings.lookup(english, 'message369'))
              : (NovaStrings.lookup(english, 'message370')),
        ),
      ),
    );
  }

  String _bucketLabel(String bucket, bool english) => switch (bucket) {
        NoorSyncService.bucketSettings =>
          NovaStrings.lookup(english, 'settings'),
        NoorSyncService.bucketLibrary =>
          NovaStrings.lookup(english, 'message371'),
        NoorSyncService.bucketLists =>
          NovaStrings.lookup(english, 'message372'),
        NoorSyncService.bucketWatchlist =>
          NovaStrings.lookup(english, 'message373'),
        NoorSyncService.bucketHistory =>
          NovaStrings.lookup(english, 'message374'),
        NoorSyncService.bucketAddons =>
          NovaStrings.lookup(english, 'message220'),
        _ => bucket,
      };

  String _format(DateTime? last, bool english) {
    if (last == null) return NovaStrings.lookup(english, 'message375');
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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.cloud,
                  color: Theme.of(context).colorScheme.secondary, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  NovaStrings.lookup(english, 'message376'),
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
          SizedBox(height: 4),
          Text(
            NovaStrings.lookup(english, 'message377', {'p0': shortId}),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          SizedBox(height: 12),
          if (enabled)
            ...NoorSyncService.buckets.map(
              (bucket) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _bucketLabel(bucket, english),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      _format(_lastSync[bucket], english),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          if (!enabled)
            Text(
              NovaStrings.lookup(english, 'message378'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.tonal(
              onPressed: _busy ? null : _syncNow,
              child: _busy
                  ? SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(NovaStrings.lookup(english, 'message379')),
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
          content: Text(NovaStrings.lookup(english, 'message380')),
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
  String? _scanError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    final entries = <_TorrentEntry>[];
    _scanError = null;
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
      if (mounted) _scanError = context.read<AppState>().tr('message381');
    }
    entries.sort((a, b) => b.size.compareTo(a.size));
    if (mounted) setState(() => _entries = entries);
  }

  Future<void> _delete(_TorrentEntry entry) async {
    final app = context.read<AppState>();
    if (!await confirmSettingsAction(context,
        title: app.tr('message382'),
        message: app.tr('message383'),
        confirm: app.tr('message384'),
        cancel: app.tr('cancel'))) return;
    if (!mounted) return;
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
    final app = context.read<AppState>();
    if (!await confirmSettingsAction(context,
        title: app.tr('message385'),
        message: app.tr('message386'),
        confirm: app.tr('message387'),
        cancel: app.tr('cancel'))) return;
    if (!mounted) return;
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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.zap,
                  color: Theme.of(context).colorScheme.secondary, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  NovaStrings.lookup(english, 'message388'),
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
                    NovaStrings.lookup(english, 'message389'),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
          SizedBox(height: 4),
          Text(
            entries == null
                ? (NovaStrings.lookup(english, 'message390'))
                : entries.isEmpty
                    ? (NovaStrings.lookup(english, 'message391'))
                    : (NovaStrings.lookup(english, 'message392',
                        {'p0': entries.length, 'p1': _formatSize(total)})),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          if (entries == null)
            const Padding(
                padding: EdgeInsetsDirectional.only(top: 16),
                child: LinearProgressIndicator()),
          if (_scanError != null) ...[
            SettingsInfoBanner(message: _scanError!, error: true),
            TextButton(
                onPressed: _scan,
                child: Text(NovaStrings.lookup(english, 'message393'))),
          ],
          if (entries != null && entries.isNotEmpty) ...[
            SizedBox(height: 10),
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
                              style: TextStyle(
                                fontSize: 12.5,
                                fontFamily: 'monospace',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: 2),
                            Text(
                              '${_formatSize(entry.size)} · ${entry.files} ${NovaStrings.lookup(english, 'message394')}',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: NovaStrings.lookup(english, 'message384'),
                        onPressed:
                            _busy ? null : () => unawaited(_delete(entry)),
                        icon: Icon(
                          LucideIcons.trash2,
                          size: 20,
                          color: Theme.of(context).colorScheme.error,
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
        title: Text(NovaStrings.lookup(widget.english, 'message395')),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: _controller,
            minLines: 5,
            maxLines: 10,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              hintText: NovaStrings.lookup(widget.english, 'message396'),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(NovaStrings.lookup(widget.english, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: Text(NovaStrings.lookup(widget.english, 'message397')),
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
        ? (NovaStrings.lookup(english, 'message398'))
        : (NovaStrings.lookup(english, 'message399', {
            'p0': _labelFor(hours, true).toLowerCase(),
            'p1': _labelFor(hours, false)
          }));
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: () => unawaited(_openSheet(context)),
          minVerticalPadding: 10,
          leading: Icon(LucideIcons.hardDrive,
              color: Theme.of(context).colorScheme.secondary),
          title: Text(NovaStrings.lookup(english, 'message400')),
          subtitle:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_labelFor(hours, english),
                style:
                    TextStyle(color: Theme.of(context).colorScheme.secondary)),
            const SizedBox(height: 6),
            Text(detail),
          ]),
          trailing: Icon(Directionality.of(context) == TextDirection.rtl
              ? LucideIcons.chevronLeft
              : LucideIcons.chevronRight),
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
      backgroundColor: Theme.of(context).colorScheme.surface,
      showDragHandle: true,
      isScrollControlled: true,
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
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
                    NovaStrings.lookup(english, 'message400'),
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 10),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    NovaStrings.lookup(english, 'message401'),
                    style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
              for (final (hours, arabic, label) in _choices)
                ListTile(
                  leading: Icon(
                    current == hours
                        ? LucideIcons.circleDot
                        : LucideIcons.circle,
                    color: current == hours
                        ? Theme.of(context).colorScheme.secondary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
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
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      )
                    : Icon(
                        LucideIcons.brushCleaning,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                title: Text(NovaStrings.lookup(english, 'message402')),
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
                              ? (NovaStrings.lookup(english, 'message403',
                                  {'p0': megs.toStringAsFixed(1)}))
                              : (NovaStrings.lookup(english, 'message404')),
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
          color: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side:
                BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            onTap: onTap,
            minVerticalPadding: 10,
            leading: Icon(icon,
                color: destructive
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.secondary),
            title: Text(title,
                style: TextStyle(
                    color: destructive
                        ? Theme.of(context).colorScheme.error
                        : null)),
            subtitle:
                Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? LucideIcons.chevronLeft
                    : LucideIcons.chevronRight,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
}

class SettingsAboutPage extends StatelessWidget {
  const SettingsAboutPage({super.key});
  @override
  Widget build(BuildContext context) {
    context.select<AppState, bool>((app) => app.english);
    final app = context.read<AppState>();
    return Scaffold(
        appBar: AppBar(title: Text(app.tr('message405'))),
        body: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 16, 24, 48),
              children: [
                Center(
                    child: Image.asset(
                        'assets/brand/android/play_store/ic_launcher-playstore-512.png',
                        width: 104,
                        height: 104,
                        filterQuality: FilterQuality.medium)),
                const SizedBox(height: 24),
                Text('NOVA',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800, letterSpacing: 8)),
                const SizedBox(height: 8),
                Text(app.tr('message406', {'p0': noorVersionLabel}),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.secondary)),
                const SizedBox(height: 32),
                Text(app.tr('message407'),
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                Text(app.tr('message408'),
                    style: Theme.of(context).textTheme.bodyLarge),
                SettingsContentSection(title: app.tr('message409'), children: [
                  SettingsTile(
                      icon: LucideIcons.codeXml,
                      title: app.tr('message410'),
                      subtitle: app.tr('message411'),
                      onTap: () => showLicensePage(
                          context: context,
                          applicationName: 'NOVA',
                          applicationVersion: noorVersionLabel)),
                  Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(app.tr('message412')),
                            const SizedBox(height: 8),
                            const SelectableText(
                                'github.com/harborstremio/harbor'),
                          ])),
                  Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(app.tr('message413'))),
                ]),
                SettingsInfoBanner(message: app.tr('message414')),
              ]),
        )));
  }
}
