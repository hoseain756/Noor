import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:noor_mobile/core/api/noor_api.dart';
import 'package:noor_mobile/core/data/catalog_repository.dart';
import 'package:noor_mobile/core/data/catalog_response_cache.dart';
import 'package:noor_mobile/features/shell/nova_catalog_refresh.dart';
import 'package:noor_mobile/core/models/addon.dart';
import 'package:noor_mobile/core/models/media_item.dart';
import 'package:noor_mobile/core/state/app_state.dart';
import 'package:noor_mobile/features/kids/kids_page.dart';
import 'package:noor_mobile/features/library/library_page.dart';
import 'package:noor_mobile/features/shell/glass_dock.dart';
import 'package:noor_mobile/features/shell/noor_dock_tabs.dart';
import 'package:noor_mobile/features/shell/nova_browse_widgets.dart';
import 'package:noor_mobile/features/shell/search_sheet.dart';

class _SearchRepository extends CatalogRepository {
  _SearchRepository(super.api);
  final Map<String, Completer<List<MediaItem>>> pending = {};
  @override
  Future<List<MediaItem>> catalog(String type, String id, {
    Map<String, dynamic> extras = const {}, Addon? addon,
  }) => pending.putIfAbsent('${extras['search']}:$type', Completer<List<MediaItem>>.new).future;
}

class _RefreshProbe extends StatefulWidget {
  const _RefreshProbe();
  @override
  State<_RefreshProbe> createState() => _RefreshProbeState();
}
class _RefreshProbeState extends State<_RefreshProbe> with NovaCatalogRefresh<_RefreshProbe> {
  int refreshes = 0;
  @override
  void refreshCachedCatalogs() => setState(() => refreshes++);
  @override
  Widget build(BuildContext context) => ListView.builder(itemCount: 50,
    itemBuilder: (_, index) => SizedBox(height: 60, child: Text('refresh:$refreshes row:$index')));
}
void _emitRefresh() {
  CatalogResponseCache.instance.revision++;
  // ignore: invalid_use_of_protected_member
  CatalogResponseCache.instance.notifyListeners();
}

void main() {
  test('Kids requires an explicit allowlisted age certificate', () {
    MediaItem title(String? certificate) => MediaItem(id: 'test', type: 'movie', name: 'Family Adventure',
      certification: certificate, genres: const ['Family', 'Animation']);
    for (final certificate in ['G', ' PG ', 'TV-Y', 'TV-Y7', 'TV-G', 'TV-PG', 'U', '0', '6', '7']) {
      expect(novaIsChildRated(title(certificate)), isTrue);
    }
    for (final certificate in [null, '', 'NR', 'R', 'TV-MA', 'PG-13', '12', 'Unrated']) {
      expect(novaIsChildRated(title(certificate)), isFalse,
        reason: 'Family genre alone must never classify an unrated/adult title as safe');
    }
  });

  test('NOVA dock preserves logical order and usable target height', () {
    expect(noorDockTabsFor(rtl: false).map((tab) => tab.id),
      ['home', 'anime', 'kids', 'library', 'settings']);
    expect(noorDockTabsFor(rtl: true).map((tab) => tab.id),
      noorDockTabsFor(rtl: false).map((tab) => tab.id));
    for (final size in [const Size(320, 700), const Size(400, 900), const Size(700, 360), const Size(800, 1000)]) {
      final sizing = glassDockSizing(viewport: size);
      expect(sizing.tabHeight, greaterThanOrEqualTo(48));
      expect(sizing.barWidth, lessThanOrEqualTo(size.width));
    }
  });

  for (final direction in TextDirection.values) {
    for (final brightness in Brightness.values) {
      for (final width in [320.0, 900.0]) {
        testWidgets('browse layout $direction $brightness $width at 200%', (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final api = NoorApi();
          final app = AppState(api, _SearchRepository(api))..english = direction == TextDirection.ltr;
          await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: app,
            child: MaterialApp(theme: ThemeData(brightness: brightness),
              home: MediaQuery(data: MediaQueryData(size: Size(width, 1000),
                textScaler: const TextScaler.linear(2), disableAnimations: true),
                child: Directionality(textDirection: direction, child: const Scaffold(body: LibraryPage()))))));
          await tester.pump();
          expect(tester.takeException(), isNull);
          await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
          await tester.pump();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          app.dispose();
        });
      }
    }
  }

  testWidgets('dock mirrors physically once and labels stay visible', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget host(TextDirection direction) => MaterialApp(home: Directionality(textDirection: direction,
      child: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: GlassDock(
        tabs: noorDockTabsFor(rtl: direction == TextDirection.rtl), activeId: 'home',
        onTabSelected: (_) {}, reduceMotion: true)))));
    await tester.pumpWidget(host(TextDirection.ltr));
    await tester.pump();
    final ltrHome = tester.getCenter(find.byIcon(LucideIcons.house)).dx;
    final ltrSettings = tester.getCenter(find.byIcon(LucideIcons.settings)).dx;
    expect(ltrHome, lessThan(ltrSettings));
    expect(find.text('Home'), findsOneWidget);
    await tester.pumpWidget(host(TextDirection.rtl));
    await tester.pump();
    expect(tester.getCenter(find.byIcon(LucideIcons.house)).dx,
      greaterThan(tester.getCenter(find.byIcon(LucideIcons.settings)).dx));
    expect(find.text('الرئيسية'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cache refresh coalesces and defers hidden pages without resetting scroll', (tester) async {
    final visible = ValueNotifier(true);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ValueListenableBuilder<bool>(
      valueListenable: visible, builder: (_, enabled, child) => TickerMode(enabled: enabled, child: child!),
      child: const _RefreshProbe()))));
    await tester.drag(find.byType(ListView), const Offset(0, -360));
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable)).position;
    final offset = scroll.pixels;
    _emitRefresh(); _emitRefresh(); _emitRefresh();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.state<_RefreshProbeState>(find.byType(_RefreshProbe)).refreshes, 1);
    expect(scroll.pixels, offset);
    visible.value = false;
    await tester.pump();
    _emitRefresh();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.state<_RefreshProbeState>(find.byType(_RefreshProbe)).refreshes, 1);
    visible.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.state<_RefreshProbeState>(find.byType(_RefreshProbe)).refreshes, 2);
    expect(scroll.pixels, offset);
    await tester.pumpWidget(const SizedBox());
    visible.dispose();
    _emitRefresh(); // Removed listeners cannot call disposed page state.
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('clearing search invalidates an older network response', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = NoorApi(); final repository = _SearchRepository(api);
    final app = AppState(api, repository)..english = true;
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: app,
      child: const MaterialApp(home: Scaffold(body: SearchSheet()))));
    await tester.enterText(find.byType(TextField), 'slow query');
    await tester.pump(const Duration(milliseconds: 400));
    expect(repository.pending.length, 2);
    await tester.enterText(find.byType(TextField), '');
    for (final response in repository.pending.values) {
      response.complete([const MediaItem(id: 'stale', type: 'movie', name: 'Stale result')]);
    }
    await tester.pump();
    expect(find.text('Stale result'), findsNothing);
    expect(find.byType(NovaBrowseDestination), findsWidgets);
    expect(find.byType(NovaBrowseSkeleton), findsNothing);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
