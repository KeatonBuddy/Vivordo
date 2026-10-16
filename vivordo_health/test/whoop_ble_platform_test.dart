import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/whoop_ble_heart_rate_service.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('live WHOOP Bluetooth is iOS-only', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(WhoopBleHeartRateService.isSupported, isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(WhoopBleHeartRateService.isSupported, isTrue);
  });
}
