import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/catalog_repository.dart';
import '../../core/models/media_item.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';
import '../media/media_detail_page.dart';

/// Live anime search over AniList's public GraphQL (works without linking).
/// Debounced, poster-grid results; tapping a result resolves it to a
/// playable Stremio entry and opens the shared detail page.
Future<void> showAnimeSearchSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AnimeSearchSheet(),
  );
}

class _AnimeSearchSheet extends StatefulWidget {
  const _AnimeSearchSheet();

  @override
  State<_AnimeSearchSheet> createState() => _AnimeSearchSheetState();
}

class _AnimeSearchSheetState extends State<_AnimeSearchSheet> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  Future<List<MediaItem>>? _results;
  final Set<String> _resolving = {};

  /// Which provider's catalog the sheet is querying — both searches are
  /// public (no link required) and parse through the same shared row shape.
  String _provider = 'anilist';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      setState(() => _results = _search(value.trim()));
    });
  }

  /// Switching provider re-runs the current query immediately so the grid
  /// reflects the other catalog without requiring a re-type.
  void _switchProvider(String provider) {
    if (provider == _provider) return;
    setState(() {
      _provider = provider;
      final term = _query.text.trim();
      _results = term.isEmpty ? null : _search(term);
    });
  }

  Future<List<MediaItem>> _search(String term) async {
    final app = context.read<AppState>();
    final rows = _provider == 'mal'
        ? await app.api.malSearch(term, limit: 30)
        : await app.api.aniListSearch(term, perPage: 30);
    if (!mounted) return const [];
    // 122 follow-up: honor the ja native-title preference here too, matching
    // the repository's AniList catalog/meta paths.
    return CatalogRepository.parseAnimeResponse(
      {
        'data': {
          'Page': {'media': rows},
        },
      },
      preferNativeTitles: await CatalogRepository.prefersNativeAnimeTitles(),
    );
  }

  Future<void> _open(MediaItem item) async {
    if (!_resolving.add(item.id)) return;
    setState(() {});
    try {
      final app = context.read<AppState>();
      final resolved = await app.catalogs.resolveAnime(item);
      if (!mounted) return;
      if (resolved == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(app.english
                ? 'A playable Stremio entry was not found for this title.'
                : 'لم يُعثر على عنوان قابل للتشغيل لهذا العمل.'),
          ),
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          // Carry the AniList/MAL identity onto the playable item so
          // library toggles and playback mirror to the linked trackers.
          builder: (_) => MediaDetailPage(
            item: resolved.withAnimeIds(
              anilistId: item.anilistId,
              idMal: item.idMal,
            ),
          ),
        ),
      );
    } finally {
      _resolving.remove(item.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final english = context.watch<AppState>().english;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 640),
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: HorseTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: HorseTheme.line),
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _query,
                focusNode: _focus,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: _provider == 'mal'
                      ? (english
                          ? 'Search anime on MyAnimeList…'
                          : 'ابحث عن الأنمي في MyAnimeList…')
                      : (english
                          ? 'Search anime on AniList…'
                          : 'ابحث عن الأنمي في AniList…'),
                  suffixIcon: _query.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 19),
                          onPressed: () {
                            _query.clear();
                            _onChanged('');
                          },
                        ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'anilist', label: Text('AniList')),
                  ButtonSegment(
                    value: 'mal',
                    label: Text('MyAnimeList'),
                  ),
                ],
                selected: {_provider},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    _switchProvider(selection.first),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _results == null
                    ? Center(
                        child: Text(
                          english
                              ? 'Type a title to search.'
                              : 'اكتب اسم عمل للبحث.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: HorseTheme.muted),
                        ),
                      )
                    : FutureBuilder<List<MediaItem>>(
                        future: _results,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          }
                          if (snapshot.hasError) {
                            return Center(
                              child: Text(
                                english
                                    ? 'Search failed — check your connection.'
                                    : 'فشل البحث — تحقق من الاتصال.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: HorseTheme.muted),
                              ),
                            );
                          }
                          final items = snapshot.data ?? const <MediaItem>[];
                          if (items.isEmpty) {
                            return Center(
                              child: Text(
                                english ? 'No results.' : 'لا نتائج.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: HorseTheme.muted),
                              ),
                            );
                          }
                          return GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 108,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: .58,
                            ),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              final busy = _resolving.contains(item.id);
                              return InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: busy ? null : () => _open(item),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            const ColoredBox(
                                              color: HorseTheme.raised,
                                            ),
                                            if (item.poster != null)
                                              Image.network(
                                                item.poster!,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) =>
                                                    const SizedBox(),
                                              ),
                                            if (busy)
                                              const ColoredBox(
                                                color: Colors.black45,
                                                child: Center(
                                                  child: SizedBox.square(
                                                    dimension: 16,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              );
                            },
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
}
