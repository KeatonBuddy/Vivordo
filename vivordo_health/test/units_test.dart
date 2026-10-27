import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/units.dart';

void main() {
  test('defaults follow the device region', () {
    final us = Units.forCountry('US');
    expect(
      [us.bodyWeight, us.liftWeight, us.distance, us.height],
      [MassUnit.lb, MassUnit.lb, DistanceUnit.mi, HeightUnit.ftIn],
    );
    final ca = Units.forCountry('ca');
    expect(
      [ca.bodyWeight, ca.liftWeight, ca.distance, ca.height],
      [MassUnit.lb, MassUnit.lb, DistanceUnit.km, HeightUnit.ftIn],
    );
    expect(Units.forCountry('IN'), Units.metric);
    expect(Units.forCountry(null), Units.metric);
  });

  test('saved choices win one measure at a time; junk falls back', () {
    final units = Units.fromPreferences({
      'bodyWeight': 'kg',
      'distance': 'furlongs',
    }, Units.forCountry('US'));
    expect(units.bodyWeight, MassUnit.kg);
    expect(units.liftWeight, MassUnit.lb);
    expect(units.distance, DistanceUnit.mi);
    expect(Units.fromPreferences(units.toMap(), Units.metric), units);
  });

  test('a lift typed in kg is stored in lb and shown back as typed', () {
    final kg = Units.metric;
    final stored = kg.liftToLbs(100);
    expect(stored, closeTo(220.462, .001));
    expect(kg.formatLift(stored), '100 kg');
    expect(kg.formatLift(kg.liftToLbs(62.5)), '62.5 kg');
    expect(Units.forCountry('US').formatLift(135), '135 lbs');
  });

  test('body weight, distance and height display', () {
    final us = Units.forCountry('US');
    expect(Units.metric.formatBodyWeight(70), '70 kg');
    expect(us.formatBodyWeight(70), '154.3 lbs');
    expect(us.bodyWeightToKg(154.3), closeTo(70, .02));
    expect(Units.metric.formatDistance(5.25), '5.3 km');
    expect(us.formatDistance(5), '3.1 mi');
    expect(us.distanceToKm(1), closeTo(1.609, .001));
    expect(Units.metric.formatHeight(175.4), '175 cm');
    expect(us.formatHeight(175.26), '5′ 9″');
    expect(Units.cmFromFeetInches(5, 9), closeTo(175.26, .001));
  });

  test('numbers drop trailing zeros only', () {
    expect(formatNumber(70, 1), '70');
    expect(formatNumber(70.06, 1), '70.1');
    expect(formatNumber(100, 0), '100');
    expect(formatNumber(2.50, 2), '2.5');
  });
}
