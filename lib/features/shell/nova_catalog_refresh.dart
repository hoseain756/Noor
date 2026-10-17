import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/data/catalog_response_cache.dart';

/// Reuses cached rows after a stale response refresh. Initial network loads do
/// not emit cache revisions. Only visible destinations refresh; hidden tabs
/// defer until their TickerMode/route becomes active, preserving scroll state.
mixin NovaCatalogRefresh<T extends StatefulWidget> on State<T> {
  Timer? _cacheRefreshDebounce;
  late int _seenCacheRevision;

  bool get catalogRefreshEnabled => true;
  void refreshCachedCatalogs();

  @override
  void initState() {
    super.initState();
    _seenCacheRevision = CatalogResponseCache.instance.revision;
    CatalogResponseCache.instance.addListener(_onCacheRefresh);
  }

  bool get _cacheDestinationVisible =>
      mounted &&
      catalogRefreshEnabled &&
      TickerMode.valuesOf(context).enabled &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  void _onCacheRefresh() {
    if (!mounted ||
        _seenCacheRevision == CatalogResponseCache.instance.revision) {
      return;
    }
    _cacheRefreshDebounce?.cancel();
    // Dependency lookups happen in the callback, not during initState.
    _cacheRefreshDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!_cacheDestinationVisible) return;
      _seenCacheRevision = CatalogResponseCache.instance.revision;
      refreshCachedCatalogs();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _onCacheRefresh();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    _onCacheRefresh();
  }

  @override
  void dispose() {
    CatalogResponseCache.instance.removeListener(_onCacheRefresh);
    _cacheRefreshDebounce?.cancel();
    super.dispose();
  }
}
