import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/widgets/day_grid.dart';

void main() {
  test('a drop snaps to 15 minutes, or 5 once zoomed far in', () {
    const scale = DayGridScale(60); // one point a minute
    expect(scale.minutesAt(9 * 60 + 7), 9 * 60);
    expect(scale.minutesAt(9 * 60 + 8), 9 * 60 + 15);
    const close = DayGridScale(120);
    expect(close.step, 5);
    expect(close.minutesAt(2 * (9 * 60 + 7)), 9 * 60 + 5);
  });

  test('a drop keeps the whole block before midnight', () {
    const scale = DayGridScale(60);
    expect(scale.minutesAt(24 * 60 - 5, length: 45), 24 * 60 - 45);
    expect(scale.minutesAt(-30), 0);
  });

  test('resizing snaps and never goes below one step', () {
    const scale = DayGridScale(60);
    expect(scale.resized(30, 22), 45);
    expect(scale.resized(30, -200), 15);
  });

  test('zoom stays within its limits', () {
    expect(DayGridScale.zoomed(46, 10), DayGridScale.max);
    expect(DayGridScale.zoomed(46, .1), DayGridScale.min);
    expect(DayGridScale.zoomed(46, 2), 92);
  });
}
