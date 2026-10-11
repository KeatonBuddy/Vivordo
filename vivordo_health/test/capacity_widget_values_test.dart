import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/home_widget_service.dart';

void main() {
  Map<String, dynamic> day(
    int score, {
    bool provisional = false,
    int version = 1,
    Map<String, Object?>? parts,
  }) => {
    'capacity': {
      'score': score,
      'label': score >= 80 ? 'high' : 'moderate',
      'provisional': provisional,
      'version': version,
      'parts': ?parts,
    },
  };

  test('score, label and the change from yesterday', () {
    final values = capacityWidgetValues(day(81), day(75));
    expect(values['dashboardHasCapacity'], true);
    expect(values['capacityScore'], 81);
    expect(values['capacityLabel'], 'high');
    expect(values['capacityDelta'], 6);
    expect(values['capacityNote'], '');
  });

  test('no change shown across formula versions or while provisional', () {
    expect(
      capacityWidgetValues(day(81), day(75, version: 0))['capacityDelta'],
      0,
    );
    final waiting = capacityWidgetValues(
      day(70, provisional: true, parts: {'sleep': null, 'body': 62}),
      day(75),
    );
    expect(waiting['capacityDelta'], 0);
    expect(waiting['capacityNote'], 'Waiting for sleep');
    expect(
      capacityWidgetValues(
        day(50, provisional: true, parts: {'sleep': null, 'body': null}),
        null,
      )['capacityNote'],
      'Based on your check-in',
    );
  });

  test('no Capacity yet clears the widget', () {
    final values = capacityWidgetValues(null, day(75));
    expect(values['dashboardHasCapacity'], false);
    expect(values['capacityScore'], 0);
  });
}
