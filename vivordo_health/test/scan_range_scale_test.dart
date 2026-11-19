import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/widgets/scan_range_scale.dart';

void main() {
  test('bands match the result label: under 65, under 80, and above', () {
    expect(HeartRateBand.of(64), HeartRateBand.resting);
    expect(HeartRateBand.of(65), HeartRateBand.typical);
    expect(HeartRateBand.of(79), HeartRateBand.typical);
    expect(HeartRateBand.of(80), HeartRateBand.higher);
  });

  test('the marker runs 40 to 120 bpm and stops at the ends', () {
    expect(scanScaleFraction(40), 0);
    expect(scanScaleFraction(80), .5);
    expect(scanScaleFraction(120), 1);
    expect(scanScaleFraction(30), 0);
    expect(scanScaleFraction(180), 1);
  });

  testWidgets('the scale names all three ranges and says which one', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 300, child: ScanRangeScale(bpm: 72)),
        ),
      ),
    );
    expect(find.text('Resting'), findsOneWidget);
    expect(find.text('Typical'), findsOneWidget);
    expect(find.text('Higher'), findsOneWidget);
    expect(
      find.bySemanticsLabel('72 beats per minute, in the Typical range'),
      findsOneWidget,
    );
    // An extreme reading still lays out, with the marker inside the scale.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 300, child: ScanRangeScale(bpm: 190)),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
