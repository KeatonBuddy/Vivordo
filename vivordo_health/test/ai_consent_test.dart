import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vivordo_health/src/services/ai_consent.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeFirebaseFirestore db;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    AiConsent.store = () => db;
    AiConsent.resetSync();
  });
  Future<Map?> saved(String uid) async =>
      (await db.collection('users').doc(uid).get()).data()?['aiConsent']
          as Map?;
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

  test('giving and withdrawing consent saves it to the account', () async {
    await AiConsent.grant('a');
    expect((await saved('a'))?['granted'], isTrue);
    expect((await saved('a'))?['version'], AiConsent.version);
    await AiConsent.revoke('a');
    expect((await saved('a'))?['granted'], isFalse);
  });

  test('consent from before it was saved is backfilled once', () async {
    FlutterSecureStorage.setMockInitialValues({'ai_consent_v2_a': 'granted'});
    expect(await AiConsent.granted('a'), isTrue);
    await pumpEventQueue();
    expect((await saved('a'))?['granted'], isTrue);
  });

  test('withdrawn on another device drops it here', () async {
    FlutterSecureStorage.setMockInitialValues({'ai_consent_v2_a': 'granted'});
    await db.collection('users').doc('a').set({
      'aiConsent': {'granted': false, 'version': AiConsent.version},
    });
    expect(await AiConsent.granted('a'), isTrue);
    await pumpEventQueue();
    expect(await AiConsent.granted('a'), isFalse);
  });
}
