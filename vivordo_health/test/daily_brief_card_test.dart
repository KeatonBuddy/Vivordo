import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/widgets/daily_brief_card.dart';

void main() {
  for (final scale in [1.0, 2.5]) {
    testWidgets('brief fits a narrow screen at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: const SingleChildScrollView(
                child: DailyBriefCard(
                  headline: 'Give yourself a little more room today',
                  summary:
                      'Your available health signals suggest moderate capacity today.',
                  capacityScore: 62,
                  capacityLabel: 'Moderate capacity',
                  scheduleScore: 74,
                  scheduleLabel: 'High demand',
                  footer: 'Health data available · Calendar loaded',
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('YOUR DAILY BRIEF'), findsOneWidget);
      expect(find.text('62%'), findsOneWidget);
      expect(find.text('74%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('missing scores are not shown as zero', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DailyBriefCard(
            headline: 'Make space for your day',
            summary: 'More health data is needed.',
            capacityScore: null,
            capacityLabel: 'Needs health data',
            scheduleScore: null,
            scheduleLabel: 'Calendar unavailable',
            footer: 'Health data unavailable · Calendar unavailable',
          ),
        ),
      ),
    );
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('0%'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
