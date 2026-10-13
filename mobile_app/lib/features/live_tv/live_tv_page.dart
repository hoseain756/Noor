import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/iptv_parser.dart';
import '../../core/models/media_item.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';
import '../player/video_player_page.dart';

class LiveTvPage extends StatefulWidget {
  const LiveTvPage({super.key});

  @override
  State<LiveTvPage> createState() => _LiveTvPageState();
}

class _LiveTvPageState extends State<LiveTvPage> {
  List<_LiveChannel> _channels = const [];
  Map<String, List<IptvProgram>> _guide = const {};
  bool _loading = false;
  String? _error;
  String _group = 'all';
  String _query = '';
  int _loadToken = 0;

  List<Map<String, dynamic>> _playlists(AppState app) =>
      (app.webSettings['iptvPlaylists'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .where((row) => row['url'] is String)
          .toList();

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final token = ++_loadToken;
    final app = context.read<AppState>();
    final playlists = _playlists(app);
    if (playlists.isEmpty) {
      setState(() {
        _channels = const [];
        _guide = const {};
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    final channels = <_LiveChannel>[];
    final guide = <String, List<IptvProgram>>{};
    var failures = 0;
    for (final playlist in playlists) {
      final url = playlist['url']!.toString();
      final name = (playlist['name'] ?? 'Playlist').toString();
      try {
        final text = await app.api.proxyText(url);
        final parsed = parseM3u(text);
        channels.addAll(parsed.map((channel) => _LiveChannel(
              playlistId: playlist['id']?.toString() ?? name,
              playlistName: name,
              channel: channel,
            )));
      } catch (_) {
        failures++;
      }

      final epgUrl = (playlist['epgUrl'] ?? '').toString().trim();
      if (epgUrl.isNotEmpty) {
        try {
          final xml = await app.api.proxyText(epgUrl);
          final parsed = parseXmltv(xml);
          for (final entry in parsed.entries) {
            guide.putIfAbsent(entry.key, () => []).addAll(entry.value);
          }
        } catch (_) {
          // A missing or malformed guide must not hide usable channels.
        }
      }
    }
    if (!mounted || token != _loadToken) return;
    setState(() {
      _channels = channels;
      _guide = guide;
      _loading = false;
      if (channels.isEmpty && failures > 0) {
        _error = app.english
            ? 'Could not load these playlists. Check their URLs and try again.'
            : 'تعذر تحميل قوائم القنوات. تحقق من الروابط ثم أعد المحاولة.';
      }
    });
  }

  Future<void> _addPlaylist() async {
    final english = context.read<AppState>().english;
    final entry = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _AddPlaylistDialog(english: english),
    );
    if (entry == null || !mounted) return;
    final app = context.read<AppState>();
    final playlists = _playlists(app);
    playlists.add({
      'id': 'mobile-${DateTime.now().microsecondsSinceEpoch}',
      'name': entry['name']!.isEmpty
          ? (app.english
              ? 'Playlist ${playlists.length + 1}'
              : 'قائمة ${playlists.length + 1}')
          : entry['name'],
      'url': entry['url'],
      if (entry['epgUrl']?.isNotEmpty == true) 'epgUrl': entry['epgUrl'],
    });
    await app.setSetting('iptvPlaylists', playlists);
    await _reload();
  }

  Future<void> _removePlaylist(String id) async {
    final app = context.read<AppState>();
    final next = _playlists(app)
      ..removeWhere((playlist) => playlist['id']?.toString() == id);
    await app.setSetting('iptvPlaylists', next);
    await _reload();
  }

  IptvProgram? _nowProgram(IptvChannel channel) {
    final id = channel.tvgId;
    if (id == null) return null;
    final now = DateTime.now();
    for (final program in _guide[id] ?? const <IptvProgram>[]) {
      if (!now.isBefore(program.start) && now.isBefore(program.stop)) {
        return program;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final english = app.english;
    final groups = _channels
        .map((entry) => entry.channel.group ?? (english ? 'General' : 'عام'))
        .toSet()
        .toList()
      ..sort();
    final visible = _channels.where((entry) {
      final group = entry.channel.group ?? (english ? 'General' : 'عام');
      final matchesGroup = _group == 'all' || group == _group;
      final matchesQuery = _query.isEmpty ||
          entry.channel.name.toLowerCase().contains(_query.toLowerCase());
      return matchesGroup && matchesQuery;
    }).toList();
    final playlists = _playlists(app);
    return Scaffold(
      appBar: AppBar(
        title: Text(english ? 'Live TV' : 'البث المباشر'),
        actions: [
          IconButton(
              tooltip: english ? 'Add playlist' : 'إضافة قائمة',
              onPressed: _addPlaylist,
              icon: const Icon(Icons.add_rounded)),
          IconButton(
              tooltip: english ? 'Refresh' : 'تحديث',
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            children: [
              if (playlists.isNotEmpty)
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 4),
                    scrollDirection: Axis.horizontal,
                    itemCount: playlists.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      final id = playlist['id']?.toString() ?? '';
                      return InputChip(
                        avatar:
                            const Icon(Icons.playlist_play_rounded, size: 18),
                        label:
                            Text((playlist['name'] ?? 'Playlist').toString()),
                        onDeleted: () => _removePlaylist(id),
                      );
                    },
                  ),
                ),
              if (_channels.isNotEmpty)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          onChanged: (value) =>
                              setState(() => _query = value.trim()),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search_rounded),
                            hintText:
                                english ? 'Find a channel' : 'ابحث عن قناة',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      DropdownButton<String>(
                        value: _group == 'all' || groups.contains(_group)
                            ? _group
                            : 'all',
                        underline: const SizedBox.shrink(),
                        onChanged: (value) =>
                            setState(() => _group = value ?? 'all'),
                        items: [
                          DropdownMenuItem(
                              value: 'all',
                              child: Text(
                                  english ? 'All groups' : 'كل المجموعات')),
                          for (final group in groups)
                            DropdownMenuItem(
                                value: group,
                                child: Text(group,
                                    overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ],
                  ),
                ),
              if (_loading) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: _error != null
                    ? _StateMessage(
                        message: _error!,
                        action: english ? 'Retry' : 'إعادة المحاولة',
                        onPressed: _reload)
                    : playlists.isEmpty
                        ? _StateMessage(
                            message: english
                                ? 'Add an M3U playlist to browse live channels.'
                                : 'أضف قائمة M3U لعرض القنوات المباشرة.',
                            action: english ? 'Add playlist' : 'إضافة قائمة',
                            onPressed: _addPlaylist,
                          )
                        : _channels.isEmpty && !_loading
                            ? _StateMessage(
                                message: english
                                    ? 'No channels were found in these playlists.'
                                    : 'لم يتم العثور على قنوات في هذه القوائم.',
                                action: english ? 'Refresh' : 'تحديث',
                                onPressed: _reload)
                            : ListView.separated(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    16, 6, 16, 28),
                                itemCount: visible.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final entry = visible[index];
                                  final channel = entry.channel;
                                  final program = _nowProgram(channel);
                                  final playable =
                                      _isHttp(Uri.tryParse(channel.url));
                                  return Card(
                                    child: ListTile(
                                      minTileHeight: 74,
                                      leading: SizedBox(
                                        width: 64,
                                        height: 54,
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(9),
                                          child: channel.logo == null
                                              ? const ColoredBox(
                                                  color: HorseTheme.raised,
                                                  child: Icon(
                                                      Icons.live_tv_rounded,
                                                      color: HorseTheme.gold))
                                              : Image.network(channel.logo!,
                                                  fit: BoxFit.contain,
                                                  errorBuilder: (_, __, ___) =>
                                                      const ColoredBox(
                                                          color:
                                                              HorseTheme.raised,
                                                          child: Icon(
                                                              Icons
                                                                  .live_tv_rounded,
                                                              color: HorseTheme
                                                                  .gold))),
                                        ),
                                      ),
                                      title: Text(channel.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      subtitle: Text(
                                        [
                                          entry.playlistName,
                                          if (program != null) program.title,
                                          if (!playable)
                                            (english
                                                ? 'Unsupported stream format'
                                                : 'صيغة بث غير مدعومة')
                                        ].join(' · '),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: Icon(
                                          playable
                                              ? Icons.play_circle_fill_rounded
                                              : Icons.error_outline_rounded,
                                          color: playable
                                              ? HorseTheme.gold
                                              : HorseTheme.muted),
                                      onTap:
                                          playable ? () => _play(entry) : null,
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _play(_LiveChannel entry) async {
    final channel = entry.channel;
    final item = MediaItem(
      id: 'live:${entry.playlistId}:${channel.tvgId ?? channel.name}',
      type: 'movie',
      name: channel.name,
      poster: channel.logo,
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => VideoPlayerPage(
          item: item,
          url: channel.url,
          streamName: channel.name,
          videoId: item.id,
          recordProgress: false,
        ),
      ),
    );
  }
}

class _AddPlaylistDialog extends StatefulWidget {
  const _AddPlaylistDialog({required this.english});
  final bool english;

  @override
  State<_AddPlaylistDialog> createState() => _AddPlaylistDialogState();
}

class _AddPlaylistDialogState extends State<_AddPlaylistDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _epg = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _epg.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.english ? 'Add live playlist' : 'إضافة قائمة قنوات'),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: InputDecoration(
                      labelText: widget.english ? 'Name' : 'الاسم'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                      labelText: widget.english ? 'M3U URL' : 'رابط M3U'),
                  validator: (value) =>
                      _isHttp(Uri.tryParse(value?.trim() ?? ''))
                          ? null
                          : (widget.english
                              ? 'Enter a valid HTTP or HTTPS URL.'
                              : 'أدخل رابط HTTP أو HTTPS صالحًا.'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _epg,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                      labelText: widget.english
                          ? 'Optional XMLTV guide URL'
                          : 'رابط دليل XMLTV اختياري'),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty || _isHttp(Uri.tryParse(text))) {
                      return null;
                    }
                    return widget.english
                        ? 'Enter a valid HTTP or HTTPS URL.'
                        : 'أدخل رابط HTTP أو HTTPS صالحًا.';
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(widget.english ? 'Cancel' : 'إلغاء')),
          FilledButton(
            onPressed: () {
              if (_formKey.currentState?.validate() != true) return;
              final playlistUri = Uri.parse(_url.text.trim());
              final guideText = _epg.text.trim();
              Navigator.pop(context, {
                'name': _name.text.trim(),
                'url': playlistUri.toString(),
                if (guideText.isNotEmpty)
                  'epgUrl': Uri.parse(guideText).toString(),
              });
            },
            child: Text(widget.english ? 'Add' : 'إضافة'),
          ),
        ],
      );
}

class _LiveChannel {
  const _LiveChannel(
      {required this.playlistId,
      required this.playlistName,
      required this.channel});
  final String playlistId;
  final String playlistName;
  final IptvChannel channel;
}

class _StateMessage extends StatelessWidget {
  const _StateMessage(
      {required this.message, required this.action, required this.onPressed});
  final String message;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.live_tv_outlined,
                  size: 44, color: HorseTheme.muted),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton.icon(
                  onPressed: onPressed,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(action)),
            ],
          ),
        ),
      );
}

bool _isHttp(Uri? uri) =>
    uri != null &&
    uri.hasAuthority &&
    (uri.scheme == 'http' || uri.scheme == 'https');
