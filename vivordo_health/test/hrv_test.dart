import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/hrv.dart';

// Same cases as functions/test/hrv.test.js, so app and server agree.
void main() {
  Map<String, dynamic> apple(double avg) => {
    'hrv': {'avg': avg, 'source': 'apple_health'},
  };
  Map<String, dynamic> whoop(double avg) => {
    'hrv_rmssd': {'avg': avg, 'source': 'whoop', 'method': 'rmssd'},
  };

  test('readings are keyed by kind and ignore unknown or invalid values', () {
    expect(hrvReadings({...apple(61), ...whoop(44)}), {
      'rmssd:whoop': 44,
      'sdnn': 61,
    });
    expect(
      hrvReadings({
        'hrv_rmssd': {'avg': 40, 'source': 'garmin'},
        'hrv': {'avg': 0},
      }),
      isEmpty,
    );
    expect(hrvReadings(null), isEmpty);
  });
}
