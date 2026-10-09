typedef FitnessActivityTotals = ({num? steps, num? calories, num? minutes});

/// Small immutable projections, not copies of the full daily metric documents.
class FitnessActivityHistory {
  Map<String, FitnessActivityTotals> _totals = const {};
  Map<String, Map<String, dynamic>> _history = const {};

  Map<String, Map<String, dynamic>> update(
    Iterable<String> currentIds,
    Map<String, FitnessActivityTotals> changed,
  ) {
    final ids = currentIds.toSet();
    final next = {..._totals}..removeWhere((id, _) => !ids.contains(id));
    for (final entry in changed.entries) {
      if (ids.contains(entry.key)) next[entry.key] = entry.value;
    }
    if (next.length == _totals.length &&
        next.entries.every((e) => _totals[e.key] == e.value)) {
      return _history;
    }
    _totals = next;
    _history = Map.unmodifiable({
      for (final entry in next.entries)
        entry.key: Map<String, dynamic>.unmodifiable({
          'steps': Map<String, dynamic>.unmodifiable({
            'sum': entry.value.steps,
          }),
          'active_calories': Map<String, dynamic>.unmodifiable({
            'sum': entry.value.calories,
          }),
          'exercise_time': Map<String, dynamic>.unmodifiable({
            'sum': entry.value.minutes,
          }),
        }),
    });
    return _history;
  }
}
