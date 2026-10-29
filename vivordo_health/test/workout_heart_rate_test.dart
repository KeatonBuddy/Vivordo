import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/workout_service.dart';
import 'package:vivordo_health/src/utils/heart_rate_history.dart';
import 'package:vivordo_health/src/utils/workout_heart_rate.dart';

void main() {
  final start = DateTime(2026, 10, 29, 18);
  final end = start.add(const Duration(minutes: 10));
  List<HeartRateHistoryReading> perMinute(List<double> bpms, {int from = 0}) =>
      [
        for (final (i, bpm) in bpms.indexed)
          HeartRateHistoryReading(
            bpm: bpm,
            timestamp: start.add(Duration(minutes: from + i)),
          ),
      ];

  test('max heart rate matches the server: Tanaka, raised to the peak', () {
    expect(workoutMaxHeartRate(30, 150), 187); // 208 − 21
    expect(workoutMaxHeartRate(30, 195), 195);
    expect(workoutMaxHeartRate(null, 120), 190);
    expect(workoutMaxHeartRate(20, 260), 220);
  });

  test('zones are shares of max heart rate', () {
    expect(workoutZoneFor(90, 200), isNull); // 45%
    expect(workoutZoneFor(100, 200), WorkoutZone.z1);
    expect(workoutZoneFor(139, 200), WorkoutZone.z2);
    expect(workoutZoneFor(150, 200), WorkoutZone.z3);
    expect(workoutZoneFor(160, 200), WorkoutZone.z4);
    expect(workoutZoneFor(185, 200), WorkoutZone.z5);
  });

  test('time in zone from readings inside the workout only', () {
    final hr = workoutHeartRate(
      [
        ...perMinute([170], from: -5), // before the workout
        // 190 max at age 30 → 187: z1 ≥ 93.5, z2 ≥ 112, z3 ≥ 131, z4 ≥ 150.
        ...perMinute([95, 120, 120, 140, 140, 140, 155, 155, 155, 155]),
        ...perMinute([170], from: 15), // after
      ],
      start: start,
      end: end,
      age: 30,
    )!;
    expect(hr.readings, hasLength(10));
    expect(hr.peak, 155);
    expect(hr.maxHr, 187);
    expect(hr.average, 138);
    expect(hr.zoneTime[WorkoutZone.z1], const Duration(minutes: 1));
    expect(hr.zoneTime[WorkoutZone.z2], const Duration(minutes: 2));
    expect(hr.zoneTime[WorkoutZone.z3], const Duration(minutes: 3));
    expect(hr.zoneTime[WorkoutZone.z4], const Duration(minutes: 4));
    expect(hr.zoneTime[WorkoutZone.z5], Duration.zero);
    expect(hr.totalInZones, const Duration(minutes: 10));
  });

  test('a gap counts for at most 2 minutes', () {
    final hr = workoutHeartRate(
      [
        ...perMinute([140, 140, 140]),
        ...perMinute([140, 140, 140], from: 7),
      ],
      start: start,
      end: end,
      age: 30,
    )!;
    // 1 + 1 + 2 (capped gap) + 1 + 1 + 1 (to the end).
    expect(hr.zoneTime[WorkoutZone.z3], const Duration(minutes: 7));
  });

  test('too few readings to draw is null', () {
    expect(
      workoutHeartRate(
        perMinute([140, 140, 140]),
        start: start,
        end: end,
        age: 30,
      ),
      isNull,
    );
    // An hour with 6 readings: a watch sampling every few minutes, not a
    // recorded workout.
    expect(
      workoutHeartRate(
        [
          for (var i = 0; i < 6; i++)
            HeartRateHistoryReading(
              bpm: 140,
              timestamp: start.add(Duration(minutes: i * 10)),
            ),
        ],
        start: start,
        end: start.add(const Duration(hours: 1)),
      ),
      isNull,
    );
  });

  group('exercise spans', () {
    WorkoutExerciseRecord lift(List<int?> minutes) => WorkoutExerciseRecord(
      name: 'Lift',
      category: 'Chest',
      sets: [
        for (final minute in minutes)
          WorkoutSetRecord(
            weightLbs: 100,
            reps: 8,
            loggedAt: minute == null
                ? null
                : start.add(Duration(minutes: minute)),
          ),
      ],
    );
    const cardio = WorkoutExerciseRecord(
      name: 'Run',
      category: 'Cardio',
      sets: [],
    );

    test('each exercise runs from the one before it to its last set', () {
      final spans = workoutExerciseSpans(
        [
          lift([2, 4]),
          cardio,
          lift([6, 9]),
        ],
        start: start,
        end: end,
      )!;
      expect(spans.map((s) => s.index), [0, 2]);
      expect(spans[0].start, start);
      expect(spans[0].end, start.add(const Duration(minutes: 4)));
      expect(spans[1].start, start.add(const Duration(minutes: 4)));
      expect(spans[1].end, start.add(const Duration(minutes: 9)));
    });

    test('ordered by when each exercise started, not list order', () {
      final spans = workoutExerciseSpans(
        [
          lift([6, 9]),
          lift([2, 4]),
        ],
        start: start,
        end: end,
      )!;
      expect(spans.map((s) => s.index), [1, 0]);
    });

    test('a set time stays JSON-safe for Vivordo AI and the draft', () {
      final set = WorkoutSetRecord(weightLbs: 100, reps: 8, loggedAt: end);
      expect(
        DateTime.parse(
          jsonDecode(jsonEncode(set.toMap()))['loggedAt'],
        ).toLocal(),
        end,
      );
    });

    test('no spans when times are missing, interleaved or all at the end', () {
      List<WorkoutExerciseSpan>? spans(List<WorkoutExerciseRecord> list) =>
          workoutExerciseSpans(list, start: start, end: end);
      expect(
        spans([
          lift([2, null]),
        ]),
        isNull,
      );
      expect(spans([cardio]), isNull);
      expect(
        spans([
          lift([2, 6]),
          lift([4, 8]),
        ]),
        isNull,
      );
      expect(
        spans([
          lift([9, 9]),
          lift([9, 9]),
        ]),
        isNull,
      );
    });
  });
}
