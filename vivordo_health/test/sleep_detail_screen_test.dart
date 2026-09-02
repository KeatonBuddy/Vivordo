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

  group('hasConnectedWhoop', () {
    test('returns true only for an explicitly connected WHOOP account', () {
      expect(hasConnectedWhoop({'whoopConnected': true}), isTrue);
      expect(hasConnectedWhoop({'whoopConnected': false}), isFalse);
      expect(hasConnectedWhoop(<String, dynamic>{}), isFalse);
      expect(hasConnectedWhoop(null), isFalse);
    });
  });

  group('includesWhoopSleepSource', () {
    test('returns true only when the displayed range contains WHOOP data', () {
      expect(includesWhoopSleepSource(['apple_health', 'whoop']), isTrue);
      expect(includesWhoopSleepSource(['WHOOP']), isTrue);
      expect(includesWhoopSleepSource(['apple_health', null]), isFalse);
      expect(includesWhoopSleepSource(const []), isFalse);
    });
  });

  group('sleepInsightInfoText', () {
    test('mentions WHOOP only when WHOOP sleep data is displayed', () {
      expect(sleepInsightInfoText(hasWhoopSleepData: true), contains('WHOOP'));
      expect(
        sleepInsightInfoText(hasWhoopSleepData: false),
        isNot(contains('WHOOP')),
      );
    });
  });
}
