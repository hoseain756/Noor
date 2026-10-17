import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:nova_mobile/core/models/media_item.dart';
import 'package:nova_mobile/core/theme/nova_theme.dart';
import 'package:nova_mobile/features/media/episode_views.dart';

void main() {
  final item = MediaItem(
    id: 'toggle-series',
    type: 'series',
    name: 'Toggle Series',
    videos: const [
      {
        'id': 'toggle-series:1:1',
        'season': 1,
        'episode': 1,
        'name': 'First episode',
      },
    ],
  );

  for (final (label, english, theme, size) in [
    ('Arabic dark phone', false, NovaTheme.dark, const Size(400, 800)),
    ('English light phone', true, NovaTheme.light, const Size(400, 800)),
    ('Arabic light tablet', false, NovaTheme.light, const Size(900, 1200)),
    ('English dark tablet', true, NovaTheme.dark, const Size(900, 1200)),
  ]) {
    testWidgets('single episode view button toggles layout — $label',
        (tester) async {
      final controller = EpisodesController(
        item: item,
        entries: const [],
        savedView: 'auto',
      );
      addTearDown(controller.dispose);
      final isWide = size.width >= 700;

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: MediaQuery(
            data: MediaQueryData(size: size),
            child: Directionality(
              textDirection: english ? TextDirection.ltr : TextDirection.rtl,
              child: Scaffold(
                body: AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) => CustomScrollView(
                    slivers: buildEpisodeSlivers(
                      controller: controller,
                      english: english,
                      isWide: isWide,
                      contentWidth: size.width - 32,
                      blurUnwatched: false,
                      ratingsEnabled: true,
                      onViewChange: controller.setView,
                      onPlay: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      IconData iconFor(String view) =>
          view == 'list' ? LucideIcons.list : LucideIcons.layoutGrid;
      String labelFor(String view) => switch ((english, view)) {
            (true, 'list') => 'List view',
            (true, _) => 'Grid view',
            (false, 'list') => 'عرض قائمة',
            (false, _) => 'عرض شبكة',
          };

      var activeView = isWide ? 'grid' : 'list';
      final toggle = find.byKey(const ValueKey('episode-view-toggle'));
      expect(toggle, findsOneWidget);
      expect(
        find.byTooltip(labelFor(activeView == 'list' ? 'grid' : 'list')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: toggle, matching: find.byIcon(iconFor(activeView))),
        findsOneWidget,
      );

      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byKey(const ValueKey('episode-view-toggle')));
        activeView = activeView == 'list' ? 'grid' : 'list';
        await tester.pump(const Duration(milliseconds: 220));
        await tester.pump();

        expect(controller.resolvedView(isWide), activeView);
        expect(
          find.byTooltip(labelFor(activeView == 'list' ? 'grid' : 'list')),
          findsOneWidget,
        );
        expect(
          find.descendant(
              of: toggle, matching: find.byIcon(iconFor(activeView))),
          findsOneWidget,
        );
      }

      expect(tester.takeException(), isNull);
    });
  }
}
