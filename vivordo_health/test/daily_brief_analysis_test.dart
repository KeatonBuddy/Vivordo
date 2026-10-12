import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/daily_brief_analysis.dart';

void main() {
  test('last night against the need, never a moving 28-night usual', () {
    // A rough fortnight: 5 h 50 against a need of 7 h 03.
    expect(sleepComparison(5.83, need: 7.05), 'Slept 1h 13m under your need.');
    expect(sleepComparison(7.75, need: 7.5), 'Slept about your need.');
    expect(sleepComparison(8.5, need: 7.5), 'Slept 1h over your need.');
    // The 8 h placeholder isn't presented as theirs.
    expect(sleepComparison(7.25, need: null), 'Slept 7h 15m.');
    expect(
      sleepComparison(null, need: 7.5),
      "Last night's sleep hasn't synced yet.",
    );
    expect(sleepComparison(null, need: 7.5, tracksSleep: false), '');
  });
  test('remaining counts read naturally', () {
    expect(remainingToday(3, 2), '3 events and 2 priorities left.');
    expect(remainingToday(1, 1), '1 event and 1 priority left.');
    expect(remainingToday(0, 2), 'No events and 2 priorities left.');
    expect(remainingToday(1, 0), '1 event and no priorities left.');
    expect(remainingToday(0, 0), 'Nothing else planned today.');
  });
}
