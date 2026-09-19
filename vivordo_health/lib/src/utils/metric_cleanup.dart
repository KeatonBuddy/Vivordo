/// Whether an Apple Health read that returned nothing for a day may clear the
/// value already saved for [metricKey] on that day.
///
/// Sleep is excluded. A sleep read comes back empty both when the user truly
/// did not sleep and when the watch has not handed last night's session to the
/// phone yet, and those two cases are indistinguishable here. Clearing on the
/// second one wipes a night the app had already recorded, so saved sleep is
/// kept until a read actually produces a session for that day.
///
/// The trade-off is deliberate: a night genuinely deleted from Apple Health is
/// no longer removed from Vivordo by a routine sync.
bool emptyReadMayClearSavedMetric(String metricKey) => metricKey != 'sleep';
