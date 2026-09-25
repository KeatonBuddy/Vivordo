import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Account-scoped consent on this device. A new disclosure version asks again.
class WorkoutAiConsent {
  static const _storage = FlutterSecureStorage();
  static String _key(String uid) => 'workout_ai_consent_v1_$uid';
  static Future<bool> granted(String uid) async =>
      await _storage.read(key: _key(uid)) == 'granted';
  static Future<void> grant(String uid) =>
      _storage.write(key: _key(uid), value: 'granted');
  static Future<void> revoke(String uid) => _storage.delete(key: _key(uid));
}
