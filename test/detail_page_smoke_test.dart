// Widget smoke test — pumps the rebuilt detail presentation widgets
// (hero + the Task 118 sliver episodes composition) on phone + tablet sizes
// to catch layout exceptions.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noor_mobile/core/models/media_item.dart';
import 'package:noor_mobile/features/media/detail_hero.dart';
import 'package:noor_mobile/features/media/episode_views.dart';

void main() {
  final item = MediaItem(
    id: 'tt1',
    type: 'series',
    name: 'Smoke Series',
    background: '',
    description: 'A smoke-test description for layout verification purposes.',
    releaseInfo: '2024',
    rating: '8.5',
    runtime: '58 min',
    certification: '16+',
    genres: const ['Drama', 'Crime'],
    cast: const ['A Actor', 'B Actor', 'C Actor', 'D Actor', 'E Actor'],
    director: const ['Some Director'],
    videos: [
      for (var e = 1; e <= 8; e++)
        {
          'id': 'tt1:1:$e',
          'season': 1,
          'episode': e,
          'name': 'Episode $e',
          'overview': 'Story $e',
          'released': '2024-01-0$e',
          'duration': '${45 + e} min',
        },
      for (var e = 1; e <= 3; e++)
        {
          'id': 'tt1:2:$e',
          'season': 2,
          'episode': e,
          'name': 'S2 Episode $e',
        },
    ],
  );

  Widget harness(double width, double height) {
    final isWide = width >= 700;
    // Fresh controller per pump — mirrors how the page creates it lazily.
    final controller = EpisodesController(
      item: item,
      entries: const [],
      savedView: 'auto',
    );
    return MaterialApp(
      theme: ThemeData.dark(),
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, height)),
        child: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 240,
                  child: DetailHero(
                    item: item,
                    backdropUrl: null,
                    logoUrl: null,
                    isWide: isWide,
                    viewportHeight: height,
                    viewportWidth: width,
                  ),
                ),
              ),
              ...buildEpisodeSlivers(
                controller: controller,
                english: false,
                isWide: isWide,
                contentWidth: width - (isWide ? 68.0 : 40.0),
                blurUnwatched: true,
                ratingsEnabled: true,
                onViewChange: (_) {},
                onPlay: (_) {},
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      DetailMetaRow(item: item, isWide: isWide),
                      DetailSynopsis(
                        description: item.description!,
                        isWide: isWide,
                        viewportWidth: width,
                      ),
                      DetailActionRow(
                        english: false,
                        isWide: isWide,
                        inList: false,
                        showTrackAnime: true,
                        primaryLabel: 'مشاهدة',
                        primaryIsResume: false,
                        loading: false,
                        onPrimaryPressed: () {},
                        onToggleWatchlist: () {},
                        onOpenStreams: () {},
                        onTrackAnime: () {},
                        onShare: () {},
                        onAddToList: () {},
                      ),
                      DetailCastCrew(item: item, english: false),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // The hero shimmer may still be alive during the first frames — pump a
  // fixed frame budget instead of pumpAndSettle.
  Future<void> settleFrames(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  for (final (label, size) in [
    ('phone', const Size(400, 800)),
    ('tablet', const Size(900, 1200)),
  ]) {
    testWidgets('layout smoke — $label', (tester) async {
      await tester.pumpWidget(harness(size.width, size.height));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('الحلقات'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('overlay menus smoke — $label', (tester) async {
      await tester.pumpWidget(harness(size.width, size.height));
      await settleFrames(tester);

      // Season dropdown → glass menu opens with season options. Scoped
      // finder: the season pill carries the ValueKey('season-<id>') key
      // (the DetailActionRow chevron is a different widget), scrolled into
      // view before the tap.
      final seasonTrigger = find
          .descendant(
            of: find.byKey(const ValueKey('season-tt1')),
            matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
          )
          .first;
      await tester.ensureVisible(seasonTrigger);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(seasonTrigger);
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('الموسم 2'), findsWidgets);
      expect(tester.takeException(), isNull);

      // Pick season 2 → menu closes, label updates.
      await tester.ensureVisible(find.text('الموسم 2').last);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('الموسم 2').last);
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.takeException(), isNull);

      // Action menu trigger → glass menu with the 4 entries. The page is a
      // real CustomScrollView now (Task 118), so the action row may live
      // below the viewport's build cache — scroll until it's instantiated.
      final actionRow = find.byType(DetailActionRow);
      await tester.scrollUntilVisible(
        actionRow,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 100));
      final menuTrigger = find
          .descendant(
            of: actionRow,
            matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
          )
          .first;
      await tester.ensureVisible(menuTrigger);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(menuTrigger);
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('مصادر التشغيل'), findsOneWidget);
      expect(find.text('مشاركة'), findsOneWidget);
      expect(find.text('تتبّع الأنمي'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Outside tap closes.
      await tester.tapAt(const Offset(10, 10));
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('مصادر التشغيل'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
