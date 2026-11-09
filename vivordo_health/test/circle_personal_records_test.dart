import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/circle_profile_service.dart';

void main() {
  const theo = CircleProfile(
    uid: 'theo',
    username: 'Theo',
    friendCode: 'T',
    bio: '',
  );

  test('a workout post carries its PRs and exercise summaries', () {
    final activity = CircleActivity.fromData('w1', theo, {
      'kind': 'workout',
      'name': 'Push',
      'day': Timestamp.fromDate(DateTime(2026, 11, 9)),
      'personalRecords': [
        {
          'name': 'Bench Press',
          'weightLbs': 185,
          'reps': 5,
          'previousWeightLbs': 175,
          'previousReps': 5,
        },
      ],
      'exercises': [
        {'name': 'Bench Press', 'sets': 4, 'bestWeightLbs': 185, 'bestReps': 5},
        {'name': 'Pull-ups', 'sets': 3, 'bestReps': 12},
      ],
    });

    expect(activity.personalRecords.single.name, 'Bench Press');
    expect(activity.personalRecords.single.weightLbs, 185);
    expect(activity.personalRecords.single.previousWeightLbs, 175);
    expect(activity.exercises.map((exercise) => exercise.name), [
      'Bench Press',
      'Pull-ups',
    ]);
    expect(activity.exercises.last.bestWeightLbs, isNull);
  });

  test('posts from before PRs were shared have none', () {
    final activity = CircleActivity.fromData('w0', theo, {'kind': 'workout'});
    expect(activity.personalRecords, isEmpty);
    expect(activity.exercises, isEmpty);
  });

  test('shared records are flattened newest first', () {
    Map<String, dynamic> post(DateTime day, List<String> lifts) => {
      'day': Timestamp.fromDate(day),
      'personalRecords': [
        for (final lift in lifts) {'name': lift, 'weightLbs': 100, 'reps': 5},
      ],
    };
    final records = CircleProfileService.sharedRecordsFrom([
      post(DateTime(2026, 10, 1), ['Squat']),
      post(DateTime(2026, 11, 2), ['Bench Press', 'Deadlift']),
      {'personalRecords': []},
    ]);
    expect(records.map((shared) => shared.record.name), [
      'Bench Press',
      'Deadlift',
      'Squat',
    ]);
  });
}
