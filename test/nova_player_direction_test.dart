import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/features/player/gesture_math.dart';
import 'package:nova_mobile/features/player/widgets/player_chrome.dart';
import 'package:nova_mobile/features/player/widgets/player_side_panel.dart';

void main() {
  test('seek coordinates and deltas mirror together', () {
    expect(logicalSeekPosition(20, 100, rtl: false), 20);
    expect(logicalSeekPosition(20, 100, rtl: true), 80);
    expect(
        directionalSeekDeltaMs(
            dx: 10, width: 100, durationMs: 100000, rtl: false),
        5000);
    expect(
        directionalSeekDeltaMs(
            dx: 10, width: 100, durationMs: 100000, rtl: true),
        -5000);
    expect(
        directionalSeekDeltaMs(dx: 10, width: 0, durationMs: 100000, rtl: true),
        0);
  });

  for (final direction in TextDirection.values) {
    testWidgets('timeline seeks from logical start $direction', (tester) async {
      double? seconds;
      await tester.pumpWidget(MaterialApp(
          home: Directionality(
              textDirection: direction,
              child: Scaffold(
                  body: Center(
                      child: SizedBox(
                          width: 400,
                          child: GradientTimeline(
                              durationMs: 100000,
                              positionMs: 0,
                              bufferedMs: 0,
                              onScrubStart: () {},
                              onScrubUpdate: (_) {},
                              onScrubEnd: (value) => seconds = value)))))));
      final rect = tester.getRect(find.byType(GradientTimeline));
      await tester.tapAt(Offset(rect.left + rect.width * .25, rect.center.dy));
      await tester.pump();
      expect(seconds, closeTo(direction == TextDirection.rtl ? 75 : 25, .1));
      expect(tester.takeException(), isNull);
    });

    for (final brightness in Brightness.values) {
      testWidgets(
          'player settings fit 320px with 200% text $direction $brightness',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: MediaQuery(
                data: const MediaQueryData(
                    size: Size(320, 800),
                    textScaler: TextScaler.linear(2),
                    disableAnimations: true),
                child: Directionality(
                    textDirection: direction,
                    child: Scaffold(
                        body: Center(
                            child: SizedBox(
                                width: 320,
                                height: 640,
                                child: PlayerSidePanel(
                                    title: direction == TextDirection.rtl
                                        ? 'إعدادات التشغيل'
                                        : 'Playback settings',
                                    english: direction == TextDirection.ltr,
                                    onClose: () {},
                                    child: PlayerSettingsPanelBody(
                                        english: direction == TextDirection.ltr,
                                        speed: 1,
                                        fit: BoxFit.contain,
                                        audioLabel: 'English',
                                        subtitleLabel: 'العربية',
                                        hasEpisodes: true,
                                        onSpeed: (_) {},
                                        onFit: (_) {},
                                        onOpenAudio: () {},
                                        onOpenSubtitles: () {},
                                        onOpenEpisodes: () {})))))))));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(ListView).first, const Offset(0, -400));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
