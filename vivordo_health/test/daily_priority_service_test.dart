import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/daily_priority_service.dart';

void main() {
  final now = DateTime(2026, 8, 28, 9);

  CalendarPriorityCandidate candidate({
    required String title,
    Duration startsIn = const Duration(hours: 8),
    Duration duration = const Duration(hours: 1),
    bool isAllDay = false,
    bool isRecurring = false,
    int attendeeCount = 0,
  }) {
    final start = now.add(startsIn);
    return CalendarPriorityCandidate(
      sourceEventKey: title,
      title: title,
      start: start,
      end: start.add(duration),
      isAllDay: isAllDay,
      isRecurring: isRecurring,
      attendeeCount: attendeeCount,
    );
  }

  test('does not suggest a social event without an action keyword', () {
    final event = candidate(
      title: 'Pub golf',
      startsIn: const Duration(minutes: 30),
      duration: const Duration(hours: 5),
      attendeeCount: 12,
    );

    expect(
      DailyPriorityService.shouldSuggestForTesting(event, now: now),
      isFalse,
    );
    expect(DailyPriorityService.scoreForTesting(event), 0);
  });

  test('suggests events containing an action keyword', () {
    final event = candidate(title: 'Prepare quarterly presentation');

    expect(
      DailyPriorityService.shouldSuggestForTesting(event, now: now),
      isTrue,
    );
    expect(DailyPriorityService.scoreForTesting(event), 3);
  });

  test('matches whole phrases through punctuation', () {
    final event = candidate(title: 'Follow-up with the doctor');

    expect(
      DailyPriorityService.shouldSuggestForTesting(event, now: now),
      isTrue,
    );
  });

  test('does not match keywords embedded inside other words', () {
    final event = candidate(title: 'Preview the new movie');

    expect(DailyPriorityService.scoreForTesting(event), 0);
  });

  test(
    'duration, proximity, attendees, and recurrence do not affect score',
    () {
      final shortSolo = candidate(
        title: 'Workout',
        duration: const Duration(minutes: 10),
      );
      final longRecurringGroup = candidate(
        title: 'Workout',
        startsIn: const Duration(minutes: 5),
        duration: const Duration(hours: 6),
        isRecurring: true,
        attendeeCount: 20,
      );

      expect(DailyPriorityService.scoreForTesting(shortSolo), 3);
      expect(DailyPriorityService.scoreForTesting(longRecurringGroup), 3);
    },
  );

  test('ignored phrases remain excluded even with an action keyword', () {
    final event = candidate(title: 'Golf workout');

    expect(
      DailyPriorityService.shouldSuggestForTesting(event, now: now),
      isFalse,
    );
    expect(DailyPriorityService.scoreForTesting(event), 0);
  });
}
