const _preferredWearableSources = {'whoop', 'whoop_ble', 'fitbit'};

/// Removes raw Apple Health samples that would compete with the canonical
/// wearable selected for the same metric and day.
///
/// Steps deliberately remain Apple Health-only. Sleep samples may include an
/// internal `_metric_date` because their timestamps can begin the evening
/// before the wake-day document that owns the canonical sleep metric.
List<Map<String, dynamic>> filterStressAppleSamplesBySource(
  Iterable<Map<String, dynamic>> samples,
  Map<String, Map<String, dynamic>> metricsByDay,
) {
  return samples
      .where((sample) {
        if (sample['source'] != 'apple_health') return true;
        final metric = sample['metric_type'] as String?;
        if (metric == null || metric == 'steps') return true;

        final timestamp = sample['timestamp'] as String?;
        final metricDate = sample['_metric_date'] as String?;
        final day =
            metricDate ??
            (timestamp != null && timestamp.length >= 10
                ? timestamp.substring(0, 10)
                : null);
        if (day == null) return true;

        final canonical = metricsByDay[day]?[metric] as Map?;
        return !_preferredWearableSources.contains(canonical?['source']);
      })
      .toList(growable: false);
}
