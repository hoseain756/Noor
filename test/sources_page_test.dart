// Regression tests for the Task 118 full-screen sources page: every stream
// from every add-on renders as a browsable row, the filter narrows the list,
// picking a playable source returns it to the caller, and unsupported rows
// stay inert.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noor_mobile/core/models/media_item.dart';
import 'package:noor_mobile/features/media/sources_page.dart';

void main() {
  final item = MediaItem(
    id: 'tt1',
    type: 'series',
    name: 'Smoke Series',
    background: '',
  );
  const streams = <Map<String, dynamic>>[
    {
      'title': '1080p H264',
      'url': 'https://example.com/a.mkv',
      'addonName': 'Cinemeta',
    },
    {
      'title': '2160p HEVC',
      'infoHash': 'abc123',
      'addonName': 'Torrentio',
    },
    {
      'title': 'broken source',
      'addonName': 'Junk',
    },
  ];

  Widget harness(ValueChanged<Map<String, dynamic>?> onPicked) => MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final result =
                  await Navigator.of(context).push<Map<String, dynamic>>(
                MaterialPageRoute(
                  builder: (_) => SourcesPage(
                    item: item,
                    video: const {
                      'season': 1,
                      'episode': 2,
                      'name': 'Pilot',
                      'id': 'tt1:1:2',
                    },
                    streams: streams,
                    english: true,
                  ),
                ),
              );
              onPicked(result);
            },
            child: const Text('open'),
          ),
        ),
      );

  testWidgets('renders all sources and returns the picked one', (tester) async {
    Map<String, dynamic>? picked;
    await tester.pumpWidget(harness((result) => picked = result));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('3 sources from 3 add-ons'), findsOneWidget);
    // Episode context line: S1:E2 · Pilot
    expect(find.text('S1:E2 · Pilot'), findsOneWidget);
    expect(find.text('1080p H264'), findsOneWidget);
    expect(find.text('2160p HEVC'), findsOneWidget);
    expect(find.text('broken source'), findsOneWidget);

    await tester.tap(find.text('1080p H264'));
    await tester.pumpAndSettle();
    expect(picked?['url'], 'https://example.com/a.mkv');
  });

  testWidgets('filter narrows the list to matching rows', (tester) async {
    Map<String, dynamic>? picked;
    await tester.pumpWidget(harness((result) => picked = result));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '2160');
    await tester.pumpAndSettle();
    expect(find.text('2160p HEVC'), findsOneWidget);
    expect(find.text('1080p H264'), findsNothing);

    // Torrent row is playable too — tapping it returns the infoHash stream.
    await tester.tap(find.text('2160p HEVC'));
    await tester.pumpAndSettle();
    expect(picked?['infoHash'], 'abc123');
  });

  testWidgets('unsupported rows are disabled', (tester) async {
    Map<String, dynamic>? picked;
    await tester.pumpWidget(harness((result) => picked = result));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('broken source'));
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });
}
