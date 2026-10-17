import '../shell/nova_catalog_refresh.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/media_item.dart';
import '../../core/state/app_state.dart';
import '../shell/nova_browse_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../shared/widgets/app_state_message.dart';
import '../../shared/widgets/poster_card.dart';
import '../media/media_detail_page.dart';

/// Full-page grid for ONE catalog — the "view all" destination of a
/// per-catalog home rail (an add-on catalog or a linked-service list).
/// Accepts either a preloaded [items] snapshot or a [loader] that (re)fetches
/// on demand with a retry affordance.
class CatalogGridPage extends StatefulWidget {
  const CatalogGridPage({
    super.key,
    required this.title,
    this.subtitle,
    this.items,
    this.loader,
    this.onOpen,
  }) : assert(items != null || loader != null, 'Provide items or a loader');

  final String title;

  /// Source line under the title (the add-on name).
  final String? subtitle;
  final List<MediaItem>? items;
  final Future<List<MediaItem>> Function()? loader;

  /// Open handler for a tapped title — the home page passes its
  /// resolve-aware opener so `anilist:`/`mal:` records land on a playable
  /// Stremio identity instead of a dead detail page.
  final ValueChanged<MediaItem>? onOpen;

  @override
  State<CatalogGridPage> createState() => _CatalogGridPageState();
}

class _CatalogGridPageState extends State<CatalogGridPage>
    with NovaCatalogRefresh<CatalogGridPage> {
  @override
  bool get catalogRefreshEnabled => widget.loader != null;

  @override
  void refreshCachedCatalogs() {
    if (!_loading) unawaited(_load());
  }

  List<MediaItem>? _items;
  bool _loading = false;
  bool _failed = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _items = widget.items;
    if (widget.loader != null) {
      unawaited(_load());
    } else {
      _items = widget.items;
    }
  }

  Future<void> _load() async {
    final loader = widget.loader;
    if (loader == null) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final items = await loader();
      if (!mounted || request != _request) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    context.select<AppState, bool>((app) => app.english);
    final app = context.read<AppState>();
    final items = _items ?? const <MediaItem>[];
    return Scaffold(
      appBar: AppBar(title: Text(app.tr('message591')), actions: [
        if (widget.loader != null)
          IconButton(
              tooltip: app.tr('message68'),
              onPressed: () => unawaited(_load()),
              icon: const Icon(LucideIcons.refreshCw))
      ]),
      body: Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1440),
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
              child: NovaBrowseHeader(
                  compact: true,
                  eyebrow: widget.subtitle ?? app.tr('message592'),
                  title: widget.title,
                  subtitle: app.tr('message593'))),
          if (_loading && items.isEmpty)
            const SliverToBoxAdapter(
                child: SizedBox(height: 600, child: NovaBrowseSkeleton()))
          else if (items.isEmpty)
            SliverFillRemaining(
                hasScrollBody: false,
                child: AppStateMessage(
                    icon: _failed ? LucideIcons.cloudOff : LucideIcons.library,
                    message:
                        _failed ? app.tr('message594') : app.tr('message595'),
                    actionLabel:
                        widget.loader == null ? null : app.tr('message174'),
                    onAction: widget.loader == null
                        ? null
                        : () => unawaited(_load())))
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
                          onTap: () => widget.onOpen != null
                              ? widget.onOpen!(items[index])
                              : Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                      builder: (_) => MediaDetailPage(
                                          item: items[index])))));
                })),
          ],
        ]),
      )),
    );
  }
}
