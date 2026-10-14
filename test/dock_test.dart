import 'dart:math' as math;

// Port QA suite — drop into the host app's test/ dir and swap the package
// imports to the host name (e.g. package:noor_mobile/... for Noor).
import 'package:noor_mobile/features/shell/dock_tab.dart';
import 'package:noor_mobile/features/shell/glass_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host({
  required List<DockTab> tabs,
  required String activeId,
  ValueChanged<DockTab>? onSelected,
  bool rtl = false,
}) {
  return MediaQuery(
    data: const MediaQueryData(size: Size(800, 600)),
    child: MaterialApp(
      home: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          body: Stack(
            children: [
              PositionedDirectional(
                start: 0,
                end: 0,
                bottom: 0,
                child: GlassDock(
                  tabs: tabs,
                  activeId: activeId,
                  onTabSelected: onSelected ?? (t) {},
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  final ltrTabs = dockTabsFor(kidsMode: false, hideAnime: false, rtl: false);
  final rtlTabs = dockTabsFor(kidsMode: false, hideAnime: false, rtl: true);

  test('dockTabsFor filters + orders (explicit arrays, no double flip)', () {
    expect(ltrTabs.map((t) => t.id).toList(),
        ['settings', 'kids', 'anime', 'home']);
    expect(rtlTabs.map((t) => t.id).toList(),
        ['home', 'anime', 'kids', 'settings']);
    final kids = dockTabsFor(kidsMode: true, hideAnime: false, rtl: false);
    expect(kids.map((t) => t.id).toList(), ['kids', 'home']);
    final noAnime = dockTabsFor(kidsMode: false, hideAnime: true, rtl: false);
    expect(noAnime.map((t) => t.id).toList(), ['settings', 'kids', 'home']);
  });

  test('labels resolve per language', () {
    final settings = ltrTabs.first;
    expect(dockTabLabel(settings, arabic: false), 'Settings');
    expect(dockTabLabel(settings, arabic: true), 'الإعدادات');
    expect(dockIsArabicLanguage('ar'), isTrue);
    expect(dockIsArabicLanguage('ar-EG'), isTrue);
    expect(dockIsArabicLanguage('en'), isFalse);
    expect(dockIsArabicLanguage(null), isFalse);
  });

  test('active-tab walk mirrors activeTabId', () {
    expect(
      dockActiveTabId(const [
        DockNavFrame.ofView('home'),
        DockNavFrame.other(),
        DockNavFrame.ofView('calendar'),
      ]),
      'settings', // non-dock view on top → settings stays lit
    );
    expect(
      dockActiveTabId(const [DockNavFrame.ofView('kids'), DockNavFrame.other()]),
      'kids',
    );
    expect(dockActiveTabId(const []), 'home');
    expect(
      dockTabIdForView('library', extraViewIds: {'library': 'library'}),
      'library',
    );
    expect(dockTabIdForView('anything'), 'settings');
  });

  testWidgets('tap commits exactly one selection', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(host(
      tabs: ltrTabs,
      activeId: 'home',
      onSelected: (t) => picked.add(t.id),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pumpAndSettle();
    expect(picked, ['anime']);
  });

  testWidgets('hold >=250ms enters scrub; release commits nearest slot',
      (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(host(
      tabs: ltrTabs,
      activeId: 'home',
      onSelected: (t) => picked.add(t.id),
    ));
    await tester.pumpAndSettle();
    final home = tester.getCenter(find.byIcon(Icons.home_outlined));
    final g = await tester.startGesture(home);
    await tester.pump(const Duration(milliseconds: 300)); // hold → scrub
    await g.moveBy(const Offset(-300, 0));
    await tester.pump(const Duration(milliseconds: 60));
    await g.up();
    await tester.pumpAndSettle();
    // Dragged from Home (far right) to the capsule's left edge → Settings.
    expect(picked, ['settings']);
  });

  testWidgets('quick tap under 250ms stays a pure tap', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(host(
      tabs: ltrTabs,
      activeId: 'settings',
      onSelected: (t) => picked.add(t.id),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(picked, ['home']);
  });

  testWidgets('RTL keeps the same visual order (Settings leftmost)',
      (tester) async {
    DockTab? picked;
    await tester.pumpWidget(host(
      tabs: rtlTabs,
      activeId: 'home',
      onSelected: (t) => picked = t,
      rtl: true,
    ));
    await tester.pumpAndSettle();
    final settingsCenter =
        tester.getCenter(find.byIcon(Icons.settings_outlined));
    final homeCenter = tester.getCenter(find.byIcon(Icons.home_outlined));
    expect(settingsCenter.dx, lessThan(homeCenter.dx));
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(picked?.id, 'settings');
  });

  testWidgets('missing active tab does not crash (kids-mode quirk)',
      (tester) async {
    final kids = dockTabsFor(kidsMode: true, hideAnime: false, rtl: false);
    await tester.pumpWidget(host(tabs: kids, activeId: 'settings'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden dock ignores pointers + drops semantics',
      (tester) async {
    final picked = <String>[];
    Widget dock(bool hidden) => Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(800, 600)),
            child: MaterialApp(
              home: Scaffold(
                body: Stack(children: [
                  PositionedDirectional(
                    start: 0,
                    end: 0,
                    bottom: 0,
                    child: GlassDock(
                      tabs: ltrTabs,
                      activeId: 'home',
                      hidden: hidden,
                      onTabSelected: (t) => picked.add(t.id),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        );
    await tester.pumpWidget(dock(true));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Home'), findsNothing);
    await tester.tap(find.byIcon(Icons.home_outlined), warnIfMissed: false);
    expect(picked, isEmpty);
    await tester.pumpWidget(dock(false));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Home'), findsOneWidget);
  });

  testWidgets('scrub cancel snaps back without navigating', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(host(
      tabs: ltrTabs,
      activeId: 'home',
      onSelected: (t) => picked.add(t.id),
    ));
    await tester.pumpAndSettle();
    final home = tester.getCenter(find.byIcon(Icons.home_outlined));
    final g = await tester.startGesture(home);
    await tester.pump(const Duration(milliseconds: 300)); // hold → scrub
    await g.moveBy(const Offset(-200, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await g.cancel();
    await tester.pumpAndSettle();
    expect(picked, isEmpty);
  });


  testWidgets('pill transform: translation math + scrub grow share ONE matrix',
      (tester) async {
    await tester.pumpWidget(host(tabs: ltrTabs, activeId: 'anime'));
    await tester.pumpAndSettle();
    Matrix4 pillMatrix() {
      final box = tester.element(
        find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              (w.decoration as BoxDecoration).color == const Color(0x29FFFFFF),
        ),
      );
      Transform? found;
      box.visitAncestorElements((Element ancestor) {
        if (ancestor.widget is Transform) {
          found = ancestor.widget as Transform;
          return false;
        }
        return true;
      });
      return found!.transform;
    }

    // At rest, scale = 1 and tx = frac * slotW * dirSign (LTR: +1).
    // 800x600 → ladder 600-839: width 360, pad 8 → trackW 344, slotW 86;
    // active 'anime' = slot 2 → tx = 172.
    final rest = pillMatrix();
    expect(rest.getTranslation().x, closeTo(172, 0.01));
    expect(rest.entry(0, 0), closeTo(1, 0.001));

    // Hold to enter scrub → grow scale 1.08 lands in the SAME matrix.
    final g = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.auto_awesome_outlined)));
    await tester.pump(const Duration(milliseconds: 400));
    await g.moveBy(const Offset(-43, 0)); // half a slot → fractional frac
    await tester.pump(const Duration(milliseconds: 200));
    final scrub = pillMatrix();
    expect(scrub.entry(0, 0), closeTo(1.08, 0.01)); // grow, same matrix
    expect(scrub.getTranslation().x % 86, isNot(closeTo(0, 0.01)));
    await g.up();
    await tester.pumpAndSettle();
  });

  test('size ladder: landscape last-wins', () {
    final landscape = glassDockSizing(viewport: const Size(915, 412));
    expect(landscape.barHeight, 48);
    expect(landscape.tabHeight, 38);
    final phone = glassDockSizing(viewport: const Size(390, 844));
    expect(phone.barHeight, 60);
    expect(phone.barWidth, math.min(390 - 32, 330));
    final tv = glassDockSizing(viewport: const Size(1920, 1080));
    expect(tv.barHeight, 78);
    expect(tv.blurSigma, 14);
    final small = glassDockSizing(viewport: const Size(320, 640));
    expect(small.blurSigma, 12);
  });
}
