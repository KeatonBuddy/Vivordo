enum WhoopAutomaticSyncSlot { overnight, morning, midday }

WhoopAutomaticSyncSlot whoopAutomaticSyncSlot(DateTime localTime) {
  if (localTime.hour < 4) return WhoopAutomaticSyncSlot.overnight;
  if (localTime.hour < 12) return WhoopAutomaticSyncSlot.morning;
  return WhoopAutomaticSyncSlot.midday;
}

/// Identifies the one automatic WHOOP check allowed for this user and slot.
///
/// Overnight automatic checks are intentionally suppressed so opening Vivordo
/// shortly after midnight cannot consume the morning sleep refresh.
String? whoopAutomaticSyncSlotKey(String uid, DateTime localTime) {
  final slot = whoopAutomaticSyncSlot(localTime);
  if (slot == WhoopAutomaticSyncSlot.overnight) return null;
  final date =
      '${localTime.year.toString().padLeft(4, '0')}-'
      '${localTime.month.toString().padLeft(2, '0')}-'
      '${localTime.day.toString().padLeft(2, '0')}';
  return '$uid:$date:${slot.name}';
}
