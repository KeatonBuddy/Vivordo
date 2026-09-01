import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/screens/sleep_detail_screen.dart';

void main() {
  group('hasRecordedSleep', () {
    test('returns true for a positive daily sleep value', () {
      expect(
        hasRecordedSleep(<String, dynamic>{
          'sleep': <String, dynamic>{'avg': 7.5},
        }),
        isTrue,
      );
    });

    test('returns false when sleep is missing or invalid', () {
      expect(hasRecordedSleep(null), isFalse);
      expect(hasRecordedSleep(<String, dynamic>{}), isFalse);
      expect(
        hasRecordedSleep(<String, dynamic>{
          'sleep': <String, dynamic>{'avg': 0},
        }),
        isFalse,
      );
      expect(
        hasRecordedSleep(<String, dynamic>{
          'sleep': <String, dynamic>{'avg': null},
        }),
        isFalse,
      );
    });
  });
}
