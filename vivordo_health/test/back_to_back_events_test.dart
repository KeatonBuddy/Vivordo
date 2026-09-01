import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/back_to_back_events.dart';

void main() {
  final now = DateTime(2026, 9, 1, 9);

  ScheduledEventWindow event(String title, int startHour, int endHour) =>
      ScheduledEventWindow(
        title: title,
        start: DateTime(2026, 9, 1, startHour),
        end: DateTime(2026, 9, 1, endHour),
      );

  test('returns a block when events touch', () {
    final block = findNextBackToBackEventBlock([
      event('Product Review', 13, 14),
      event('Planning', 14, 15),
      event('Focus', 16, 17),
    ], now: now);

    expect(block?.events.map((item) => item.title), [
      'Product Review',
      'Planning',
    ]);
  });

  test('does not return a block when events have a gap', () {
    final block = findNextBackToBackEventBlock([
      event('Product Review', 13, 14),
      ScheduledEventWindow(
        title: 'Planning',
        start: DateTime(2026, 9, 1, 14, 1),
        end: DateTime(2026, 9, 1, 15),
      ),
    ], now: now);

    expect(block, isNull);
  });

  test('ignores a block after it has ended', () {
    final block = findNextBackToBackEventBlock([
      event('Standup', 9, 10),
      event('Review', 10, 11),
    ], now: DateTime(2026, 9, 1, 12));

    expect(block, isNull);
  });

  test('deduplicates the same event from two providers', () {
    final duplicate = event('Product Review', 13, 14);
    final block = findNextBackToBackEventBlock([
      duplicate,
      duplicate,
    ], now: now);

    expect(block, isNull);
  });
}
