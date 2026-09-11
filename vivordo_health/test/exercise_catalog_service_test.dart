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
}
