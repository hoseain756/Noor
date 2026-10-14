import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/media_item.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';
import '../../shared/widgets/media_rail.dart';
import '../../shared/widgets/poster_card.dart';
import '../../shared/widgets/glass_navigation.dart';
import '../media/media_detail_page.dart';

class KidsPage extends StatefulWidget {
  const KidsPage({super.key});

  @override
  State<KidsPage> createState() => _KidsPageState();
}

class _KidsPageState extends State<KidsPage> {
  Future<List<List<MediaItem>>>? _content;

  @override
  void initState() {
    super.initState();
    _content = _loadContent();
  }

  Future<List<List<MediaItem>>> _loadContent() {
    final repository = context.read<AppState>().catalogs;
    return Future.wait([repository.kids(), repository.kids(series: true)]);
  }

  void _retry() => setState(() => _content = _loadContent());

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final english = app.english;
    final cardSize = app.webSettings['kidsCardSize']?.toString() ?? 'medium';
    final maxCardWidth = cardSize == 'large'
        ? 220.0
        : cardSize == 'small'
            ? 140.0
            : 170.0;
    final showPosterTitles = app.webSettings['hidePosterTitles'] != true;
    final preferredCardHeight = cardSize == 'large'
        ? 370.0
        : cardSize == 'small'
            ? 260.0
            : 300.0;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final cardTextHeight =
        showPosterTitles ? 8 + 36 * textScale + 3 + 14 * textScale + 12 : 0.0;
    final cardHeight = showPosterTitles
        ? math.max(
            preferredCardHeight,
            maxCardWidth / .72 + cardTextHeight,
          )
        : maxCardWidth / .72;
    return FutureBuilder<List<List<MediaItem>>>(
      future: _content,
      builder: (context, snapshot) {
        final groups = snapshot.data ?? const <List<MediaItem>>[];
        final items = groups.expand((group) => group).toList();
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: HorseTheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF303333)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: HorseTheme.gold.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.child_care_rounded,
                          color: HorseTheme.gold,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              english ? 'Family time' : 'وقت العائلة',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              english
                                  ? 'Family and child-safe catalogs from Cinemeta.'
                                  : 'كتالوجات العائلة والمحتوى المناسب للأطفال من Cinemeta.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (snapshot.connectionState == ConnectionState.waiting &&
                groups.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(
                    color: HorseTheme.gold,
                    strokeWidth: 2,
                  ),
                ),
              ),
            if (snapshot.hasError ||
                (snapshot.connectionState == ConnectionState.done &&
                    items.isEmpty))
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          snapshot.hasError
                              ? (english
                                  ? 'Family catalogs are temporarily unavailable.'
                                  : 'كتالوجات العائلة غير متاحة مؤقتًا.')
                              : (english
                                  ? 'No child-safe titles are available right now.'
                                  : 'لا تتوفر عناوين مناسبة للأطفال حاليًا.'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _retry,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(english ? 'Retry' : 'إعادة المحاولة'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (groups.isNotEmpty && groups.first.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaRail.sectionSpacing(context),
                  ),
                  child: MediaRail(
                    title: english ? 'Family movies' : 'أفلام عائلية',
                    items: groups.first,
                    onTap: _open,
                  ),
                ),
              ),
            if (groups.length > 1 && groups[1].isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaRail.sectionSpacing(context),
                  ),
                  child: MediaRail(
                    title: english ? 'Family series' : 'مسلسلات عائلية',
                    items: groups[1],
                    onTap: _open,
                  ),
                ),
              ),
            if (groups.isNotEmpty)
              SliverPadding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  20,
                  0,
                  20,
                  MediaQuery.paddingOf(context).bottom +
                      GlassNavigationBar.contentBottomInset,
                ),
                sliver: SliverGrid.builder(
                  itemCount: items.length,
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: maxCardWidth,
                    mainAxisExtent: cardHeight,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 16,
                  ),
                  itemBuilder: (context, index) {
                    return PosterCard(
                      item: items[index],
                      width: double.infinity,
                      onTap: () => _open(items[index]),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  void _open(MediaItem item) => Navigator.of(
        context,
      ).push(
          MaterialPageRoute<void>(builder: (_) => MediaDetailPage(item: item)));
}
