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
    this.activityName,
    this.activityCategory,
  });

  final String id;
  final DateTime completedAt;
  final int durationSeconds;
  final List<WorkoutExerciseRecord> exercises;
  final int exerciseCount;
  final int setCount;
  final String? activityName;
  final String? activityCategory;

  WorkoutExerciseRecord? get primaryCardioOrSportExercise {
    for (final exercise in exercises) {
      if (exercise.category == 'Cardio' || exercise.category == 'Sports') {
        return exercise;
      }
    }
    return null;
  }

  String get displayName {
    final savedName = activityName?.trim();
    if (savedName?.isNotEmpty == true && savedName != 'Workout') {
      return savedName!;
    }
    return primaryCardioOrSportExercise?.name ?? 'Workout';
  }

  String? get displayCategory =>
      activityCategory ?? primaryCardioOrSportExercise?.category;

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
      activityName: data['activityName'] as String?,
      activityCategory: data['activityCategory'] as String?,
    );
  }
}

class WorkoutService {
  const WorkoutService._();

  static Future<int>? _legacyExerciseMinutesMigration;

  /// Adds legacy workout durations to the daily exercise-time metric.
  ///
  /// Workouts saved before exercise-goal integration do not contain
  /// `exerciseGoalDay`. Each transaction re-checks that field and writes it
  /// alongside the daily total, making this safe to retry without counting a
  /// workout twice.
  static Future<int> migrateLegacyExerciseMinutesOnce() {
    return _legacyExerciseMinutesMigration ??= _migrateLegacyExerciseMinutes();
  }

  static Future<int> _migrateLegacyExerciseMinutes() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;

    final db = FirebaseFirestore.instance;
    final workouts = await db
        .collection('users')
        .doc(user.uid)
        .collection('workouts')
        .get();
    var migrated = 0;

    for (final workout in workouts.docs) {
      final data = workout.data();
      if (data['exerciseGoalDay'] != null) continue;
      final durationSeconds = (data['durationSeconds'] as num?)?.round() ?? 0;
      final completedAt =
          (data['completedAt'] as Timestamp?)?.toDate() ??
          (data['startedAt'] as Timestamp?)?.toDate();
      if (durationSeconds <= 0 || completedAt == null) continue;

      final migratedWorkout = await db.runTransaction<bool>((
        transaction,
      ) async {
        final freshWorkout = await transaction.get(workout.reference);
        final freshData = freshWorkout.data();
        if (freshData == null || freshData['exerciseGoalDay'] != null) {
          return false;
        }

        final freshDurationSeconds =
            (freshData['durationSeconds'] as num?)?.round() ?? 0;
        final freshCompletedAt =
            (freshData['completedAt'] as Timestamp?)?.toDate() ??
            (freshData['startedAt'] as Timestamp?)?.toDate();
        if (freshDurationSeconds <= 0 || freshCompletedAt == null) return false;

        final goalMinutes = (freshDurationSeconds / 60).ceil();
        final goalDay = _dayKey(freshCompletedAt);
        final dailyReference = db
            .collection('users')
            .doc(user.uid)
            .collection('metrics_daily')
            .doc(goalDay);
        final dailySnapshot = await transaction.get(dailyReference);
        final exerciseTime =
            dailySnapshot.data()?['exercise_time'] as Map<String, dynamic>? ??
            const <String, dynamic>{};
        final currentWorkoutMinutes =
            (exerciseTime['workoutMinutes'] as num?)?.toDouble() ?? 0;
        final healthMinutes =
            (exerciseTime['healthSum'] as num?)?.toDouble() ??
            (((exerciseTime['sum'] as num?)?.toDouble() ?? 0) -
                    currentWorkoutMinutes)
                .clamp(0, double.infinity);
        final updatedWorkoutMinutes = currentWorkoutMinutes + goalMinutes;

        transaction.update(workout.reference, {
          'exerciseGoalDay': goalDay,
          'exerciseGoalMinutes': goalMinutes,
          'exerciseMinutesBackfilledAt': FieldValue.serverTimestamp(),
        });
        transaction.set(dailyReference, {
          'exercise_time': {
            ...exerciseTime,
            'healthSum': healthMinutes,
            'workoutMinutes': updatedWorkoutMinutes,
            'sum': healthMinutes + updatedWorkoutMinutes,
            'unit': 'min',
            'dimension': 'activity',
          },
          'date': goalDay,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return true;
      });
      if (migratedWorkout) migrated++;
    }

    return migrated;
  }

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

  static Future<void> deleteTemplate(String templateId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Sign in before deleting a workout.');
    }
    final cleanId = templateId.trim();
    if (cleanId.isEmpty) {
      throw ArgumentError('Workout template ID is required.');
    }
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('workout_templates')
        .doc(cleanId)
        .delete();
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
    await db.runTransaction((transaction) async {
      final workoutSnapshot = await transaction.get(workoutReference);
      final workoutData = workoutSnapshot.data();
      final goalDay = workoutData?['exerciseGoalDay'] as String?;
      final goalMinutes =
          (workoutData?['exerciseGoalMinutes'] as num?)?.toInt() ?? 0;

      if (goalDay != null && goalMinutes > 0) {
        final dailyReference = db
            .collection('users')
            .doc(user.uid)
            .collection('metrics_daily')
            .doc(goalDay);
        final dailySnapshot = await transaction.get(dailyReference);
        final exerciseTime =
            dailySnapshot.data()?['exercise_time'] as Map<String, dynamic>? ??
            const <String, dynamic>{};
        final currentWorkoutMinutes =
            (exerciseTime['workoutMinutes'] as num?)?.toDouble() ?? 0;
        final healthMinutes =
            (exerciseTime['healthSum'] as num?)?.toDouble() ??
            (((exerciseTime['sum'] as num?)?.toDouble() ?? 0) -
                    currentWorkoutMinutes)
                .clamp(0, double.infinity);
        final updatedWorkoutMinutes = (currentWorkoutMinutes - goalMinutes)
            .clamp(0, double.infinity);
        transaction.set(dailyReference, {
          'exercise_time': {
            ...exerciseTime,
            'healthSum': healthMinutes,
            'workoutMinutes': updatedWorkoutMinutes,
            'sum': healthMinutes + updatedWorkoutMinutes,
            'unit': 'min',
            'dimension': 'activity',
          },
          'date': goalDay,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      transaction.delete(workoutReference);
      transaction.delete(circleActivityReference);
    });
  }

  static Future<String> save({
    required DateTime startedAt,
    required int durationSeconds,
    required List<WorkoutExerciseRecord> exercises,
    bool shareToCircle = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in before saving a workout.');

    final completedAt = DateTime.now();
    final goalMinutes = durationSeconds <= 0
        ? 0
        : (durationSeconds / 60).ceil();
    final goalDay = _dayKey(completedAt);
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
    WorkoutExerciseRecord? selectedActivity;
    for (final exercise in exercises) {
      if (exercise.category == 'Cardio' || exercise.category == 'Sports') {
        selectedActivity = exercise;
        break;
      }
    }
    final activityName = selectedActivity?.name ?? 'Workout';
    final activityCategory = selectedActivity?.category;
    final activityFields = <String, dynamic>{'activityName': activityName};
    if (activityCategory != null) {
      activityFields['activityCategory'] = activityCategory;
    }
    final circleActivityFields = <String, dynamic>{
      'name': activityName,
      ...activityFields,
    };
    if (selectedActivity?.distanceKm != null) {
      circleActivityFields['km'] = selectedActivity!.distanceKm;
    }
    final circleDocument = db
        .collection('users')
        .doc(user.uid)
        .collection('circle_activity')
        .doc(document.id);
    final dailyReference = db
        .collection('users')
        .doc(user.uid)
        .collection('metrics_daily')
        .doc(goalDay);
    await db.runTransaction((transaction) async {
      final dailySnapshot = await transaction.get(dailyReference);
      final exerciseTime =
          dailySnapshot.data()?['exercise_time'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      final currentWorkoutMinutes =
          (exerciseTime['workoutMinutes'] as num?)?.toDouble() ?? 0;
      final healthMinutes =
          (exerciseTime['healthSum'] as num?)?.toDouble() ??
          (((exerciseTime['sum'] as num?)?.toDouble() ?? 0) -
                  currentWorkoutMinutes)
              .clamp(0, double.infinity);
      final updatedWorkoutMinutes = currentWorkoutMinutes + goalMinutes;

      transaction.set(document, {
        'startedAt': Timestamp.fromDate(startedAt),
        'completedAt': Timestamp.fromDate(completedAt),
        'durationSeconds': durationSeconds,
        'durationMinutes': durationSeconds / 60,
        'exerciseGoalDay': goalDay,
        'exerciseGoalMinutes': goalMinutes,
        'shareToCircle': shareToCircle,
        ...activityFields,
        'exerciseCount': exercises.length,
        'setCount': setCount,
        'exercises': exercises
            .map((exercise) => exercise.toMap())
            .toList(growable: false),
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (shareToCircle) {
        transaction.set(circleDocument, {
          ...circleActivityFields,
          'minutes': goalMinutes,
          'day': Timestamp.fromDate(completedAt),
          'sets': setCount,
          'kind': 'workout',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      transaction.set(dailyReference, {
        'exercise_time': {
          ...exerciseTime,
          'healthSum': healthMinutes,
          'workoutMinutes': updatedWorkoutMinutes,
          'sum': healthMinutes + updatedWorkoutMinutes,
          'unit': 'min',
          'dimension': 'activity',
        },
        'date': goalDay,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
    return document.id;
  }

  static String _dayKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
