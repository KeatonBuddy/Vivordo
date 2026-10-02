import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:vivordo_health/src/utils/day_key.dart';
import 'ai_consent.dart';
import 'panda_prompts.dart';

export 'panda_prompts.dart';

// =============================================================================
// ClaudeService
//
// Calls Vivordo AI's Cloud Functions; the prompts and the Anthropic key stay
// on the server (VIV-309), so the app only ever sends data:
//   assistant — one chat turn (functions/assistant.js)
//   aiTask    — check-in questions, chat summaries, workout analysis
//               (functions/ai_tasks.js); returns {text}
//
// Firestore reads, the compact spike payload and response parsing live in
// PandaPrompts.
// =============================================================================

class ClaudeService {
  Future<String> workoutInsight(String context) async {
    if (context.length > 20000)
      throw StateError('Workout is too large for analysis.');
    final text = await _task('workout_insight', {'context': context});
    if (text.isEmpty) throw StateError('No workout insight returned.');
    return text;
  }

  static final _taskFn = FirebaseFunctions.instance.httpsCallable('aiTask');
  static final _assistantFn = FirebaseFunctions.instance.httpsCallable(
    'assistant',
    options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
  );

  /// Every model call goes through here, so nothing reaches Anthropic without
  /// the signed-in user's AI consent on this device.
  static Future<HttpsCallableResult<dynamic>> _call(
    HttpsCallable function,
    Map<String, dynamic> data,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !await AiConsent.granted(uid)) {
      throw StateError('Vivordo AI consent has not been given.');
    }
    return function.call<dynamic>(data);
  }

  /// One server-side AI task (functions/ai_tasks.js): the server owns the
  /// prompt, the app sends only [input]. Returns the model's text.
  static Future<String> _task(String task, Map<String, dynamic> input) async {
    final result = await _call(_taskFn, {'task': task, 'input': input});
    return (result.data as Map?)?['text']?.toString().trim() ?? '';
  }

  // ---------------------------------------------------------------------------
  // analyzePandaSession
  // ---------------------------------------------------------------------------

  Future<PandaSessionData> analyzePandaSession({
    String? extraUserContext,
    String? userName,
    String? userId,
  }) async {
    if (userId == null || userId.isEmpty) {
      return PandaPrompts.emptyStateSession(userName ?? 'there');
    }

    final payload = await PandaPrompts.fetchRealUserPayload(userId);
    if (payload == null) {
      return PandaPrompts.emptyStateSession(userName ?? 'there');
    }

    final compact = PandaPrompts.buildCompactPayload(payload, topK: 1);

    // Nothing to analyze (no spike candidates — e.g. every detected spike day
    // was already surfaced once). Skip the LLM round trip entirely: it would
    // just return `spikes: []` after several seconds. Opens the chat instantly.
    if ((compact['spike_candidates'] as List? ?? const []).isEmpty) {
      if (kDebugMode) {
        debugPrint('[Claude][spike] no spike candidates — skipping LLM call');
      }
      return PandaPrompts.noSpikesSession(payload, overrideName: userName);
    }

    return _runSpikeAnalysis(
      userId: userId,
      payload: payload,
      compact: compact,
      userName: userName,
      extraUserContext: extraUserContext,
    );
  }

  Future<PandaSessionBootstrap> startSession({
    bool analyzeSpikes = true,
    String? extraUserContext,
    String? userName,
    String? userId,
  }) async {
    if (userId == null || userId.isEmpty) {
      return PandaSessionBootstrap(
        session: PandaPrompts.emptyStateSession(userName ?? 'there'),
      );
    }

    final payload = await PandaPrompts.fetchRealUserPayload(userId);
    if (payload == null) {
      return PandaSessionBootstrap(
        session: PandaPrompts.emptyStateSession(userName ?? 'there'),
      );
    }

    final compact = PandaPrompts.buildCompactPayload(payload, topK: 1);

    // Nothing to analyze → no LLM call at all; the chat is already final.
    if (!analyzeSpikes ||
        (compact['spike_candidates'] as List? ?? const []).isEmpty) {
      if (kDebugMode) {
        debugPrint('[Claude][spike] no spike candidates — skipping LLM call');
      }
      return PandaSessionBootstrap(
        session: PandaPrompts.noSpikesSession(payload, overrideName: userName),
      );
    }

    // Opener NOW; the labeling questions stream in behind it.
    return PandaSessionBootstrap(
      session: PandaPrompts.bootstrapSession(
        payload,
        overrideName: userName,
        hasSpikes: true,
      ),
      spikeAnalysis: _runSpikeAnalysis(
        userId: userId,
        payload: payload,
        compact: compact,
        userName: userName,
        extraUserContext: extraUserContext,
      ),
    );
  }

  /// The spike-analysis LLM round trip — shared by analyzePandaSession (await)
  /// and startSession (background).
  Future<PandaSessionData> _runSpikeAnalysis({
    required String userId,
    required Map<String, dynamic> payload,
    required Map<String, dynamic> compact,
    String? userName,
    String? extraUserContext,
  }) async {
    compact['user_context'] = extraUserContext?.trim() ?? '';
    compact['_variability_seed'] =
        DateTime.now().millisecondsSinceEpoch % 100000;

    final raw = await _task('checkin_questions', {'compact': compact});
    if (kDebugMode) {
      debugPrint('[Claude][spike] response length: ${raw.length} chars');
    }

    // The spike day is recorded as analyzed only once the user answers or
    // skips a question about it (PandaScreen), so closing the chat early
    // doesn't lose it.
    return PandaPrompts.parsePandaSession(raw, payload, overrideName: userName);
  }

  // ---------------------------------------------------------------------------
  // processTurn
  //
  // One chat turn through the `assistant` function, which owns the prompt and
  // fetches health metrics and workouts itself. [context] carries what only
  // the app has, keyed as the function expects: checkin, screen, schedule,
  // priorities, insights, spikes, workout.
  // ---------------------------------------------------------------------------

  Future<PandaTurnReply> processTurn({
    required String userMessage,
    required List<Map<String, String>> conversationHistory,
    Map<String, String> context = const {},
    bool workoutCoach = false,
    String? conversationId,
  }) async {
    // The screen adds the message to the transcript before calling; the
    // function appends it itself, so don't send it twice.
    final history = [...conversationHistory];
    if (history.isNotEmpty &&
        history.last['role'] == 'user' &&
        history.last['text'] == userMessage) {
      history.removeLast();
    }
    final now = DateTime.now();
    final result = await _call(_assistantFn, {
      'message': userMessage,
      'history': history.where((t) => (t['text'] ?? '').isNotEmpty).toList(),
      'context': {
        for (final entry in context.entries)
          if (entry.value.trim().isNotEmpty) entry.key: entry.value,
      },
      'today': localDayKey(now),
      'now': now.toIso8601String(),
      'utcOffsetMinutes': now.timeZoneOffset.inMinutes,
      'workoutCoach': workoutCoach,
      'conversationId': ?conversationId,
    });
    return PandaPrompts.parseTurnReply(jsonEncode(result.data));
  }

  // ---------------------------------------------------------------------------
  // summarizeSession
  //
  // The brief continuity note for a finished chat (or a stressor it
  // surfaced), written server-side. Returns '' on any failure so the caller
  // falls back to the deterministic summary.
  // ---------------------------------------------------------------------------

  Future<String> summarizeSession({
    required List<Map<String, String>> conversation,
    required Map<String, String> slots,
    required Map<String, String> labeledAnswers,
  }) async {
    try {
      return await _task('session_summary', {
        'conversation': conversation,
        'slots': slots,
        'labeledAnswers': labeledAnswers,
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[Claude][summary] failed: $e');
      return '';
    }
  }
}
