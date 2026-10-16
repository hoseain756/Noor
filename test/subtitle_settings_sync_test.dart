import 'dart:async';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noor_mobile/features/player/engine/playback_engine.dart';
import 'package:noor_mobile/features/player/widgets/subtitle_overlay.dart';

/// Minimal [PlaybackEngine] stand-in (same pattern as the overlay suite).
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

  testerSurface() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1920, 1080);
    view.devicePixelRatio = 1.0;
  }

  group('SubtitleStyle.valuesFrom (settings projection)', () {
    test('projects only the subtitle keys that are present', () {
      final values = SubtitleStyle.valuesFrom(const {
        'subFontSize': 34,
        'subFontColor': '#00FF00',
        'subtitlesOffByDefault': true, // NOT a style key
        'watchedCount': 7, // unrelated
        'subPos': null, // absent values are dropped
      });
      expect(values.keys, containsAll(['subFontSize', 'subFontColor']));
      expect(values.containsKey('subtitlesOffByDefault'), isFalse);
      expect(values.containsKey('watchedCount'), isFalse);
      expect(values.containsKey('subPos'), isFalse);
    });

    test('projection round-trips into fromMap without data loss', () {
      const settings = {
        'subFontSize': 30,
        'subFontColor': '#123456',
        'subBorderColor': '#654321',
        'subBorderSize': 3,
        'subBackgroundOpacity': 0.6,
        'subStyle': 'outline',
        'subPos': 40,
        'subFontFamily': 'Tajawal',
        'subtitleOffsetMs': -250,
      };
      final direct = SubtitleStyle.fromMap(settings);
      final projected = SubtitleStyle.fromMap(
        SubtitleStyle.valuesFrom(settings),
      );
      expect(projected.fontSize, direct.fontSize);
      expect(projected.color, direct.color);
      expect(projected.borderColor, direct.borderColor);
      expect(projected.borderSize, direct.borderSize);
      expect(projected.backgroundOpacity, direct.backgroundOpacity);
      expect(projected.style, direct.style);
      expect(projected.position, direct.position);
      expect(projected.fontFamily, direct.fontFamily);
    });

    test('mapEquals diff semantics: same values → equal, changed → not', () {
      const a = {'subFontSize': 28, 'subFontColor': '#FFFFFF'};
      final projectedA = SubtitleStyle.valuesFrom(a);
      // Identical projection → no propagation needed.
      expect(mapEquals(projectedA, SubtitleStyle.valuesFrom(a)), isTrue);
      // One key changed elsewhere → diff fires.
      final projectedB = SubtitleStyle.valuesFrom(
        const {'subFontSize': 36, 'subFontColor': '#FFFFFF'},
      );
      expect(mapEquals(projectedA, projectedB), isFalse);
      // Cosmetic transport difference (int 28 vs num 28.0) parses to the
      // same style — the map diff may fire, the style stays stable.
      final styleA = SubtitleStyle.fromMap(projectedA);
      final styleC = SubtitleStyle.fromMap(
        SubtitleStyle.valuesFrom(const {
          'subFontSize': 28.0,
          'subFontColor': '#FFFFFF',
        }),
      );
      expect(styleC.fontSize, styleA.fontSize);
    });
  });

  group('SubtitleOverlay engine swap (workstream C, Break B)', () {
    testWidgets('swapping the engine re-subscribes the text stream',
        (tester) async {
      testerSurface();
      final first = StreamController<List<String>>.broadcast();
      final second = StreamController<List<String>>.broadcast();
      addTearDown(first.close);
      addTearDown(second.close);
      final engineA = _FakeEngine(first.stream, const <String>[]);
      final engineB = _FakeEngine(second.stream, const <String>[]);
      final style = ValueNotifier<SubtitleStyle>(SubtitleStyle.fallback);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SubtitleOverlay(engine: engineA, style: style),
          ),
        ),
      );
      await tester.pump();

      first.add(const ['from engine A']);
      await tester.pump();
      await tester.pump();
      expect(find.text('from engine A'), findsOneWidget);

      // THE regression: the software-decode retry / error retry swaps the
      // engine instance in place. Without didUpdateWidget the subscription
      // stayed on the disposed engine and the text froze forever.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SubtitleOverlay(engine: engineB, style: style),
          ),
        ),
      );
      await tester.pump();

      second.add(const ['from engine B']);
      await tester.pump();
      await tester.pump();
      expect(find.text('from engine B'), findsOneWidget);
      expect(find.text('from engine A'), findsNothing);
    });

    testWidgets('swap re-seeds from the new engine snapshot', (tester) async {
      testerSurface();
      final first = StreamController<List<String>>.broadcast();
      final second = StreamController<List<String>>.broadcast();
      addTearDown(first.close);
      addTearDown(second.close);
      final engineA = _FakeEngine(first.stream, const ['old snapshot']);
      final engineB = _FakeEngine(second.stream, const ['new snapshot']);
      final style = ValueNotifier<SubtitleStyle>(SubtitleStyle.fallback);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SubtitleOverlay(engine: engineA, style: style),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('old snapshot'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SubtitleOverlay(engine: engineB, style: style),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('new snapshot'), findsOneWidget);
    });
  });
}
