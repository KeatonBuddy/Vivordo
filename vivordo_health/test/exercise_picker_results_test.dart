import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/exercise_picker_results.dart';

void main() {
  const catalog = <PickerExercise>[
    (name: 'Barbell Row', category: 'Back', isCustom: false),
    (name: 'Arnold Press', category: 'Shoulders', isCustom: false),
    (name: 'Cable Press', category: 'Chest', isCustom: false),
  ];
  const custom = <PickerExercise>[
    (name: 'Sled Push', category: 'Legs', isCustom: true),
    (name: 'Cable Y-Raise', category: 'Shoulders', isCustom: true),
  ];

  ExercisePickerResults results({String search = '', String filter = 'All'}) =>
      exercisePickerResults(
        search: search,
        filter: filter,
        catalog: catalog,
        custom: custom,
      );

  test('browsing splits custom into its own section', () {
    final result = results();

    expect(result.sectioned, isTrue);
    expect(result.custom.map((e) => e.name), ['Cable Y-Raise', 'Sled Push']);
    expect(result.defaults.map((e) => e.name), [
      'Arnold Press',
      'Barbell Row',
      'Cable Press',
    ]);
  });

  test('a search collapses to one merged, sorted list', () {
    final result = results(search: 'cable');

    expect(result.sectioned, isFalse);
    expect(result.custom, isEmpty);
    expect(result.defaults.map((e) => e.name), [
      'Cable Press',
      'Cable Y-Raise',
    ]);
  });

  test('custom entries keep their flag inside a merged list', () {
    final result = results(search: 'cable');

    final yRaise = result.defaults.firstWhere((e) => e.name == 'Cable Y-Raise');
    final press = result.defaults.firstWhere((e) => e.name == 'Cable Press');
    expect(yRaise.isCustom, isTrue);
    expect(press.isCustom, isFalse);
  });

  test('a category filter collapses sections and filters both sources', () {
    final result = results(filter: 'Shoulders');

    expect(result.sectioned, isFalse);
    expect(result.defaults.map((e) => e.name), [
      'Arnold Press',
      'Cable Y-Raise',
    ]);
  });

  test('search matches category as well as name', () {
    final result = results(search: 'legs');

    expect(result.defaults.map((e) => e.name), ['Sled Push']);
  });

  test('search ignores case and surrounding whitespace', () {
    expect(results(search: '  ROW  ').defaults.map((e) => e.name), [
      'Barbell Row',
    ]);
  });

  test('whitespace-only search still counts as browsing', () {
    expect(results(search: '   ').sectioned, isTrue);
  });

  test('no custom exercises yields an empty custom section', () {
    final result = exercisePickerResults(
      search: '',
      filter: 'All',
      catalog: catalog,
      custom: const [],
    );

    expect(result.sectioned, isTrue);
    expect(result.custom, isEmpty);
    expect(result.defaults, hasLength(3));
  });
}
