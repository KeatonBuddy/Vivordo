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

/// The suggested plan, plus every time each task could go instead
/// ([options], by task id).
typedef DayPlan = ({
  List<PlannedSlot> placed,
  List<UnplacedTask> unplaced,
  Map<String, List<PlannedSlot>> options,
});

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
/// Each task's [DayPlan.options] are one time in every free stretch it fits
/// (the best fit in it), around events only, so you can choose your own.
/// Priorities without a time already count in Demand, so placing them
/// doesn't add to the day.
DayPlan planMyDay({
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

  PlannedSlot slot(PlanTask task, DateTime start) => (
    task: task,
    start: start,
    end: start.add(Duration(minutes: task.minutes)),
    reason: switch ((task.effort, forecast?.phaseAt(start))) {
      ('light', EnergyPhase.dip) => 'Light work for your dip',
      (_, EnergyPhase.peak) => 'In your peak',
      (_, EnergyPhase.secondWind) => 'In your second wind',
      _ => 'The next open time',
    },
  );

  // Before the plan takes any time: one option per free stretch.
  final options = {
    for (final task in tasks)
      task.id: () {
        final length = Duration(minutes: task.minutes);
        final found = <PlannedSlot>[];
        DateTime? best;
        var bestFit = 1 << 30;
        void close() {
          if (best case final start?) found.add(slot(task, start));
          best = null;
          bestFit = 1 << 30;
        }

        for (
          var start = earliest;
          !start.add(length).isAfter(limit);
          start = start.add(_step)
        ) {
          if (!free(start, start.add(length))) {
            close();
            continue;
          }
          final score = fit(task, forecast?.phaseAt(start));
          if (score < bestFit) {
            best = start;
            bestFit = score;
          }
        }
        close();
        return found;
      }(),
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
    busy.add((start: best, end: best.add(length)));
    placed.add(slot(task, best));
  }
  placed.sort((a, b) => a.start.compareTo(b.start));
  return (placed: placed, unplaced: unplaced, options: options);
}

String _gapLabel(int minutes) =>
    minutes % 60 == 0 ? '${minutes ~/ 60}-hour' : '$minutes-minute';
