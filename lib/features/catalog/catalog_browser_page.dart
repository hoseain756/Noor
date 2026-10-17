import 'package:nova_mobile/l10n/nova_strings.dart';
import '../shell/nova_catalog_refresh.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/media_item.dart';
import '../../core/state/app_state.dart';
import '../../shared/widgets/app_state_message.dart';
import '../../shared/widgets/poster_card.dart';
import '../media/media_detail_page.dart';
import '../shell/nova_browse_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum CatalogBrowseMode { discover, movies, shows, catalogs }

class CatalogBrowserPage extends StatefulWidget {
  const CatalogBrowserPage({super.key, required this.mode});

  final CatalogBrowseMode mode;

  @override
  State<CatalogBrowserPage> createState() => _CatalogBrowserPageState();
}

class _CatalogBrowserPageState extends State<CatalogBrowserPage>
    with NovaCatalogRefresh<CatalogBrowserPage> {
  @override
  void refreshCachedCatalogs() {
    if (!_loading) unawaited(_load(query: _search.text.trim()));
  }

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
        CatalogBrowseMode.discover => NovaStrings.lookup(english, 'message576'),
        CatalogBrowseMode.movies => NovaStrings.lookup(english, 'message577'),
        CatalogBrowseMode.shows => NovaStrings.lookup(english, 'message578'),
        CatalogBrowseMode.catalogs => NovaStrings.lookup(english, 'message579'),
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
        if (query.isNotEmpty &&
            !item.name.toLowerCase().contains(query.toLowerCase())) {
          return false;
        }
        if (hideWatched && watchedIds.contains(item.id)) return false;
        return seen.add(item.id);
      }).toList();
      setState(() {
        _items = items;
        _loading = false;
        if (items.isEmpty && results.every((rows) => rows.isEmpty)) {
          _error = NovaStrings.lookup(app.english, 'message580');
        }
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = NovaStrings.lookup(app.english, 'message581');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    context.select<AppState, bool>((app) => app.english);
    final app = context.read<AppState>();
    final showTypeFilter = widget.mode == CatalogBrowseMode.discover ||
        widget.mode == CatalogBrowseMode.catalogs;
    final items = _items
        .where((item) => _typeFilter == 'all' || item.type == _typeFilter)
        .toList();
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
    return Scaffold(
      appBar: AppBar(title: Text(app.tr('message582')), actions: [
        IconButton(
            tooltip: app.tr('message68'),
            onPressed: () => unawaited(_load(query: _search.text.trim())),
            icon: const Icon(LucideIcons.refreshCw))
      ]),
      body: Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1440),
        child: RefreshIndicator(
          onRefresh: () => _load(query: _search.text.trim()),
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(
                child: NovaBrowseHeader(
              compact: true,
              eyebrow: app.tr('message583'),
              title: _title(app.english),
              subtitle: widget.mode == CatalogBrowseMode.catalogs
                  ? app.tr('message584')
                  : app.tr('message585'),
            )),
            SliverToBoxAdapter(
                child: Padding(
                    padding:
                        const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 16),
                    child: TextField(
                        controller: _search,
                        onChanged: _onSearch,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                            prefixIcon: const Icon(LucideIcons.search),
                            hintText: app.tr('message586'),
                            suffixIcon: _search.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: app.tr('message473'),
                                    onPressed: () {
                                      _search.clear();
                                      _onSearch('');
                                    },
                                    icon: const Icon(LucideIcons.x)))))),
            SliverToBoxAdapter(
                child: Padding(
                    padding:
                        const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 24),
                    child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (showTypeFilter)
                            for (final entry in [
                              ('all', app.tr('message587')),
                              ('movie', app.tr('message106')),
                              ('series', app.tr('message107'))
                            ])
                              ChoiceChip(
                                  label: Text(entry.$2),
                                  selected: _typeFilter == entry.$1,
                                  onSelected: (_) =>
                                      setState(() => _typeFilter = entry.$1)),
                          SizedBox(
                              width: 200,
                              child: DropdownButtonFormField<String>(
                                  initialValue: _sort,
                                  decoration: InputDecoration(
                                      labelText: app.tr('message588')),
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() => _sort = value);
                                    }
                                  },
                                  items: [
                                    for (final entry in [
                                      ('popular', app.tr('message589')),
                                      ('rating', app.tr('message158')),
                                      ('year', app.tr('message441')),
                                      ('title', app.tr('message440'))
                                    ])
                                      DropdownMenuItem(
                                          value: entry.$1,
                                          child: Text(entry.$2))
                                  ])),
                        ]))),
            if (_loading && _items.isEmpty)
              const SliverToBoxAdapter(
                  child: SizedBox(height: 600, child: NovaBrowseSkeleton()))
            else if (items.isEmpty)
              SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppStateMessage(
                      icon: _error != null
                          ? LucideIcons.cloudOff
                          : LucideIcons.search,
                      message: _error ?? app.tr('message590'),
                      actionLabel: app.tr('message174'),
                      onAction: () =>
                          unawaited(_load(query: _search.text.trim()))))
            else ...[
              if (_loading)
                const SliverToBoxAdapter(
                    child: LinearProgressIndicator(minHeight: 2)),
              SliverPadding(
                  padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 48),
                  sliver: SliverLayoutBuilder(builder: (context, constraints) {
                    final columns =
                        (constraints.crossAxisExtent / 190).floor().clamp(2, 7);
                    final width =
                        (constraints.crossAxisExtent - (columns - 1) * 20) /
                            columns;
                    return SliverGrid.builder(
                        itemCount: items.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            mainAxisExtent: width / .72 +
                                78 * MediaQuery.textScalerOf(context).scale(1),
                            crossAxisSpacing: 20,
                            mainAxisSpacing: 24),
                        itemBuilder: (context, index) => PosterCard(
                            item: items[index],
                            width: width,
                            onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                    builder: (_) =>
                                        MediaDetailPage(item: items[index])))));
                  })),
            ],
          ]),
        ),
      )),
    );
  }
}
