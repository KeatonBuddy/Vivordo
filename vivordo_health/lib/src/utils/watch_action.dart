/// One thing done on the Apple Watch, as queued by the phone
/// (`pendingWatchActions` on the home-widgets channel): a finished reset, an
/// energy check-in or a priority ticked off.
typedef PendingWatchAction = ({
  String id,
  String kind,
  DateTime at,
  int? seconds,
  int? hrStart,
  int? hrEnd,
  double? score,
  String? priorityId,
  String? day,
});

/// This account's queued actions, oldest first. Anything malformed, of an
/// unknown kind or from another account is left in the queue untouched.
List<PendingWatchAction> pendingWatchActions(String uid, List<Object?> raw) {
  final actions = <PendingWatchAction>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final id = item['id'];
    final kind = item['kind'];
    final at = item['at'];
    if (item['account'] != uid ||
        id is! String ||
        kind is! String ||
        at is! num) {
      continue;
    }
    final seconds = item['seconds'];
    final score = item['score'];
    final priorityId = item['priorityId'];
    final day = item['day'];
    final complete = switch (kind) {
      'reset' => seconds is num,
      'checkIn' => score is num,
      'taskDone' => priorityId is String && day is String,
      _ => false,
    };
    if (!complete) continue;
    final hrStart = item['hrStart'];
    final hrEnd = item['hrEnd'];
    actions.add((
      id: id,
      kind: kind,
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
      seconds: seconds is num ? seconds.toInt() : null,
      hrStart: hrStart is num ? hrStart.toInt() : null,
      hrEnd: hrEnd is num ? hrEnd.toInt() : null,
      score: score is num ? score.toDouble().clamp(0, 100).toDouble() : null,
      priorityId: priorityId is String ? priorityId : null,
      day: day is String ? day : null,
    ));
  }
  return actions..sort((a, b) => a.at.compareTo(b.at));
}
