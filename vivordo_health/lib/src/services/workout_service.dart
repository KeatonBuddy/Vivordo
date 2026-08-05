import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class WorkoutSetRecord {
  const WorkoutSetRecord({required this.weightLbs, required this.reps});

  final double weightLbs;
  final int reps;

  Map<String, dynamic> toMap() => {'weightLbs': weightLbs, 'reps': reps};
}

class WorkoutExerciseRecord {
  const WorkoutExerciseRecord({
    required this.name,
    required this.category,
    required this.sets,
    this.distanceKm,
  });

  final String name;
  final String category;
  final List<WorkoutSetRecord> sets;
  final double? distanceKm;

  Map<String, dynamic> toMap() => {
    'name': name,
    'category': category,
    'sets': sets.map((set) => set.toMap()).toList(growable: false),
    if (distanceKm != null) 'distanceKm': distanceKm,
  };
}

class SavedWorkout {
  const SavedWorkout({
    required this.id,
    required this.completedAt,
    required this.durationSeconds,
    required this.exercises,
    required this.exerciseCount,
    required this.setCount,
  });

  final String id;
  final DateTime completedAt;
  final int durationSeconds;
  final List<WorkoutExerciseRecord> exercises;
  final int exerciseCount;
  final int setCount;

  List<String> get exerciseNames =>
      exercises.map((exercise) => exercise.name).toList(growable: false);

  factory SavedWorkout.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final rawExercises = data['exercises'] as List? ?? const [];
    final exercises = <WorkoutExerciseRecord>[];
    var calculatedSets = 0;
    for (final rawExercise in rawExercises.whereType<Map>()) {
      final name = rawExercise['name'] as String?;
      final rawSets = rawExercise['sets'] as List? ?? const [];
      calculatedSets += rawSets.length;
      final sets = <WorkoutSetRecord>[];
      for (final rawSet in rawSets.whereType<Map>()) {
        final weight = (rawSet['weightLbs'] as num?)?.toDouble() ?? 0;
        final reps = (rawSet['reps'] as num?)?.toInt() ?? 0;
        sets.add(WorkoutSetRecord(weightLbs: weight, reps: reps));
      }
      if (name != null && name.trim().isNotEmpty) {
        exercises.add(
          WorkoutExerciseRecord(
            name: name.trim(),
            category: rawExercise['category'] as String? ?? 'Other',
            sets: sets,
            distanceKm: (rawExercise['distanceKm'] as num?)?.toDouble(),
          ),
        );
      }
    }
    return SavedWorkout(
      id: document.id,
      completedAt:
          (data['completedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      durationSeconds: (data['durationSeconds'] as num?)?.round() ?? 0,
      exercises: exercises,
      exerciseCount:
          (data['exerciseCount'] as num?)?.round() ?? rawExercises.length,
      setCount: (data['setCount'] as num?)?.round() ?? calculatedSets,
    );
  }
}

class WorkoutService {
  const WorkoutService._();

  static int calculateCurrentStreak(List<SavedWorkout> workouts) {
    if (workouts.isEmpty) return 0;
    final workoutDays = workouts.map((workout) {
      final local = workout.completedAt.toLocal();
      return DateTime(local.year, local.month, local.day);
    }).toSet();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var cursor = workoutDays.contains(today)
        ? today
        : today.subtract(const Duration(days: 1));
    if (!workoutDays.contains(cursor)) return 0;

    var streak = 0;
    while (workoutDays.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  static Stream<List<SavedWorkout>> watchRecent({int limit = 3}) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(const []);
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('workouts')
        .orderBy('completedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(SavedWorkout.fromDocument)
              .toList(growable: false),
        );
  }

  static Stream<List<SavedWorkout>> watchAll() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(const []);
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('workouts')
        .orderBy('completedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(SavedWorkout.fromDocument)
              .toList(growable: false),
        );
  }

  static Future<String> save({
    required DateTime startedAt,
    required int durationSeconds,
    required List<WorkoutExerciseRecord> exercises,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in before saving a workout.');

    final completedAt = DateTime.now();
    final document = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('workouts')
        .add({
          'startedAt': Timestamp.fromDate(startedAt),
          'completedAt': Timestamp.fromDate(completedAt),
          'durationSeconds': durationSeconds,
          'durationMinutes': durationSeconds / 60,
          'exerciseCount': exercises.length,
          'setCount': exercises.fold<int>(
            0,
            (total, exercise) => total + exercise.sets.length,
          ),
          'exercises': exercises
              .map((exercise) => exercise.toMap())
              .toList(growable: false),
          'createdAt': FieldValue.serverTimestamp(),
        });
    return document.id;
  }
}
