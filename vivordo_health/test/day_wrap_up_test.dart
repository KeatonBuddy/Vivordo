import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/day_wrap_up.dart';

void main() {
  test('the signup answer becomes minutes after midnight', () {
    expect(dayWrapUpMinutes({'q10': 18 * 60 + 30}), 1110);
    expect(dayWrapUpMinutes({'q10': 'varies'}), isNull);
    expect(dayWrapUpMinutes({}), kDefaultDayWrapUpMinutes);
    expect(dayWrapUpMinutes({'q10': 24 * 60}), kDefaultDayWrapUpMinutes);
  });
}
