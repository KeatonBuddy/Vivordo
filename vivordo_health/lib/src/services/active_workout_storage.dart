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

  /// Per-user workout preferences that outlive a single workout, kept apart
  /// from the draft because [clear] runs when a workout ends.
  static String? _preferenceKey(String name) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null ? null : 'workout_${name}_v1_$uid';
  }

  static Future<String?> _readPreference(String name) async {
    final key = _preferenceKey(name);
    if (key == null) return null;
    try {
      return await _storage.read(key: key);
    } catch (error) {
      debugPrint('Could not read workout preference $name: $error');
      return null;
    }
  }

  static Future<void> _writePreference(String name, String value) async {
    final key = _preferenceKey(name);
    if (key == null) return;
    await _storage.write(key: key, value: value);
  }

  /// The user's last Share to Circle choice, used for their next workout.
  static Future<bool> readShareDefault() async =>
      await _readPreference('share_default') == 'true';

  static Future<void> writeShareDefault(bool share) =>
      _writePreference('share_default', '$share');

  /// The rest length the user last set, in seconds, used for every rest.
  static Future<int?> readRestPreset() async =>
      int.tryParse(await _readPreference('rest_preset') ?? '');

  static Future<void> writeRestPreset(int seconds) =>
      _writePreference('rest_preset', '$seconds');
}
