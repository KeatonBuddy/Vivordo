import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Account-scoped consent, on this device, to send data to Anthropic for
/// Vivordo AI (chat, check-ins and workout analysis). ClaudeService refuses
/// every call without it. A new disclosure version asks again.
class AiConsent {
  static const _storage = FlutterSecureStorage();
  static String _key(String uid) => 'ai_consent_v1_$uid';
  static Future<bool> granted(String uid) async =>
      await _storage.read(key: _key(uid)) == 'granted';
  static Future<void> grant(String uid) =>
      _storage.write(key: _key(uid), value: 'granted');
  static Future<void> revoke(String uid) => _storage.delete(key: _key(uid));
}
