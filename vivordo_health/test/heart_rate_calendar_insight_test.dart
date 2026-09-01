import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/heart_rate_calendar_insight.dart';

void main() {
  final readingTime = DateTime(2026, 9, 1, 14, 37);

  test('mentions the matching event for an elevated reading', () {
    final insight = buildHeartRateCalendarInsight(
      bpm: 108,
      timestamp: readingTime,
      events: [
        HeartRateCalendarEvent(
          title: 'Product Review',
          start: DateTime(2026, 9, 1, 14),
          end: DateTime(2026, 9, 1, 15),
        ),
      ],
    );

    expect(insight.title, contains('elevated during “Product Review”'));
    expect(insight.subtitle, contains('108 bpm'));
  });

  test('mentions a relaxed reading during an event', () {
    final insight = buildHeartRateCalendarInsight(
      bpm: 56,
      timestamp: readingTime,
      events: [
        HeartRateCalendarEvent(
          title: 'Focus Time',
          start: DateTime(2026, 9, 1, 14),
          end: DateTime(2026, 9, 1, 15),
        ),
      ],
    );

    expect(insight.title, contains('relaxed during “Focus Time”'));
  });

  test('uses the reading time when no event overlaps', () {
    final insight = buildHeartRateCalendarInsight(
      bpm: 105,
      timestamp: readingTime,
    );

    expect(insight.title, contains('elevated to 105 bpm'));
    expect(insight.title, contains('2:37'));
  });
}
