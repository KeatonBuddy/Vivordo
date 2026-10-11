import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/custom_exercise_backfill.dart';

void main() {
  const catalog = <WorkoutExerciseCatalogItem>[
    (name: 'Barbell Bench Press', category: 'Chest'),
    (name: 'Barbell Row', category: 'Back'),
  ];

  test('returns nothing when the catalog failed to load', () {
    final additions = customExerciseAdditions(
      catalogLoaded: false,
      catalog: const [],
      known: const [],
      recovered: const [
        (name: 'Barbell Bench Press', category: 'Chest'),
        (name: 'Barbell Row', category: 'Back'),
      ],
    );

    expect(
      additions,
      isEmpty,
      reason: 'a cold catalog must never relabel defaults as user-created',
    );
  });

  test(
    'returns nothing when the catalog failed to load, even with non-empty inputs',
    () {
      final additions = customExerciseAdditions(
        catalogLoaded: false,
        catalog: catalog,
        known: const [(name: 'Sled Push', category: 'Legs')],
        recovered: const [
          (name: 'Barbell Row', category: 'Back'),
          (name: 'Sled Push', category: 'Legs'),
        ],
      );

      expect(
        additions,
        isEmpty,
        reason:
            'the guard must short-circuit regardless of the other '
            'arguments, not just because they happen to be empty',
      );
    },
  );

  test('keeps history entries that are genuinely not in the catalog', () {
    final additions = customExerciseAdditions(
      catalogLoaded: true,
      catalog: catalog,
      known: const [],
      recovered: const [
        (name: 'Barbell Row', category: 'Back'),
        (name: 'Sled Push', category: 'Legs'),
      ],
    );

    expect(additions.map((e) => e.name), ['Sled Push']);
  });

  test('an empty but loaded catalog still allows additions', () {
    final additions = customExerciseAdditions(
      catalogLoaded: true,
      catalog: const [],
      known: const [],
      recovered: const [(name: 'Sled Push', category: 'Legs')],
    );

    expect(additions.map((e) => e.name), ['Sled Push']);
  });

  test('ignores entries already known as custom', () {
    final additions = customExerciseAdditions(
      catalogLoaded: true,
      catalog: catalog,
      known: const [(name: 'Sled Push', category: 'Legs')],
      recovered: const [(name: 'Sled Push', category: 'Legs')],
    );

    expect(additions, isEmpty);
  });

  test('matches the catalog ignoring case and punctuation', () {
    final additions = customExerciseAdditions(
      catalogLoaded: true,
      catalog: catalog,
      known: const [],
      recovered: const [(name: 'barbell-bench  press', category: 'Chest')],
    );

    expect(additions, isEmpty);
  });

  test('de-duplicates repeats within the recovered list', () {
    final additions = customExerciseAdditions(
      catalogLoaded: true,
      catalog: catalog,
      known: const [],
      recovered: const [
        (name: 'Sled Push', category: 'Legs'),
        (name: 'Sled Push', category: 'Legs'),
      ],
    );

    expect(additions, hasLength(1));
  });

  test('drops entries whose name has no usable characters', () {
    final additions = customExerciseAdditions(
      catalogLoaded: true,
      catalog: catalog,
      known: const [],
      recovered: const [(name: '!!!', category: 'Legs')],
    );

    expect(additions, isEmpty);
  });
}
