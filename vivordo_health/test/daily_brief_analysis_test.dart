import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/daily_brief_analysis.dart';

void main() {
  test('baseline requires seven valid nights and uses median', () {
    expect(sleepBaseline([0, double.nan, 8, 8]), isNull);
    expect(sleepBaseline([8, 8, 8, 8, 8, 8, 2]), 8);
    expect(sleepComparison(6.5, 8), 'Slept 1h 30m less than usual.');
    expect(sleepComparison(8.75, 8), 'Slept 45 min more than usual.');
    expect(sleepComparison(10, 8), 'Slept 2h more than usual.');
    expect(sleepComparison(7.5, 8), 'Slept about your usual.');
    expect(sleepComparison(8, null), 'Still learning your usual sleep.');
    expect(sleepComparison(null, 8), 'Sleep data unavailable.');
  });
  test('remaining counts read naturally', () {
    expect(remainingToday(3, 2), '3 events and 2 priorities left.');
    expect(remainingToday(1, 1), '1 event and 1 priority left.');
    expect(remainingToday(0, 2), 'No events and 2 priorities left.');
    expect(remainingToday(0, 0), 'Nothing else planned today.');
  });
}
