import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/day_effort.dart';
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
      expect(find.text('Your daily brief'), findsOneWidget);
      expect(find.text('62'), findsOneWidget);
      expect(find.text('74'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a changed score glides there from the old one', (tester) async {
    Widget card(int? demand) => MaterialApp(
      home: Scaffold(
        body: DailyBriefCard(
          headline: 'Room to spare today',
          summary: '',
          capacityScore: 84,
          capacityLabel: 'Near your usual',
          scheduleScore: demand,
          scheduleLabel: 'Remaining today',
          footer: '',
        ),
      ),
    );
    await tester.pumpWidget(card(null));
    await tester.pumpWidget(card(18));
    expect(find.text('18'), findsOneWidget); // arrives as is, no count-up
    await tester.pumpWidget(card(30));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('18'), findsNothing);
    expect(find.text('30'), findsNothing); // on its way
    await tester.pumpAndSettle();
    expect(find.text('30'), findsOneWidget);
  });

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
    expect(find.text('0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('the sun rises, peaks and sets through the day', () {
    Offset? at(int hour, [int minute = 0]) =>
        briefSunPosition(DateTime(2026, 9, 30, hour, minute));
    expect(at(5, 59), isNull);
    expect(at(20, 1), isNull);
    final rise = at(6)!, noon = at(13)!, set = at(20)!;
    expect(rise.dx, lessThan(noon.dx));
    expect(noon.dx, lessThan(set.dx));
    // Smaller dy is higher on the card.
    expect(noon.dy, lessThan(rise.dy));
    expect(noon.dy, lessThan(set.dy));
    expect(rise.dy, closeTo(set.dy, 1e-9));
  });

  testWidgets('live Capacity shows one ring: free, booked and spent', (
    tester,
  ) async {
    Widget card(CapacityLeft live) => MaterialApp(
      home: Scaffold(
        body: DailyBriefCard(
          headline: 'A full afternoon ahead',
          summary: '',
          capacityScore: live.morning,
          capacityLabel: '',
          scheduleScore: live.booked.round(),
          scheduleLabel: 'Remaining today',
          footer: '',
          capacityLeft: live,
        ),
      ),
    );
    await tester.pumpWidget(
      card(capacityLeft(morning: 72, effortSoFar: 31, demand: 23)),
    );
    expect(find.text('41'), findsOneWidget);
    expect(find.text('started today at 72'), findsOneWidget);
    expect(find.text('18 free by tonight'), findsOneWidget);
    expect(find.text('23 booked'), findsOneWidget);
    expect(find.text('31 spent'), findsOneWidget);
    // No second ring: Demand is the booked share.
    expect(find.text('Remaining today'), findsNothing);

    await tester.pumpWidget(
      card(capacityLeft(morning: 58, effortSoFar: 24, demand: 42)),
    );
    await tester.pumpAndSettle();
    expect(find.text('42 booked'), findsOneWidget);
    expect(find.text('Short by 8'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("the evening keeps today's ring as it ended beside tomorrow's", (
    tester,
  ) async {
    Widget card(double tomorrowDemand) => MaterialApp(
      home: Scaffold(
        body: DailyBriefCard(
          headline: 'Today’s plan is done',
          summary: '',
          capacityScore: 50,
          capacityLabel: 'Your usual',
          scheduleScore: tomorrowDemand.round(),
          scheduleLabel: 'Expected tomorrow',
          footer: '',
          evening: (
            today: capacityLeft(morning: 50, effortSoFar: 42, demand: 0),
            tomorrowDemand: tomorrowDemand,
            tomorrowCapacity: 50,
          ),
        ),
      ),
    );
    await tester.pumpWidget(card(32));
    expect(find.text('8 left of 50'), findsOneWidget);
    expect(find.text('32 booked of a usual 50'), findsOneWidget);
    // No full Capacity ring that reads as refilled.
    expect(find.text('Your usual'), findsNothing);

    await tester.pumpWidget(card(61));
    expect(find.text('61 booked, more than a usual 50'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
