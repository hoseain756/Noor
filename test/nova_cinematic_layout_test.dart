import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noor_mobile/core/models/media_item.dart';
import 'package:noor_mobile/features/home/widgets/cinematic_cover_scroll.dart';
import 'package:noor_mobile/features/media/detail_hero.dart';

void main() {
  const item = MediaItem(
    id: 'nova-test',
    type: 'series',
    name: 'A story across two languages',
    originalTitle: 'حكاية طويلة بين لغتين',
    releaseInfo: '2026',
    description:
        'A detailed synopsis that remains fully readable when text is enlarged.',
    genres: ['Drama', 'Adventure'],
    certification: 'PG',
    seasonCount: 2,
    episodeCount: 16,
    cast: ['One Person', 'شخص آخر'],
    director: ['A Director'],
    productionCompanies: [MediaCompany(name: 'A production company')],
  );

  for (final width in [320.0, 800.0]) {
    for (final direction in TextDirection.values) {
      for (final brightness in Brightness.values) {
        testWidgets('cinematic layout $width $direction $brightness at 200%',
            (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final english = direction == TextDirection.ltr;
          await tester.pumpWidget(MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: MediaQuery(
                data: MediaQueryData(
                    size: Size(width, 900),
                    textScaler: const TextScaler.linear(2),
                    disableAnimations: true),
                child: Directionality(
                    textDirection: direction,
                    child: Scaffold(
                        body: ListView(children: [
                      SizedBox(
                          height: 400,
                          child: DetailHero(
                              item: item,
                              backdropUrl: null,
                              logoUrl: null,
                              isWide: width >= 700,
                              viewportHeight: 900,
                              viewportWidth: width)),
                      Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                DetailMetaRow(item: item, isWide: width >= 700),
                                DetailActionRow(
                                    english: english,
                                    isWide: width >= 700,
                                    inList: false,
                                    showTrackAnime: true,
                                    primaryLabel:
                                        english ? 'Watch now' : 'شاهد الآن',
                                    primaryIsResume: false,
                                    loading: false,
                                    onPrimaryPressed: () {},
                                    onToggleWatchlist: () {},
                                    onOpenStreams: () {},
                                    onTrackAnime: () {},
                                    onShare: () {},
                                    onAddToList: () {},
                                    onDownload: () {}),
                                DetailSynopsis(
                                    description: item.description!,
                                    isWide: width >= 700,
                                    viewportWidth: width),
                                DetailCastCrew(item: item, english: english),
                                DetailProduction(item: item, english: english),
                                DetailFactsTable(item: item, english: english),
                              ])),
                    ])))),
          ));
          await tester.pump();
          expect(tester.takeException(), isNull);
          await tester.drag(find.byType(ListView).first, const Offset(0, -500));
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('hero remains stationary while content covers it',
      (tester) async {
    const marker = Key('hero-marker');
    const cover = Key('content-cover');
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: Scaffold(
          body: CinematicCoverScroll(
        heroHeight: 400,
        hero: const Center(child: SizedBox(key: marker, width: 20, height: 20)),
        slivers: const [
          SliverToBoxAdapter(child: SizedBox(key: cover, height: 1200))
        ],
      )),
    )));
    final beforeHero = tester.getTopLeft(find.byKey(marker));
    final beforeCover = tester.getTopLeft(find.byKey(cover));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -160));
    await tester.pumpAndSettle();
    expect(
        tester.getTopLeft(find.byKey(marker)).dy, closeTo(beforeHero.dy, .1));
    expect(tester.getTopLeft(find.byKey(cover)).dy,
        lessThan(beforeCover.dy - 100));
    expect(tester.takeException(), isNull);
  });
}
