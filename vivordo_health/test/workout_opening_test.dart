import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/workout_opening.dart';

void main() {
  test('fast cached response updates the already-inserted stable slot', () {
    final slot = WorkoutOpening();
    final messages = [slot];
    final id = slot.id;
    expect(slot.complete('Cached advice'), isTrue);
    expect(messages.single.text, 'Cached advice');
    expect(messages.single.id, same(id));
    expect(messages.single.busy, isFalse);
  });
  test('slow response and failure text update the same slot', () async {
    final slot = WorkoutOpening();
    final result = Completer<String>();
    final pending = result.future.then(slot.complete);
    expect(slot.text, 'Looking at your workout…');
    result.complete('Could not analyze. Please try again.');
    await pending;
    expect(slot.text, 'Could not analyze. Please try again.');
    expect(slot.busy, isFalse);
  });
  test('switch, restart, or end invalidates late replies', () async {
    for (final action in ['switch', 'restart', 'end']) {
      final previous = WorkoutOpening();
      final result = Completer<String>();
      final pending = result.future.then(previous.complete);
      previous.invalidate();
      expect(previous.text, 'Workout analysis cancelled.');
      final next = WorkoutOpening();
      result.complete('Stale $action advice');
      expect(await pending, isFalse);
      expect(previous.text, 'Workout analysis cancelled.');
      expect(next.busy, isTrue);
      expect(next.text, 'Looking at your workout…');
      expect(previous.id, isNot(same(next.id)));
    }
  });
  test('switching preserves completed advice', () {
    final opening = WorkoutOpening();
    opening.complete('Completed advice');
    opening.invalidate();
    expect(opening.text, 'Completed advice');
  });
}
