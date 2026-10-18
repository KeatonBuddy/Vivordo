import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/health_service.dart';

void main() {
  bool due(Object? run, {bool explicit = false, bool onboarded = true}) =>
      HealthService.calendarHistoryDue(
        run,
        explicit: explicit,
        onboarded: onboarded,
        today: '2026-10-17',
      );

  test('a recorded calendar history is never read again', () {
    expect(due({'calendar': 'done'}), isFalse);
    expect(due({'calendar': 'done'}, explicit: true), isFalse);
  });

  test('an empty or failed calendar is retried once a day', () {
    expect(due(null), isTrue);
    expect(due({'state': 'done'}), isTrue);
    expect(due({'calendarTriedOn': '2026-10-17'}), isFalse);
    expect(due({'calendarTriedOn': '2026-10-16'}), isTrue);
  });

  test(
    "onboarding's own call always reads it; before onboarding nothing does",
    () {
      expect(due({'calendarTriedOn': '2026-10-17'}, explicit: true), isTrue);
      expect(due(null, onboarded: false), isFalse);
    },
  );
}
