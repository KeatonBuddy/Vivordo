import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/activity_goals_service.dart';
import 'package:vivordo_health/src/utils/replay_latest.dart';

void main() {
  test('late ring subscribers receive 500 and subsequent updates', () async {
    final source = StreamController<ActivityGoals>();
    final stream = replayLatest(source.stream);
    final first = <int>[];
    final second = <int>[];
    final a = stream.listen((g) => first.add(g.activeCalories));
    source.add(const ActivityGoals(activeCalories: 500));
    await Future<void>.delayed(Duration.zero);
    final b = stream.listen((g) => second.add(g.activeCalories));
    await Future<void>.delayed(Duration.zero);
    expect(second, [500]);
    source.add(const ActivityGoals(activeCalories: 600));
    await Future<void>.delayed(Duration.zero);
    expect(first, [500, 600]);
    expect(second, [500, 600]);
    await a.cancel();
    await b.cancel();
    expect((await stream.first).activeCalories, 600);
    await source.close();
  });

  test(
    'different account stream does not replay another user target',
    () async {
      final a = replayLatest(
        Stream.value(const ActivityGoals(activeCalories: 500)),
      );
      final b = replayLatest(
        Stream.value(const ActivityGoals(activeCalories: 900)),
      );
      expect((await a.first).activeCalories, 500);
      expect((await b.first).activeCalories, 900);
    },
  );
}
