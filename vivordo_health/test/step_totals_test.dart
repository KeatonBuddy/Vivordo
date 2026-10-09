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
}
