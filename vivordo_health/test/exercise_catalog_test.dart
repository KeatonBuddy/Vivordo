import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/exercise_catalog.dart';

void main() {
  test('parses entries in document order', () {
    final items = parseExerciseCatalog({
      'version': 1,
      'exercises': [
        {'n': 'Barbell Bench Press', 'c': 'Chest'},
        {'n': 'Barbell Row', 'c': 'Back'},
      ],
    });

    expect(items, hasLength(2));
    expect(items.first.name, 'Barbell Bench Press');
    expect(items.first.category, 'Chest');
    expect(items.last.name, 'Barbell Row');
  });

  test('returns empty for a null or malformed document', () {
    expect(parseExerciseCatalog(null), isEmpty);
    expect(parseExerciseCatalog({}), isEmpty);
    expect(parseExerciseCatalog({'exercises': 'not a list'}), isEmpty);
  });

  test('skips unusable entries but keeps the rest', () {
    final items = parseExerciseCatalog({
      'exercises': [
        {'n': 'Good Lift', 'c': 'Chest'},
        {'n': '   ', 'c': 'Chest'},
        {'c': 'Chest'},
        'not a map',
        {'n': 'Another Lift'},
      ],
    });

    expect(items.map((e) => e.name), ['Good Lift', 'Another Lift']);
    expect(items.last.category, 'Other', reason: 'missing category defaults');
  });

  test('trims surrounding whitespace on names and categories', () {
    final items = parseExerciseCatalog({
      'exercises': [
        {'n': '  Sled Push  ', 'c': '  Legs  '},
      ],
    });

    expect(items.single.name, 'Sled Push');
    expect(items.single.category, 'Legs');
  });

  test('exerciseNameKey ignores case, spacing and punctuation', () {
    expect(exerciseNameKey('Barbell Bench Press'), 'barbellbenchpress');
    expect(exerciseNameKey('barbell-bench  press'), 'barbellbenchpress');
    expect(exerciseNameKey('!!!'), isEmpty);
  });
}
