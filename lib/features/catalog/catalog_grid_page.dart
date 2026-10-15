import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/media_item.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';
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

class _CatalogGridPageState extends State<CatalogGridPage> {
  List<MediaItem>? _items;
  bool _loading = false;
  bool _failed = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
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
    final app = context.watch<AppState>();
    final english = app.english;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final gridTileExtent = 185 / .72 + 68 * textScale + 12;
    final items = _items ?? const <MediaItem>[];
    final onOpen = widget.onOpen;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title),
            if (widget.subtitle != null)
              Text(
                widget.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: HorseTheme.muted),
              ),
          ],
        ),
        actions: [
          if (widget.loader != null)
            IconButton(
              tooltip: english ? 'Refresh' : 'تحديث',
              onPressed: () => unawaited(_load()),
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1250),
          child: _loading && items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _failed && items.isEmpty
                  ? AppStateMessage(
                      icon: Icons.movie_filter_outlined,
                      iconSize: 42,
                      padding: const EdgeInsets.all(24),
                      message: english
                          ? 'This catalog could not be loaded.'
                          : 'تعذر تحميل هذا الكتالوج.',
                      actionLabel: english ? 'Try again' : 'إعادة المحاولة',
                      onAction: () => unawaited(_load()),
                    )
                  : items.isEmpty && !_loading
                      ? AppStateMessage(
                          icon: Icons.movie_filter_outlined,
                          iconSize: 42,
                          padding: const EdgeInsets.all(24),
                          message: english
                              ? 'No titles are available in this catalog.'
                              : 'لا توجد عناوين في هذا الكتالوج.',
                          actionLabel: english ? 'Refresh' : 'تحديث',
                          onAction: () => unawaited(_load()),
                        )
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
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return PosterCard(
                              item: item,
                              width: double.infinity,
                              onTap: () => onOpen != null
                                  ? onOpen(item)
                                  : Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            MediaDetailPage(item: item),
                                      ),
                                    ),
                            );
                          },
                        ),
        ),
      ),
    );
  }
}
