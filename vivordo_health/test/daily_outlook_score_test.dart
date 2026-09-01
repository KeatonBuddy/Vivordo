import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/daily_outlook_score.dart';

void main() {
  group('calculateDailyCapacity', () {
    test('combines the available capacity signals', () {
      final result = calculateDailyCapacity(
        sleepHours: 5.8,
        stressScore: 68,
        heartRate: 72,
      );

      expect(result.score, 57);
      expect(result.label, 'Moderate');
      expect(result.availableSignals, 3);
    });

    test('rebalances weights when signals are missing', () {
      final result = calculateDailyCapacity(sleepHours: 8);

      expect(result.score, 100);
      expect(result.label, 'High');
      expect(result.availableSignals, 1);
    });

    test('does not invent a score without health data', () {
      final result = calculateDailyCapacity();

      expect(result.score, isNull);
      expect(result.label, 'Not enough data');
    });
  });

  group('calculateScheduleDemand', () {
    final dayStart = DateTime(2026, 9, 1);
    final dayEnd = DateTime(2026, 9, 2);

    DailyScheduleEvent event(
      String title,
      int startHour,
      int startMinute,
      int endHour,
      int endMinute,
    ) => DailyScheduleEvent(
      title: title,
      start: DateTime(2026, 9, 1, startHour, startMinute),
      end: DateTime(2026, 9, 1, endHour, endMinute),
    );

    test('rates a two-hour back-to-back block as high demand', () {
      final result = calculateScheduleDemand(
        events: [
          event('Product review', 13, 0, 13, 30),
          event('Stakeholder sync', 13, 30, 14, 30),
          event('Roadmap update', 14, 30, 15, 0),
        ],
        dayStart: dayStart,
        dayEnd: dayEnd,
      );

      expect(result.score, 66);
      expect(result.label, 'High');
      expect(result.occupancyPoints, closeTo(8.75, .01));
      expect(result.continuousLoadPoints, 25);
      expect(result.breakQualityPoints, 25);
      expect(result.occupiedMinutes, 120);
      expect(result.unscheduledMinutes, 360);
    });

    test('rates a lightly scheduled day as low demand', () {
      final result = calculateScheduleDemand(
        events: [event('Planning', 9, 0, 10, 0)],
        dayStart: dayStart,
        dayEnd: dayEnd,
      );

      expect(result.score, 17);
      expect(result.label, 'Low');
    });

    test('merges overlaps instead of double counting occupied time', () {
      final result = calculateScheduleDemand(
        events: [
          event('Planning', 9, 0, 10, 30),
          event('Team sync', 10, 0, 11, 0),
        ],
        dayStart: dayStart,
        dayEnd: dayEnd,
      );

      expect(result.occupancyPoints, closeTo(8.75, .01));
      expect(result.score, 63);
      expect(result.occupiedMinutes, 120);
      expect(result.unscheduledMinutes, 360);
    });

    test('meaningful breaks reduce demand', () {
      final eventsWithBreaks = [
        event('One', 9, 0, 9, 30),
        event('Two', 10, 0, 10, 30),
        event('Three', 11, 0, 11, 30),
      ];
      final eventsWithShortGaps = [
        event('One', 9, 0, 9, 30),
        event('Two', 9, 35, 10, 5),
        event('Three', 10, 10, 10, 40),
      ];

      final withBreaks = calculateScheduleDemand(
        events: eventsWithBreaks,
        dayStart: dayStart,
        dayEnd: dayEnd,
      );
      final withShortGaps = calculateScheduleDemand(
        events: eventsWithShortGaps,
        dayStart: dayStart,
        dayEnd: dayEnd,
      );

      expect(withBreaks.score, 20);
      expect(withBreaks.breakQualityPoints, 0);
      expect(withShortGaps.score, 60);
      expect(withShortGaps.breakQualityPoints, 25);
    });

    test('includes evening events in the whole-day score', () {
      final result = calculateScheduleDemand(
        events: [event('Evening class', 20, 0, 21, 0)],
        dayStart: dayStart,
        dayEnd: dayEnd,
      );

      expect(result.score, 17);
      expect(result.occupancyPoints, greaterThan(0));
    });
  });
}
