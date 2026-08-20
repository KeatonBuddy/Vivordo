import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/heart_rate_zones.dart';

void main() {
  test('categorizes values below 60 as low', () {
    expect(heartRateZoneFor(59.9), HeartRateZone.low);
  });

  test('categorizes 60 through 79 as relaxed', () {
    expect(heartRateZoneFor(60), HeartRateZone.relaxed);
    expect(heartRateZoneFor(79.9), HeartRateZone.relaxed);
  });

  test('categorizes 80 through 99 as raised', () {
    expect(heartRateZoneFor(80), HeartRateZone.raised);
    expect(heartRateZoneFor(99.9), HeartRateZone.raised);
  });

  test('categorizes values of 100 or more as high', () {
    expect(heartRateZoneFor(100), HeartRateZone.high);
    expect(heartRateZoneFor(180), HeartRateZone.high);
  });
}
