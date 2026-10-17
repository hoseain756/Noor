import 'package:nova_mobile/l10n/nova_strings.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/media_item.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';
import '../../core/torrent/torrent_models.dart';
import '../../core/torrent/torrent_service.dart';
import '../player/video_player_page.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../shared/widgets/shimmer_box.dart';

/// Set while the magnet sheet is on screen so a second incoming link
/// (e.g. another tap on a magnet URL) does not stack sheets.
bool _flowOpen = false;

/// Opens the paste-a-magnet flow: validates the user input, resolves the
/// torrent metadata on-device, lets the user pick a video file and pushes
/// the player streaming straight from the built-in torrent engine.
///
/// Pass [initialMagnet] (e.g. from an incoming `magnet:` intent) to skip
/// the paste step and start resolving right away.
///
/// Everything happens locally — no account, no server, no login.
Future<void> openMagnetFlow(
  BuildContext context, {
  String? initialMagnet,
}) async {
  if (_flowOpen) return;
  final app = context.read<AppState>();
  final english = app.english;
  final messenger = ScaffoldMessenger.of(context);

  bool supported = false;
  try {
    supported = await TorrentService.instance.isSupported;
  } catch (_) {
    supported = false;
  }
  if (!supported) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          NovaStrings.lookup(english, 'message706'),
        ),
      ),
    );
    return;
  }
  if (!context.mounted) return;
  _flowOpen = true;
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 800),
      useSafeArea: true,
      backgroundColor: NovaTheme.of(context).surface,
      barrierColor: NovaColors.scrim,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _MagnetSheet(initialMagnet: initialMagnet),
    );
  } finally {
    _flowOpen = false;
  }
}

class _MagnetSheet extends StatefulWidget {
  const _MagnetSheet({this.initialMagnet});

  /// Magnet link to start resolving immediately (incoming VIEW intent).
  final String? initialMagnet;

  @override
  State<_MagnetSheet> createState() => _MagnetSheetState();
}

enum _Stage { input, resolving, files, preparing }

class _MagnetSheetState extends State<_MagnetSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  _Stage _stage = _Stage.input;
  String? _error;
  Timer? _ticker;
  int _elapsed = 0;
  TorrentMetadata? _meta;
  String _magnet = '';
  int _selectedFile = -1;
  PreparedTorrent? _prepared;

  bool get _english => context.read<AppState>().english;

  @override
  void initState() {
    super.initState();
    final magnet = widget.initialMagnet;
    if (magnet != null && magnet.trim().isNotEmpty) {
      _controller.text = magnet.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _start();
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Accepts a full magnet URI, a bare 40-char hex info hash (v1) or a
  /// 32-char base32 hash. Returns a normalized magnet URI or null.
  String? _normalize(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final lower = text.toLowerCase();
    if (lower.startsWith('magnet:')) {
      final match = RegExp(r'urn:btih:([a-z0-9]+)').firstMatch(lower);
      final hash = match?.group(1);
      if (hash == null) return null;
      if (!_validHash(hash)) return null;
      return text;
    }
    if (_validHash(lower)) {
      return TorrentService.magnetFor(lower);
    }
    return null;
  }

  bool _validHash(String hash) {
    if (hash.length == 40) {
      return RegExp(r'^[0-9a-f]{40}$').hasMatch(hash);
    }
    if (hash.length == 32) {
      return RegExp(r'^[a-z2-7]{32}$').hasMatch(hash);
    }
    return false;
  }

  Future<void> _start() async {
    final magnet = _normalize(_controller.text);
    if (magnet == null) {
      setState(() {
        _error = NovaStrings.lookup(_english, 'message707');
      });
      return;
    }
    setState(() {
      _error = null;
      _magnet = magnet;
      _stage = _Stage.resolving;
      _elapsed = 0;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += 1);
    });
    try {
      final meta = await TorrentService.instance.resolve(magnet);
      if (!mounted) return;
      final videoFiles = _videoFiles(meta);
      if (videoFiles.isEmpty) {
        _ticker?.cancel();
        setState(() {
          _stage = _Stage.input;
          _error = NovaStrings.lookup(_english, 'message708');
        });
        return;
      }
      _ticker?.cancel();
      if (videoFiles.length == 1) {
        await _play(meta, videoFiles.first.index);
        return;
      }
      setState(() {
        _meta = meta;
        _selectedFile =
            videoFiles.reduce((a, b) => a.size >= b.size ? a : b).index;
        _stage = _Stage.files;
      });
    } on TorrentException catch (error) {
      _ticker?.cancel();
      if (!mounted) return;
      setState(() {
        _stage = _Stage.input;
        _error =
            NovaStrings.lookup(_english, 'message709', {'p0': error.message});
      });
    } catch (_) {
      _ticker?.cancel();
      if (!mounted) return;
      setState(() {
        _stage = _Stage.input;
        _error = NovaStrings.lookup(_english, 'message710');
      });
    }
  }

  List<TorrentFileInfo> _videoFiles(TorrentMetadata meta) {
    const extensions = [
      '.mp4',
      '.mkv',
      '.avi',
      '.webm',
      '.mov',
      '.flv',
      '.ts',
      '.rmvb',
      '.m2ts',
    ];
    return meta.files
        .where((file) =>
            extensions.any((ext) => file.name.toLowerCase().endsWith(ext)))
        .toList();
  }

  Future<void> _play(TorrentMetadata meta, int fileIndex) async {
    final english = _english;
    final file = meta.files.firstWhere((f) => f.index == fileIndex);
    setState(() {
      _stage = _Stage.preparing;
      _error = null;
    });
    PreparedTorrent? prepared;
    try {
      prepared = await TorrentService.instance.prepare(
        infoHash: meta.infoHash,
        magnet: _magnet,
        filename: file.name,
        filesize: file.size,
        displayName: meta.name,
      );
      if (!mounted) {
        unawaited(prepared.stop());
        return;
      }
      final item = MediaItem(
        id: 'torrent:${meta.infoHash}',
        type: 'movie',
        name: meta.name,
      );
      final navigator = Navigator.of(context, rootNavigator: true);
      // prepare() returns only after the local range server is bound. Hand off
      // immediately; the server and player buffer missing pieces while the
      // torrent continues downloading.
      if (!mounted) {
        unawaited(prepared.stop());
        return;
      }
      // Final local so the route-builder closure sees a promoted non-null
      // value (Dart does not promote captured non-final variables).
      final torrent = prepared;
      navigator.pop();
      await navigator.push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => VideoPlayerPage(
            item: item,
            url: torrent.url,
            torrent: torrent,
            streamName: file.name,
            videoId: 'torrent:${meta.infoHash}',
          ),
        ),
      );
    } on TorrentException catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _restoreStage();
        _error =
            NovaStrings.lookup(english, 'message711', {'p0': error.message});
      });
    } catch (_) {
      if (!mounted) return;
      unawaited(prepared?.stop());
      if (!mounted) return;
      setState(() {
        _stage = _restoreStage();
        _error = NovaStrings.lookup(english, 'message712');
      });
    }
  }

  /// After a failed prepare, return to the file picker when the torrent has
  /// several videos, otherwise back to the paste field.
  _Stage _restoreStage() {
    final meta = _meta;
    if (meta != null && _videoFiles(meta).length > 1) return _Stage.files;
    return _Stage.input;
  }

  Future<void> _cancelPreparing() async {
    final prepared = _prepared;
    _prepared = null;
    if (prepared != null) {
      unawaited(prepared.stop());
      unawaited(TorrentService.instance.remove(prepared.infoHash));
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  String _formatSize(int bytes) {
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
    final english = _english;
    final scheme = Theme.of(context).colorScheme;
    final index = switch (_stage) {
      _Stage.input => 0,
      _Stage.resolving => 0,
      _Stage.files => 1,
      _Stage.preparing => 2
    };
    final stages = [
      NovaStrings.lookup(english, 'message38'),
      NovaStrings.lookup(english, 'message713'),
      NovaStrings.lookup(english, 'message714')
    ];
    return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsetsDirectional.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .88),
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 32),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Icon(LucideIcons.magnet,
                          color: scheme.secondary, size: 32),
                      const SizedBox(width: 16),
                      Expanded(
                          child: Text(NovaStrings.lookup(english, 'message715'),
                              style:
                                  Theme.of(context).textTheme.headlineSmall)),
                      IconButton(
                          onPressed: _cancelPreparing,
                          tooltip: NovaStrings.lookup(english, 'close'),
                          icon: const Icon(LucideIcons.x))
                    ]),
                    const SizedBox(height: 16),
                    Text(NovaStrings.lookup(english, 'message716'),
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 24),
                    Wrap(spacing: 16, runSpacing: 12, children: [
                      for (var i = 0; i < stages.length; i++)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          CircleAvatar(
                              radius: 14,
                              backgroundColor: i == index
                                  ? scheme.primary
                                  : scheme.surfaceContainerHigh,
                              child: Text('${i + 1}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: i == index
                                          ? scheme.onPrimary
                                          : scheme.onSurfaceVariant))),
                          const SizedBox(width: 8),
                          Text(stages[i],
                              style: TextStyle(
                                  fontWeight: i == index
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: i == index
                                      ? scheme.onSurface
                                      : scheme.onSurfaceVariant))
                        ])
                    ]),
                    const SizedBox(height: 32),
                    switch (_stage) {
                      _Stage.input => _buildInput(english),
                      _Stage.resolving => _buildResolving(english),
                      _Stage.files => _buildFiles(english),
                      _Stage.preparing => _buildPreparing(english)
                    },
                  ]),
            ),
          ),
        ));
  }

  Widget _buildInput(bool english) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          maxLines: 4,
          textDirection: TextDirection.ltr,
          minLines: 1,
          style: const TextStyle(fontSize: 13.5, height: 1.35),
          decoration: InputDecoration(
            hintText: NovaStrings.lookup(english, 'message717'),
            hintStyle:
                TextStyle(color: NovaTheme.of(context).muted, fontSize: 12.5),
            filled: true,
            fillColor: NovaTheme.of(context).raised,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: NovaTheme.of(context).line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: NovaTheme.of(context).line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: NovaTheme.of(context).gold),
            ),
            suffixIcon: IconButton(
              tooltip: NovaStrings.lookup(english, 'message718'),
              onPressed: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                final text = data?.text?.trim();
                if (text != null && text.isNotEmpty) {
                  _controller.text = text;
                  if (mounted) setState(() => _error = null);
                }
              },
              icon: Icon(LucideIcons.clipboard,
                  size: 20, color: NovaTheme.of(context).muted),
            ),
          ),
          onSubmitted: (_) => _start(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(LucideIcons.circleAlert,
                  color: NovaTheme.of(context).theme.colorScheme.error,
                  size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
          onPressed: _start,
          icon: const Icon(LucideIcons.play, size: 21),
          label: Text(
            NovaStrings.lookup(english, 'message719'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
          ),
        ),
      ],
    );
  }

  Widget _buildResolving(bool english) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          const Column(children: [
            ShimmerBox(height: 56),
            SizedBox(height: 12),
            ShimmerBox(height: 56)
          ]),
          const SizedBox(height: 16),
          Text(
            NovaStrings.lookup(english, 'message720', {'p0': _elapsed}),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            NovaStrings.lookup(english, 'message721'),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: NovaTheme.of(context).muted),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              _ticker?.cancel();
              Navigator.of(context).pop();
            },
            child: Text(NovaStrings.lookup(english, 'cancel')),
          ),
        ],
      ),
    );
  }

  Widget _buildFiles(bool english) {
    final meta = _meta;
    if (meta == null) return const SizedBox.shrink();
    final videos = _videoFiles(meta);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: NovaTheme.of(context).raised,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: NovaTheme.of(context).line),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.film,
                  color: NovaTheme.of(context).gold, size: 19),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  meta.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .42),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: videos.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final file = videos[i];
              final selected = file.index == _selectedFile;
              return Material(
                color: selected
                    ? NovaTheme.of(context).gold.withValues(alpha: .12)
                    : NovaTheme.of(context).raised,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: selected
                        ? NovaTheme.of(context).gold
                        : NovaTheme.of(context).line,
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _selectedFile = file.index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          selected
                              ? LucideIcons.circleCheck
                              : LucideIcons.circle,
                          color: selected
                              ? NovaTheme.of(context).gold
                              : NovaTheme.of(context).muted,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            file.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatSize(file.size),
                          style: TextStyle(
                            color: NovaTheme.of(context).muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
          onPressed: () => _play(meta, _selectedFile),
          icon: const Icon(LucideIcons.play, size: 21),
          label: Text(
            NovaStrings.lookup(english, 'message722'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
          ),
        ),
      ],
    );
  }

  Widget _buildPreparing(bool english) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          const Column(children: [
            ShimmerBox(height: 56),
            SizedBox(height: 12),
            ShimmerBox(height: 56)
          ]),
          const SizedBox(height: 16),
          Text(
            NovaStrings.lookup(english, 'message650'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            NovaStrings.lookup(english, 'message723'),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: NovaTheme.of(context).muted),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _cancelPreparing,
            child: Text(NovaStrings.lookup(english, 'cancel')),
          ),
        ],
      ),
    );
  }
}
