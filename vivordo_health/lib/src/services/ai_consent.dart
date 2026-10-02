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

/// What Vivordo AI sends and why, shown wherever consent is asked
/// (onboarding; the chat's own consent view words the same thing).
const aiConsentDisclosure =
    'Vivordo AI uses Anthropic’s Claude to answer you, and to sort your '
    'calendar events and priorities so your Effort and Demand are accurate. '
    'To do that, Vivordo sends your messages and the health, sleep, fitness, '
    'workout, calendar, priority, journal and past-conversation information '
    'relevant to your question, and the titles of the events and priorities '
    'it sorts (never their notes), to Anthropic for processing. Nothing is '
    'sent until you allow it.\n\n'
    'AI responses can be inaccurate and are not medical advice. You can '
    'reset this choice in Profile under Vivordo AI.';
