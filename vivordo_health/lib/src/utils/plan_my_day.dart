import 'day_effort.dart';
import 'energy_forecast.dart';

/// A priority with no time today, to place: how long and how hard
/// (`planning.effort`: demanding, moderate or light).
typedef PlanTask = ({String id, String title, int minutes, String? effort});

typedef PlannedSlot = ({
  PlanTask task,
  DateTime start,
  DateTime end,
  String reason,
});

typedef UnplacedTask = ({PlanTask task, String reason});

const _step = Duration(minutes: 15);

/// How soon from now a slot may start.
const _lead = Duration(minutes: 15);

/// Kept free between one thing and the next.
// ponytail: a flat 10 minutes around everything; scale it with the length
// of the stretch before if people want longer breaks after long runs.
const _gap = Duration(minutes: 10);

/// "Plan my day": a time for each of [tasks] in the free time between [now]
/// (or your wake, if later) and [wrapUp] (or wind-down, if earlier), around [items] (the day's events
/// and timed priorities, as for Demand) with a short break either side.
/// Demanding work goes first, into your peak or second wind; light work
/// into the dip; moderate anywhere but a low patch. Without a [forecast],
/// the earliest free time. Tasks with no room are [UnplacedTask]s, with why.
/// Priorities without a time already count in Demand, so placing them
/// doesn't add to the day.
({List<PlannedSlot> placed, List<UnplacedTask> unplaced}) planMyDay({
  required DateTime now,
  required DateTime wrapUp,
  required List<EffortItem> items,
  required List<PlanTask> tasks,
  EnergyForecast? forecast,
}) {
  final windDown = forecast?.window(EnergyPhase.windDown)?.start;
  final limit = windDown != null && windDown.isBefore(wrapUp)
      ? windDown
      : wrapUp;
  // Not before you're up: after midnight, the day starts at your wake.
  final wake = forecast?.wake;
  final soonest = wake != null && wake.isAfter(now.add(_lead))
      ? wake
      : now.add(_lead);
  // Round up to the next quarter hour.
  final earliest = DateTime(
    soonest.year,
    soonest.month,
    soonest.day,
    soonest.hour,
    (soonest.minute + 14) ~/ 15 * 15,
  );
  final busy = [
    for (final item in items)
      if (item.event.contributesToSchedule)
        (start: item.event.start, end: item.event.end),
  ];
  bool free(DateTime start, DateTime end) => !busy.any(
    (b) => start.isBefore(b.end.add(_gap)) && b.start.isBefore(end.add(_gap)),
  );

  int rank(PlanTask task) => switch (task.effort) {
    'demanding' => 0,
    'light' => 2,
    _ => 1,
  };
  final ordered = [...tasks]
    ..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : b.minutes.compareTo(a.minutes);
    });

  // Lower is a better fit for the task's effort, by the window the slot
  // starts in, so it isn't "in your peak" while you're still groggy.
  int fit(PlanTask task, EnergyPhase? phase) => switch ((task.effort, phase)) {
    (_, null) => 1,
    ('demanding', EnergyPhase.peak) => 0,
    ('demanding', EnergyPhase.secondWind) => 1,
    ('demanding', _) => 3,
    ('light', EnergyPhase.dip) => 0,
    ('light', EnergyPhase.peak) => 2,
    ('light', _) => 1,
    (_, EnergyPhase.dip || EnergyPhase.groggy) => 2,
    _ => 0,
  };

  final placed = <PlannedSlot>[];
  final unplaced = <UnplacedTask>[];
  for (final task in ordered) {
    final length = Duration(minutes: task.minutes);
    DateTime? best;
    var bestFit = 1 << 30;
    for (
      var start = earliest;
      !start.add(length).isAfter(limit);
      start = start.add(_step)
    ) {
      if (!free(start, start.add(length))) continue;
      final score = fit(task, forecast?.phaseAt(start));
      if (score < bestFit) {
        best = start;
        bestFit = score;
        if (score == 0) break;
      }
    }
    if (best == null) {
      unplaced.add((
        task: task,
        reason: 'No ${_gapLabel(task.minutes)} gap before your wrap-up',
      ));
      continue;
    }
    final end = best.add(length);
    busy.add((start: best, end: end));
    final phase = forecast?.phaseAt(best);
    placed.add((
      task: task,
      start: best,
      end: end,
      reason: switch ((task.effort, phase)) {
        ('light', EnergyPhase.dip) => 'Light work for your dip',
        (_, EnergyPhase.peak) => 'In your peak',
        (_, EnergyPhase.secondWind) => 'In your second wind',
        _ => 'The next open time',
      },
    ));
  }
  placed.sort((a, b) => a.start.compareTo(b.start));
  return (placed: placed, unplaced: unplaced);
}

String _gapLabel(int minutes) =>
    minutes % 60 == 0 ? '${minutes ~/ 60}-hour' : '$minutes-minute';
