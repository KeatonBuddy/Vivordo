import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/widgets/day_timeline.dart';

void main() {
  Widget host({required bool reduceMotion}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(body: TimelineNowLine(DateTime(2026, 11, 12, 14))),
    ),
  );

  testWidgets('the now dot breathes', (tester) async {
    await tester.pumpWidget(host(reduceMotion: false));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('and holds still with Reduce Motion', (tester) async {
    await tester.pumpWidget(host(reduceMotion: true));
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });
}
