import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'claude_service.dart';
import 'workout_ai_consent.dart';

Future<bool> ensureWorkoutAiConsent(BuildContext context, String uid) async {
  if (await WorkoutAiConsent.granted(uid))
    return FirebaseAuth.instance.currentUser?.uid == uid;
  if (!context.mounted) return false;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Allow AI workout advice?'),
      content: const Text(
        'Vivordo sends the selected workout’s exercises, sets, weights, reps, duration, and saved performance comparisons to Anthropic (Claude) for analysis and follow-up advice. AI advice can be inaccurate. Remember this choice for your account on this device. You can reset it in Settings under AI Workout Analysis.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Allow'),
        ),
      ],
    ),
  );
  if (accepted != true || FirebaseAuth.instance.currentUser?.uid != uid)
    return false;
  await WorkoutAiConsent.grant(uid);
  return true;
}

Future<String> loadWorkoutAiAdvice(String uid, String context) async {
  const storage = FlutterSecureStorage();
  final id = (jsonDecode(context) as Map)['workoutId'];
  final key = 'workout_ai_v2_${uid}_$id';
  try {
    final raw = await storage.read(key: key);
    final cached = raw == null ? null : jsonDecode(raw);
    if (cached is Map &&
        cached['context'] == context &&
        cached['text'] is String)
      return cached['text'] as String;
  } catch (_) {
    /* An unavailable cache must not block advice. */
  }
  if (FirebaseAuth.instance.currentUser?.uid != uid ||
      !await WorkoutAiConsent.granted(uid))
    throw StateError('Workout advice is not authorized.');
  final text = await ClaudeService().workoutInsight(context);
  if (FirebaseAuth.instance.currentUser?.uid != uid)
    throw StateError('Account changed.');
  try {
    await storage.write(
      key: key,
      value: jsonEncode({'context': context, 'text': text}),
    );
  } catch (_) {
    /* Still show generated advice. */
  }
  return text;
}
