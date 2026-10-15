// Widget test — pins the Task 119 edge-to-edge contract of the main shell:
//
//  1. The HOME page is FULL-BLEED: its scroll view starts at y=0, so the
//     featured hero (and its artwork) bleeds behind the fully transparent
//     status bar instead of leaving a solid strip above the content.
//  2. The other four tabs keep their status-bar inset (SafeArea wrapper) —
//     identical geometry to the old shell-wide SafeArea.
//  3. The floating chrome (glass search button) is pushed below the status
//     bar (`safeTop + 12`) and never collides with the clock/battery icons.
//
// The shell is pumped with a REAL AppState whose CatalogRepository is an
// offline fake (instant empty results) so no network access is needed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:noor_mobile/core/api/noor_api.dart';
import 'package:noor_mobile/core/data/catalog_repository.dart';
import 'package:noor_mobile/core/models/addon.dart';
import 'package:noor_mobile/core/models/featured_artwork.dart';
import 'package:noor_mobile/core/models/media_item.dart';
import 'package:noor_mobile/core/state/app_state.dart';
import 'package:noor_mobile/core/theme/horse_theme.dart';
import 'package:noor_mobile/features/anime/anime_page.dart';
import 'package:noor_mobile/features/home/home_page.dart';
import 'package:noor_mobile/features/kids/kids_page.dart';
import 'package:noor_mobile/features/library/library_page.dart';
import 'package:noor_mobile/features/settings/settings_page.dart';
import 'package:noor_mobile/features/shell/main_shell.dart';
import 'package:noor_mobile/shared/widgets/glass_navigation.dart';

/// Offline, instant repository: every catalog source resolves empty so the
/// shell can be pumped deterministically without network access.
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

Widget _harness({double safeTop = 44}) {
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

void main() {
  testWidgets('shell edge-to-edge contract (Task 119)', (tester) async {
    await tester.pumpWidget(_harness());
    // Let the page futures resolve (fake repo → instant) and frames settle.
    // Fixed pumps — pumpAndSettle can hang on the loading skeletons.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 80));

    expect(tester.takeException(), isNull);

    // 1) Home is edge-to-edge: the page's scroll view starts at the very
    //    top of the screen (y=0) — before Task 119 it sat at `safeTop`
    //    because the shell SafeArea pushed every page below the status bar.
    final homeScroll = find
        .descendant(
          of: find.byType(IndexedStack),
          matching: find.byType(CustomScrollView),
        )
        .first;
    expect(
      tester.getTopLeft(homeScroll).dy,
      0,
      reason: 'HomePage content must start at y=0 (edge-to-edge hero)',
    );

    // 2) The four non-home tabs keep the previous top inset via SafeArea.
    //    IndexedStack keeps the unselected tabs offstage, so every finder
    //    here must include offstage widgets.
    for (final page in const [AnimePage, KidsPage, LibraryPage, SettingsPage]) {
      expect(
        find.ancestor(
          of: find.byType(page, skipOffstage: false),
          matching: find.byType(SafeArea, skipOffstage: false),
        ),
        findsWidgets,
        reason: '$page must keep its status-bar inset',
      );
    }
    expect(
      find.ancestor(
        of: find.byType(HomePage, skipOffstage: false),
        matching: find.byType(SafeArea, skipOffstage: false),
      ),
      findsNothing,
      reason: 'HomePage is the edge-to-edge page — no SafeArea ancestor',
    );

    // 3) The glass search button clears the status icons: safeTop + 12.
    expect(
      tester.getTopLeft(find.byType(GlassSearchButton)).dy,
      44 + 12,
      reason: 'shell chrome must sit below the status bar',
    );

    // 4) Scrolling the home page keeps working (content flows under the
    //    transparent bar) — drag up and expect no exceptions.
    await tester.drag(homeScroll, const Offset(0, -240));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.takeException(), isNull);
  });
}
