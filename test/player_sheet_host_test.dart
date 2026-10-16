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
  }) {
    // Mirror the page's real overlay: right-half Positioned inside a Stack.
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: playerPanelWidth(888),
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
}
