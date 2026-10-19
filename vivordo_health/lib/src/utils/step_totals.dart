/// A day's steps from raw HealthKit samples, or null when there are none.
///
/// Devices record the same walking independently: the iPhone and a watch or
/// WHOOP each write their own samples, and the plugin's duplicate removal
/// only drops identical samples. Summing every sample counted shared walking
/// twice (Sept 2026: 18,239 steps restored for a 4.6 km day). One device's
/// own samples never overlap, so the largest single-device total cannot
/// inflate. It undercounts only when devices covered different parts of the
/// day, which is safer than doubling.
double? largestSourceStepTotal(
  Iterable<({String source, double steps})> samples,
) {
  final bySource = <String, double>{};
  for (final sample in samples) {
    bySource[sample.source] = (bySource[sample.source] ?? 0) + sample.steps;
  }
  if (bySource.isEmpty) return null;
  return bySource.values.reduce((a, b) => a > b ? a : b);
}

/// A day's steps from Apple Health's hourly totals (merged across devices
/// by Health's source order), or null when there are none.
///
/// The plugin's day total only counts samples that start that day, so a
/// long sample begun before midnight (WHOOP writes hour-long ones) was left
/// out of the day entirely: 4,604 against Health's 6,152 on 2026-10-19. The
/// hourly totals split such a sample across the hours it covers, as the
/// Health app does.
double? dayStepTotal(List<int>? hours) {
  final total = hours?.fold<int>(0, (a, b) => a + b) ?? 0;
  return total > 0 ? total.toDouble() : null;
}
