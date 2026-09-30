import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/exercise_minutes.dart';

/// One-minute Apple Watch style samples starting at [hour]:[minute].
List<ExerciseSample> _minutes(String source, int hour, int minute, int count) =>
    [
      for (var i = 0; i < count; i++)
        (
          source: source,
          from: DateTime(2026, 9, 29, hour, minute + i),
          to: DateTime(2026, 9, 29, hour, minute + i + 1),
          minutes: 1.0,
        ),
    ];

void main() {
  test('adds one source\'s samples', () {
    expect(healthExerciseMinutes(_minutes('watch', 7, 0, 30), const []), 30);
  });

  test('does not add two devices reporting the same minutes', () {
    final samples = [
      ..._minutes('watch', 7, 0, 30),
      ..._minutes('phone', 7, 0, 20),
    ];
    expect(healthExerciseMinutes(samples, const []), 30);
  });

  test('counts a repeated sample once', () {
    final samples = [
      ..._minutes('watch', 7, 0, 10),
      ..._minutes('watch', 7, 0, 10),
    ];
    expect(healthExerciseMinutes(samples, const []), 10);
  });

  test('leaves minutes inside an in-app workout to that workout', () {
    // 60 Watch minutes 18:00-19:00; the app workout covered 18:15-18:45.
    final workout = (
      start: DateTime(2026, 9, 29, 18, 15),
      end: DateTime(2026, 9, 29, 18, 45),
    );
    expect(healthExerciseMinutes(_minutes('watch', 18, 0, 60), [workout]), 30);
  });

  test('splits a sample that straddles the workout start', () {
    final sample = (
      source: 'watch',
      from: DateTime(2026, 9, 29, 18, 0),
      to: DateTime(2026, 9, 29, 18, 10),
      minutes: 10.0,
    );
    final workout = (
      start: DateTime(2026, 9, 29, 18, 5),
      end: DateTime(2026, 9, 29, 19, 0),
    );
    expect(healthExerciseMinutes([sample], [workout]), 5);
  });

  test('returns zero with no samples', () {
    expect(healthExerciseMinutes(const [], const []), 0);
  });
}
