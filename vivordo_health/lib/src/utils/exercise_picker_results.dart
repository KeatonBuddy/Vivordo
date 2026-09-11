/// One row in the Add Exercise picker.
typedef PickerExercise = ({String name, String category, bool isCustom});

/// What the picker should render for the current search and filter.
///
/// When [sectioned] is true, [custom] is shown under its own heading above
/// [defaults]. Otherwise [custom] is empty and [defaults] holds every match in
/// one ranking, each still carrying its own `isCustom` flag.
class ExercisePickerResults {
  const ExercisePickerResults({
    required this.sectioned,
    required this.custom,
    required this.defaults,
  });

  final bool sectioned;
  final List<PickerExercise> custom;
  final List<PickerExercise> defaults;
}

List<PickerExercise> _matching(
  Iterable<PickerExercise> source,
  String query,
  String filter,
) =>
    source.where((exercise) {
        final matchesFilter = filter == 'All' || exercise.category == filter;
        final matchesSearch =
            query.isEmpty ||
            exercise.name.toLowerCase().contains(query) ||
            exercise.category.toLowerCase().contains(query);
        return matchesFilter && matchesSearch;
      }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

/// Splits the picker into a pinned custom section plus the defaults while
/// browsing, and into one merged list once a search or category filter is
/// narrowing things down — a user who typed a query wants one ranking, not
/// their match split across two headings.
ExercisePickerResults exercisePickerResults({
  required String search,
  required String filter,
  required Iterable<PickerExercise> catalog,
  required Iterable<PickerExercise> custom,
}) {
  final query = search.trim().toLowerCase();
  final sectioned = query.isEmpty && filter == 'All';

  if (!sectioned) {
    return ExercisePickerResults(
      sectioned: false,
      custom: const [],
      defaults: _matching([...catalog, ...custom], query, filter),
    );
  }

  return ExercisePickerResults(
    sectioned: true,
    custom: _matching(custom, query, filter),
    defaults: _matching(catalog, query, filter),
  );
}
