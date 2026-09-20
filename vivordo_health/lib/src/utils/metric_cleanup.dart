/// Whether an Apple Health read that returned nothing for a day may clear the
/// value already saved for [metricKey] on that day.
///
/// Sleep is excluded even when the read covered other days. A night is handed
/// to the phone long after it ends, so a read can legitimately return
/// yesterday's sleep and not last night's while the watch is still catching
/// up. Treating that gap as "no sleep" wipes a night the app had recorded.
bool emptyReadMayClearSavedMetric(String metricKey) => metricKey != 'sleep';

/// Whether a completed read may clear the days inside its window that it did
/// not return data for.
///
/// [readCoveredAnyDay] is false when the read produced nothing anywhere in the
/// window. That result is ambiguous on iOS: HealthKit returns an empty set
/// both when the user genuinely has no data and when read access for the type
/// was never granted, and it deliberately does not reveal which. Clearing on
/// it deletes history the app already holds — for the whole window, which for
/// the Metrics tab is seven or thirty days at a time.
///
/// A read that covered at least one day is trusted: the type is readable, so a
/// day it skipped really is empty.
bool readMayClearMissingDays({
  required String metricKey,
  required bool readCoveredAnyDay,
}) =>
    emptyReadMayClearSavedMetric(metricKey) && readCoveredAnyDay;
