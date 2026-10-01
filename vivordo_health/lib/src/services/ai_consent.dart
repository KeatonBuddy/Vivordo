import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Account-scoped consent, on this device, to send data to Anthropic for
/// Vivordo AI (chat, check-ins, workout analysis, and sorting calendar
/// events and priorities for Effort and Demand). ClaudeService and
/// PlanClassifier refuse every call without it. A new disclosure version
/// asks again: v2 added the sorting of events and priorities.
class AiConsent {
  static const _storage = FlutterSecureStorage();
  static String _key(String uid) => 'ai_consent_v2_$uid';
  static Future<bool> granted(String uid) async =>
      await _storage.read(key: _key(uid)) == 'granted';
  static Future<void> grant(String uid) =>
      _storage.write(key: _key(uid), value: 'granted');
  static Future<void> revoke(String uid) => _storage.delete(key: _key(uid));
}
