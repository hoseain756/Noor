import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noor_mobile/features/player/engine/playback_engine.dart';
import 'package:noor_mobile/features/player/widgets/subtitle_overlay.dart';

/// Minimal [PlaybackEngine] stand-in: the overlay only touches the subtitle
/// text stream, so everything else is a stub.
class _FakeEngine extends PlaybackEngine {
  _FakeEngine(this.texts, this.snapshot);

  final Stream<List<String>> texts;
  final List<String> snapshot;

  @override
  Stream<List<String>> get subtitleTexts => texts;
  @override
  List<String> get subtitleTextSnapshot => snapshot;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 1:1 reference surface → SubtitleStyle.scaleFactor == 1.0 and the style
  // numbers are asserted exactly, without scale math.
  testerSurface() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1920, 1080);
    view.devicePixelRatio = 1.0;
  }

  testWidgets('renders the current mpv subtitle text', (tester) async {
    testerSurface();
    final controller = StreamController<List<String>>.broadcast();
    addTearDown(controller.close);
    final engine = _FakeEngine(controller.stream, const ['Hello world']);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubtitleOverlay(
            engine: engine,
            style: ValueNotifier<SubtitleStyle>(SubtitleStyle.fallback),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Hello world'), findsOneWidget);
  });

  testWidgets('live settings change restyles the on-screen text instantly',
      (tester) async {
    testerSurface();
    final controller = StreamController<List<String>>.broadcast();
    addTearDown(controller.close);
    final engine = _FakeEngine(controller.stream, const ['نص الترجمة']);
    final style = ValueNotifier<SubtitleStyle>(
      SubtitleStyle.fromMap({'subFontSize': 20, 'subFontColor': '#FF0000'}),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubtitleOverlay(engine: engine, style: style),
        ),
      ),
    );
    await tester.pump();

    final before = tester.widget<Text>(find.text('نص الترجمة')).style!;
    expect(before.fontSize, 20);
    expect(before.color, const Color(0xFFFF0000));

    // THE regression: a settings change during playback must reach the
    // rendered Text — no restart, no re-open (Task 130 root cause).
    style.value = SubtitleStyle.fromMap(
        {'subFontSize': 40, 'subFontColor': '#00FF00', 'subStyle': 'box'});
    await tester.pump();

    final after = tester.widget<Text>(find.text('نص الترجمة')).style!;
    expect(after.fontSize, 40);
    expect(after.color, const Color(0xFF00FF00));
  });

  testWidgets('position setting moves the overlay on screen', (tester) async {
    testerSurface();
    final controller = StreamController<List<String>>.broadcast();
    addTearDown(controller.close);
    final engine = _FakeEngine(controller.stream, const ['line']);
    final style =
        ValueNotifier<SubtitleStyle>(SubtitleStyle.fromMap({'subPos': 100}));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubtitleOverlay(engine: engine, style: style),
        ),
      ),
    );
    await tester.pump();

    double centerY() =>
        tester.getCenter(find.text('line')).dy /
        tester.view.physicalSize.height;
    final bottomY = centerY();

    style.value = SubtitleStyle.fromMap({'subPos': 0});
    await tester.pump();
    final topY = centerY();

    expect(topY, lessThan(bottomY));
  });

  testWidgets('new subtitle lines from the engine stream update the text',
      (tester) async {
    testerSurface();
    final controller = StreamController<List<String>>.broadcast();
    addTearDown(controller.close);
    final engine = _FakeEngine(controller.stream, const <String>[]);
    final style = ValueNotifier<SubtitleStyle>(SubtitleStyle.fallback);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubtitleOverlay(engine: engine, style: style),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('second line', findRichText: false), findsNothing);

    controller.add(const ['first line', 'second line']);
    // Broadcast-stream delivery lands in a microtask after the current
    // frame: one pump flushes it into setState, the next renders it.
    await tester.pump();
    await tester.pump();

    expect(find.text('first line\nsecond line'), findsOneWidget);
  });

  testWidgets('blank subtitle payload renders nothing', (tester) async {
    testerSurface();
    final controller = StreamController<List<String>>.broadcast();
    addTearDown(controller.close);
    final engine = _FakeEngine(controller.stream, const ['', '   ']);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubtitleOverlay(
            engine: engine,
            style: ValueNotifier<SubtitleStyle>(SubtitleStyle.fallback),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Text), findsNothing);
  });
}
