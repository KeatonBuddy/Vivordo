import 'package:cloud_firestore/cloud_firestore.dart';

import 'energy_forecast.dart';

/// Nights with both a bedtime and a wake time, from `metrics_daily` days'
/// `sleep` maps, for the energy forecast; `avg` is the hours asleep.
List<SleepPeriod> sleepNights(Iterable<Map<String, dynamic>?> days) => [
  for (final day in days)
    if (day?['sleep'] case {
      'bedtime': final Timestamp start,
      'wakeTime': final Timestamp end,
    })
      (
        start: start.toDate(),
        end: end.toDate(),
        asleepHours: (day!['sleep']['avg'] as num?)?.toDouble(),
      ),
];
