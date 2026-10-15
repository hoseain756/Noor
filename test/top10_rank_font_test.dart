import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noor_mobile/features/home/top10_rail.dart';

void main() {
  // The Top 10 rank numerals must stay Roboto regardless of the app-wide
  // theme family (Cairo historically, Tajawal since v1.2.32): the rank
  // geometry (_digitFactor .58, overlap fractions, the "10" lockup pull) is
  // calibrated on Roboto metrics and Roboto is the look the user approved.
  Future<List<Text>> pumpRank(WidgetTester tester, int rank) async {
    await tester.pumpWidget(
      MaterialApp(
        // Deliberately cascade a DIFFERENT family: the numerals must
        // override it on every layer.
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

  testWidgets('single-digit ranks: fill and stroke layers are both Roboto',
      (tester) async {
    final texts = await pumpRank(tester, 7);
    expect(texts, hasLength(2), reason: 'fill layer + stroke layer');
    for (final text in texts) {
      expect(text.style?.fontFamily, 'Roboto');
      expect(text.style?.fontWeight, FontWeight.w900);
    }
  });

  testWidgets('rank 10 lockup: every glyph on every layer is Roboto',
      (tester) async {
    final texts = await pumpRank(tester, 10);
    expect(texts, hasLength(4), reason: '"0" and "1" glyphs, each fill+stroke');
    for (final text in texts) {
      expect(text.style?.fontFamily, 'Roboto');
    }
  });
}
