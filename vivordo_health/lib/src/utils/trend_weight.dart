import 'dart:math' as math;

/// Each day moves the trend 10% of the way to the scale, as in the Hacker's
/// Diet moving average that MacroFactor-style trend weights build on.
const _dailyWeight = 0.1;

/// The trend weight at each weigh-in, in [weights]' order (oldest first):
/// an exponentially smoothed average that evens out water and food swings.
/// A gap of several days counts as several days of smoothing, so sparse
/// weigh-ins aren't held back by an old trend.
List<double> trendWeights(List<({DateTime date, double value})> weights) {
  final trend = <double>[];
  for (final (i, w) in weights.indexed) {
    if (i == 0) {
      trend.add(w.value);
      continue;
    }
    final days =
        w.date.difference(weights[i - 1].date).inMinutes /
        Duration.minutesPerDay;
    final share = 1 - math.pow(1 - _dailyWeight, math.max(days, 0));
    trend.add(trend.last + share * (w.value - trend.last));
  }
  return trend;
}
