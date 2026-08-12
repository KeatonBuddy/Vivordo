import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class JournalLockService {
  JournalLockService._();

  static const _storage = FlutterSecureStorage();
  static final _authentication = LocalAuthentication();

  static String? get _key {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null ? null : 'journal_lock_enabled_$uid';
  }

  static String? get _introKey {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null ? null : 'journal_lock_intro_seen_$uid';
  }

  static Future<bool> isEnabled() async {
    final key = _key;
    if (key == null) return false;
    return await _storage.read(key: key) == 'true';
  }

  static Future<void> setEnabled(bool enabled) async {
    final key = _key;
    if (key == null) throw StateError('Sign in to change Journal Lock.');
    await _storage.write(key: key, value: enabled ? 'true' : 'false');
  }

  static Future<bool> hasSeenIntroduction() async {
    final key = _introKey;
    if (key == null) return false;
    return await _storage.read(key: key) == 'true';
  }

  static Future<void> markIntroductionSeen() async {
    final key = _introKey;
    if (key == null) return;
    await _storage.write(key: key, value: 'true');
  }

  static Future<bool> authenticate({required String reason}) async {
    try {
      if (!await _authentication.isDeviceSupported()) return false;
      return await _authentication.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}
