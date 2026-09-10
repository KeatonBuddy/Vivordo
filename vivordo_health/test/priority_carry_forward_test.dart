import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/daily_priority_service.dart';

void main() {
  const original = '2026-09-09';
  const today = '2026-09-10';
  final untimed = <String, dynamic>{'source': 'manual', 'completed': false};
  test(
    'unfinished untimed tasks carry across days, but not before their date',
    () {
      expect(
        DailyPriorityService.visibleOnDay(untimed, original, today),
        isTrue,
      );
      expect(
        DailyPriorityService.visibleOnDay(untimed, today, original),
        isFalse,
      );
    },
  );
  test('completed and dismissed tasks do not carry forward', () {
    expect(
      DailyPriorityService.visibleOnDay(
        {...untimed, 'completed': true},
        original,
        today,
      ),
      isFalse,
    );
    expect(
      DailyPriorityService.visibleOnDay(
        {...untimed, 'dismissed': true},
        original,
        today,
      ),
      isFalse,
    );
    expect(
      DailyPriorityService.visibleOnDay(
        {...untimed, 'completed': true},
        original,
        original,
      ),
      isTrue,
    );
  });
  test('timed, recurring, and calendar priorities remain date-bound', () {
    for (final data in [
      {...untimed, 'sourceStart': DateTime(2026, 9, 9, 12)},
      {...untimed, 'source': 'recurring_manual'},
      {...untimed, 'source': 'google', 'isAllDay': true},
    ]) {
      expect(DailyPriorityService.visibleOnDay(data, original, today), isFalse);
      expect(
        DailyPriorityService.visibleOnDay(data, original, original),
        isTrue,
      );
    }
  });
  test(
    'carried completion remains today, disappears tomorrow, and can reopen',
    () {
      final completed = {...untimed, 'completed': true, 'completedDay': today};
      expect(
        DailyPriorityService.visibleOnDay(completed, original, today),
        isTrue,
      );
      expect(
        DailyPriorityService.visibleOnDay(completed, original, '2026-09-11'),
        isFalse,
      );
      final reopened = {...completed, 'completed': false, 'completedDay': null};
      expect(
        DailyPriorityService.visibleOnDay(reopened, original, today),
        isTrue,
      );
      expect(
        DailyPriorityService.visibleOnDay(reopened, original, '2026-09-11'),
        isTrue,
      );
      expect(
        DailyPriorityService.visibleOnDay(
          {...completed, 'dismissed': true},
          original,
          today,
        ),
        isFalse,
      );
    },
  );
}
