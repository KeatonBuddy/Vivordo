import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists an in-progress workout so iOS suspension or process termination
/// does not reset its timer or discard the user's current entries.
class ActiveWorkoutStorage {
  const ActiveWorkoutStorage._();

  static const _storage = FlutterSecureStorage();
  static const _keyPrefix = 'active_workout_v1_';

  static String? get _key {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null ? null : '$_keyPrefix$uid';
  }

  static Future<Map<String, dynamic>?> read() async {
    final key = _key;
    if (key == null) return null;
    final encoded = await _storage.read(key: key);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final value = jsonDecode(encoded);
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      await _storage.delete(key: key);
      return null;
    }
  }

  static Future<void> write(Map<String, dynamic> draft) async {
    final key = _key;
    if (key == null) return;
    await _storage.write(key: key, value: jsonEncode(draft));
  }

  static Future<void> clear() async {
    final key = _key;
    if (key != null) await _storage.delete(key: key);
  }

  /// The user's last Share to Circle choice, used for their next workout.
  /// Kept separately from the draft because [clear] runs when a workout ends.
  static String? get _shareKey {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null ? null : 'workout_share_default_v1_$uid';
  }

  static Future<bool> readShareDefault() async {
    final key = _shareKey;
    if (key == null) return false;
    try {
      return await _storage.read(key: key) == 'true';
    } catch (error) {
      debugPrint('Could not read workout sharing default: $error');
      return false;
    }
  }

  static Future<void> writeShareDefault(bool share) async {
    final key = _shareKey;
    if (key == null) return;
    await _storage.write(key: key, value: '$share');
  }
}
