import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vivordo_health/src/utils/personal_best.dart';

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
    this.personalBest = false,
    this.personalBestEstimatedOneRepMax,
    this.previousBestEstimatedOneRepMax,
    this.personalBestWeightLbs,
    this.personalBestReps,
    this.currentAttemptEstimatedOneRepMax,
    this.previousAttemptEstimatedOneRepMax,
    this.currentAttemptWeightLbs,
    this.previousAttemptWeightLbs,
    this.currentAttemptReps,
    this.previousAttemptReps,
    this.attemptChangePercent,
    this.attemptTrend,
  });

  final String name;
  final String category;
  final List<WorkoutSetRecord> sets;
  final double? distanceKm;
  final bool personalBest;
  final double? personalBestEstimatedOneRepMax;
  final double? previousBestEstimatedOneRepMax;
  final double? personalBestWeightLbs;
  final int? personalBestReps;
  final double? currentAttemptEstimatedOneRepMax;
  final double? previousAttemptEstimatedOneRepMax;
  final double? currentAttemptWeightLbs;
  final double? previousAttemptWeightLbs;
  final int? currentAttemptReps;
  final int? previousAttemptReps;
  final double? attemptChangePercent;
  final ExerciseAttemptTrend? attemptTrend;

  Map<String, dynamic> toMap() => {
    'name': name,
    'category': category,
    'sets': sets.map((set) => set.toMap()).toList(growable: false),
    if (distanceKm != null) 'distanceKm': distanceKm,
    'personalBest': personalBest,
    if (personalBestEstimatedOneRepMax != null)
      'personalBestEstimatedOneRepMax': personalBestEstimatedOneRepMax,
    if (previousBestEstimatedOneRepMax != null)
      'previousBestEstimatedOneRepMax': previousBestEstimatedOneRepMax,
    if (personalBestWeightLbs != null)
      'personalBestWeightLbs': personalBestWeightLbs,
    if (personalBestReps != null) 'personalBestReps': personalBestReps,
    if (currentAttemptEstimatedOneRepMax != null)
      'currentAttemptEstimatedOneRepMax': currentAttemptEstimatedOneRepMax,
    if (previousAttemptEstimatedOneRepMax != null)
      'previousAttemptEstimatedOneRepMax': previousAttemptEstimatedOneRepMax,
    if (currentAttemptWeightLbs != null)
      'currentAttemptWeightLbs': currentAttemptWeightLbs,
    if (previousAttemptWeightLbs != null)
      'previousAttemptWeightLbs': previousAttemptWeightLbs,
    if (currentAttemptReps != null) 'currentAttemptReps': currentAttemptReps,
    if (previousAttemptReps != null) 'previousAttemptReps': previousAttemptReps,
    if (attemptChangePercent != null)
      'attemptChangePercent': attemptChangePercent,
    if (attemptTrend != null) 'attemptTrend': attemptTrend!.name,
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

  int get personalBestCount =>
      exercises.where((exercise) => exercise.personalBest).length;

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
            personalBest: rawExercise['personalBest'] == true,
            personalBestEstimatedOneRepMax:
                (rawExercise['personalBestEstimatedOneRepMax'] as num?)
                    ?.toDouble(),
            previousBestEstimatedOneRepMax:
                (rawExercise['previousBestEstimatedOneRepMax'] as num?)
                    ?.toDouble(),
            personalBestWeightLbs:
                (rawExercise['personalBestWeightLbs'] as num?)?.toDouble(),
            personalBestReps: (rawExercise['personalBestReps'] as num?)
                ?.toInt(),
            currentAttemptEstimatedOneRepMax:
                (rawExercise['currentAttemptEstimatedOneRepMax'] as num?)
                    ?.toDouble(),
            previousAttemptEstimatedOneRepMax:
                (rawExercise['previousAttemptEstimatedOneRepMax'] as num?)
                    ?.toDouble(),
            currentAttemptWeightLbs:
                (rawExercise['currentAttemptWeightLbs'] as num?)?.toDouble(),
            previousAttemptWeightLbs:
                (rawExercise['previousAttemptWeightLbs'] as num?)?.toDouble(),
            currentAttemptReps: (rawExercise['currentAttemptReps'] as num?)
                ?.toInt(),
            previousAttemptReps: (rawExercise['previousAttemptReps'] as num?)
                ?.toInt(),
            attemptChangePercent: (rawExercise['attemptChangePercent'] as num?)
                ?.toDouble(),
            attemptTrend: _parseExerciseAttemptTrend(
              rawExercise['attemptTrend'] as String?,
            ),
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

  static const int _legacyExerciseMinutesMigrationVersion = 1;
  static const int _personalBestBackfillVersion = 3;

  static Future<int>? _legacyExerciseMinutesMigration;
  static String? _legacyExerciseMinutesMigrationUserId;
  static Future<int>? _personalBestBackfill;
  static String? _personalBestBackfillUserId;

  static Future<int> backfillPersonalBestsOnce() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return Future.value(0);
    if (_personalBestBackfillUserId != userId) {
      _personalBestBackfillUserId = userId;
      _personalBestBackfill = null;
    }
    return _personalBestBackfill ??= _runPersonalBestBackfill(userId);
  }

  static Future<int> _runPersonalBestBackfill(String userId) async {
    try {
      return await _backfillPersonalBests(userId);
    } catch (_) {
      if (_personalBestBackfillUserId == userId) {
        _personalBestBackfill = null;
      }
      rethrow;
    }
  }

  static Future<int> _backfillPersonalBests(String userId) async {
    final db = FirebaseFirestore.instance;
    final userReference = db.collection('users').doc(userId);
    final userSnapshot = await userReference.get();
    if (((userSnapshot.data()?['personalBestBackfillVersion'] as num?)
                ?.toInt() ??
            0) >=
        _personalBestBackfillVersion) {
      return 0;
    }

    final workouts = await userReference
        .collection('workouts')
        .orderBy('completedAt')
        .get();
    final currentRecords = <String, _StoredPersonalBest>{};
    final latestAttempts = <String, _StoredExerciseAttempt>{};
    final workoutUpdates = <_PersonalBestWorkoutUpdate>[];

    for (final workout in workouts.docs) {
      final data = workout.data();
      final completedAt =
          (data['completedAt'] as Timestamp?)?.toDate() ??
          (data['startedAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final rawExercises = data['exercises'] as List? ?? const [];
      final exerciseMaps = rawExercises
          .whereType<Map>()
          .map((exercise) => Map<String, dynamic>.from(exercise))
          .toList(growable: false);
      final candidates = _bestCandidatesForRawExercises(exerciseMaps);
      final personalBestExerciseIndexes = <int>{};
      final previousRecords = <String, _StoredPersonalBest?>{};
      final previousAttempts = <String, _StoredExerciseAttempt?>{
        for (final normalizedName in candidates.keys)
          normalizedName: latestAttempts[normalizedName],
      };
      var personalBestCount = 0;

      for (final entry in candidates.entries) {
        final candidate = entry.value;
        final previous = currentRecords[entry.key];
        previousRecords[entry.key] = previous;
        final isPersonalBest = isNewPersonalBest(
          candidateEstimatedOneRepMax: candidate.performance.estimatedOneRepMax,
          previousEstimatedOneRepMax: previous?.performance.estimatedOneRepMax,
        );
        if (!isPersonalBest) continue;
        personalBestExerciseIndexes.add(candidate.exerciseIndex);
        personalBestCount++;
        currentRecords[entry.key] = _StoredPersonalBest(
          exerciseName: candidate.exerciseName,
          normalizedName: entry.key,
          performance: candidate.performance,
          workoutId: workout.id,
          achievedAt: completedAt,
        );
      }

      final updatedExercises = <Map<String, dynamic>>[];
      for (var index = 0; index < exerciseMaps.length; index++) {
        final exercise = exerciseMaps[index];
        final normalizedName = normalizeExerciseName(
          exercise['name'] as String? ?? '',
        );
        final candidate = candidates[normalizedName];
        final updated = _withoutPersonalBestMetadata(exercise);
        final isPersonalBest = personalBestExerciseIndexes.contains(index);
        updated['personalBest'] = isPersonalBest;
        if (candidate != null && candidate.exerciseIndex == index) {
          _addExerciseAttemptMetadata(
            updated,
            candidate.performance,
            previousPerformance: previousAttempts[normalizedName]?.performance,
          );
        }
        if (isPersonalBest && candidate != null) {
          _addPersonalBestMetadata(
            updated,
            candidate.performance,
            previousEstimatedOneRepMax:
                previousRecords[normalizedName]?.performance.estimatedOneRepMax,
          );
        }
        updatedExercises.add(updated);
      }
      for (final entry in candidates.entries) {
        latestAttempts[entry.key] = _StoredExerciseAttempt(
          exerciseName: entry.value.exerciseName,
          normalizedName: entry.key,
          performance: entry.value.performance,
          workoutId: workout.id,
          completedAt: completedAt,
        );
      }
      workoutUpdates.add(
        _PersonalBestWorkoutUpdate(
          reference: workout.reference,
          exercises: updatedExercises,
          personalBestCount: personalBestCount,
        ),
      );
    }

    var batch = db.batch();
    var operationCount = 0;
    Future<void> commitIfFull() async {
      if (operationCount < 400) return;
      await batch.commit();
      batch = db.batch();
      operationCount = 0;
    }

    for (final update in workoutUpdates) {
      batch.update(update.reference, {
        'exercises': update.exercises,
        'personalBestCount': update.personalBestCount,
        'personalBestVersion': _personalBestBackfillVersion,
        'exerciseComparisonVersion': 2,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      operationCount++;
      await commitIfFull();
    }
    for (final record in currentRecords.values) {
      final reference = userReference
          .collection('exercise_personal_bests')
          .doc(Uri.encodeComponent(record.normalizedName));
      batch.set(reference, record.toMap(), SetOptions(merge: true));
      operationCount++;
      await commitIfFull();
    }
    for (final attempt in latestAttempts.values) {
      final reference = userReference
          .collection('exercise_latest_attempts')
          .doc(Uri.encodeComponent(attempt.normalizedName));
      batch.set(reference, attempt.toMap(), SetOptions(merge: true));
      operationCount++;
      await commitIfFull();
    }
    batch.set(userReference, {
      'personalBestBackfillVersion': _personalBestBackfillVersion,
      'personalBestBackfilledAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    operationCount++;
    if (operationCount > 0) await batch.commit();
    return workoutUpdates.length;
  }

  /// Adds legacy workout durations to the daily exercise-time metric.
  ///
  /// Workouts saved before exercise-goal integration do not contain
  /// `exerciseGoalDay`. Each transaction re-checks that field and writes it
  /// alongside the daily total, making this safe to retry without counting a
  /// workout twice.
  static Future<int> migrateLegacyExerciseMinutesOnce() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return Future.value(0);
    if (_legacyExerciseMinutesMigrationUserId != userId) {
      _legacyExerciseMinutesMigrationUserId = userId;
      _legacyExerciseMinutesMigration = null;
    }
    return _legacyExerciseMinutesMigration ??=
        _runLegacyExerciseMinutesMigration(userId);
  }

  static Future<int> _runLegacyExerciseMinutesMigration(String userId) async {
    try {
      return await _migrateLegacyExerciseMinutes(userId);
    } catch (_) {
      if (_legacyExerciseMinutesMigrationUserId == userId) {
        _legacyExerciseMinutesMigration = null;
      }
      rethrow;
    }
  }

  static Future<int> _migrateLegacyExerciseMinutes(String userId) async {
    final db = FirebaseFirestore.instance;
    final userReference = db.collection('users').doc(userId);
    final userSnapshot = await userReference.get();
    if (((userSnapshot.data()?['exerciseMinutesBackfillVersion'] as num?)
                ?.toInt() ??
            0) >=
        _legacyExerciseMinutesMigrationVersion) {
      return 0;
    }

    final workouts = await userReference.collection('workouts').get();
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
        final dailyReference = userReference
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

    await userReference.set({
      'exerciseMinutesBackfillVersion': _legacyExerciseMinutesMigrationVersion,
      'exerciseMinutesBackfilledAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

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

  static Future<List<WorkoutTemplateExercise>> loadCustomExercises() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const [];
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('custom_exercises')
        .get();
    return snapshot.docs
        .map((document) {
          final data = document.data();
          final name = (data['name'] as String? ?? '').trim();
          final category = (data['category'] as String? ?? 'Other').trim();
          return WorkoutTemplateExercise(
            name: name,
            category: category.isEmpty ? 'Other' : category,
          );
        })
        .where((exercise) => exercise.name.isNotEmpty)
        .toList(growable: false);
  }

  static Future<void> saveCustomExercise({
    required String name,
    required String category,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Sign in before creating a custom exercise.');
    }
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Exercise name is required.');
    final cleanCategory = category.trim().isEmpty ? 'Other' : category.trim();
    final normalizedName = cleanName.toLowerCase();
    final collection = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('custom_exercises');
    final existing = await collection
        .where('normalizedName', isEqualTo: normalizedName)
        .limit(1)
        .get();
    final document = existing.docs.isEmpty
        ? collection.doc()
        : existing.docs.first.reference;
    await document.set({
      'name': cleanName,
      'normalizedName': normalizedName,
      'category': cleanCategory,
      'updatedAt': FieldValue.serverTimestamp(),
      if (existing.docs.isEmpty) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
    await backfillPersonalBestsOnce();

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
    final personalBestCandidates = _bestCandidatesForExerciseRecords(exercises);
    final personalBestReferences = {
      for (final normalizedName in personalBestCandidates.keys)
        normalizedName: db
            .collection('users')
            .doc(user.uid)
            .collection('exercise_personal_bests')
            .doc(Uri.encodeComponent(normalizedName)),
    };
    final latestAttemptReferences = {
      for (final normalizedName in personalBestCandidates.keys)
        normalizedName: db
            .collection('users')
            .doc(user.uid)
            .collection('exercise_latest_attempts')
            .doc(Uri.encodeComponent(normalizedName)),
    };
    await db.runTransaction((transaction) async {
      final dailySnapshot = await transaction.get(dailyReference);
      final personalBestSnapshots =
          <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final entry in personalBestReferences.entries) {
        personalBestSnapshots[entry.key] = await transaction.get(entry.value);
      }
      final latestAttemptSnapshots =
          <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final entry in latestAttemptReferences.entries) {
        latestAttemptSnapshots[entry.key] = await transaction.get(entry.value);
      }
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
      final exerciseMaps = exercises
          .map((exercise) => _withoutPersonalBestMetadata(exercise.toMap()))
          .toList(growable: false);
      var personalBestCount = 0;

      for (final entry in personalBestCandidates.entries) {
        final candidate = entry.value;
        final previousAttemptData = latestAttemptSnapshots[entry.key]?.data();
        final previousAttemptEstimate =
            (previousAttemptData?['estimatedOneRepMax'] as num?)?.toDouble();
        final exerciseMap = exerciseMaps[candidate.exerciseIndex];
        _addExerciseAttemptMetadata(
          exerciseMap,
          candidate.performance,
          previousPerformance: previousAttemptEstimate == null
              ? null
              : PersonalBestPerformance(
                  weightLbs:
                      (previousAttemptData?['weightLbs'] as num?)?.toDouble() ??
                      0,
                  reps: (previousAttemptData?['reps'] as num?)?.toInt() ?? 0,
                  estimatedOneRepMax: previousAttemptEstimate,
                ),
        );
        transaction.set(latestAttemptReferences[entry.key]!, {
          'exerciseName': candidate.exerciseName,
          'normalizedName': entry.key,
          'estimatedOneRepMax': candidate.performance.estimatedOneRepMax,
          'weightLbs': candidate.performance.weightLbs,
          'reps': candidate.performance.reps,
          'workoutId': document.id,
          'completedAt': Timestamp.fromDate(completedAt),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        final previousData = personalBestSnapshots[entry.key]?.data();
        final previousEstimate = (previousData?['estimatedOneRepMax'] as num?)
            ?.toDouble();
        final isPersonalBest = isNewPersonalBest(
          candidateEstimatedOneRepMax: candidate.performance.estimatedOneRepMax,
          previousEstimatedOneRepMax: previousEstimate,
        );
        if (!isPersonalBest) continue;
        personalBestCount++;
        exerciseMap['personalBest'] = true;
        _addPersonalBestMetadata(
          exerciseMap,
          candidate.performance,
          previousEstimatedOneRepMax: previousEstimate,
        );
        transaction.set(personalBestReferences[entry.key]!, {
          'exerciseName': candidate.exerciseName,
          'normalizedName': entry.key,
          'estimatedOneRepMax': candidate.performance.estimatedOneRepMax,
          'weightLbs': candidate.performance.weightLbs,
          'reps': candidate.performance.reps,
          'workoutId': document.id,
          'achievedAt': Timestamp.fromDate(completedAt),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

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
        'exercises': exerciseMaps,
        'personalBestCount': personalBestCount,
        'personalBestVersion': 3,
        'exerciseComparisonVersion': 2,
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

Map<String, _PersonalBestCandidate> _bestCandidatesForExerciseRecords(
  List<WorkoutExerciseRecord> exercises,
) {
  final candidates = <String, _PersonalBestCandidate>{};
  for (var index = 0; index < exercises.length; index++) {
    final exercise = exercises[index];
    final normalizedName = normalizeExerciseName(exercise.name);
    if (normalizedName.isEmpty) continue;
    final performance = bestPersonalBestPerformance(
      exercise.sets.map((set) => (weightLbs: set.weightLbs, reps: set.reps)),
    );
    if (performance == null) continue;
    final existing = candidates[normalizedName];
    if (existing == null ||
        performance.estimatedOneRepMax >
            existing.performance.estimatedOneRepMax) {
      candidates[normalizedName] = _PersonalBestCandidate(
        exerciseIndex: index,
        exerciseName: exercise.name.trim(),
        performance: performance,
      );
    }
  }
  return candidates;
}

Map<String, _PersonalBestCandidate> _bestCandidatesForRawExercises(
  List<Map<String, dynamic>> exercises,
) {
  final candidates = <String, _PersonalBestCandidate>{};
  for (var index = 0; index < exercises.length; index++) {
    final exercise = exercises[index];
    final exerciseName = (exercise['name'] as String? ?? '').trim();
    final normalizedName = normalizeExerciseName(exerciseName);
    if (normalizedName.isEmpty) continue;
    final rawSets = exercise['sets'] as List? ?? const [];
    final performance = bestPersonalBestPerformance(
      rawSets.whereType<Map>().map(
        (set) => (
          weightLbs: (set['weightLbs'] as num?)?.toDouble() ?? 0,
          reps: (set['reps'] as num?)?.toInt() ?? 0,
        ),
      ),
    );
    if (performance == null) continue;
    final existing = candidates[normalizedName];
    if (existing == null ||
        performance.estimatedOneRepMax >
            existing.performance.estimatedOneRepMax) {
      candidates[normalizedName] = _PersonalBestCandidate(
        exerciseIndex: index,
        exerciseName: exerciseName,
        performance: performance,
      );
    }
  }
  return candidates;
}

Map<String, dynamic> _withoutPersonalBestMetadata(
  Map<String, dynamic> exercise,
) {
  final cleaned = Map<String, dynamic>.from(exercise);
  cleaned.remove('personalBest');
  cleaned.remove('personalBestEstimatedOneRepMax');
  cleaned.remove('previousBestEstimatedOneRepMax');
  cleaned.remove('personalBestWeightLbs');
  cleaned.remove('personalBestReps');
  cleaned.remove('currentAttemptEstimatedOneRepMax');
  cleaned.remove('previousAttemptEstimatedOneRepMax');
  cleaned.remove('currentAttemptWeightLbs');
  cleaned.remove('previousAttemptWeightLbs');
  cleaned.remove('currentAttemptReps');
  cleaned.remove('previousAttemptReps');
  cleaned.remove('attemptChangePercent');
  cleaned.remove('attemptTrend');
  return cleaned;
}

void _addPersonalBestMetadata(
  Map<String, dynamic> exercise,
  PersonalBestPerformance performance, {
  double? previousEstimatedOneRepMax,
}) {
  exercise['personalBestEstimatedOneRepMax'] = performance.estimatedOneRepMax;
  exercise['personalBestWeightLbs'] = performance.weightLbs;
  exercise['personalBestReps'] = performance.reps;
  if (previousEstimatedOneRepMax != null) {
    exercise['previousBestEstimatedOneRepMax'] = previousEstimatedOneRepMax;
  }
}

void _addExerciseAttemptMetadata(
  Map<String, dynamic> exercise,
  PersonalBestPerformance performance, {
  PersonalBestPerformance? previousPerformance,
}) {
  exercise['currentAttemptEstimatedOneRepMax'] = performance.estimatedOneRepMax;
  exercise['currentAttemptWeightLbs'] = performance.weightLbs;
  exercise['currentAttemptReps'] = performance.reps;
  if (previousPerformance == null) return;
  final changePercent = exercisePerformanceChangePercent(
    currentEstimatedOneRepMax: performance.estimatedOneRepMax,
    previousEstimatedOneRepMax: previousPerformance.estimatedOneRepMax,
  );
  exercise['previousAttemptEstimatedOneRepMax'] =
      previousPerformance.estimatedOneRepMax;
  exercise['previousAttemptWeightLbs'] = previousPerformance.weightLbs;
  exercise['previousAttemptReps'] = previousPerformance.reps;
  exercise['attemptChangePercent'] = changePercent;
  exercise['attemptTrend'] = exerciseAttemptTrend(changePercent).name;
}

ExerciseAttemptTrend? _parseExerciseAttemptTrend(String? value) =>
    switch (value) {
      'improved' => ExerciseAttemptTrend.improved,
      'maintained' => ExerciseAttemptTrend.maintained,
      'declined' => ExerciseAttemptTrend.declined,
      _ => null,
    };

class _PersonalBestCandidate {
  const _PersonalBestCandidate({
    required this.exerciseIndex,
    required this.exerciseName,
    required this.performance,
  });

  final int exerciseIndex;
  final String exerciseName;
  final PersonalBestPerformance performance;
}

class _StoredPersonalBest {
  const _StoredPersonalBest({
    required this.exerciseName,
    required this.normalizedName,
    required this.performance,
    required this.workoutId,
    required this.achievedAt,
  });

  final String exerciseName;
  final String normalizedName;
  final PersonalBestPerformance performance;
  final String workoutId;
  final DateTime achievedAt;

  Map<String, dynamic> toMap() => {
    'exerciseName': exerciseName,
    'normalizedName': normalizedName,
    'estimatedOneRepMax': performance.estimatedOneRepMax,
    'weightLbs': performance.weightLbs,
    'reps': performance.reps,
    'workoutId': workoutId,
    'achievedAt': Timestamp.fromDate(achievedAt),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

class _StoredExerciseAttempt {
  const _StoredExerciseAttempt({
    required this.exerciseName,
    required this.normalizedName,
    required this.performance,
    required this.workoutId,
    required this.completedAt,
  });

  final String exerciseName;
  final String normalizedName;
  final PersonalBestPerformance performance;
  final String workoutId;
  final DateTime completedAt;

  Map<String, dynamic> toMap() => {
    'exerciseName': exerciseName,
    'normalizedName': normalizedName,
    'estimatedOneRepMax': performance.estimatedOneRepMax,
    'weightLbs': performance.weightLbs,
    'reps': performance.reps,
    'workoutId': workoutId,
    'completedAt': Timestamp.fromDate(completedAt),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

class _PersonalBestWorkoutUpdate {
  const _PersonalBestWorkoutUpdate({
    required this.reference,
    required this.exercises,
    required this.personalBestCount,
  });

  final DocumentReference<Map<String, dynamic>> reference;
  final List<Map<String, dynamic>> exercises;
  final int personalBestCount;
}
