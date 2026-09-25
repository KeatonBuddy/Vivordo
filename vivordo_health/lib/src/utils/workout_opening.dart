/// One stable message slot per workout handoff; late results cannot revive it.
class WorkoutOpening {
  final Object id = Object();
  String text = 'Looking at your workout…';
  bool busy = true;
  bool _active = true;
  bool get active => _active;

  bool complete(String advice) {
    if (!_active || !busy) return false;
    text = advice;
    busy = false;
    return true;
  }

  void invalidate() {
    if (busy) text = 'Workout analysis cancelled.';
    _active = false;
    busy = false;
  }
}
