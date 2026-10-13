import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horse_mobile/features/player/player_timeline.dart';
import 'package:video_player/video_player.dart';

void main() {
  const widths = [360.0, 390.0, 480.0, 768.0, 834.0, 1024.0, 1280.0];

  for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
    testWidgets('timeline fits responsive widths in ${direction.name}',
        (tester) async {
      for (final width in widths) {
        await tester.binding.setSurfaceSize(Size(width, 180));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Directionality(
                textDirection: direction,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: PlayerTimeline(
                    position: const Duration(minutes: 1, seconds: 12),
                    duration: const Duration(minutes: 8, seconds: 24),
                    buffered: [
                      DurationRange(
                        Duration.zero,
                        const Duration(minutes: 3),
                      ),
                      DurationRange(
                        const Duration(minutes: 4),
                        const Duration(minutes: 5),
                      ),
                    ],
                    onSeekStart: _ignoreSeek,
                    onSeekPreview: _ignoreSeek,
                    onSeekEnd: _ignoreSeek,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(Slider), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'width=$width');
      }
      await tester.binding.setSurfaceSize(null);
    });
  }

  testWidgets('timeline reports preview and commits a dragged seek',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 180));
    final starts = <Duration>[];
    final previews = <Duration>[];
    final commits = <Duration>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: PlayerTimeline(
              position: const Duration(seconds: 20),
              duration: const Duration(seconds: 100),
              buffered: const [],
              onSeekStart: starts.add,
              onSeekPreview: previews.add,
              onSeekEnd: commits.add,
            ),
          ),
        ),
      ),
    );

    final slider = find.byType(Slider);
    final rect = tester.getRect(slider);
    await tester.drag(slider, Offset(rect.width * .48, 0));
    await tester.pumpAndSettle();

    expect(starts, isNotEmpty);
    expect(previews, isNotEmpty);
    expect(commits, hasLength(1));
    expect(commits.single.inSeconds, greaterThan(50));
    expect(commits.single.inSeconds, lessThanOrEqualTo(100));
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });
}

void _ignoreSeek(Duration _) {}
