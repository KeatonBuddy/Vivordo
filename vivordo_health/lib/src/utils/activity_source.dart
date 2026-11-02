/// Whether any of [days] (metrics_daily documents, or projections of them)
/// has steps, active calories or exercise. iOS never says whether Health
/// read access was granted, so the data is the only reliable sign: with
/// none for days, nothing is supplying activity, and zeros would be
/// missing data rather than a still day.
bool hasActivityData(Iterable<Map<String, dynamic>?> days) => days.any(
  (day) => const [
    'steps',
    'active_calories',
    'exercise_time',
  ].any((metric) => (((day?[metric] as Map?)?['sum'] as num?) ?? 0) > 0),
);
