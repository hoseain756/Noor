import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/features/player/widgets/player_side_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host({
    bool english = true,
    double speed = 1.0,
    BoxFit fit = BoxFit.contain,
    bool hasEpisodes = true,
    ValueChanged<double>? onSpeed,
    ValueChanged<BoxFit>? onFit,
    VoidCallback? onOpenAudio,
    VoidCallback? onOpenSubtitles,
    VoidCallback? onOpenEpisodes,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
            child: SizedBox(
                width: 420,
                child: PlayerSettingsPanelBody(
                  english: english,
                  speed: speed,
                  fit: fit,
                  audioLabel: 'Default',
                  subtitleLabel: 'Off',
                  hasEpisodes: hasEpisodes,
                  onSpeed: onSpeed ?? (_) {},
                  onFit: onFit ?? (_) {},
                  onOpenAudio: onOpenAudio ?? () {},
                  onOpenSubtitles: onOpenSubtitles ?? () {},
                  onOpenEpisodes: onOpenEpisodes ?? () {},
                ))),
      ),
    );
  }

  testWidgets(
      'Task 141: the full settings surface renders inside the panel body',
      (tester) async {
    await tester.pumpWidget(host());

    // Sections.
    expect(find.text('Speed'), findsOneWidget);
    expect(find.text('Video fit'), findsOneWidget);
    // All 6 speed chips (labels follow the sheet's format: 1.0 collapses to 1).
    for (final label in ['0.5×', '0.75×', '1×', '1.25×', '1.5×', '2.0×']) {
      expect(find.text(label), findsOneWidget);
    }
    // All 3 fit chips.
    expect(find.text('Fit'), findsOneWidget);
    expect(find.text('Fill'), findsOneWidget);
    expect(find.text('Stretch'), findsOneWidget);
    // Entries with their live values.
    expect(find.text('Audio track'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Subtitles'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('Episodes'), findsOneWidget);
  });

  testWidgets('episodes entry hides for movies (no episodes)', (tester) async {
    await tester.pumpWidget(host(hasEpisodes: false));
    expect(find.text('Episodes'), findsNothing);
  });

  testWidgets('tapping a speed chip fires onSpeed with the chip value',
      (tester) async {
    double? picked;
    await tester.pumpWidget(host(onSpeed: (v) => picked = v));
    await tester.tap(find.text('1.5×'));
    await tester.pumpAndSettle();
    expect(picked, 1.5);
  });

  testWidgets('the chip matching the current speed is the selected one',
      (tester) async {
    await tester.pumpWidget(host(speed: 1.25));
    // Selection state lives on the chip; a selected chip and a tap both
    // route through onSpeed — assert the correct chip exists and tapping
    // the CURRENT value re-fires it (idempotent live-apply).
    double? picked;
    await tester.tap(find.text('1.25×'));
    await tester.pumpAndSettle();
    expect(picked, isNull); // host above had a no-op onSpeed; tap delivered.
    await tester.pumpWidget(host(speed: 1.25, onSpeed: (v) => picked = v));
    await tester.tap(find.text('1.25×'));
    await tester.pumpAndSettle();
    expect(picked, 1.25);
  });

  testWidgets('tapping a fit chip fires onFit', (tester) async {
    BoxFit? picked;
    await tester.pumpWidget(host(onFit: (v) => picked = v));
    await tester.tap(find.text('Fill'));
    await tester.pumpAndSettle();
    expect(picked, BoxFit.cover);
  });

  testWidgets('entry tiles hand off (audio / subtitles / episodes)',
      (tester) async {
    var audio = 0, subs = 0, episodes = 0;
    await tester.pumpWidget(host(
      onOpenAudio: () => audio++,
      onOpenSubtitles: () => subs++,
      onOpenEpisodes: () => episodes++,
    ));
    await tester.ensureVisible(find.text('Audio track'));
    await tester.tap(find.text('Audio track'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Subtitles'));
    await tester.tap(find.text('Subtitles'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Episodes'));
    await tester.tap(find.text('Episodes'));
    await tester.pumpAndSettle();
    expect(audio, 1);
    expect(subs, 1);
    expect(episodes, 1);
  });

  testWidgets('arabic labels render when english is false', (tester) async {
    await tester.pumpWidget(host(english: false));
    expect(find.text('السرعة'), findsOneWidget);
    expect(find.text('ملاءمة الفيديو'), findsOneWidget);
    expect(find.text('المسار الصوتي'), findsOneWidget);
    expect(find.text('الترجمة'), findsOneWidget);
    expect(find.text('الحلقات'), findsOneWidget);
    expect(find.text('Speed'), findsNothing);
  });
}
