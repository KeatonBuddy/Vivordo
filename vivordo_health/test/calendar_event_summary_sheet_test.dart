import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/calendar_cognitive_load_service.dart';
import 'package:vivordo_health/src/utils/body_reaction.dart';
import 'package:vivordo_health/src/utils/day_effort.dart';
import 'package:vivordo_health/src/utils/heart_rate_history.dart';
import 'package:vivordo_health/src/utils/meeting_patterns.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/calendar_event_summary_sheet.dart';

void main() {
  CognitiveLoadScore score(String category, int value) => CognitiveLoadScore(
    eventId: 'e',
    score: value,
    category: category,
    reason: '',
    usedAi: false,
    confidence: 1,
  );

  /// One reading a minute from [start]: [bpms] in order.
  BodyReaction reaction(DateTime start, List<double> bpms) {
    final samples = [
      for (final (i, bpm) in bpms.indexed)
        HeartRateHistoryReading(
          bpm: bpm,
          timestamp: start.add(Duration(minutes: i)),
        ),
    ];
    return BodyReaction(
      level: BodyReactionLevel.up,
      median: 84,
      peak: 94,
      usualLow: 68,
      usualHigh: 76,
      usualMedian: 72,
      readings: samples.length,
      samples: samples,
    );
  }

  CalendarEventSummaryAction? action;

  Future<void> open(
    WidgetTester tester,
    CalendarEventSummaryData event, {
    EventSummarySources? sources,
  }) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    action = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.dark,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => action = await showCalendarEventSummarySheet(
              context,
              event: event,
              sources:
                  sources ??
                  EventSummarySources(
                    reaction: (_, _) async => null,
                    patterns: () async => MeetingPatterns.empty,
                  ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the event, and Edit returns edit', (tester) async {
    final start = DateTime(2026, 9, 1, 9);
    await open(
      tester,
      CalendarEventSummaryData(
        title: 'Product Review',
        start: start,
        end: start.add(const Duration(hours: 1)),
        isAllDay: false,
        isRecurring: false,
        color: Colors.blue,
        calendarName: 'Google Calendar',
        canEdit: true,
      ),
    );
    expect(find.text('Product Review'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Google Calendar'), findsOneWidget);
    expect(find.text('1h'), findsOneWidget);
    expect(find.text("Doesn't repeat"), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    // No heart rate for this event, and no trend: neither section shows.
    expect(find.text('Heart rate'), findsNothing);
    expect(find.text('Trends'), findsNothing);

    await tester.ensureVisible(find.text('Edit Event'));
    await tester.tap(find.text('Edit Event'));
    await tester.pumpAndSettle();
    expect(action, CalendarEventSummaryAction.edit);
  });

  testWidgets('a finished event shows its heart rate and trends', (
    tester,
  ) async {
    final start = DateTime(2026, 10, 1, 14);
    final end = start.add(const Duration(minutes: 30));
    final typeEvent = CalendarCognitiveEvent(
      id: 'e',
      title: 'Weekly planning',
      start: start,
      end: end,
    );
    final collaboration = score('collaboration', 40);
    MeetingReaction meeting(int day, double median) => MeetingReaction(
      day: DateTime(2026, 9, day),
      key: 'k$day',
      series: 'series',
      category: 'collaboration',
      guests: 4,
      minutes: 30,
      startHour: 14,
      median: median,
      usual: 72,
    );
    final series = MeetingPattern(
      id: 'series',
      label: 'A repeating meeting',
      isSeries: true,
      direction: PatternDirection.high,
      count: 4,
      agreeing: 4,
      liftBpm: 6,
      liftPercent: 8,
      events: [for (var d = 3; d <= 24; d += 7) meeting(d, 78)],
    );
    await open(
      tester,
      CalendarEventSummaryData(
        title: 'Weekly planning',
        start: start,
        end: end,
        isAllDay: false,
        isRecurring: true,
        color: Colors.blue,
        calendarName: 'Google Calendar',
        canEdit: true,
        typeEvent: typeEvent,
        seriesKey: 'series',
      ),
      sources: EventSummarySources(
        score: (_) async => collaboration,
        reaction: (s, _) async => reaction(s, [
          ...List.filled(10, 72.0),
          ...List.filled(8, 80.0),
          ...List.filled(12, 92.0),
        ]),
        patterns: () async => MeetingPatterns(
          measured: 4,
          high: [series],
          calm: const [],
          bySeries: {'series': series},
        ),
      ),
    );

    expect(find.text('Meeting or class'), findsOneWidget);
    expect(find.text('Repeating'), findsOneWidget);
    final points = eventPoints(typeEvent, collaboration).round();
    expect(find.text('Added $points'), findsOneWidget);
    expect(find.text('Heart rate'), findsOneWidget);
    expect(find.text('82 avg · 92 max'), findsOneWidget);
    expect(
      find.textContaining('12 min well above usual', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Trends'), findsOneWidget);
    expect(
      find.text('This meeting usually runs your heart rate up'),
      findsOneWidget,
    );
    expect(find.text('8% over your usual · 4 of 4 times'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an upcoming event says when its heart rate shows', (
    tester,
  ) async {
    final start = DateTime.now().add(const Duration(days: 2));
    var asked = false;
    await open(
      tester,
      CalendarEventSummaryData(
        title: 'Board presentation',
        start: start,
        end: start.add(const Duration(hours: 1)),
        isAllDay: false,
        isRecurring: false,
        color: Colors.blue,
        calendarName: 'Outlook',
        canEdit: true,
        typeEvent: CalendarCognitiveEvent(
          id: 'e',
          title: 'Board presentation',
          start: start,
          end: start.add(const Duration(hours: 1)),
        ),
      ),
      sources: EventSummarySources(
        score: (_) async => score('high-consequence', 75),
        reaction: (_, _) async {
          asked = true;
          return null;
        },
        patterns: () async => MeetingPatterns.empty,
      ),
    );
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Demand'), findsOneWidget);
    expect(find.textContaining('Adds about'), findsOneWidget);
    expect(
      find.text("Shows after it's over, if wearable data is available."),
      findsOneWidget,
    );
    expect(asked, isFalse);
  });

  test('minutes against your usual, and the summary line', () {
    final start = DateTime(2026, 10, 1, 9);
    final r = reaction(start, [70, 74, 78, 80, 86, 90]);
    expect(heartBandMinutes(r), {
      HeartBand.usual: 2,
      HeartBand.above: 2,
      HeartBand.wellAbove: 2,
    });
    expect(heartBandSummary(r), (
      headline: '2 min well above usual',
      overall: '+12 bpm overall',
    ));
    final calm = reaction(start, [70, 72, 74]);
    expect(heartBandSummary(calm).headline, 'Within your usual');
  });

  test('an event adds its own points, more for heavier types', () {
    final start = DateTime(2026, 10, 1, 10);
    final event = CalendarCognitiveEvent(
      id: 'e',
      title: 'x',
      start: start,
      end: start.add(const Duration(hours: 1)),
    );
    final light = eventPoints(event, score('routine', 20));
    final heavy = eventPoints(event, score('high-consequence', 75));
    expect(light, greaterThan(0));
    expect(heavy, greaterThan(light));
    expect(eventPoints(event, score('rest', 0)), 0);
  });
}
