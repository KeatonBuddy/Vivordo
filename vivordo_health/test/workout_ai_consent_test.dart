import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vivordo_health/src/services/workout_ai_consent.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('consent defaults off, persists per account, and can be revoked', () async {
    expect(await WorkoutAiConsent.granted('a'), isFalse);
    await WorkoutAiConsent.grant('a');
    expect(await WorkoutAiConsent.granted('a'), isTrue);
    expect(await WorkoutAiConsent.granted('b'), isFalse);
    await WorkoutAiConsent.revoke('a');
    expect(await WorkoutAiConsent.granted('a'), isFalse);
  });
}
