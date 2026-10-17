import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/downloads/download_manager.dart';
import '../../core/models/media_item.dart';
import '../../l10n/nova_strings.dart';
import '../../shared/widgets/app_state_message.dart';
import '../../shared/widgets/noor_toast.dart';
import '../player/video_player_page.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});
  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  final _manager = DownloadManager.instance;
  @override
  void initState() {
    super.initState();
    _manager.initialize();
  }

  String _size(int bytes) => bytes < 1
      ? '—'
      : bytes >= 1073741824
          ? '${(bytes / 1073741824).toStringAsFixed(1)} GB'
          : '${(bytes / 1048576).toStringAsFixed(1)} MB';
  Future<void> _action(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        NoorToast.show(
            context, NovaStrings.of(context).text('operationFailed'));
      }
    }
  }

  String _failure(String? code) => NovaStrings.of(context).text(switch (code) {
        'storage' => 'downloadStorageError',
        'interrupted' => 'downloadInterrupted',
        'missingFile' => 'downloadMissingFile',
        'invalidSource' => 'downloadInvalidSource',
        _ => 'downloadNetworkError',
      });

  Future<void> _remove(NovaDownload job) async {
    final s = NovaStrings.of(context);
    final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(s.text('downloadDelete')),
                content: Text(s.text('downloadDeleteBody')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(s.text('cancel'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(s.text('remove')))
                ]));
    if (yes == true) await _action(() => _manager.remove(job));
  }

  @override
  Widget build(BuildContext context) {
    final s = NovaStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
        appBar: AppBar(title: Text(s.text('downloads'))),
        body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: AnimatedBuilder(
                  animation: _manager,
                  builder: (context, _) {
                    if (!_manager.initialized) {
                      final error = _manager.initializationError != null;
                      return AppStateMessage(
                        loading: !error,
                        icon: LucideIcons.hardDrive,
                        message: error
                            ? s.text('downloadStorageError')
                            : s.text('downloads'),
                        actionLabel: error ? s.text('retry') : null,
                        onAction:
                            error ? () => _action(_manager.initialize) : null,
                      );
                    }
                    final jobs = _manager.jobs;
                    return CustomScrollView(slivers: [
                      SliverPadding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              24, 24, 24, 32),
                          sliver: SliverToBoxAdapter(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Icon(LucideIcons.download,
                                    size: 32, color: scheme.secondary),
                                const SizedBox(height: 16),
                                Text(s.text('downloadIntro'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium),
                                const SizedBox(height: 12),
                                Text(s.text('downloadForeground'),
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                                if (_manager.storageError != null) ...[
                                  const SizedBox(height: 12),
                                  Text(s.text('downloadStorageError'),
                                      style: TextStyle(color: scheme.error)),
                                ],
                              ]))),
                      if (jobs.isEmpty)
                        SliverFillRemaining(
                            hasScrollBody: false,
                            child: AppStateMessage(
                                icon: LucideIcons.download,
                                message:
                                    '${s.text('downloadsEmpty')}\n${s.text('downloadsEmptyBody')}'))
                      else
                        SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            sliver: SliverList.builder(
                                itemCount: jobs.length,
                                itemBuilder: (context, index) {
                                  final job = jobs[index];
                                  final key = switch (job.status) {
                                    'complete' => 'downloadComplete',
                                    'downloading' => 'downloading',
                                    'queued' => 'downloadQueued',
                                    'cancelled' => 'downloadCancelled',
                                    _ => 'downloadFailed'
                                  };
                                  return Padding(
                                      padding: const EdgeInsetsDirectional.only(
                                          bottom: 24),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(children: [
                                              Container(
                                                  width: 64,
                                                  height: 80,
                                                  decoration: BoxDecoration(
                                                      color: scheme
                                                          .surfaceContainerHigh,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12)),
                                                  child: Icon(
                                                      job.status == 'complete'
                                                          ? LucideIcons
                                                              .circleCheck
                                                          : LucideIcons.film,
                                                      color: scheme.secondary)),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                  child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                    Text(job.title,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .titleMedium),
                                                    const SizedBox(height: 4),
                                                    Text(s.text(key),
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodySmall),
                                                    if (job.status == 'failed')
                                                      Text(_failure(job.error),
                                                          style: TextStyle(
                                                              color: scheme
                                                                  .error)),
                                                    Text(
                                                        s.text(
                                                            'downloadBytes', {
                                                          'received': _size(
                                                              job.received),
                                                          'total':
                                                              _size(job.total)
                                                        }),
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodySmall),
                                                  ]))
                                            ]),
                                            const SizedBox(height: 12),
                                            if (job.status == 'downloading')
                                              LinearProgressIndicator(
                                                  value: job.total > 0
                                                      ? job.received / job.total
                                                      : null,
                                                  semanticsLabel:
                                                      s.text('downloading')),
                                            const SizedBox(height: 8),
                                            Wrap(
                                                spacing: 8,
                                                runSpacing: 8,
                                                children: [
                                                  if (job.status == 'complete')
                                                    FilledButton.icon(
                                                        icon: const Icon(
                                                            LucideIcons.play),
                                                        label: Text(s.text(
                                                            'playOffline')),
                                                        onPressed: () => Navigator.of(context).push(MaterialPageRoute<
                                                                void>(
                                                            builder: (_) => VideoPlayerPage(
                                                                item: MediaItem(
                                                                    id: 'local:${job.id}',
                                                                    name: job.title,
                                                                    type: 'movie'),
                                                                url: job.path,
                                                                streamName: job.title,
                                                                videoId: job.id,
                                                                recordProgress: false))))
                                                  else if (job.status == 'downloading' || job.status == 'queued')
                                                    TextButton(onPressed: () => _action(() => _manager.cancel(job)), child: Text(s.text('cancel')))
                                                  else
                                                    OutlinedButton.icon(onPressed: () => _action(() => _manager.retry(job)), icon: const Icon(LucideIcons.rotateCw), label: Text(s.text('retry'))),
                                                  TextButton.icon(
                                                      onPressed: () =>
                                                          _remove(job),
                                                      icon: const Icon(
                                                          LucideIcons.trash2),
                                                      label: Text(
                                                          s.text('remove'))),
                                                ]),
                                            const SizedBox(height: 16),
                                            Divider(
                                                color: scheme.outlineVariant),
                                          ]));
                                })),
                      const SliverToBoxAdapter(child: SizedBox(height: 48)),
                    ]);
                  })),
        ));
  }
}
