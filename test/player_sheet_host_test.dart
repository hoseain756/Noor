import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noor_mobile/features/player/widgets/player_side_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Landscape phone surface (SM-A217F class): 888×412 logical, dpr 1.0 —
  // short height must trigger the compact geometry and still fit content.
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(888, 412);
    view.devicePixelRatio = 1.0;
  });
  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(800, 600);
    view.devicePixelRatio = 1.0;
  });

  Widget host({
    VoidCallback? onRefresh,
    bool refreshing = false,
    VoidCallback? onClose,
    EdgeInsets padding = EdgeInsets.zero,
  }) {
    // Mirror the page's real overlay: right-half Positioned inside a Stack.
    // [padding] simulates the system MediaQuery the panel would see on a real
    // device (e.g. a landscape camera cutout reported on one display edge).
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: playerPanelWidth(888),
              child: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(padding: padding),
                  child: PlayerSidePanel(
                    title: 'Panel',
                    english: true,
                    onClose: onClose ?? () {},
                    onRefresh: onRefresh,
                    refreshing: refreshing,
                    child: ListView.builder(
                      itemCount: 60,
                      itemBuilder: (context, index) => ListTile(
                        dense: true,
                        title: Text('Row $index'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Finder headerButton(String label) => find.bySemanticsLabel(label);

  testWidgets('panel width is exactly HALF the landscape screen',
      (tester) async {
    // 888 / 2 = 444 — the user mandate ("نصف الشاشة الأيمن كاملاً").
    expect(playerPanelWidth(888), 444.0);
    // Narrow phones never go below 300dp; tablets never past 640dp.
    expect(playerPanelWidth(560), 300.0);
    expect(playerPanelWidth(1400), 640.0);
  });

  testWidgets('panel occupies the RIGHT half, full height', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final box = tester.getRect(find.byType(PlayerSidePanel));
    // Full height, right half: x spans [444, 888].
    expect(box.top, 0);
    expect(box.bottom, 412);
    expect(box.left, 444);
    expect(box.right, 888);
  });

  testWidgets('compact geometry on a short landscape screen', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // <520 dp height ⇒ titleMedium + tighter paddings (no overflow errors —
    // pumpAndSettle above would have thrown on a RenderFlex overflow).
    final title = tester.widget<Text>(find.text('Panel'));
    expect(
      title.style,
      Theme.of(tester.element(find.text('Panel'))).textTheme.titleMedium,
    );
  });

  testWidgets('refresh button sits in the header and fires onRefresh',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var refreshed = 0;
    await tester.pumpWidget(host(onRefresh: () => refreshed++));
    await tester.pumpAndSettle();

    final refreshButton = headerButton('Refresh');
    expect(refreshButton, findsOneWidget);
    // Header zone: above the scrollable list body.
    final center = tester.getCenter(refreshButton);
    expect(center.dy, lessThan(120));
    await tester.tap(refreshButton);
    await tester.pumpAndSettle();
    expect(refreshed, 1);
    // The panel stays open — refreshing never dismisses it.
    expect(find.byType(PlayerSidePanel), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('refreshing state replaces the icon with a spinner',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(onRefresh: () {}, refreshing: true));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('close button fires onClose', (tester) async {
    final semantics = tester.ensureSemantics();
    var closed = 0;
    await tester.pumpWidget(host(onClose: () => closed++));
    await tester.pumpAndSettle();

    final closeButton = headerButton('Close');
    expect(closeButton, findsOneWidget);
    await tester.tap(closeButton);
    await tester.pumpAndSettle();
    expect(closed, 1);
    semantics.dispose();
  });

  testWidgets('list scrolling inside the right-half panel works',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // Scroll the list DOWN (drag up) until a far row is visible — content
    // moves, panel stays (the panel never dismisses on scroll: it is an
    // in-page overlay, not a drag-to-dismiss route).
    await tester.dragUntilVisible(
      find.text('Row 30'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PlayerSidePanel), findsOneWidget);
    expect(find.text('Row 30'), findsOneWidget);
  });

  Finder bodyRow(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byType(ListTile),
      );

  testWidgets(
      'Task 140: content stretches FLUSH to the mid-screen edge — a '
      'landscape camera cutout reported on the display\'s LEFT side never '
      'opens a phantom dead strip inside the panel', (tester) async {
    final semantics = tester.ensureSemantics();
    // SM-A217F-class rotation: the punch-hole cutout shows up as the
    // SCREEN's left padding. The panel's left edge is MID-SCREEN, so that
    // inset must be dropped (user mandate: "لا أريد أن تتواجد فراغات").
    // The old SafeArea chrome would have pushed content ~40dp+18dp inward.
    await tester.pumpWidget(
      host(padding: const EdgeInsets.only(left: 40)),
    );
    await tester.pumpAndSettle();

    final panel = tester.getRect(find.byType(PlayerSidePanel));
    expect(panel.left, 444);

    // Body rows AND header icons start exactly at the mid-screen edge and
    // run to the glass edge (no right inset reported in this rotation).
    final row = tester.getRect(bodyRow('Row 0'));
    expect(row.left, 444);
    expect(row.right, 888);

    final close = tester.getRect(headerButton('Close'));
    expect(close.right, 888);
    semantics.dispose();
  });

  testWidgets(
      'Task 140: real screen-edge insets are still honored — with the '
      'camera on the RIGHT the content avoids the punch hole, while the '
      'mid-screen edge stays flush', (tester) async {
    await tester.pumpWidget(
      host(padding: const EdgeInsets.only(left: 40, right: 36)),
    );
    await tester.pumpAndSettle();

    // LEFT: always flush (mid-screen edge — never inset, cutout or not).
    final row = tester.getRect(bodyRow('Row 0'));
    expect(row.left, 444);
    // RIGHT: the panel's real screen edge keeps its system inset so no
    // content ever sits under the physical camera hole in this rotation.
    expect(row.right, 888 - 36);
  });
}
