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
