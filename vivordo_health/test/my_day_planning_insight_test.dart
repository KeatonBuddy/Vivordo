import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/daily_brief_analysis.dart';
import 'package:vivordo_health/src/utils/my_day_planning_insight.dart';

void main() {
  final now = DateTime(2026, 9, 24, 10);
  String insight({
    List<BriefCommitment> events = const [],
    List<BriefPriority> priorities = const [],
    bool ready = true,
    int allDay = 0,
  }) => myDayPlanningInsight(
    now: now,
    events: events,
    priorities: priorities,
    calendarReady: ready,
    prioritiesReady: true,
    allDayEvents: allDay,
  );
  test('empty plan offers help without inventing work', () {
    expect(insight(), contains('no unfinished priorities'));
  });
  test('missing calendar is not called an empty schedule', () {
    expect(insight(ready: false), contains('calendar is not fully available'));
    expect(insight(ready: false), isNot(contains('No calendar events')));
  });
  test('remaining events, back-to-back tasks and unlinked workload', () {
    final text = insight(
      events: [
        BriefCommitment(
          'old',
          'Past',
          now.subtract(const Duration(hours: 2)),
          now.subtract(const Duration(hours: 1)),
        ),
        BriefCommitment('a', 'First', now, now.add(const Duration(hours: 1))),
        BriefCommitment(
          'b',
          'Second',
          now.add(const Duration(hours: 1)),
          now.add(const Duration(hours: 2)),
        ),
      ],
      priorities: [
        const BriefPriority(id: 'linked', eventKey: 'a', minutes: 60),
        const BriefPriority(id: 'flex', minutes: 90),
        const BriefPriority(id: 'unknown'),
        const BriefPriority(id: 'done', minutes: 30, completed: true),
      ],
    );
    expect(text, contains('2 calendar events remaining'));
    expect(text, contains('3 unfinished priorities'));
    expect(text, contains('At least 90 minutes'));
    expect(text, contains('back-to-back tasks'));
    expect(text, contains('1 priority is already linked'));
  });
  test('all-day events counted but do not create back-to-back pressure', () {
    final text = insight(allDay: 2);
    expect(text, contains('including 2 all-day'));
    expect(text, isNot(contains('back-to-back')));
  });
}
