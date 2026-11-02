import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Account-scoped consent to send data to Anthropic for Vivordo AI (chat,
/// check-ins, workout analysis, and sorting calendar events and priorities
/// for Effort and Demand). ClaudeService and PlanClassifier refuse every call
/// without it. A new disclosure version asks again: v2 added the sorting of
/// events and priorities.
///
/// Kept on this device, and saved to the account as
/// `users/{uid}.aiConsent {granted, version, at}`, which the AI functions on
/// the server check (functions/ai_consent.js), so withdrawing stops AI
/// processing everywhere.
class AiConsent {
  static const version = 2;
  static const _storage = FlutterSecureStorage();
  static String _key(String uid) => 'ai_consent_v2_$uid';

  /// Accounts whose saved choice has been checked this run.
  static final _synced = <String>{};

  /// Where the choice is saved; replaced in tests.
  @visibleForTesting
  static FirebaseFirestore Function() store = () => FirebaseFirestore.instance;

  @visibleForTesting
  static void resetSync() => _synced.clear();

  static Future<bool> granted(String uid) async {
    final granted = await _storage.read(key: _key(uid)) == 'granted';
    if (granted) unawaited(_sync(uid));
    return granted;
  }

  static Future<void> grant(String uid) async {
    await _storage.write(key: _key(uid), value: 'granted');
    _synced.add(uid);
    await _save(uid, granted: true);
  }

  static Future<void> revoke(String uid) async {
    await _storage.delete(key: _key(uid));
    _synced.add(uid);
    await _save(uid, granted: false);
  }

  /// Once a run, for consent given on this device: saves it to the account
  /// if it isn't there yet (given before it was saved), and drops it here if
  /// it was withdrawn on another device or is for an older disclosure.
  static Future<void> _sync(String uid) async {
    if (!_synced.add(uid)) return;
    try {
      final saved = (await store().collection('users').doc(uid).get())
          .data()?['aiConsent'];
      if (saved is! Map) {
        await _save(uid, granted: true);
      } else if (saved['granted'] != true ||
          ((saved['version'] as num?) ?? 0) < version) {
        await _storage.delete(key: _key(uid));
      }
    } catch (error) {
      _synced.remove(uid);
      debugPrint('AI consent sync failed: $error');
    }
  }

  static Future<void> _save(String uid, {required bool granted}) async {
    try {
      await store().collection('users').doc(uid).set({
        'aiConsent': {
          'granted': granted,
          'version': version,
          'at': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Saving AI consent failed: $error');
    }
  }
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
