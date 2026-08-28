import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/widgets/home_stress_card.dart';

void main() {
  Widget card({
    required double score,
    bool updating = false,
    int steps = 1200,
    Brightness brightness = Brightness.light,
  }) => MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: Scaffold(
      body: HomeStressCard(
        score: score,
        updatedAt: DateTime(2026, 8, 28, 9),
        sevenDayAverage: 52,
        drivers: const [],
        steps: steps,
        loading: false,
        updating: updating,
        revealScore: true,
        onInfoTap: () {},
      ),
    ),
  );

  testWidgets('isolates the animated ring behind a repaint boundary', (
    tester,
  ) async {
    await tester.pumpWidget(card(score: 48));

    expect(find.byType(RepaintBoundary), findsWidgets);
  });

  testWidgets('does not restart animation for an unrelated rebuild', (
    tester,
  ) async {
    await tester.pumpWidget(card(score: 48));
    await tester.pumpAndSettle();

    await tester.pumpWidget(card(score: 48, steps: 1800));
    await tester.pump();

    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('uses a lighter purple gradient in light mode', (tester) async {
    await tester.pumpWidget(card(score: 48));

    final lightGradient = _stressGradient(tester);
    expect(lightGradient.colors.first, const Color(0xFF8D78F4));

    await tester.pumpWidget(card(score: 48, brightness: Brightness.dark));
    await tester.pumpAndSettle();
    final darkGradient = _stressGradient(tester);
    expect(darkGradient.colors.first, const Color(0xFF4327EC));
  });
}

LinearGradient _stressGradient(WidgetTester tester) {
  for (final container in tester.widgetList<Container>(
    find.byType(Container),
  )) {
    final decoration = container.decoration;
    if (decoration is BoxDecoration && decoration.gradient is LinearGradient) {
      return decoration.gradient! as LinearGradient;
    }
  }
  throw TestFailure('Stress card gradient was not found.');
}
