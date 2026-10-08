import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/heavy_days.dart';
import 'package:vivordo_health/src/utils/meeting_patterns.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/meeting_patterns_view.dart';

void main() {
  var n = 0;
  MeetingReaction reaction({
    String? series,
    double lift = 0,
    String category = 'collaboration',
    int guests = 2,
    int hour = 11,
    int minutes = 60,
    int day = 1,
  }) => MeetingReaction(
    day: DateTime(2026, 9, day),
    key: 'e${n++}',
    series: series,
    category: category,
    guests: guests,
    minutes: minutes,
    startHour: hour,
    median: 70 + lift,
    usual: 70,
  );

  test('a series needs 4 consistent times to count as up', () {
    final three = [for (var i = 0; i < 3; i++) reaction(series: 's', lift: 15)];
    expect(meetingPatternsFrom(three).bySeries, isEmpty);
    final four = [...three, reaction(series: 's', lift: 12, day: 9)];
    final p = meetingPatternsFrom(four).bySeries['s']!;
    expect(p.high, isTrue);
    expect(p.countLabel, '4 of 4 times');
    expect(p.liftLabel, '21% over your usual');
    expect(p.label, startsWith('A repeating meeting · Wed 11 AM'));
  });

  test('mixed or small changes make no pattern', () {
    final mixed = [
      for (final lift in <double>[15, 12, -4, 9, -6])
        reaction(series: 's', lift: lift),
    ];
    expect(meetingPatternsFrom(mixed).bySeries, isEmpty);
    final small = [for (var i = 0; i < 6; i++) reaction(series: 's', lift: 3)];
    expect(meetingPatternsFrom(small).bySeries, isEmpty);
  });

  test('kinds need 8 events; calm needs 3 bpm under and 70% agreeing', () {
    final focus = [
      for (var i = 0; i < 8; i++)
        reaction(category: 'focused-work', guests: 0, lift: -5),
    ];
    final result = meetingPatternsFrom(focus);
    expect(result.calm.single.label, 'Focus blocks');
    expect(result.calm.single.liftLabel, '7% under your usual');
    expect(result.learning, isFalse);
    expect(meetingPatternsFrom(focus.take(7).toList()).learning, isTrue);
  });

  test('a kind made mostly of shown events is skipped', () {
    final focus = [
      for (var i = 0; i < 9; i++)
        reaction(category: 'focused-work', hour: 9, minutes: 90, lift: -5),
    ];
    expect(meetingPatternsFrom(focus).calm.map((p) => p.label), [
      'Focus blocks',
    ]);
  });

  test('a kind made mostly of a shown series is skipped', () {
    final sprint = [
      for (var i = 0; i < 6; i++) reaction(series: 's', guests: 8, lift: 20),
    ];
    final others = [for (var i = 0; i < 2; i++) reaction(guests: 8, lift: 8)];
    final result = meetingPatternsFrom([...sprint, ...others]);
    expect(result.high.map((p) => p.id), ['s']);
  });

  test('reactions parse from event_reactions documents', () {
    final all = MeetingReaction.fromDays({
      '2026-10-06': {
        'abc': {
          'v': 1,
          'series': 's1',
          'category': 'social',
          'guests': 4,
          'minutes': 30,
          'startHour': 17,
          'median': 82,
          'usual': 70,
        },
        'bad': {'v': 2},
      },
    });
    expect(all.single.series, 's1');
    expect(all.single.liftBpm, 12);
    expect(all.single.day, DateTime(2026, 10, 6));
  });

  test('heavy days compare that night and the next morning', () {
    final scores = <String, Map<String, dynamic>>{};
    String key(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    // 6 weeks of weekdays from Mon Aug 31: Mon/Wed heavy.
    for (var i = 0; i < 42; i++) {
      final d = DateTime(2026, 8, 31 + i);
      final heavy = d.weekday == 1 || d.weekday == 3;
      scores[key(d)] = {
        ...?scores[key(d)],
        'effort': {'busyMinutes': heavy ? 300 : 120},
      };
      final next = DateTime(2026, 8, 31 + i + 1);
      scores[key(next)] = {
        ...?scores[key(next)],
        'capacity': {
          'sleepHours': heavy ? 6.5 : 7.25,
          'score': heavy ? 70 : 78,
          'version': 2,
        },
      };
    }
    final result = heavyDaysFrom(scores);
    expect(result.heavy, 12);
    expect(result.sleepMinutes, -45);
    expect(result.capacity, -8);
    expect(heavyDaysFrom(const {}).ready, isFalse);
  });

  group('Home row', () {
    final high = meetingPatternsFrom([
      for (var i = 0; i < 4; i++) reaction(series: 's', lift: 15, guests: 8),
    ]);
    final now = DateTime(2026, 10, 8, 9);
    Future<void> show(
      WidgetTester tester,
      MeetingPatterns patterns,
      List<({String? series, String title, DateTime start})> events, {
      DateTime? at,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.light,
        home: Scaffold(
          body: MeetingPatternsRow(
            patterns: patterns,
            now: at ?? now,
            today: todaysPatternMeetings(
              patterns: patterns,
              events: events,
              now: at ?? now,
            ),
          ),
        ),
      ),
    );

    testWidgets('names today\'s meeting that raises heart rate', (
      tester,
    ) async {
      await show(tester, high, [
        (
          series: 's',
          title: 'Sprint planning',
          start: DateTime(2026, 10, 8, 14),
        ),
        (series: 'x', title: 'Lunch', start: DateTime(2026, 10, 8, 12)),
      ]);
      expect(
        find.text('Sprint planning usually raises your heart rate'),
        findsOneWidget,
      );
      expect(find.textContaining('Today at 2 PM'), findsOneWidget);
      await show(tester, high, [
        (
          series: 's',
          title: 'Sprint planning',
          start: DateTime(2026, 10, 8, 15, 30),
        ),
      ]);
      expect(find.textContaining('Today at 3:30 PM'), findsOneWidget);
    });

    testWidgets('hides when nothing matches or it already happened', (
      tester,
    ) async {
      await show(tester, high, [
        (
          series: 's',
          title: 'Sprint planning',
          start: DateTime(2026, 10, 8, 8),
        ),
      ]);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('learning shows on Mondays only', (tester) async {
      final learning = meetingPatternsFrom([reaction(lift: 3)]);
      await show(tester, learning, const []);
      expect(find.byType(InkWell), findsNothing);
      await show(tester, learning, const [], at: DateTime(2026, 10, 5, 9));
      expect(find.text('Learning which meetings get to you'), findsOneWidget);
    });
  });
}
