// Task 120 regression lock — the floating-glass family wears the OLD
// detail back-pill recipe (user mandate): blur backdrop over a black/55
// fill, 1px white/15 ring, soft black shadow — and NO cyan-tint layers
// (`#BFE6F2` sheen / ring / saturate filter) remain on any surface.
//
// Surfaces pinned here: GlassSearchButton (search + detail back + sources
// back), GlassPillSurface (season dropdown + sort chip + view toggle) and
// the GlassDock (bottom navigation bar).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noor_mobile/features/media/detail_glass.dart';
import 'package:noor_mobile/features/shell/dock_tab.dart';
import 'package:noor_mobile/features/shell/glass_dock.dart';
import 'package:noor_mobile/shared/widgets/glass_navigation.dart';

// The pre-118 back-pill decoration, expressed as matchers.
Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

BoxDecoration _firstOwnDecoration(WidgetTester tester, Type type) {
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byType(type),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return box.decoration as BoxDecoration;
}

void _expectBackPillRecipe(BoxDecoration d) {
  expect(d.border, isA<Border>());
  expect((d.border! as Border).top.color, Colors.white.withValues(alpha: .15));
  expect(d.boxShadow, isNotNull);
  expect(d.boxShadow!.first.color, Colors.black.withValues(alpha: .35));
  expect(d.boxShadow!.first.blurRadius, 14);
  expect(d.boxShadow!.first.offset, const Offset(0, 4));
}

void _expectNoCyanLayers(WidgetTester tester, Finder scope) {
  // The old recipe has no saturate ColorFiltered layer and no `#BFE6F2`
  // tint gradient anywhere in the subtree.
  expect(
    find.descendant(of: scope, matching: find.byType(ColorFiltered)),
    findsNothing,
  );
}

void main() {
  testWidgets('GlassSearchButton wears the pre-118 back-pill recipe',
      (tester) async {
    await tester.pumpWidget(_host(GlassSearchButton(
      tooltip: 'search',
      onPressed: () {},
    )));
    await tester.pumpAndSettle();

    _expectBackPillRecipe(_firstOwnDecoration(tester, GlassSearchButton));

    // Exactly ONE backdrop blur (sigma 12) and no tint layers.
    final filters = tester.widgetList<BackdropFilter>(find.descendant(
      of: find.byType(GlassSearchButton),
      matching: find.byType(BackdropFilter),
    ));
    expect(filters.length, 1);
    _expectNoCyanLayers(tester, find.byType(GlassSearchButton));
  });

  testWidgets('GlassPillSurface wears the pre-118 back-pill recipe',
      (tester) async {
    await tester.pumpWidget(_host(
      const GlassPillSurface(child: SizedBox(width: 120, height: 48)),
    ));
    await tester.pumpAndSettle();

    _expectBackPillRecipe(_firstOwnDecoration(tester, GlassPillSurface));

    final filters = tester.widgetList<BackdropFilter>(find.descendant(
      of: find.byType(GlassPillSurface),
      matching: find.byType(BackdropFilter),
    ));
    expect(filters.length, 1);
    _expectNoCyanLayers(tester, find.byType(GlassPillSurface));
  });

  testWidgets('GlassDock wears the pre-118 back-pill recipe', (tester) async {
    final tabs = dockTabsFor(kidsMode: false, hideAnime: false, rtl: false);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(800, 600)),
        child: MaterialApp(
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

    // Some descendant DecoratedBox carries the white/15 ring + soft shadow.
    final decorations = tester
        .widgetList<DecoratedBox>(find.descendant(
          of: find.byType(GlassDock),
          matching: find.byType(DecoratedBox),
        ))
        .map((b) => b.decoration)
        .whereType<BoxDecoration>()
        .toList();
    expect(
      decorations.where((d) =>
          d.border is Border &&
          (d.border! as Border).top.color ==
              Colors.white.withValues(alpha: .15)),
      isNotEmpty,
    );
    expect(
      decorations.any((d) =>
          d.boxShadow != null &&
          d.boxShadow!.isNotEmpty &&
          d.boxShadow!.first.color == Colors.black.withValues(alpha: .35)),
      isTrue,
    );

    // The dock kept its backdrop blur and lost the cyan saturate layer.
    expect(
      find.descendant(
        of: find.byType(GlassDock),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );
    _expectNoCyanLayers(tester, find.byType(GlassDock));
  });
}
