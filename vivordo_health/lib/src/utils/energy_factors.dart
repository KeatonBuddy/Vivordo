import 'day_key.dart';

/// Something about last night or yesterday that changes today's energy
/// forecast (docs/scores.md §8): it adds [pressure] to the sleep pressure
/// you wake with, so the day runs a little lower, most of all early on.
class EnergyFactor {
  const EnergyFactor(this.id, this.reason, this.pressure, {this.personal});

  /// A night tag id (daily_tags) or 'hard_training'.
  final String id;

  /// One sentence for the forecast sheet's "What shaped today".
  final String reason;
  final double pressure;

  /// How much lower your next-morning Capacity has been after nights with
  /// this tag (points), when there are enough of them to say.
  final double? personal;
}

/// What each tag does when there aren't enough of your own nights to tell.
/// ponytail: product estimates in the model's own units (0.06 ≈ an hour of
/// lost sleep), from what the research says each tends to do to sleep; your
/// own mornings replace them once tagged 3 times.
const _defaults = <String, ({double pressure, String reason})>{
  'alcohol': (
    pressure: 0.08,
    reason:
        'You tagged alcohol last night. It tends to make sleep lighter, so '
        'expect a lower afternoon.',
  ),
  'late_caffeine': (
    pressure: 0.05,
    reason:
        'Late caffeine last night can make sleep lighter, so today may feel '
        'a little flatter.',
  ),
  'late_meal': (
    pressure: 0.03,
    reason: 'A late meal can make sleep a little lighter.',
  ),
  'screens_in_bed': (
    pressure: 0.03,
    reason: 'Screens in bed tend to make sleep a little lighter.',
  ),
  'sick': (
    pressure: 0.15,
    reason: 'You tagged sick, so expect less energy all day. Go easy.',
  ),
  'travel': (
    pressure: 0.05,
    reason: 'Travel can throw your body clock off, so today may be uneven.',
  ),
};

const _tagNames = {
  'alcohol': 'alcohol',
  'late_caffeine': 'late caffeine',
  'late_meal': 'a late meal',
  'screens_in_bed': 'screens in bed',
  'sick': 'sick',
  'travel': 'travel',
};

/// Your own nights needed, with and without a tag, before they're used.
const _minTagged = 3;
const _minUntagged = 5;

/// A Capacity difference smaller than this (points) counts as "no change".
const _noChange = 3.0;

/// Model pressure per point of next-morning Capacity lost.
const _pressurePerPoint = 0.008;
const _maxPressure = 0.15;

/// The factor id for a hard training day yesterday.
const hardTrainingFactor = 'hard_training';

/// The hard-day line of training load (training_load.js HARD_DAY).
const _hardDay = 1.5;
const _hardTrainingPressure = 0.05;

/// Today's factors: last night's [tags] (night key = yesterday), with your
/// own effect where [tagsByNight] (the last few weeks' daily_tags, keyed by
/// night) and [scores] (scores_daily by day, including today's) have enough
/// nights to compare, and yesterday's training from today's training load.
List<EnergyFactor> energyFactors({
  required DateTime today,
  required Map<String, Set<String>> tagsByNight,
  required Map<String, Map<String, dynamic>> scores,
}) {
  final day = DateTime(today.year, today.month, today.day);
  final yesterday = localDayKey(DateTime(day.year, day.month, day.day - 1));
  double? morningAfter(String night) {
    final d = DateTime.parse(night);
    final capacity =
        scores[localDayKey(DateTime(d.year, d.month, d.day + 1))]?['capacity'];
    return capacity is Map ? (capacity['score'] as num?)?.toDouble() : null;
  }

  final factors = <EnergyFactor>[];
  for (final tag in _defaults.keys) {
    if (!(tagsByNight[yesterday]?.contains(tag) ?? false)) continue;
    final withTag = <double>[], without = <double>[];
    for (final MapEntry(key: night, value: tags) in tagsByNight.entries) {
      if (night == yesterday) continue;
      if (morningAfter(night) case final c?) {
        (tags.contains(tag) ? withTag : without).add(c);
      }
    }
    final fallback = _defaults[tag]!;
    if (withTag.length < _minTagged || without.length < _minUntagged) {
      factors.add(EnergyFactor(tag, fallback.reason, fallback.pressure));
      continue;
    }
    final drop = _median(without) - _median(withTag);
    final name = _tagNames[tag]!;
    factors.add(
      drop < _noChange
          ? EnergyFactor(
              tag,
              'You tagged $name last night. It hasn\'t made much difference '
              'to your mornings so far.',
              0,
              personal: drop,
            )
          : EnergyFactor(
              tag,
              'You tagged $name last night. After those nights your Capacity '
              'has been about ${drop.round()} lower the next morning.',
              (drop * _pressurePerPoint).clamp(0, _maxPressure),
              personal: drop,
            ),
    );
  }

  final load = scores[localDayKey(day)]?['trainingLoad'];
  final days = load is Map ? load['days'] : null;
  final last = days is List ? days.lastOrNull : null;
  if (last case {
    'day': final String d,
    'value': final num v,
  } when d == yesterday && v >= _hardDay) {
    factors.add(
      const EnergyFactor(
        hardTrainingFactor,
        'Yesterday was one of your hard training days, so you may have a '
        'little less energy today, most of all this morning.',
        _hardTrainingPressure,
      ),
    );
  }
  return factors;
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}
