import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/exercise_picker_results.dart';

void main() {
  const catalog = <PickerExercise>[
    (name: 'Barbell Row', category: 'Back', isCustom: false),
    (name: 'Arnold Press', category: 'Shoulders', isCustom: false),
    (name: 'Cable Press', category: 'Chest', isCustom: false),
  ];
  // 'Aardvark Cable Curl' is named to sort before every catalog match it
  // shares a search term or category with ('Cable Press', 'Arnold Press'),
  // so a merge that sorted each source separately before concatenating would
  // place it after those catalog entries instead of before them.
  const custom = <PickerExercise>[
    (name: 'Sled Push', category: 'Legs', isCustom: true),
    (name: 'Aardvark Cable Curl', category: 'Shoulders', isCustom: true),
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

    expect(result.custom.map((e) => e.name), [
      'Aardvark Cable Curl',
      'Sled Push',
    ]);
    expect(result.defaults.map((e) => e.name), [
      'Arnold Press',
      'Barbell Row',
      'Cable Press',
    ]);
  });

  test('a search collapses to one merged, sorted list', () {
    final result = results(search: 'cable');

    expect(result.custom, isEmpty);
    expect(result.defaults.map((e) => e.name), [
      'Aardvark Cable Curl',
      'Cable Press',
    ]);
  });

  test('custom entries keep their flag inside a merged list', () {
    final result = results(search: 'cable');

    final custom = result.defaults.firstWhere(
      (e) => e.name == 'Aardvark Cable Curl',
    );
    final press = result.defaults.firstWhere((e) => e.name == 'Cable Press');
    expect(custom.isCustom, isTrue);
    expect(press.isCustom, isFalse);
  });

  test('a category filter collapses sections and filters both sources', () {
    final result = results(filter: 'Shoulders');

    expect(result.custom, isEmpty);
    expect(result.defaults.map((e) => e.name), [
      'Aardvark Cable Curl',
      'Arnold Press',
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
    final result = results(search: '   ');

    expect(result.custom.map((e) => e.name), [
      'Aardvark Cable Curl',
      'Sled Push',
    ]);
    expect(result.defaults, hasLength(3));
  });

  test('no custom exercises yields an empty custom section', () {
    final result = exercisePickerResults(
      search: '',
      filter: 'All',
      catalog: catalog,
      custom: const [],
    );

    expect(result.custom, isEmpty);
    expect(result.defaults, hasLength(3));
  });
}
