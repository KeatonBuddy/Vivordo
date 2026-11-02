import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'claude_service.dart';
import 'ai_consent.dart';
import '../../theme/vivordo_theme.dart';

Future<String> loadWorkoutAiAdvice(String uid, String context) async {
  const storage = FlutterSecureStorage();
  final id = (jsonDecode(context) as Map)['workoutId'];
  final key = 'workout_ai_v2_${uid}_$id';
  // Advice is written in Settings → Units, so changing them asks again.
  final units = jsonEncode(ThemeController.current.toMap());
  try {
    final raw = await storage.read(key: key);
    final cached = raw == null ? null : jsonDecode(raw);
    if (cached is Map &&
        cached['context'] == context &&
        cached['units'] == units &&
        cached['text'] is String) {
      return cached['text'] as String;
    }
  } catch (_) {
    /* An unavailable cache must not block advice. */
  }
  if (FirebaseAuth.instance.currentUser?.uid != uid ||
      !await AiConsent.granted(uid)) {
    throw StateError('Workout advice is not authorized.');
  }
  final text = await ClaudeService().workoutInsight(context);
  if (FirebaseAuth.instance.currentUser?.uid != uid) {
    throw StateError('Account changed.');
  }
  try {
    await storage.write(
      key: key,
      value: jsonEncode({'context': context, 'units': units, 'text': text}),
    );
  } catch (_) {
    /* Still show generated advice. */
  }
  return text;
}
