// Task 136 perf contracts — regression guards for the "app feels heavy" fix:
//
//  1. PERSISTENT CHROME CARRIES NO LIVE BLUR: the glass dock, the glass
//     search button and the detail-page glass pill mount on every screen /
//     above every scrolling list. A BackdropFilter there re-blurred the page
//     beneath on EVERY content frame (the single heaviest GPU cost on the
//     low-end target device). They must stay blur-free forever.
//  2. HIDDEN SHELL PAGES ARE DORMANT: the shell keeps all five tabs alive
//     (state preservation) but each hidden page must be Offstage (skipped by
//     layout AND paint) and TickerMode-muted (no animation tickers burning
//     CPU off-screen — the old IndexedStack muted neither).
//  3. `imageCacheWidth` decode math: logical width × DPR, clamped.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:nova_mobile/core/api/noor_api.dart';
import 'package:nova_mobile/core/data/catalog_repository.dart';
import 'package:nova_mobile/core/models/addon.dart';
import 'package:nova_mobile/core/models/featured_artwork.dart';
import 'package:nova_mobile/core/models/media_item.dart';
import 'package:nova_mobile/core/state/app_state.dart';
import 'package:nova_mobile/core/theme/horse_theme.dart';
import 'package:nova_mobile/features/anime/anime_page.dart';
import 'package:nova_mobile/features/home/home_page.dart';
import 'package:nova_mobile/features/kids/kids_page.dart';
import 'package:nova_mobile/features/library/library_page.dart';
import 'package:nova_mobile/features/media/detail_glass.dart';
import 'package:nova_mobile/features/shell/dock_tab.dart';
import 'package:nova_mobile/features/shell/glass_dock.dart';
import 'package:nova_mobile/features/shell/main_shell.dart';
import 'package:nova_mobile/features/settings/settings_page.dart';
import 'package:nova_mobile/shared/widgets/glass_navigation.dart';
import 'package:nova_mobile/shared/widgets/image_decode.dart';

/// Depth-first walk: does the subtree rooted at [root] contain a widget of
/// type [T]?
bool _subtreeContains<T>(Element root) {
  if (root.widget is T) return true;
  var found = false;
  root.visitChildElements((child) {
    if (!found && _subtreeContains<T>(child)) found = true;
  });
  return found;
}

class _FakeCatalogRepository extends CatalogRepository {
  _FakeCatalogRepository(super.api);

  @override
  Future<List<MediaItem>> catalog(
    String type,
    String id, {
    Map<String, dynamic> extras = const {},
    Addon? addon,
  }) async =>
      const <MediaItem>[];

  @override
  Future<List<MediaItem>> homeTopTen() async => const <MediaItem>[];

  @override
  Future<List<MediaItem>> anime() async => const <MediaItem>[];

  @override
  Future<List<MediaItem>> kids({bool series = false}) async =>
      const <MediaItem>[];

  @override
  Future<FeaturedArtwork> featuredArtwork(
    MediaItem item, {
    String language = 'en-US',
    String region = 'US',
    String uiLanguage = 'en',
  }) async =>
      const FeaturedArtwork();

  @override
  Future<List<MediaItem>> tmdbRecommendations(
    MediaItem seed, {
    String language = 'en-US',
    String region = 'US',
  }) async =>
      const <MediaItem>[];
}

Widget _shellHarness({double safeTop = 44}) {
  final api = NoorApi();
  final app = AppState(api, _FakeCatalogRepository(api));
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      theme: HorseTheme.dark,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(400, 860),
          padding: EdgeInsets.only(top: safeTop),
          viewPadding: EdgeInsets.only(top: safeTop),
        ),
        child: const MainShell(),
      ),
    ),
  );
}

void _setShellTestViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 860);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void _activateDockTab(WidgetTester tester, String id) {
  final dock = tester.widget<GlassDock>(find.byType(GlassDock));
  dock.onTabSelected(dock.tabs.singleWhere((tab) => tab.id == id));
}

void main() {
  group('no live blur in persistent chrome (Task 136)', () {
    testWidgets('GlassDock subtree has no BackdropFilter', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: HorseTheme.dark,
        home: Scaffold(
          body: GlassDock(
            tabs: kDockTabs,
            activeId: DockTab.homeId,
            onTabSelected: (_) {},
            languageCode: 'en',
          ),
        ),
      ));
      await tester.pump();
      expect(
        _subtreeContains<BackdropFilter>(
            tester.element(find.byType(GlassDock))),
        isFalse,
        reason: 'the dock mounts on every screen — a BackdropFilter there '
            're-blurs the page on every content frame (Task 136 removed it)',
      );
    });

    testWidgets('GlassSearchButton subtree has no BackdropFilter',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: HorseTheme.dark,
        home: Scaffold(
          body: Center(
            child: GlassSearchButton(
              tooltip: 'search',
              onPressed: () {},
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(
        _subtreeContains<BackdropFilter>(
            tester.element(find.byType(GlassSearchButton))),
        isFalse,
        reason: 'the search button mounts on every screen — no live blur',
      );
    });

    testWidgets('GlassPillSurface subtree has no BackdropFilter',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: HorseTheme.dark,
        home: Scaffold(
          body: Center(
            child: GlassPillSurface(
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('pill'),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(
        _subtreeContains<BackdropFilter>(
            tester.element(find.byType(GlassPillSurface))),
        isFalse,
        reason: 'the pill floats over scrolling lists — no live blur',
      );
    });
  });

  group('shell hidden pages are dormant (Task 136)', () {
    testWidgets('unvisited pages stay unmounted until their first visit',
        (tester) async {
      _setShellTestViewport(tester);
      await tester.pumpWidget(_shellHarness());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.takeException(), isNull);

      expect(find.byType(HomePage, skipOffstage: false), findsOneWidget);
      for (final page in const [
        AnimePage,
        KidsPage,
        LibraryPage,
        SettingsPage
      ]) {
        expect(find.byType(page, skipOffstage: false), findsNothing,
            reason: '$page should mount only after its first visit');
      }
    });

    testWidgets('visited pages stay alive, offstage and muted when hidden',
        (tester) async {
      _setShellTestViewport(tester);
      await tester.pumpWidget(_shellHarness());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 80));

      _activateDockTab(tester, DockTab.animeId);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      _activateDockTab(tester, 'library');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byType(AnimePage, skipOffstage: false), findsOneWidget);
      expect(find.byType(LibraryPage, skipOffstage: false), findsOneWidget);
      final libraryBefore =
          tester.element(find.byType(LibraryPage, skipOffstage: false).first);
      final animeBefore =
          tester.element(find.byType(AnimePage, skipOffstage: false).first);

      // Force a shell-level rebuild via a MediaQuery change — the same
      // build path a scroll auto-hide toggle takes (setState on the SHELL
      // only; with stable page instances the pages are not rebuilt).
      await tester.pumpWidget(_shellHarness(safeTop: 48));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.takeException(), isNull);

      final libraryAfter =
          tester.element(find.byType(LibraryPage, skipOffstage: false).first);
      final animeAfter =
          tester.element(find.byType(AnimePage, skipOffstage: false).first);
      expect(identical(libraryBefore, libraryAfter), isTrue,
          reason: 'shell rebuilds must not remount a visited page');
      expect(identical(animeBefore, animeAfter), isTrue,
          reason: 'shell rebuilds must not remount a visited page');

      bool offstaged(Element page) => tester
          .widgetList<Offstage>(
            find.ancestor(
              of: find.byElementPredicate((e) => identical(e, page),
                  skipOffstage: false),
              matching: find.byType(Offstage, skipOffstage: false),
            ),
          )
          .any((stage) => stage.offstage);
      bool muted(Element page) => tester
          .widgetList<TickerMode>(
            find.ancestor(
              of: find.byElementPredicate((e) => identical(e, page),
                  skipOffstage: false),
              matching: find.byType(TickerMode, skipOffstage: false),
            ),
          )
          .any((mode) => !mode.enabled);

      expect(offstaged(libraryAfter), isFalse,
          reason: 'the selected Library page remains visible');
      expect(muted(libraryAfter), isFalse,
          reason: 'the selected Library page may animate');
      expect(offstaged(animeAfter), isTrue,
          reason: 'the previously visited Anime page skips paint and layout');
      expect(muted(animeAfter), isTrue,
          reason: 'offscreen Anime tickers stay paused');

      // The dock is still mounted exactly once after the rebuild.
      expect(find.byType(GlassDock), findsOneWidget);
    });
  });

  group('imageCacheWidth math (Task 136)', () {
    testWidgets('scales by DPR and clamps', (tester) async {
      late int at122;
      late int tiny;
      late int huge;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 3.0),
          child: Builder(builder: (context) {
            at122 = imageCacheWidth(context, 122);
            tiny = imageCacheWidth(context, 10);
            return const SizedBox.shrink();
          }),
        ),
      );
      expect(at122, 122 * 3, reason: 'logical width × devicePixelRatio');
      expect(tiny, 64 * 3,
          reason: 'tiny logos clamp to the 64-logical floor, then × DPR');

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 1.0),
          child: Builder(builder: (context) {
            huge = imageCacheWidth(context, 4000);
            return const SizedBox.shrink();
          }),
        ),
      );
      expect(huge, 1280, reason: 'ceiling clamp bounds hero decode memory');
    });
  });
}
