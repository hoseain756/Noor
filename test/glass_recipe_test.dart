// Floating chrome uses the NOVA theme's palette roles and avoids live blur
// layers so scrolling remains smooth on lower-end devices.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/theme/nova_theme.dart';
import 'package:nova_mobile/features/media/detail_glass.dart';
import 'package:nova_mobile/features/shell/dock_tab.dart';
import 'package:nova_mobile/features/shell/glass_dock.dart';
import 'package:nova_mobile/shared/widgets/glass_navigation.dart';

Widget _host(Widget child, Brightness brightness) => MaterialApp(
      theme: NovaTheme.build(brightness),
      home: Scaffold(body: Center(child: child)),
    );

Material _surfaceMaterial(WidgetTester tester, Type surfaceType) =>
    tester.widget<Material>(
      find
          .descendant(
            of: find.byType(surfaceType),
            matching: find.byType(Material),
          )
          .first,
    );

void _expectNoLiveBlur(WidgetTester tester, Finder scope) {
  expect(
    find.descendant(of: scope, matching: find.byType(BackdropFilter)),
    findsNothing,
  );
}

void main() {
  for (final brightness in [Brightness.dark, Brightness.light]) {
    testWidgets('floating controls use NOVA ${brightness.name} palette roles',
        (tester) async {
      await tester.pumpWidget(_host(
        GlassSearchButton(tooltip: 'search', onPressed: () {}),
        brightness,
      ));
      await tester.pumpAndSettle();

      final search = _surfaceMaterial(tester, GlassSearchButton);
      final scheme =
          Theme.of(tester.element(find.byType(GlassSearchButton))).colorScheme;
      expect(search.color, scheme.surface.withValues(alpha: .94));
      expect(search.shape, isA<CircleBorder>());
      expect((search.shape! as CircleBorder).side.color, scheme.outline);
      _expectNoLiveBlur(tester, find.byType(GlassSearchButton));

      await tester.pumpWidget(_host(
        const GlassPillSurface(child: SizedBox(width: 120, height: 48)),
        brightness,
      ));
      await tester.pumpAndSettle();

      final pill = _surfaceMaterial(tester, GlassPillSurface);
      final pillScheme =
          Theme.of(tester.element(find.byType(GlassPillSurface))).colorScheme;
      expect(pill.color, pillScheme.surfaceContainerHigh);
      expect(pill.shape, isA<RoundedRectangleBorder>());
      expect((pill.shape! as RoundedRectangleBorder).side.color,
          pillScheme.outlineVariant);
      _expectNoLiveBlur(tester, find.byType(GlassPillSurface));
    });
  }

  testWidgets('GlassDock uses palette-derived fill and avoids live blur',
      (tester) async {
    final tabs = dockTabsFor(kidsMode: false, hideAnime: false, rtl: false);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(800, 600)),
        child: MaterialApp(
          theme: NovaTheme.dark,
          home: Directionality(
            textDirection: TextDirection.ltr,
            child: Scaffold(
              body: Stack(children: [
                PositionedDirectional(
                  start: 0,
                  end: 0,
                  bottom: 0,
                  child: GlassDock(
                    tabs: tabs,
                    activeId: 'home',
                    onTabSelected: (_) {},
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scope = find.byType(GlassDock);
    final scheme = Theme.of(tester.element(scope)).colorScheme;
    final decorations = tester
        .widgetList<DecoratedBox>(find.descendant(
          of: scope,
          matching: find.byType(DecoratedBox),
        ))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .toList();
    expect(
      decorations.where((decoration) =>
          decoration.border is Border &&
          (decoration.border! as Border).top.color ==
              scheme.outlineVariant.withValues(alpha: .65)),
      isNotEmpty,
    );
    final fills = tester.widgetList<ColoredBox>(
      find.descendant(of: scope, matching: find.byType(ColoredBox)),
    );
    expect(
      fills.any((fill) =>
          fill.color == scheme.surfaceContainerHigh.withValues(alpha: .96)),
      isTrue,
    );
    _expectNoLiveBlur(tester, scope);
  });
}
