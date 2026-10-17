import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nova_mobile/features/home/top10_rail.dart';

void main() {
  // NOVA uses clear editorial rank labels instead of the old outlined,
  // overlapping numeral lockup. Keep the compatibility widget compact and
  // direction-safe while the current Top10Rail renders rank + real title.
  Future<List<Text>> pumpRank(WidgetTester tester, int rank) async {
    await tester.pumpWidget(
      MaterialApp(
        // The compatibility widget follows the surrounding theme typography.
        theme: ThemeData(fontFamily: 'Tajawal'),
        home: Scaffold(
          body: Center(
            child: OutlinedRankNumber(rank: rank, fontSize: 100),
          ),
        ),
      ),
    );
    return tester.widgetList<Text>(find.byType(Text)).toList();
  }

  testWidgets('single-digit rank renders one readable label', (tester) async {
    final texts = await pumpRank(tester, 7);
    expect(texts, hasLength(1));
    expect(texts.single.data, '7');
    expect(texts.single.textDirection, TextDirection.ltr);
    expect(texts.single.style?.fontSize, 100);
    expect(texts.single.style?.fontWeight, FontWeight.w800);
  });

  testWidgets('rank ten is one direction-safe number label', (tester) async {
    final texts = await pumpRank(tester, 10);
    expect(texts, hasLength(1));
    expect(texts.single.data, '10');
    expect(texts.single.textDirection, TextDirection.ltr);
  });
}
