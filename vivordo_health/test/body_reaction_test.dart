import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/body_reaction.dart';
import 'package:vivordo_health/src/utils/heart_rate_history.dart';

void main() {
  final day = DateTime(2026, 10, 6);
  final start = DateTime(2026, 10, 6, 10, 30);
  final end = DateTime(2026, 10, 6, 11);

  HeartRateHistoryReading at(DateTime t, double bpm) =>
      HeartRateHistoryReading(bpm: bpm, timestamp: t);

  /// Five earlier days, readings every 10 min from 9:30 to 12:00 around
  /// 66 bpm (62–70), plus one walk spike a day that the usual should ignore.
  final history = [
    for (var d = 1; d <= 5; d++)
      for (var m = 0; m <= 150; m += 10)
        at(
          day
              .subtract(Duration(days: d))
              .add(Duration(hours: 9, minutes: 30 + m)),
          m == 60 ? 115 : 62.0 + (m ~/ 10) % 9,
        ),
  ];

  List<HeartRateHistoryReading> during(double bpm, {int count = 8}) => [
    for (var i = 0; i < count; i++)
      at(start.add(Duration(minutes: i * 3)), bpm + (i.isEven ? 1 : -1)),
  ];

  test('a raised heart rate in a meeting reads as up or high', () {
    expect(
      bodyReactionFor(
        start: start,
        end: end,
        // About 13 bpm over a usual of ~65.
        today: during(78),
        history: history,
      )!.level,
      BodyReactionLevel.up,
    );
    final high = bodyReactionFor(
      start: start,
      end: end,
      today: during(95),
      history: history,
    )!;
    expect(high.level, BodyReactionLevel.high);
    expect(high.readings, 8);
    expect(high.usualMedian, closeTo(66, 2));
  });

  test('near your usual is steady; well below it is calm', () {
    expect(
      bodyReactionFor(
        start: start,
        end: end,
        today: during(67),
        history: history,
      )!.level,
      BodyReactionLevel.steady,
    );
    expect(
      bodyReactionFor(
        start: start,
        end: end,
        today: during(56),
        history: history,
      )!.level,
      BodyReactionLevel.calm,
    );
  });

  test('too few readings, or too little history, says nothing', () {
    expect(
      bodyReactionFor(
        start: start,
        end: end,
        today: during(95, count: 4),
        history: history,
      ),
      isNull,
    );
    expect(
      bodyReactionFor(
        start: start,
        end: end,
        today: during(95),
        history: history.take(30).toList(),
      ),
      isNull,
    );
    // Readings from today don't count towards the usual.
    expect(
      bodyReactionFor(
        start: start,
        end: end,
        today: during(95),
        history: [for (final r in during(70, count: 40)) r],
      ),
      isNull,
    );
  });

  test('exercise titles are spotted; keys are stable and opaque', () {
    expect(looksLikeExercise('Lunch walk'), isTrue);
    expect(looksLikeExercise('Gym session'), isTrue);
    expect(looksLikeExercise('Design review'), isFalse);
    expect(looksLikeExercise('Running notes sync'), isTrue);
    expect(reactionKey('google:abc'), reactionKey('google:abc'));
    expect(reactionKey('google:abc'), isNot(reactionKey('google:abd')));
    expect(reactionKey('google:abc'), hasLength(8));
  });
}
