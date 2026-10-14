import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/media_item.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';
import '../../shared/widgets/poster_card.dart';
import '../media/media_detail_page.dart';

enum CatalogBrowseMode { discover, movies, shows, catalogs }

class CatalogBrowserPage extends StatefulWidget {
  const CatalogBrowserPage({super.key, required this.mode});

  final CatalogBrowseMode mode;

  @override
  State<CatalogBrowserPage> createState() => _CatalogBrowserPageState();
}

class _CatalogBrowserPageState extends State<CatalogBrowserPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<MediaItem> _items = const [];
  bool _loading = true;
  String? _error;
  String _typeFilter = 'all';
  String _sort = 'popular';
  int _request = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  String _title(bool english) => switch (widget.mode) {
        CatalogBrowseMode.discover => english ? 'Discover' : 'اكتشف',
        CatalogBrowseMode.movies => english ? 'Movies' : 'الأفلام',
        CatalogBrowseMode.shows => english ? 'Series' : 'المسلسلات',
        CatalogBrowseMode.catalogs =>
          english ? 'Add-on catalogs' : 'كتالوجات الإضافات',
      };

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_load(query: value.trim()));
    });
  }

  Future<List<MediaItem>> _safe(Future<List<MediaItem>> future) async {
    try {
      return await future;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _load({String query = ''}) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    final app = context.read<AppState>();
    final catalog = app.catalogs;
    final searchQuery = query.length >= 2 ? query : null;
    final jobs = <Future<List<MediaItem>>>[];

    switch (widget.mode) {
      case CatalogBrowseMode.discover:
        if (searchQuery == null) {
          jobs.add(catalog.homeTopTen());
          jobs.add(catalog.catalog('movie', 'top'));
          jobs.add(catalog.catalog('series', 'top'));
          jobs.add(catalog.addonCatalogs(app.addons));
        } else {
          jobs.add(
              catalog.catalog('movie', 'top', extras: {'search': searchQuery}));
          jobs.add(catalog
              .catalog('series', 'top', extras: {'search': searchQuery}));
        }
      case CatalogBrowseMode.movies:
        jobs.add(catalog.catalog('movie', 'top',
            extras: searchQuery == null ? const {} : {'search': searchQuery}));
        if (searchQuery == null) {
          jobs.add(catalog.catalog('movie', 'trailer'));
        }
      case CatalogBrowseMode.shows:
        jobs.add(catalog.catalog('series', 'top',
            extras: searchQuery == null ? const {} : {'search': searchQuery}));
        if (searchQuery == null) {
          jobs.add(catalog.catalog('series', 'trailer'));
        }
      case CatalogBrowseMode.catalogs:
        jobs.add(
            catalog.addonCatalogs(app.addons, showAll: searchQuery == null));
        if (searchQuery != null) {
          jobs.add(
              catalog.catalog('movie', 'top', extras: {'search': searchQuery}));
          jobs.add(catalog
              .catalog('series', 'top', extras: {'search': searchQuery}));
        }
    }

    try {
      final results = await Future.wait(jobs.map(_safe));
      if (!mounted || request != _request) return;
      final seen = <String>{};
      final hideWatched = app.webSettings['hideWatchedInCatalogs'] == true;
      final watchedIds = app.history.map((entry) => entry.item.id).toSet();
      final items = results.expand((rows) => rows).where((item) {
        if (_typeFilter != 'all' && item.type != _typeFilter) return false;
        if (query.isNotEmpty &&
            !item.name.toLowerCase().contains(query.toLowerCase())) {
          return false;
        }
        if (hideWatched && watchedIds.contains(item.id)) return false;
        return seen.add(item.id);
      }).toList();
      switch (_sort) {
        case 'title':
          items.sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        case 'year':
          items.sort((a, b) => (int.tryParse(b.releaseInfo ?? '') ?? 0)
              .compareTo(int.tryParse(a.releaseInfo ?? '') ?? 0));
        case 'rating':
          items.sort((a, b) => (double.tryParse(b.rating ?? '') ?? 0)
              .compareTo(double.tryParse(a.rating ?? '') ?? 0));
      }
      setState(() {
        _items = items;
        _loading = false;
        if (items.isEmpty && results.every((rows) => rows.isEmpty)) {
          _error = app.english
              ? 'Catalogs could not be loaded. Check the connection or add an add-on.'
              : 'تعذر تحميل الكتالوجات. تحقق من الاتصال أو أضف إضافة.';
        }
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = app.english
            ? 'Catalogs could not be loaded.'
            : 'تعذر تحميل الكتالوجات.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final english = app.english;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final gridTileExtent = 185 / .72 + 68 * textScale + 12;
    final showTypeFilter = widget.mode == CatalogBrowseMode.discover ||
        widget.mode == CatalogBrowseMode.catalogs;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title(english)),
        actions: [
          IconButton(
            tooltip: english ? 'Refresh' : 'تحديث',
            onPressed: () => unawaited(_load(query: _search.text.trim())),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1250),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 10),
                child: TextField(
                  controller: _search,
                  onChanged: _onSearch,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: english ? 'Search titles' : 'ابحث عن عنوان',
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: english ? 'Clear search' : 'مسح البحث',
                            onPressed: () {
                              _search.clear();
                              _onSearch('');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 10),
                child: Row(
                  children: [
                    if (showTypeFilter)
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final entry in [
                                ('all', english ? 'All' : 'الكل'),
                                ('movie', english ? 'Movies' : 'أفلام'),
                                ('series', english ? 'Series' : 'مسلسلات'),
                              ])
                                Padding(
                                  padding:
                                      const EdgeInsetsDirectional.only(end: 7),
                                  child: ChoiceChip(
                                    label: Text(entry.$2),
                                    selected: _typeFilter == entry.$1,
                                    onSelected: (_) {
                                      setState(() => _typeFilter = entry.$1);
                                      unawaited(
                                          _load(query: _search.text.trim()));
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    const SizedBox(width: 8),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _sort,
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _sort = value);
                          unawaited(_load(query: _search.text.trim()));
                        },
                        items: [
                          DropdownMenuItem(
                              value: 'popular',
                              child: Text(english ? 'Popular' : 'الرائج')),
                          DropdownMenuItem(
                              value: 'rating',
                              child: Text(english ? 'Rating' : 'التقييم')),
                          DropdownMenuItem(
                              value: 'year',
                              child: Text(english ? 'Year' : 'السنة')),
                          DropdownMenuItem(
                              value: 'title',
                              child: Text(english ? 'Title' : 'العنوان')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_loading) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: _error != null && _items.isEmpty
                    ? _Message(
                        message: _error!,
                        action: english ? 'Try again' : 'إعادة المحاولة',
                        onPressed: () =>
                            unawaited(_load(query: _search.text.trim())))
                    : _items.isEmpty && !_loading
                        ? _Message(
                            message: english
                                ? 'No titles match these filters.'
                                : 'لا توجد عناوين تطابق عوامل التصفية.',
                            action: english ? 'Refresh' : 'تحديث',
                            onPressed: () =>
                                unawaited(_load(query: _search.text.trim())))
                        : GridView.builder(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                16, 8, 16, 120),
                            gridDelegate:
                                SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 185,
                              mainAxisExtent: gridTileExtent,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 14,
                            ),
                            itemCount: _items.length,
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              return PosterCard(
                                item: item,
                                width: double.infinity,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                      builder: (_) =>
                                          MediaDetailPage(item: item)),
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
}

class _Message extends StatelessWidget {
  const _Message(
      {required this.message, required this.action, required this.onPressed});
  final String message;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.movie_filter_outlined,
                  size: 42, color: HorseTheme.muted),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              OutlinedButton(onPressed: onPressed, child: Text(action)),
            ],
          ),
        ),
      );
}
