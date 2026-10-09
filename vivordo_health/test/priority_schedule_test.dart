import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:vivordo_health/src/services/daily_priority_service.dart';
import 'package:vivordo_health/src/utils/priority_schedule.dart';

// ignore: subtype_of_sealed_class, must_be_immutable
class _Ref extends Mock implements DocumentReference<Map<String, dynamic>> {}

void main() {
  final today = DateTime(2026, 10, 6, 14);
  DailyPriority p({
    DateTime? date,
    bool completed = false,
    Map<String, dynamic> planning = const {},
    DateTime? start,
    DateTime? end,
  }) => DailyPriority(
    id: 'p',
    title: 'p',
    completed: completed,
    reference: _Ref(),
    isAllDay: false,
    source: 'manual',
    date: date,
    planning: planning,
    sourceStart: start,
    sourceEnd: end,
  );

  test('open priorities from earlier days are overdue', () {
    expect(
      overdueSince(p(date: DateTime(2026, 10, 5)), today),
      DateTime(2026, 10, 5),
    );
    expect(overdueSince(p(date: DateTime(2026, 10, 6)), today), isNull);
    expect(overdueSince(p(date: DateTime(2026, 10, 7)), today), isNull);
    expect(
      overdueSince(p(date: DateTime(2026, 10, 1), completed: true), today),
      isNull,
    );
  });

  test('a priority moved to a day counts from that day', () {
    final moved = p(
      date: DateTime(2026, 10, 1),
      planning: {'plannedDay': '2026-10-06'},
    );
    expect(overdueSince(moved, today), isNull);
    final movedEarlier = p(
      date: DateTime(2026, 10, 1),
      planning: {'plannedDay': '2026-10-04'},
    );
    expect(overdueSince(movedEarlier, today), DateTime(2026, 10, 4));
  });

  test('overdue labels read naturally', () {
    expect(overdueLabel(DateTime(2026, 10, 5), today), 'From yesterday');
    expect(overdueLabel(DateTime(2026, 10, 2), today), 'From Fri');
    expect(overdueLabel(DateTime(2026, 9, 28), today), 'From Sep 28');
  });

  test('length comes from the estimate, else calendar time', () {
    expect(priorityMinutes(p(planning: {'minutes': 45})), 45);
    expect(
      priorityMinutes(
        p(start: DateTime(2026, 10, 6, 9), end: DateTime(2026, 10, 6, 10)),
      ),
      60,
    );
    expect(priorityMinutes(p()), isNull);
    expect(formatPriorityMinutes(105), '1h 45m');
    expect(formatPriorityMinutes(120), '2h');
    expect(formatPriorityMinutes(15), '15 min');
  });

  test('a habit streak counts scheduled days done in a row', () {
    final weekdays = PriorityTemplate(
      id: 't',
      title: 'Stretch',
      recurrence: 'weekly',
      weekdays: const {1, 3, 5},
      doneDays: const {'2026-10-05', '2026-10-02', '2026-09-30', '2026-09-25'},
    );
    // Today (Tue) isn't scheduled; Mon, Fri, Wed done; Mon Sep 28 missed.
    expect(weekdays.streak(today), 3);
    final daily = PriorityTemplate(
      id: 'd',
      title: 'Water',
      recurrence: 'daily',
      doneDays: const {'2026-10-05', '2026-10-04'},
    );
    // Today still open doesn't break it; doing it adds one.
    expect(daily.streak(today), 2);
    expect(
      habitStreak({...daily.doneDays, '2026-10-06'}, daily.repeatsOn, today),
      3,
    );
    expect(
      PriorityTemplate(
        id: 'n',
        title: 'New',
        recurrence: 'daily',
        startDate: DateTime(2026, 10, 6),
      ).streak(today),
      0,
    );
  });

  test('habit icons come from the title', () {
    expect(habitIcon('Drink water'), isNotNull);
    expect(habitIcon('Meditate'), habitIcon('Breathing'));
    expect(habitIcon('Meditate'), isNot(habitIcon('Take meds')));
    expect(habitIcon('Call mum'), isNull);
  });
}
