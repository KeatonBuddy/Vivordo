import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/step_totals.dart';

void main() {
  test('overlapping devices are not added together', () {
    // The same walk recorded by the iPhone and a watch.
    expect(
      largestSourceStepTotal([
        (source: 'iphone', steps: 4000),
        (source: 'iphone', steps: 2000),
        (source: 'watch', steps: 5500),
        (source: 'watch', steps: 1000),
      ]),
      6500,
    );
  });

  test('a single device is summed', () {
    expect(
      largestSourceStepTotal([
        (source: 'iphone', steps: 1200),
        (source: 'iphone', steps: 800),
      ]),
      2000,
    );
  });

  test('no samples is no data, not zero', () {
    expect(largestSourceStepTotal(const []), isNull);
  });

  test("a day's steps come from Health's hourly totals, so a sample begun "
      'before midnight still counts its share of today', () {
    // 2026-10-19: hours summed to 6,152 (the Health app's number) while the
    // plugin's day total, counting only samples begun that day, gave 4,604.
    final hours = [
      539,
      539,
      470,
      0,
      0,
      0,
      0,
      0,
      0,
      30,
      1023,
      0,
      1017,
      123,
      800,
      1611,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
    ];
    expect(dayStepTotal(hours), 6152);
    expect(dayStepTotal(List.filled(24, 0)), isNull);
    expect(dayStepTotal(null), isNull);
  });
}
