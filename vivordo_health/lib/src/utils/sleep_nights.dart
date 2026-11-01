import 'package:cloud_firestore/cloud_firestore.dart';

import 'detail_insights.dart' show SleepNight;
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

/// Nights for sleepPatterns, keyed by the morning they end on, from
/// metrics_daily days by day key (whole or projected).
Map<DateTime, SleepNight> patternNights(
  Map<String, Map<String, dynamic>> days,
) => {
  for (final MapEntry(:key, :value) in days.entries)
    if (value['sleep'] case {'avg': final num hours} && final Map sleep
        when hours > 0)
      ?DateTime.tryParse(key): SleepNight(
        hours.toDouble(),
        (sleep['bedtime'] as Timestamp?)?.toDate().toLocal(),
        (sleep['wakeTime'] as Timestamp?)?.toDate().toLocal(),
        sleep['measure'] == 'inBed',
      ),
};

/// "How did you sleep?" answers (0–100) by morning.
Map<DateTime, double> sleepRatings(Map<String, Map<String, dynamic>> days) => {
  for (final MapEntry(:key, :value) in days.entries)
    if ((value['morning_check_in'] as Map?)?['sleep'] case final num rating)
      ?DateTime.tryParse(key): rating.toDouble(),
};
