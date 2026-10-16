import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noor_mobile/features/player/widgets/player_sheets.dart';

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

  Widget host() => MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showPlayerFullScreenSheet<void>(
                  context,
                  builder: (_) => SheetScaffold(
                    title: 'Panel',
                    expanded: true,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: 60,
                      itemBuilder: (context, index) => ListTile(
                        dense: true,
                        title: Text('Row $index'),
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  testWidgets('full-screen selection panel fills the entire screen',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final box = tester.getRect(find.byType(SheetScaffold));
    // Both dimensions — not the old 66%-height bottom sheet.
    expect(box.topLeft, Offset.zero);
    expect(box.size, const Size(888, 412));
  });

  testWidgets('compact geometry on a short landscape screen', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // <520 dp height ⇒ titleMedium + tighter paddings (no overflow errors —
    // pumpAndSettle above would have thrown on a RenderFlex overflow).
    final title = tester.widget<Text>(find.text('Panel'));
    expect(title.style,
        Theme.of(tester.element(find.text('Panel'))).textTheme.titleMedium);
  });

  testWidgets('visible close button dismisses the panel', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(SheetScaffold), findsNothing);
  });

  testWidgets('swipe down from the header area dismisses the panel',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Drag on the non-scrollable header/title zone (the handle area).
    final headerCenter = tester.getCenter(find.text('Panel'));
    await tester.dragFrom(headerCenter, const Offset(0, 260));
    await tester.pumpAndSettle();
    expect(find.byType(SheetScaffold), findsNothing);
  });

  testWidgets('list scrolling never dismisses the panel', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Scroll the list DOWN (drag up) until a far row is visible — content
    // moves, panel stays. dragUntilVisible handles the small viewport
    // (~7 rows visible on the 412dp landscape surface).
    await tester.dragUntilVisible(
      find.text('Row 30'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SheetScaffold), findsOneWidget);
    expect(find.text('Row 30'), findsOneWidget);
  });
}
