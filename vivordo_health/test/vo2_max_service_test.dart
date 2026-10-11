import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/vo2_max_service.dart';

void main() {
  test('keeps the latest reading per local day and drops bad values', () {
    final morning = DateTime(2026, 9, 30, 8).millisecondsSinceEpoch;
    final evening = DateTime(2026, 9, 30, 19).millisecondsSinceEpoch;
    final next = DateTime(2026, 10, 1, 7).millisecondsSinceEpoch;
    expect(
      Vo2MaxService.latestByDay([
        {'date': evening, 'value': 41.2},
        {'date': morning, 'value': 40.1},
        {'date': next, 'value': 0},
        {'date': next, 'value': 250},
        'not a sample',
      ]),
      {'2026-09-30': 41.2},
    );
  });
}
