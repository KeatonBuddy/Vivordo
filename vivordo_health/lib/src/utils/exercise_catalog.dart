/// One exercise offered by the workout builder.
typedef WorkoutExerciseCatalogItem = ({String name, String category});

/// Identity key for an exercise name. Case, spacing and punctuation are
/// ignored so "Barbell Bench Press" and "barbell-bench press" are one exercise.
String exerciseNameKey(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

/// Reads the `exercise_catalog/current` document body.
///
/// Order is preserved: the Circle challenge picker renders the catalog
/// unsorted, so the stored order is what users see.
///
/// Never throws. A missing or malformed document yields an empty list, and a
/// single unusable entry is skipped rather than discarding the whole catalog.
/// Callers must not treat an empty result as "the catalog loaded and is
/// empty" — see ExerciseCatalogService.isLoaded.
List<WorkoutExerciseCatalogItem> parseExerciseCatalog(
  Map<String, dynamic>? data,
) {
  final raw = data?['exercises'];
  if (raw is! List) return const [];

  final items = <WorkoutExerciseCatalogItem>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final name = (entry['n'] as String? ?? '').trim();
    if (name.isEmpty) continue;
    final category = (entry['c'] as String? ?? '').trim();
    items.add((name: name, category: category.isEmpty ? 'Other' : category));
  }
  return List.unmodifiable(items);
}
