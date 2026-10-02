import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:vivordo_health/src/utils/day_key.dart';
import 'ai_consent.dart';
import 'panda_prompts.dart';
import 'workout_coach_prompt.dart';

export 'panda_prompts.dart';

// =============================================================================
// ClaudeService
//
// Proxies every LLM call through the `pandaClaude`
// Firebase HTTPS Callable Cloud Function.  The function holds the Anthropic
// API key in Secret Manager — the key NEVER leaves the server (VIV-309).
//
// Cloud Function contract:
//   Request : { "system": String, "user": String }
//   Response: { "text": String }   (raw JSON from Claude)
//
// All data-processing logic (Firestore fetch, compact payload, JSON parsing)
// delegates to PandaPrompts to avoid duplication.
// =============================================================================

class ClaudeService {
  Future<String> workoutInsight(String context) async {
    if (context.length > 20000)
      throw StateError('Workout is too large for analysis.');
    final result = await _call({
      'system': [
        {
          'type': 'text',
          'text':
              '$workoutCoachPrompt\nGive one grounded observation and one practical suggestion in at most 80 words. Return plain text.',
        },
      ],
      'user': [
        {'type': 'text', 'text': context},
      ],
      'maxTokens': 250,
    });
    final text = (result.data as Map?)?['text']?.toString().trim() ?? '';
    if (text.isEmpty) throw StateError('No workout insight returned.');
    return text;
  }

  static final _fn = FirebaseFunctions.instance.httpsCallable('pandaClaude');
  static final _assistantFn = FirebaseFunctions.instance.httpsCallable(
    'assistant',
    options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
  );

  /// Every model call goes through here, so nothing reaches Anthropic without
  /// the signed-in user's AI consent on this device.
  static Future<HttpsCallableResult<dynamic>> _call(
    Map<String, dynamic> data, {
    HttpsCallable? function,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !await AiConsent.granted(uid)) {
      throw StateError('Vivordo AI consent has not been given.');
    }
    return (function ?? _fn).call<dynamic>(data);
  }

  // Appended to PandaPrompts.spikeSystemPrompt for Claude calls.
  // Together they must exceed 1,024 tokens so Anthropic caches the prefix.
  static const _spikeJsonSuffix = '''

OUTPUT FORMAT
Return ONLY a valid JSON object. No markdown fences, no backticks, no prose outside
the braces. Any text outside the JSON will break the parser.

Required top-level keys:
  "summary": {
    "data_window_start": "ISO-8601 string — start of the analysis window",
    "data_window_end":   "ISO-8601 string — end of the analysis window",
    "overall_notes":     "≤140 chars — one sentence describing the week at a glance"
  },
  "spikes": [ /* zero or more spike objects — see schema below */ ]

Spike object schema:
  "spike_id":  "spk_N" (N = 1-based index),
  "day":       "human day label — copy DATA spike.day verbatim, e.g. \"Wed, Jun 17\"",
  "start":     "YYYY-MM-DD — the day the spike occurred (DATE ONLY, no time)",
  "end":       "YYYY-MM-DD — same day (DATE ONLY, no time)",
  "signals": {
    "heart_rate": { "baseline": number, "peak": number },
    "hrv":        { "baseline": number, "min": number },
    "steps":      { "peak_window": number }
  },
  "context":   { "nearby_events": [], "confidence": 0.0–1.0 },
  "hypotheses": [
    { "label": string, "reason": "≤80 chars", "confidence": 0.0–1.0 }
  ],
  "questions": [
    {
      "question_id":   "q_N",
      "prompt":        "≤90 chars — what were you doing / feeling?",
      "type":          "multiple_choice",
      "options":       ["Chip A 😊", "Chip B 😕", "Something else 🙋"],
      "depth_prompts": ["follow-up 1", "follow-up 2"]
    }
  ],
  "ml_labels_to_collect": ["label_key_1", "label_key_2"]

RULES
• Max 3 questions per spike. Prefer multiple-choice with 4-5 options plus
  "Something else 🙋". Never ask open-ended questions on the predefined path.
• Vary phrasing across calls — never reuse the same question wording verbatim.
• Generate 2-3 depth_prompts per question for the "tell me more" flow.
• Keep question prompts ≤ 90 chars, overall_notes ≤ 140 chars.
• Do NOT diagnose. Use "may be related to" language. Never say "stress" alone
  — say "work-related stress" or "social pressure" etc.
• Do NOT invent symptoms, events, journal entries, goals, or any context not
  present in DATA. If a field is absent, omit it from your hypotheses.
• heart_rate values are the day's RESTING heart rate, not a peak or workout
  heart rate. Call them "resting heart rate" and compare them to the baseline.
• DAILY DATA ONLY: metrics are daily aggregates — you do NOT know the time of
  day a spike happened. Reference the DAY (copy spike.day) and NEVER state or
  invent a clock time ("2pm", "noon", "this morning", "afternoon", "evening").
• If no spikes are detected, return "spikes": [] with a reassuring overall_notes.

HYPOTHESIS LABEL TAXONOMY
Use exactly these label strings in hypotheses[].label:
  work_stress      — deadline, meeting, performance pressure, task overload
  social_conflict  — argument, disagreement, difficult conversation, social pressure
  exercise         — intentional workout, sport, physical training (HR spike is expected)
  illness          — feeling unwell, fever, physical discomfort
  anxiety          — general worry, rumination, panic, anticipatory stress
  commute          — travel, transport delays, driving in traffic
  family           — family conflict, caregiving pressure, domestic tension
  financial        — money worries, bills, job security
  environmental    — noise, heat, crowding, sensory overload
  unknown          — no clear trigger identifiable from available data

ML LABELS TO COLLECT PER SPIKE
"ml_labels_to_collect" must be a subset of these keys:
  stressor_type    — which hypothesis label applies (required for every spike)
  stress_intensity — low | medium | high | very_high
  aware_at_time    — was the user aware of stress as it happened? yes | no | retrospective
  coping_used      — did the user try a coping strategy? yes | no | not_yet
  trigger_recurs   — is this a recurring trigger? yes | no | unsure

QUESTION PHRASING GUIDE
• Use conversational language: "What was going on for you on [DAY]?" not
  "What was your primary activity during the spike window?"
• Reference the DAY using spike.day (e.g. "on Wed, Jun 17") — NEVER a clock time.
• Name the signal: "your resting heart rate was [PEAK] bpm vs your usual
  [BASELINE]" grounds it in data
• Chip option order: most likely hypothesis first, then alternatives, then
  "Something else 🙋" always last
• depth_prompts should be open-ended: "What made that feel particularly hard?"
  not leading: "Was it the deadline that caused it?"

EXAMPLE OUTPUT (reference only — vary wording each call)
{
  "summary": {
    "data_window_start": "2026-06-09",
    "data_window_end": "2026-06-16",
    "overall_notes": "Tuesday stood out — resting heart rate 9 bpm above usual."
  },
  "spikes": [{
    "spike_id": "spk_1",
    "day": "Tue, Jun 16",
    "start": "2026-06-16",
    "end": "2026-06-16",
    "signals": {
      "heart_rate": {"baseline": 62.0, "peak": 71.0},
      "hrv": {"baseline": 52.0, "min": 38.0},
      "steps": {"peak_window": 847.0}
    },
    "context": {"nearby_events": [], "confidence": 0.72},
    "hypotheses": [
      {"label": "work_stress",
       "reason": "Low steps that day — may be related to desk-bound deadline pressure",
       "confidence": 0.74}
    ],
    "questions": [{
      "question_id": "q_1",
      "prompt": "What was going on for you on Tue, Jun 16? Resting HR was 9 bpm up.",
      "type": "multiple_choice",
      "options": ["Work / study 📚", "Exercise 🏃", "Social situation 👥", "Commute 🚗", "Something else 🙋"],
      "depth_prompts": [
        "What made that day feel particularly stressful?",
        "How long did that pressure last?"
      ]
    }],
    "ml_labels_to_collect": ["stressor_type", "stress_intensity", "aware_at_time"]
  }]
}''';

  static Map<String, dynamic> _cacheBlock(String text) => {
    'type': 'text',
    'text': text,
    'cache_control': {'type': 'ephemeral'},
  };

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

    final userPrompt = PandaPrompts.buildSpikeUserPrompt(compact);
    final systemPrompt = '${PandaPrompts.spikeSystemPrompt}$_spikeJsonSuffix';

    final result = await _call({
      'system': [_cacheBlock(systemPrompt)],
      'user': [
        {'type': 'text', 'text': userPrompt},
      ],
      'maxTokens': kMaxOutputTokensSpike,
    });

    final raw = (result.data as Map?)?['text']?.toString() ?? '';
    final usage = (result.data as Map?)?['usage'] as Map?;
    if (kDebugMode) {
      debugPrint('[Claude][spike] response length: ${raw.length} chars');
      debugPrint(
        '[Claude][spike] usage — input: ${usage?['input_tokens'] ?? 0}, '
        'output: ${usage?['output_tokens'] ?? 0}, '
        'cache_create: ${usage?['cache_creation_input_tokens'] ?? 0}, '
        'cache_read: ${usage?['cache_read_input_tokens'] ?? 0}',
      );
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
    final result = await _call(function: _assistantFn, {
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
    });
    return PandaPrompts.parseTurnReply(jsonEncode(result.data));
  }

  // ---------------------------------------------------------------------------
  // summarizeSession
  //
  // Generates the brief end-of-session continuity note via the pandaClaude
  // proxy. Reuses PandaPrompts.summarySystemPrompt + buildSummaryPrompt so
  // both backends produce the same shape. Returns '' on any failure so the
  // caller falls back to the deterministic summary.
  // ---------------------------------------------------------------------------

  Future<String> summarizeSession({
    required List<Map<String, String>> conversation,
    required Map<String, String> slots,
    required Map<String, String> labeledAnswers,
  }) async {
    try {
      final userPrompt = PandaPrompts.buildSummaryPrompt(
        conversation: conversation,
        slots: slots,
        labeledAnswers: labeledAnswers,
      );

      final estimated = PandaPrompts.estimateTokens(
        PandaPrompts.summarySystemPrompt + userPrompt,
      );
      if (estimated > kMaxInputTokens) return '';

      final result = await _call({
        'system': [
          {'type': 'text', 'text': PandaPrompts.summarySystemPrompt},
        ],
        'user': [
          {'type': 'text', 'text': userPrompt},
        ],
        'maxTokens': kMaxOutputTokensSummary,
      });

      final raw = (result.data as Map?)?['text']?.toString() ?? '';
      if (kDebugMode) {
        final usage = (result.data as Map?)?['usage'] as Map?;
        debugPrint(
          '[Claude][summary] length: ${raw.length} chars, '
          'input: ${usage?['input_tokens'] ?? 0}, '
          'output: ${usage?['output_tokens'] ?? 0}',
        );
      }
      return raw.trim();
    } catch (e) {
      if (kDebugMode) debugPrint('[Claude][summary] failed: $e');
      return '';
    }
  }
}
