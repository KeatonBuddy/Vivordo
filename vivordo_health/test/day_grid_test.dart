import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
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

  testWidgets('a block shows its chip, and a tappable chip acts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final day = DateTime(2026, 11, 17);
    var moved = 0, opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.light,
        home: Scaffold(
          body: DayGrid(
            day: day,
            now: day.add(const Duration(hours: 9)),
            height: 600,
            onDrop: (_, _) {},
            onResize: (_, _) {},
            blocks: [
              DayGridBlock(
                id: 'slides',
                title: 'Prep slides for Wednesday review',
                start: day.add(const Duration(hours: 10)),
                end: day.add(const Duration(hours: 11)),
                color: const Color(0xFF54C75B),
                onTap: () => opened++,
                chip: DayGridChip(
                  label: 'In your afternoon dip · Move to 2 PM',
                  foreground: Colors.white,
                  background: const Color(0xFF6B5CE7),
                  onTap: () => moved++,
                ),
              ),
              DayGridBlock(
                id: 'standup',
                title: 'Team standup',
                start: day.add(const Duration(hours: 11)),
                end: day.add(const Duration(hours: 11, minutes: 30)),
                color: const Color(0xFF3B82F6),
                chip: const DayGridChip(
                  label: 'Heart rate usually up',
                  foreground: Color(0xFF712B13),
                  background: Color(0xFFFAECE7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    // Both chips are on screen, even on the half-hour block.
    expect(find.text('In your afternoon dip · Move to 2 PM'), findsOneWidget);
    expect(find.text('Heart rate usually up'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // The chip is its own button: it moves the item, not opens it.
    await tester.tap(find.text('In your afternoon dip · Move to 2 PM'));
    expect(moved, 1);
    expect(opened, 0);
  });
}
