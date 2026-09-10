import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:vivordo_health/src/services/calendar_baas_context.dart';
import 'package:vivordo_health/src/utils/home_stress_card_logic.dart';

void main() {
  final start = DateTime.utc(2026, 9, 10, 12);
  gcal.Event event(String id, int from, int to) => gcal.Event()
    ..id = id
    ..summary = 'Client presentation'
    ..start = (gcal.EventDateTime()
      ..dateTime = start.add(Duration(minutes: from)))
    ..end = (gcal.EventDateTime()..dateTime = start.add(Duration(minutes: to)));
  test(
    'indicators describe the existing pressure calculation without changing load',
    () {
      final overlap = CalendarBaasContext.build(
        events: [event('a', 0, 60), event('b', 15, 60)],
        from: start,
        asOf: start.add(const Duration(hours: 1)),
      ).single;
      expect(overlap['overlap_minutes'], 45);
      expect(overlap['back_to_back_minutes'], 0);
      expect(overlap['calendar_load'], 82.5);
      final tight = CalendarBaasContext.build(
        events: [event('a', -30, 0), event('b', 0, 60)],
        from: start,
        asOf: start.add(const Duration(minutes: 30)),
      ).single;
      expect(tight['back_to_back_minutes'], 30);
      expect(tight['back_to_back_transitions'], 1);
      expect(tight['overlap_minutes'], 0);
      expect(tight['calendar_load'], 42.5);
    },
  );
  test('calendar driver labels fall back safely and respect top two', () {
    const labels = {
      'event_demand': 'High-demand schedule',
      'back_to_back': 'Back-to-back events',
      'overlap': 'Overlapping commitments',
      'schedule_pressure': 'Schedule pressure',
      'mixed': 'Demanding schedule',
      'unknown': 'Calendar load',
    };
    for (final entry in labels.entries) {
      final driver = homeStressDrivers([
        {'name': 'Calendar load', 'reason_code': entry.key},
      ]).single;
      expect(driver.type, HomeStressDriverType.calendar);
      expect(driver.label, entry.value);
    }
    expect(homeStressDrivers(['Calendar load']).single.label, 'Calendar load');
    expect(homeStressDrivers(['Sleep', 'HRV', 'Calendar load']).length, 2);
  });
}
