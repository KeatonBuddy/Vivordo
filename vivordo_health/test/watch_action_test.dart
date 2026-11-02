import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/workout_service.dart';
import 'package:vivordo_health/src/utils/watch_action.dart';

void main() {
  test('queued actions are this account only, oldest first, complete', () {
    final queued = pendingWatchActions('me', [
      {
        'id': 'pendingWatch.2',
        'kind': 'reset',
        'at': 2000,
        'seconds': 60,
        'hrStart': 82,
        'hrEnd': 71,
        'account': 'me',
      },
      {
        'id': 'pendingWatch.1',
        'kind': 'checkIn',
        'at': 1000,
        'score': 80,
        'account': 'me',
      },
      {
        'id': 'pendingWatch.3',
        'kind': 'taskDone',
        'at': 3000,
        'priorityId': 'p1',
        'day': '2026-10-31',
        'account': 'me',
      },
      {'id': 'pendingWatch.4', 'kind': 'taskDone', 'at': 4000, 'account': 'me'},
      {
        'id': 'pendingWatch.5',
        'kind': 'reset',
        'at': 5000,
        'seconds': 60,
        'account': 'other',
      },
      {'id': 'pendingWatch.6', 'kind': 'dance', 'at': 6000, 'account': 'me'},
    ]);
    expect(queued.map((a) => a.id), [
      'pendingWatch.1',
      'pendingWatch.2',
      'pendingWatch.3',
    ]);
    expect(queued[0].score, 80);
    expect(queued[1].hrStart, 82);
    expect(queued[1].hrEnd, 71);
    expect(queued[2].priorityId, 'p1');
    expect(queued[2].day, '2026-10-31');
  });

  test('a watch workout keeps its sets and drops bad ones', () {
    final queued = pendingWatchActions('me', [
      {
        'id': 'pendingWatch.7',
        'kind': 'workout',
        'at': 7000,
        'account': 'me',
        'name': 'Push day',
        'startAt': 1000,
        'endAt': 2900000,
        'seconds': 2890,
        'exercises': [
          {
            'name': 'Bench press',
            'category': 'Chest',
            'sets': [
              {'w': 135, 'r': 8, 'at': 1500},
              {'w': 135, 'r': 0},
              {'w': -5, 'r': 8},
            ],
          },
          {'name': ' '},
          {'name': 'Run', 'category': 'Cardio', 'sets': [], 'km': 4.8},
        ],
      },
      {
        'id': 'pendingWatch.8',
        'kind': 'workout',
        'at': 8000,
        'account': 'me',
        'name': 'Broken',
        'startAt': 5000,
        'endAt': 4000,
        'seconds': 10,
        'exercises': [],
      },
    ]);
    expect(queued.map((a) => a.id), ['pendingWatch.7']);
    final workout = queued.single.workout!;
    expect(workout.name, 'Push day');
    expect(workout.seconds, 2890);
    expect(workout.endedAt.millisecondsSinceEpoch, 2900000);
    expect(workout.exercises.map((e) => e.name), ['Bench press', 'Run']);
    expect(workout.exercises.first.sets.single.weightLbs, 135);
    expect(
      workout.exercises.first.sets.single.loggedAt?.millisecondsSinceEpoch,
      1500,
    );
    expect(workout.exercises.last.distanceKm, 4.8);
  });

  test('saved workouts go to the watch with last time\'s sets', () {
    final values = watchWorkoutValues(
      [
        WorkoutTemplate(
          id: 't1',
          name: 'Push day',
          createdAt: null,
          exercises: const [
            WorkoutTemplateExercise(
              name: 'Bench Press',
              category: 'Chest',
              sets: 4,
            ),
            WorkoutTemplateExercise(name: 'Dips', category: 'Chest'),
          ],
        ),
        const WorkoutTemplate(
          id: 't2',
          name: 'Empty',
          createdAt: null,
          exercises: [],
        ),
      ],
      {
        'bench press': const [WorkoutSetRecord(weightLbs: 135, reps: 8)],
      },
    );
    expect(values, [
      {
        'id': 't1',
        'name': 'Push day',
        'exercises': [
          {
            'name': 'Bench Press',
            'category': 'Chest',
            'sets': 4,
            'last': [
              {'w': 135.0, 'r': 8},
            ],
          },
          {'name': 'Dips', 'category': 'Chest', 'last': []},
        ],
      },
    ]);
  });
}
