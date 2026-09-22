import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/daily_brief_analysis.dart';

void main() {
  final now = DateTime(2026, 9, 22, 9);
  BriefCommitment event(String id, int hour, int end) => BriefCommitment(
    id,
    id,
    DateTime(2026, 9, 22, hour),
    DateTime(2026, 9, 22, end),
  );
  test('baseline requires seven valid nights and uses median', () {
    expect(sleepBaseline([0, double.nan, 8, 8]), isNull);
    expect(sleepBaseline([8, 8, 8, 8, 8, 8, 2]), 8);
    expect(sleepComparison(6.5, 8), contains('1h 30m less'));
    expect(sleepComparison(7.5, 8), contains('close'));
  });
  test(
    'backlog excluded; planned flexible work contributes without blocking openings',
    () {
      const backlog = BriefPriority(id: 'a', minutes: 120);
      expect(analyzeBriefPlan(now, [], [backlog]).score, 0);
      final planned = BriefPriority(id: 'a', minutes: 120, plannedDay: now);
      final plan = analyzeBriefPlan(now, [], [planned]);
      expect(plan.score, greaterThan(0));
      expect(plan.flexibleMinutes, 120);
      expect(plan.observation, contains('opening now'));
    },
  );
  test('completion removes flexible work and uncompletion restores it', () {
    final done = BriefPriority(
      id: 'a',
      minutes: 120,
      plannedDay: now,
      completed: true,
    );
    expect(analyzeBriefPlan(now, [], [done]).score, 0);
    expect(
      analyzeBriefPlan(now, [], [
        BriefPriority(id: 'a', minutes: 120, plannedDay: now),
      ]).score,
      greaterThan(0),
    );
  });
  test('linked event counted once even for a completed task', () {
    final events = [event('google:a', 10, 11)];
    final base = analyzeBriefPlan(now, events, []).score;
    for (final completed in [false, true]) {
      expect(
        analyzeBriefPlan(now, events, [
          BriefPriority(
            id: 'a',
            eventKey: 'google:a',
            start: now,
            minutes: 60,
            completed: completed,
          ),
        ]).score,
        base,
      );
    }
  });
  test('missing estimate or unavailable linked event is disclosed', () {
    final result = analyzeBriefPlan(now, [], [
      BriefPriority(id: 'a', plannedDay: now),
      BriefPriority(
        id: 'b',
        plannedDay: now,
        eventKey: 'google:missing',
        minutes: 60,
      ),
    ]);
    expect(result.missingEstimates, 2);
    expect(result.score, 0);
  });
  test('overlaps do not create false free gaps', () {
    final plan = analyzeBriefPlan(now, [
      event('a', 9, 12),
      event('b', 10, 11),
    ], []);
    expect(plan.observation, contains('12:00 PM'));
  });
  test('past events do not contribute to remaining demand', () {
    expect(
      analyzeBriefPlan(DateTime(2026, 9, 22, 12), [
        event('a', 9, 10),
      ], []).score,
      0,
    );
  });
  test('busy afternoon and consecutive commitments are grounded', () {
    expect(
      analyzeBriefPlan(now, [event('a', 13, 16)], []).observation,
      contains('Busy afternoon'),
    );
    expect(
      analyzeBriefPlan(now, [
        event('a', 9, 10),
        event('b', 10, 11),
        event('c', 11, 12),
      ], []).observation,
      contains('3 consecutive'),
    );
  });
  test('effort influences workload without altering real duration', () {
    final light = analyzeBriefPlan(now, [], [
      BriefPriority(id: 'a', minutes: 120, plannedDay: now, effort: 'light'),
    ]);
    final high = analyzeBriefPlan(now, [], [
      BriefPriority(
        id: 'a',
        minutes: 120,
        plannedDay: now,
        effort: 'demanding',
      ),
    ]);
    expect(high.score, greaterThan(light.score));
    expect(high.flexibleMinutes, light.flexibleMinutes);
  });
}
