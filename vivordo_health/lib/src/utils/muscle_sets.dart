import '../services/workout_service.dart';

/// Strength sets by muscle group (muscleGroupOf) for the Exercise screen's
/// card. Weeks run Monday to Sunday. A group's "usual week"
/// is the mean of recent weeks that had any strength sets, so a week off
/// doesn't lower it.

const muscleGroups = [
  'Chest',
  'Back',
  'Shoulders',
  'Biceps',
  'Triceps',
  'Arms',
  'Legs',
  'Core',
];

/// The Monday of [day]'s week.
DateTime weekStart(DateTime day) =>
    DateTime(day.year, day.month, day.day - (day.weekday - 1));

DateTime _day(DateTime t) {
  final local = t.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Sets per group in [workouts]; groups without sets are left out.
Map<String, int> setsByGroup(Iterable<SavedWorkout> workouts) {
  final sets = <String, int>{};
  for (final workout in workouts) {
    for (final exercise in workout.exercises) {
      final group = muscleGroupOf(exercise);
      if (group == null || exercise.sets.isEmpty) continue;
      sets[group] = (sets[group] ?? 0) + exercise.sets.length;
    }
  }
  return sets;
}

/// Sets by group for each week (by its Monday) that had any.
Map<DateTime, Map<String, int>> weeklySets(Iterable<SavedWorkout> workouts) {
  final byWeek = <DateTime, List<SavedWorkout>>{};
  for (final workout in workouts) {
    byWeek
        .putIfAbsent(weekStart(_day(workout.completedAt)), () => [])
        .add(workout);
  }
  return {
    for (final MapEntry(:key, :value) in byWeek.entries)
      if (setsByGroup(value) case final sets when sets.isNotEmpty) key: sets,
  };
}

/// The usual week for each group, from the [count] weeks before [before]
/// that had sets. Null with fewer than 2 such weeks.
Map<String, double>? usualWeek(
  Map<DateTime, Map<String, int>> weekly,
  DateTime before, {
  int count = 4,
}) {
  final weeks = [
    for (var i = 1; i <= count; i++)
      ?weekly[DateTime(before.year, before.month, before.day - 7 * i)],
  ];
  if (weeks.length < 2) return null;
  final usual = <String, double>{};
  for (final week in weeks) {
    for (final MapEntry(:key, :value) in week.entries) {
      usual[key] = (usual[key] ?? 0) + value / weeks.length;
    }
  }
  return usual;
}

/// A row of the card: sets (or sets a week, on Month), the usual week, and
/// on Month each of the 4 weeks.
class MuscleGroupSets {
  const MuscleGroupSets(
    this.group,
    this.value, {
    this.usual,
    this.usualByNow,
    this.weeks,
  });

  final String group;
  final double value;
  final double? usual;

  /// Week: the usual sets by this day of the week, which [low] compares
  /// with, so a week in progress isn't held to a whole week.
  final double? usualByNow;
  final List<int>? weeks;

  /// Well under the usual: 60% or less of a usual of 3 or more.
  bool get low {
    final usual = usualByNow ?? this.usual;
    return usual != null && usual >= 3 && value <= usual * .6;
  }
}

class MuscleSetsView {
  const MuscleSetsView({
    required this.total,
    required this.groups,
    this.note,
    this.weeks = const [],
  });

  /// Sets in the range, or on Month, sets a week.
  final int total;
  final List<MuscleGroupSets> groups;
  final String? note;

  /// Month: the Mondays of its 4 weeks, oldest first.
  final List<DateTime> weeks;
}

List<MuscleGroupSets> _sorted(List<MuscleGroupSets> rows) => rows
  ..sort((a, b) {
    final bySets = b.value.compareTo(a.value);
    return bySets != 0
        ? bySets
        : muscleGroups.indexOf(a.group) - muscleGroups.indexOf(b.group);
  });

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// This week (Monday to today) against the usual week of the 4 before it.
/// Groups are flagged against the usual by this day of the week. Null when
/// nothing was trained and there's no usual to miss.
MuscleSetsView? muscleSetsWeek(List<SavedWorkout> workouts, DateTime today) {
  final day = _day(today);
  final thisWeek = weekStart(day);
  final sets = setsByGroup(
    workouts.where((w) => !_day(w.completedAt).isBefore(thisWeek)),
  );
  final weekly = weeklySets(workouts);
  final usual = usualWeek(weekly, thisWeek) ?? const {};
  if (sets.isEmpty && usual.isEmpty) return null;
  // The same usual, counting only Monday to today's weekday of each week.
  final byNow = usual.isEmpty
      ? const <String, double>{}
      : usualWeek({
              for (final week in weekly.keys)
                week: setsByGroup(
                  workouts.where((w) {
                    final d = _day(w.completedAt);
                    return weekStart(d) == week && d.weekday <= day.weekday;
                  }),
                ),
            }, thisWeek) ??
            const <String, double>{};
  final rows = _sorted([
    for (final group in muscleGroups)
      if ((sets[group] ?? 0) > 0 || (usual[group] ?? 0) >= 1)
        MuscleGroupSets(
          group,
          (sets[group] ?? 0).toDouble(),
          usual: usual.isEmpty ? null : usual[group] ?? 0,
          usualByNow: usual.isEmpty ? null : byNow[group] ?? 0,
        ),
  ]);
  final low = rows.where((r) => r.low).toList()
    ..sort(
      (a, b) => (b.usualByNow! - b.value).compareTo(a.usualByNow! - a.value),
    );
  final sunday = day.weekday == DateTime.sunday;
  String line(MuscleGroupSets r, bool first) {
    final had = r.value == 0 ? 'none' : '${r.value.round()} sets';
    final usual = r.usualByNow!.round();
    if (!first) {
      return r.value == 0
          ? '${r.group}: none ${sunday ? 'this week' : 'yet'}.'
          : '${r.group}: ${r.value.round()}, against $usual.';
    }
    return sunday
        ? '${r.group} had $had this week, against your usual $usual.'
        : '${r.group}: $had so far this week, against your usual $usual by '
              '${_weekdays[day.weekday - 1]}.';
  }

  return MuscleSetsView(
    total: sets.values.fold(0, (a, b) => a + b),
    groups: rows,
    note: low.isEmpty
        ? null
        : [for (final (i, r) in low.take(2).indexed) line(r, i == 0)].join(' '),
  );
}

/// The last 4 full weeks, a week at a time, against the usual week of the
/// 8 weeks before them. Null without sets in them.
MuscleSetsView? muscleSetsMonth(List<SavedWorkout> workouts, DateTime today) {
  final weekly = weeklySets(workouts);
  final thisWeek = weekStart(_day(today));
  final weeks = [
    for (var i = 4; i >= 1; i--)
      DateTime(thisWeek.year, thisWeek.month, thisWeek.day - 7 * i),
  ];
  final counts = [for (final w in weeks) weekly[w] ?? const <String, int>{}];
  if (counts.every((c) => c.isEmpty)) return null;
  final usual = usualWeek(weekly, weeks.first, count: 8) ?? const {};
  final rows = _sorted([
    for (final group in muscleGroups)
      if (counts.any((c) => (c[group] ?? 0) > 0) || (usual[group] ?? 0) >= 1)
        MuscleGroupSets(
          group,
          counts.fold<int>(0, (t, c) => t + (c[group] ?? 0)) / 4,
          usual: usual.isEmpty ? null : usual[group] ?? 0,
          weeks: [for (final c in counts) c[group] ?? 0],
        ),
  ]);
  final low = rows.where((r) => r.low).toList()
    ..sort((a, b) => (b.usual! - b.value).compareTo(a.usual! - a.value));
  String line(MuscleGroupSets r) {
    final w = r.weeks!;
    if (w[0] > w[1] && w[1] > w[2] && w[2] > w[3]) {
      return '${r.group} sets dropped three weeks running, from ${w[0]} to '
          '${w[3]}.';
    }
    return r.value == 0
        ? '${r.group} had none, against your usual ${r.usual!.round()} a week.'
        : '${r.group} averaged ${r.value.round()} sets a week, against your '
              'usual ${r.usual!.round()}.';
  }

  final total = counts.fold<int>(
    0,
    (t, c) => t + c.values.fold(0, (a, b) => a + b),
  );
  return MuscleSetsView(
    total: (total / 4).round(),
    groups: rows,
    note: low.isEmpty ? null : low.take(2).map(line).join(' '),
    weeks: weeks,
  );
}

/// Each exercise's sets in [workouts] for [group] (null: every group), most
/// sets first: "Bench Press 4 · Cable Fly 3".
String exerciseSets(Iterable<SavedWorkout> workouts, [String? group]) {
  final sets = <String, int>{};
  for (final workout in workouts) {
    for (final exercise in workout.exercises) {
      final g = muscleGroupOf(exercise);
      if (g == null || exercise.sets.isEmpty) continue;
      if (group != null && g != group) continue;
      final name = exercise.name.trim();
      sets[name] = (sets[name] ?? 0) + exercise.sets.length;
    }
  }
  final sorted = sets.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return sorted.map((e) => '${e.key} ${e.value}').join(' · ');
}
