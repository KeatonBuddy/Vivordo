import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vivordo_health/src/services/ai_consent.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'consent defaults off, persists per account, and can be revoked',
    () async {
      expect(await AiConsent.granted('a'), isFalse);
      await AiConsent.grant('a');
      expect(await AiConsent.granted('a'), isTrue);
      expect(await AiConsent.granted('b'), isFalse);
      await AiConsent.revoke('a');
      expect(await AiConsent.granted('a'), isFalse);
    },
  );

  test('earlier workout-only consent does not count as AI consent', () async {
    FlutterSecureStorage.setMockInitialValues({
      'workout_ai_consent_v1_a': 'granted',
    });
    expect(await AiConsent.granted('a'), isFalse);
  });
}
