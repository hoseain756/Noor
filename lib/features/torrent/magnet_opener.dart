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
          english
              ? 'Torrent streaming needs a device with the built-in torrent engine (Android) or a connected Debrid service.'
              : 'البث عبر التورنت يحتاج جهازًا يدعم محرك التورنت المدمج (أندرويد) أو خدمة Debrid متصلة.',
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
      useSafeArea: true,
      backgroundColor: HorseTheme.surface,
      barrierColor: Colors.black54,
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
        _error = _english
            ? 'Paste a magnet link or a 40-character info hash.'
            : 'الصق رابط magnet أو معرّف info hash بطول 40 حرفًا.';
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
          _error = _english
              ? 'No playable video files found in this torrent.'
              : 'لا توجد ملفات فيديو قابلة للتشغيل في هذا التورنت.';
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
        _error = _english
            ? 'Could not fetch torrent info: ${error.message}'
            : 'تعذّر جلب معلومات التورنت: ${error.message}';
      });
    } catch (_) {
      _ticker?.cancel();
      if (!mounted) return;
      setState(() {
        _stage = _Stage.input;
        _error = _english
            ? 'Could not fetch torrent info. Check the link and your connection.'
            : 'تعذّر جلب معلومات التورنت. تحقق من الرابط والاتصال.';
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
        _error = english
            ? 'Failed to start the stream: ${error.message}'
            : 'فشل بدء البث: ${error.message}';
      });
    } catch (_) {
      if (!mounted) return;
      unawaited(prepared?.stop());
      if (!mounted) return;
      setState(() {
        _stage = _restoreStage();
        _error = english
            ? 'Failed to start the stream. Try again.'
            : 'فشل بدء البث. حاول مرة أخرى.';
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
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: HorseTheme.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: HorseTheme.gold.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.bolt_rounded,
                      color: HorseTheme.gold,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      english ? 'Open torrent' : 'فتح تورنت',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                english
                    ? 'Paste a magnet link — it plays directly on this device, no account needed.'
                    : 'الصق رابط magnet — يعمل مباشرة على هذا الجهاز بدون حساب.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: HorseTheme.muted),
              ),
              const SizedBox(height: 16),
              switch (_stage) {
                _Stage.input => _buildInput(english),
                _Stage.resolving => _buildResolving(english),
                _Stage.files => _buildFiles(english),
                _Stage.preparing => _buildPreparing(english),
              },
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInput(bool english) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          maxLines: 3,
          minLines: 1,
          style: const TextStyle(fontSize: 13.5, height: 1.35),
          decoration: InputDecoration(
            hintText: english
                ? 'magnet:?xt=urn:btih:…  or info hash'
                : 'magnet:?xt=urn:btih:…  أو info hash',
            hintStyle: const TextStyle(color: HorseTheme.muted, fontSize: 12.5),
            filled: true,
            fillColor: HorseTheme.raised,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: HorseTheme.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: HorseTheme.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: HorseTheme.gold),
            ),
            suffixIcon: IconButton(
              tooltip: english ? 'Paste' : 'لصق',
              onPressed: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                final text = data?.text?.trim();
                if (text != null && text.isNotEmpty) {
                  _controller.text = text;
                  if (mounted) setState(() => _error = null);
                }
              },
              icon: const Icon(Icons.content_paste_rounded,
                  size: 20, color: HorseTheme.muted),
            ),
          ),
          onSubmitted: (_) => _start(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Color(0xFFE0705A), size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFE0705A),
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
            backgroundColor: HorseTheme.gold,
            foregroundColor: const Color(0xFF16130D),
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
          onPressed: _start,
          icon: const Icon(Icons.play_arrow_rounded, size: 21),
          label: Text(
            english ? 'Stream' : 'تشغيل',
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
          const SizedBox.square(
            dimension: 30,
            child: CircularProgressIndicator(strokeWidth: 2.6),
          ),
          const SizedBox(height: 16),
          Text(
            english
                ? 'Fetching torrent info…  ${_elapsed}s'
                : 'جارٍ جلب معلومات التورنت…  ${_elapsed}s',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            english
                ? 'Talking to the swarm — usually a few seconds.'
                : 'الاتصال بالشبكة — عادةً يستغرق ثوانٍ قليلة.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: HorseTheme.muted),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              _ticker?.cancel();
              Navigator.of(context).pop();
            },
            child: Text(english ? 'Cancel' : 'إلغاء'),
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
            color: HorseTheme.raised,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: HorseTheme.line),
          ),
          child: Row(
            children: [
              const Icon(Icons.movie_outlined,
                  color: HorseTheme.gold, size: 19),
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
          constraints: const BoxConstraints(maxHeight: 260),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: videos.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final file = videos[i];
              final selected = file.index == _selectedFile;
              return Material(
                color: selected
                    ? HorseTheme.gold.withValues(alpha: .12)
                    : HorseTheme.raised,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: selected ? HorseTheme.gold : HorseTheme.line,
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
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: selected ? HorseTheme.gold : HorseTheme.muted,
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
                          style: const TextStyle(
                            color: HorseTheme.muted,
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
            backgroundColor: HorseTheme.gold,
            foregroundColor: const Color(0xFF16130D),
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
          onPressed: () => _play(meta, _selectedFile),
          icon: const Icon(Icons.play_arrow_rounded, size: 21),
          label: Text(
            english ? 'Play selected' : 'تشغيل المحدد',
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
          const SizedBox.square(
            dimension: 30,
            child: CircularProgressIndicator(strokeWidth: 2.6),
          ),
          const SizedBox(height: 16),
          Text(
            english ? 'Preparing the stream…' : 'جارٍ تجهيز البث…',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            english
                ? 'Connecting to peers and buffering the first pieces.'
                : 'الاتصال بالمشاركين وتحميل الأجزاء الأولى.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: HorseTheme.muted),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _cancelPreparing,
            child: Text(english ? 'Cancel' : 'إلغاء'),
          ),
        ],
      ),
    );
  }
}
