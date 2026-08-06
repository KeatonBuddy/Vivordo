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

class WorkoutTemplateExercise {
  const WorkoutTemplateExercise({required this.name, required this.category});

  final String name;
  final String category;

  Map<String, dynamic> toMap() => {'name': name, 'category': category};
}

class WorkoutTemplate {
  const WorkoutTemplate({
    required this.id,
    required this.name,
    required this.exercises,
    required this.createdAt,
  });

  final String id;
  final String name;
  final List<WorkoutTemplateExercise> exercises;
  final DateTime? createdAt;

  factory WorkoutTemplate.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final exercises = (data['exercises'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (exercise) => WorkoutTemplateExercise(
            name: exercise['name'] as String? ?? '',
            category: exercise['category'] as String? ?? 'Other',
          ),
        )
        .where((exercise) => exercise.name.trim().isNotEmpty)
        .toList(growable: false);
    return WorkoutTemplate(
      id: document.id,
      name: data['name'] as String? ?? 'Saved Workout',
      exercises: exercises,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
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

  static Stream<List<WorkoutTemplate>> watchTemplates() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(const []);
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('workout_templates')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(WorkoutTemplate.fromDocument)
              .toList(growable: false),
        );
  }

  static Future<String> saveTemplate({
    required String name,
    required List<WorkoutTemplateExercise> exercises,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in before saving a workout.');
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Workout name is required.');
    if (exercises.isEmpty) {
      throw ArgumentError('Add at least one exercise before saving.');
    }
    final document = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('workout_templates')
        .doc();
    await document.set({
      'name': cleanName,
      'exerciseCount': exercises.length,
      'exercises': exercises
          .map((exercise) => exercise.toMap())
          .toList(growable: false),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return document.id;
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

  static Stream<List<SavedWorkout>> watchBetween({
    required DateTime start,
    required DateTime end,
  }) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(const []);
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('workouts')
        .where(
          'completedAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(start),
          isLessThan: Timestamp.fromDate(end),
        )
        .orderBy('completedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(SavedWorkout.fromDocument)
              .toList(growable: false),
        );
  }

  static Future<List<SavedWorkout>> loadRecent({int limit = 12}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const [];
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('workouts')
        .orderBy('completedAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs.map(SavedWorkout.fromDocument).toList(growable: false);
  }

  static Future<Map<String, List<WorkoutSetRecord>>> loadLatestExerciseSets(
    Iterable<String> exerciseNames,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const {};
    final requested = {
      for (final name in exerciseNames)
        if (name.trim().isNotEmpty) name.trim().toLowerCase(),
    };
    if (requested.isEmpty) return const {};
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('workouts')
        .orderBy('completedAt', descending: true)
        .limit(100)
        .get();
    final latest = <String, List<WorkoutSetRecord>>{};
    for (final document in snapshot.docs) {
      final workout = SavedWorkout.fromDocument(document);
      for (final exercise in workout.exercises) {
        final key = exercise.name.trim().toLowerCase();
        if (requested.contains(key) &&
            !latest.containsKey(key) &&
            exercise.sets.isNotEmpty) {
          latest[key] = exercise.sets;
        }
      }
      if (latest.length == requested.length) break;
    }
    return latest;
  }

  static Future<void> delete(String workoutId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in before deleting a workout.');
    if (workoutId.trim().isEmpty) {
      throw ArgumentError('Workout ID is required.');
    }
    final db = FirebaseFirestore.instance;
    final workoutReference = db
        .collection('users')
        .doc(user.uid)
        .collection('workouts')
        .doc(workoutId);
    final circleActivityReference = db
        .collection('users')
        .doc(user.uid)
        .collection('circle_activity')
        .doc(workoutId);
    final batch = db.batch();
    batch.delete(workoutReference);
    batch.delete(circleActivityReference);
    await batch.commit();
  }

  static Future<String> save({
    required DateTime startedAt,
    required int durationSeconds,
    required List<WorkoutExerciseRecord> exercises,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in before saving a workout.');

    final completedAt = DateTime.now();
    final db = FirebaseFirestore.instance;
    final document = db
        .collection('users')
        .doc(user.uid)
        .collection('workouts')
        .doc();
    final setCount = exercises.fold<int>(
      0,
      (total, exercise) => total + exercise.sets.length,
    );
    final batch = db.batch();
    batch.set(document, {
      'startedAt': Timestamp.fromDate(startedAt),
      'completedAt': Timestamp.fromDate(completedAt),
      'durationSeconds': durationSeconds,
      'durationMinutes': durationSeconds / 60,
      'exerciseCount': exercises.length,
      'setCount': setCount,
      'exercises': exercises
          .map((exercise) => exercise.toMap())
          .toList(growable: false),
      'createdAt': FieldValue.serverTimestamp(),
    });
    final circleDocument = db
        .collection('users')
        .doc(user.uid)
        .collection('circle_activity')
        .doc(document.id);
    batch.set(circleDocument, {
      'name': 'Workout',
      'minutes': (durationSeconds / 60).ceil(),
      'day': Timestamp.fromDate(completedAt),
      'sets': setCount,
      'kind': 'workout',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return document.id;
  }
}
