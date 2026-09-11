import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/exercise_catalog_service.dart';

void main() {
  setUp(ExerciseCatalogService.resetForTesting);

  test('starts empty and not loaded', () {
    expect(ExerciseCatalogService.defaults, isEmpty);
    expect(ExerciseCatalogService.isLoaded, isFalse);
  });

  test('loadForTesting publishes items and marks the catalog loaded', () {
    ExerciseCatalogService.loadForTesting([
      (name: 'Barbell Row', category: 'Back'),
    ]);

    expect(ExerciseCatalogService.defaults.single.name, 'Barbell Row');
    expect(ExerciseCatalogService.isLoaded, isTrue);
  });

  test('an empty catalog still counts as loaded', () {
    ExerciseCatalogService.loadForTesting(const []);

    expect(ExerciseCatalogService.defaults, isEmpty);
    expect(
      ExerciseCatalogService.isLoaded,
      isTrue,
      reason: 'empty-but-present must be distinct from fetch failure',
    );
  });

  test('reset returns the service to the not-loaded state', () {
    ExerciseCatalogService.loadForTesting([
      (name: 'Barbell Row', category: 'Back'),
    ]);
    ExerciseCatalogService.resetForTesting();

    expect(ExerciseCatalogService.defaults, isEmpty);
    expect(ExerciseCatalogService.isLoaded, isFalse);
  });

  // State machine tests for applySnapshot, which is the safety-critical path.
  group('applySnapshot state machine', () {
    test('missing document does not change state', () {
      ExerciseCatalogService.applySnapshot(exists: false, data: {});

      expect(ExerciseCatalogService.defaults, isEmpty);
      expect(ExerciseCatalogService.isLoaded, isFalse);
    });

    test('present document with valid entries sets loaded and defaults', () {
      ExerciseCatalogService.applySnapshot(
        exists: true,
        data: {
          'exercises': [
            {'n': 'Barbell Row', 'c': 'Back'},
            {'n': 'Bench Press', 'c': 'Chest'},
          ],
        },
      );

      expect(ExerciseCatalogService.defaults, hasLength(2));
      expect(ExerciseCatalogService.defaults[0].name, 'Barbell Row');
      expect(ExerciseCatalogService.defaults[0].category, 'Back');
      expect(ExerciseCatalogService.defaults[1].name, 'Bench Press');
      expect(ExerciseCatalogService.defaults[1].category, 'Chest');
      expect(ExerciseCatalogService.isLoaded, isTrue);
    });

    test(
      'present document with empty exercises array sets loaded with empty defaults',
      () {
        ExerciseCatalogService.applySnapshot(
          exists: true,
          data: {'exercises': []},
        );

        expect(ExerciseCatalogService.defaults, isEmpty);
        expect(
          ExerciseCatalogService.isLoaded,
          isTrue,
          reason: 'empty-but-present must be distinct from fetch failure',
        );
      },
    );

    test(
      'present document with garbage exercises sets loaded with empty defaults',
      () {
        ExerciseCatalogService.applySnapshot(
          exists: true,
          data: {'exercises': 'nope'},
        );

        expect(ExerciseCatalogService.defaults, isEmpty);
        expect(
          ExerciseCatalogService.isLoaded,
          isTrue,
          reason: 'unparseable-but-present must be distinct from fetch failure',
        );
      },
    );

    test(
      'missing document after successful load does not clear previously loaded state',
      () {
        // Load some data first.
        ExerciseCatalogService.applySnapshot(
          exists: true,
          data: {
            'exercises': [
              {'n': 'Barbell Row', 'c': 'Back'},
            ],
          },
        );

        // Apply a missing document snapshot.
        ExerciseCatalogService.applySnapshot(exists: false, data: null);

        // State should be unchanged.
        expect(ExerciseCatalogService.defaults, hasLength(1));
        expect(ExerciseCatalogService.defaults.single.name, 'Barbell Row');
        expect(ExerciseCatalogService.isLoaded, isTrue);
      },
    );
  });
}
