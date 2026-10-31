/// One reset finished on the Apple Watch, as queued by the phone
/// (`pendingWatchResets` on the home-widgets channel).
typedef PendingWatchReset = ({
  String id,
  DateTime at,
  int seconds,
  int? hrStart,
  int? hrEnd,
});

/// This account's queued resets, oldest first. Anything malformed or from
/// another account is left in the queue untouched.
List<PendingWatchReset> pendingWatchResets(String uid, List<Object?> raw) {
  final resets = <PendingWatchReset>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final id = item['id'];
    final at = item['at'];
    final seconds = item['seconds'];
    final hrStart = item['hrStart'];
    final hrEnd = item['hrEnd'];
    if (item['account'] != uid ||
        id is! String ||
        at is! num ||
        seconds is! num) {
      continue;
    }
    resets.add((
      id: id,
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
      seconds: seconds.toInt(),
      hrStart: hrStart is num ? hrStart.toInt() : null,
      hrEnd: hrEnd is num ? hrEnd.toInt() : null,
    ));
  }
  return resets..sort((a, b) => a.at.compareTo(b.at));
}
