import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/activity_source.dart';

void main() {
  test('any steps, calories or exercise in the window counts', () {
    expect(hasActivityData([]), isFalse);
    expect(
      hasActivityData([
        null,
        {
          'steps': {'sum': 0},
          'sleep': {'avg': 7.5},
        },
      ]),
      isFalse,
    );
    expect(
      hasActivityData([
        {
          'exercise_time': {'sum': 12},
        },
      ]),
      isTrue,
    );
    expect(
      hasActivityData([
        {
          'steps': {'sum': 4200},
        },
      ]),
      isTrue,
    );
  });
}
