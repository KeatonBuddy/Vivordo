import 'exercise_catalog.dart';

export 'exercise_catalog.dart' show WorkoutExerciseCatalogItem;

/// Exercises recovered from workout history that should be saved as the user's
/// own custom exercises.
///
/// Returns nothing unless [catalogLoaded] is true. The caller writes these into
/// `users/{uid}/custom_exercises`, so running against a catalog that failed to
/// load would permanently relabel that user's default exercises as
/// user-created. An empty catalog that did load is a legitimate state and does
/// not block the back-fill.
List<WorkoutExerciseCatalogItem> customExerciseAdditions({
  required bool catalogLoaded,
  required Iterable<WorkoutExerciseCatalogItem> catalog,
  required Iterable<WorkoutExerciseCatalogItem> known,
  required Iterable<WorkoutExerciseCatalogItem> recovered,
}) {
  if (!catalogLoaded) return const [];

  final seen = <String>{
    for (final exercise in catalog) exerciseNameKey(exercise.name),
    for (final exercise in known) exerciseNameKey(exercise.name),
  };

  final additions = <WorkoutExerciseCatalogItem>[];
  for (final exercise in recovered) {
    final key = exerciseNameKey(exercise.name);
    if (key.isEmpty) continue;
    if (seen.add(key)) additions.add(exercise);
  }
  return List.unmodifiable(additions);
}
