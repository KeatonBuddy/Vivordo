import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/whoop_ble_heart_rate_service.dart';

void main() {
  test('parses an 8-bit Bluetooth heart-rate measurement', () {
    expect(WhoopBleHeartRateService.parseHeartRateMeasurement([0x00, 72]), 72);
  });

  test('parses a 16-bit Bluetooth heart-rate measurement', () {
    expect(
      WhoopBleHeartRateService.parseHeartRateMeasurement([0x01, 0x2c, 0x01]),
      300,
    );
  });

  test('rejects incomplete Bluetooth heart-rate measurements', () {
    expect(WhoopBleHeartRateService.parseHeartRateMeasurement([]), isNull);
    expect(
      WhoopBleHeartRateService.parseHeartRateMeasurement([0x01, 0x2c]),
      isNull,
    );
  });
}
