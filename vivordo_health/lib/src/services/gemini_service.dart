import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

import '../demo/demo_user_repository.dart';
import '../demo/demo_user_data.dart';
import 'ai_service.dart';

export 'ai_service.dart' show kMaxInputTokens, kMaxOutputTokensChat, kMaxOutputTokensSpike;

export 'panda_types.dart';

// =============================================================================
// ARCHITECTURE OVERVIEW
// =============================================================================
//
// This service implements a HYBRID DIALOGUE MANAGER based on 2025 best
// practices from Rasa, Aisera, and the ICM+LLM literature:
//
//   Predefined path  →  Structured labeling questions generated from spike data.
//                       Questions vary each session (seeded prompting + temp).
//                       User can go as deep as they want per question.
//
//   Undefined path   →  Fully open conversation: advice, tips, venting, etc.
//                       Triggered by intent = "digress" | "advice" | "support"
//
//   Dialogue stack   →  When user digreses mid-predefined-path, the path context
//                       is pushed onto a stack. After the digression is resolved
//                       (intent = "digression_complete"), it is popped and the
//                       predefined path resumes seamlessly.
//
//   Slot filling     →  Every turn, the model extracts wellness entities
//                       (stressor, emotion, intensity, activity, coping_strategy,
//                       etc.) and accumulates them in a slot store.
//
// Static helpers (fetchRealUserPayload, buildCompactPayload, parsePandaSession,
// parseTurnReply, buildSpikeUserPrompt, buildDialoguePrompt, etc.) are public
// so that ClaudeService can reuse the same data-processing logic without
// instantiating Gemini models.
//
// =============================================================================

// ---------------------------------------------------------------------------
// GeminiService
// ---------------------------------------------------------------------------

class GeminiService implements AIService {
  GeminiService()
      : _spikeModel = FirebaseAI.googleAI().generativeModel(
          model: 'gemini-2.5-flash',
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
            responseSchema: _spikeSchema,
            candidateCount: 1,
            temperature: 0,
            maxOutputTokens: kMaxOutputTokensSpike,
          ),
        ),
        _dialogueModel = FirebaseAI.googleAI().generativeModel(
          model: 'gemini-2.5-flash',
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
            responseSchema: _turnSchema,
            candidateCount: 1,
            temperature: 0.5,
            maxOutputTokens: kMaxOutputTokensChat,
          ),
        );

  final GenerativeModel _spikeModel;
  final GenerativeModel _dialogueModel;

  final DemoUserRepository _demoRepo = DemoUserRepository();
  DemoUserData? _activeDemoUser;

  DemoUserData getActiveDemoUser() {
    _activeDemoUser ??= _demoRepo.getRandomDemoUser();
    return _activeDemoUser!;
  }

  DemoUserData switchDemoUser() {
    _activeDemoUser = _demoRepo.getRandomDemoUser();
    return _activeDemoUser!;
  }

  DemoUserData peekDemoUser() => getActiveDemoUser();
  DemoUserData pickNewDemoUser() => switchDemoUser();

  Map<String, dynamic> buildCompactPayloadForTest(Map<String, dynamic> raw,
          {int topK = 3}) =>
      buildCompactPayload(raw, topK: topK);

  // =========================================================================
  // Spike analysis schema
  // =========================================================================

  static const String spikeSystemPrompt = '''
You are Vivordo Stress Labeling Assistant.

GOAL: Given pre-detected spike candidates + events, generate varied labeling
questions to collect ML labels. Also generate depth probes for each question
so the user can explore each topic as deeply as they wish.

RULES:
- Do NOT diagnose or give medical advice. Use "may be related to" language.
- Max 3 questions per spike. Prefer multiple-choice + open option.
- VARY the phrasing each call — never reuse the same wording.
- Generate 2–3 depth_prompts per question (open-ended follow-ups if user wants more).
- Keep question prompts ≤ 90 chars. overall_notes ≤ 140 chars.
''';

  static final Schema _spikeSchema = Schema(
    SchemaType.object,
    properties: {
      "summary": Schema(SchemaType.object, properties: {
        "data_window_start": Schema(SchemaType.string),
        "data_window_end": Schema(SchemaType.string),
        "overall_notes": Schema(SchemaType.string),
      }),
      "spikes": Schema(SchemaType.array,
          items: Schema(SchemaType.object, properties: {
            "spike_id": Schema(SchemaType.string),
            "start": Schema(SchemaType.string),
            "end": Schema(SchemaType.string),
            "signals": Schema(SchemaType.object, properties: {
              "heart_rate": Schema(SchemaType.object, properties: {
                "baseline": Schema(SchemaType.number),
                "peak": Schema(SchemaType.number),
              }),
              "hrv": Schema(SchemaType.object, properties: {
                "baseline": Schema(SchemaType.number),
                "min": Schema(SchemaType.number),
              }),
              "steps": Schema(SchemaType.object, properties: {
                "peak_window": Schema(SchemaType.number),
              }),
            }),
            "context": Schema(SchemaType.object, properties: {
              "nearby_events": Schema(SchemaType.array,
                  items: Schema(SchemaType.object, properties: {
                    "time": Schema(SchemaType.string),
                    "type": Schema(SchemaType.string),
                    "detail": Schema(SchemaType.string),
                  })),
              "confidence": Schema(SchemaType.number),
            }),
            "hypotheses": Schema(SchemaType.array,
                items: Schema(SchemaType.object, properties: {
                  "label": Schema(SchemaType.string),
                  "reason": Schema(SchemaType.string),
                  "confidence": Schema(SchemaType.number),
                })),
            "questions": Schema(SchemaType.array,
                items: Schema(SchemaType.object, properties: {
                  "question_id": Schema(SchemaType.string),
                  "prompt": Schema(SchemaType.string),
                  "type": Schema(SchemaType.string),
                  "options": Schema(SchemaType.array,
                      items: Schema(SchemaType.string)),
                  "depth_prompts": Schema(SchemaType.array,
                      items: Schema(SchemaType.string)),
                })),
            "ml_labels_to_collect":
                Schema(SchemaType.array, items: Schema(SchemaType.string)),
          })),
    },
  );

  // =========================================================================
  // Dialogue turn schema
  // =========================================================================

  static final Schema _turnSchema = Schema(
    SchemaType.object,
    properties: {
      "intent": Schema(SchemaType.string),
      "message": Schema(SchemaType.string),
      "depth_follow_up": Schema(SchemaType.string),
      "injected_question": Schema(SchemaType.object, properties: {
        "question_id": Schema(SchemaType.string),
        "prompt": Schema(SchemaType.string),
        "options": Schema(SchemaType.array, items: Schema(SchemaType.string)),
      }),
      "filled_slots": Schema(SchemaType.object, properties: {
        "stressor": Schema(SchemaType.string),
        "emotion": Schema(SchemaType.string),
        "intensity": Schema(SchemaType.string),
        "physical_symptom": Schema(SchemaType.string),
        "activity": Schema(SchemaType.string),
        "location": Schema(SchemaType.string),
        "time_context": Schema(SchemaType.string),
        "coping_strategy": Schema(SchemaType.string),
        "sleep_quality": Schema(SchemaType.string),
        "social_context": Schema(SchemaType.string),
        "other": Schema(SchemaType.string),
      }),
      "rec_hint": Schema(SchemaType.string),
    },
  );

  // =========================================================================
  // Sample data (demo / test path only)
  // =========================================================================

  Map<String, dynamic> getSampleData() {
    final demo = getActiveDemoUser();
    final day = DateTime.tryParse(demo.date) ?? DateTime.now();
    final start = DateTime(day.year, day.month, day.day, 18, 0);
    final end = start.add(const Duration(hours: 24));
    final baselineHr = demo.restingHeartRate.toDouble();
    final baselineHrv = demo.hrv.toDouble();
    final samples = <Map<String, dynamic>>[];
    final stressLift = (demo.dailyStressLevel / 25.0);
    final hrvDrop = (demo.dailyStressLevel / 40.0);
    final stepsPerHour = (demo.stepsCount / 24.0);

    for (int i = 0; i < 24; i++) {
      final t = start.add(Duration(hours: i));
      double hr = baselineHr + stressLift;
      double hrv = baselineHrv - hrvDrop;
      double steps = stepsPerHour;
      String activity = "sedentary";
      String tag = "";

      if (i == 14) {
        activity = "light";
        tag = "commute";
        steps += 200;
        hr += 10;
      }
      if (i == 15) {
        activity = "sedentary";
        tag = "work_focus";
        if (demo.stressed) {
          hr += 30;
          hrv -= 18;
        } else {
          hr += 12;
          hrv -= 6;
        }
      }
      if (i == 20) {
        activity = "sedentary";
        tag = "deadline";
        final extra = (demo.stressVariability / 10.0);
        hr += extra;
        hrv -= extra / 2.0;
      }
      if (i == 22 && demo.exerciseSessions > 0) {
        activity = "workout";
        tag = "gym";
        hr += 50;
        hrv -= 22;
        steps += 900;
      }

      hr = hr.clamp(45, 190);
      hrv = hrv.clamp(10, 140);
      steps = steps.clamp(0, 2500);

      samples.add({
        "t": t.toIso8601String(),
        "hr": hr.round(),
        "hrv": hrv.round(),
        "steps": steps.round(),
        "stress_score": demo.dailyStressLevel,
        "activity": activity,
        "tag": tag,
      });
    }

    final events = <Map<String, dynamic>>[
      {
        "time": start
            .add(const Duration(hours: 13, minutes: 40))
            .toIso8601String(),
        "type": "caffeine",
        "detail": demo.stressed ? "coffee (strong)" : "coffee (small)",
      },
      {
        "time": start.add(const Duration(hours: 15)).toIso8601String(),
        "type": "work",
        "detail": "work / class start",
      },
      {
        "time": start.add(const Duration(hours: 20)).toIso8601String(),
        "type": "work",
        "detail": "deadline / high focus",
      },
      if (demo.exerciseSessions > 0)
        {
          "time": start.add(const Duration(hours: 22)).toIso8601String(),
          "type": "activity",
          "detail": "gym workout started",
        },
    ];

    return {
      "demo_user": demo.toMap(),
      "user_profile": {
        "timezone": demo.timezone,
        "age_range": (demo.age < 18) ? "teen" : "adult",
        "resting_hr_typical": demo.restingHeartRate,
        "hrv_rmssd_typical": demo.hrv,
      },
      "data_window": {
        "start": start.toIso8601String(),
        "end": end.toIso8601String(),
      },
      "samples_5min": samples,
      "events": events,
      "sleep_summary": {
        "total_minutes": (demo.sleepDurationHours * 60).round(),
        "sleep_quality": demo.sleepQualityScore,
      },
    };
  }

  // =========================================================================
  // Spike analysis
  // =========================================================================

  Future<String> analyzeStressSpikes({
    required Map<String, dynamic> data,
    String? extraUserContext,
  }) async {
    final Map<String, dynamic> compact = data.containsKey("spike_candidates")
        ? Map<String, dynamic>.from(data)
        : buildCompactPayload(data, topK: 3);

    compact["user_context"] = extraUserContext?.trim() ?? "";
    compact["_variability_seed"] =
        DateTime.now().millisecondsSinceEpoch % 100000;

    final userPrompt = buildSpikeUserPrompt(compact);

    // Token guard — reject before hitting the model if the prompt is too large.
    final estimated = estimateTokens(spikeSystemPrompt + userPrompt);
    if (estimated > kMaxInputTokens) {
      if (kDebugMode) {
        debugPrint('[Gemini][spike] token guard fired: ~$estimated tokens (limit $kMaxInputTokens)');
      }
      return '';
    }

    final response = await _spikeModel.generateContent([
      Content.text(spikeSystemPrompt),
      Content.text(userPrompt),
    ]);
    if (kDebugMode) {
      final usage = response.usageMetadata;
      debugPrint('[Gemini][spike] tokens — in: ${usage?.promptTokenCount}, '
          'out: ${usage?.candidatesTokenCount}');
    }
    return response.text ?? '';
  }

  // =========================================================================
  // Panda session init  (implements AIService)
  // =========================================================================

  @override
  Future<PandaSessionData> analyzePandaSession({
    String? extraUserContext,
    String? userName,
    String? userId,
  }) async {
    if (userId != null && userId.isNotEmpty) {
      // ── Production path: real metrics_daily data ──────────────────────
      final payload = await fetchRealUserPayload(userId);
      if (payload == null) {
        return emptyStateSession(userName ?? 'there');
      }
      final compact = buildCompactPayload(payload, topK: 1);
      final raw = await analyzeStressSpikes(
          data: compact, extraUserContext: extraUserContext);
      return parsePandaSession(raw, payload, overrideName: userName);
    }

    // ── Demo / test path — only reachable from test pages ────────────────
    final rawSample = getSampleData();
    final compact = buildCompactPayload(rawSample, topK: 1);
    final raw = await analyzeStressSpikes(
        data: compact, extraUserContext: extraUserContext);
    return parsePandaSession(raw, rawSample, overrideName: userName);
  }

  // =========================================================================
  // Dialogue turn  (implements AIService)
  // =========================================================================

  @override
  Future<PandaTurnReply> processTurn({
    required String userMessage,
    required List<Map<String, String>> conversationHistory,
    required List<Map<String, dynamic>> spikeContext,
    required bool isOnPredefinedPath,
    required bool isInDigression,
    required int digressionTurnCount,
    String? pendingQuestionId,
    String? pendingQuestionPrompt,
    String? digressionTopic,
    Map<String, String>? accumulatedSlots,
  }) async {
    // Token guard on RAW inputs — fires before buildDialoguePrompt caps history
    // to 6 items, so a 50-turn history is still caught here as a safety net.
    final rawHistoryText = conversationHistory
        .map((t) => '${t['role']}: ${t['text']}')
        .join('\n');
    final estimated = estimateTokens(
        rawHistoryText + userMessage + jsonEncode(trimSpikeContext(spikeContext)));
    if (estimated > kMaxInputTokens) {
      if (kDebugMode) {
        debugPrint('[Gemini][dialogue] token guard fired: ~$estimated tokens (limit $kMaxInputTokens)');
      }
      return PandaTurnReply(
        intent: PandaIntent.chitchat,
        message: "We've covered a lot of ground! Our conversation is getting "
            "quite long — let's wrap up here and you can start a fresh session "
            "anytime 💜",
      );
    }

    final prompt = buildDialoguePrompt(
      userMessage: userMessage,
      conversationHistory: conversationHistory,
      spikeContext: spikeContext,
      isOnPredefinedPath: isOnPredefinedPath,
      isInDigression: isInDigression,
      digressionTurnCount: digressionTurnCount,
      pendingQuestionId: pendingQuestionId,
      pendingQuestionPrompt: pendingQuestionPrompt,
      digressionTopic: digressionTopic,
      accumulatedSlots: accumulatedSlots,
    );

    final response =
        await _dialogueModel.generateContent([Content.text(prompt)]);
    if (kDebugMode) {
      final usage = response.usageMetadata;
      debugPrint('[Gemini][dialogue] tokens — in: ${usage?.promptTokenCount}, '
          'out: ${usage?.candidatesTokenCount}');
    }
    return parseTurnReply(response.text ?? '');
  }

  // =========================================================================
  // Real user data fetch  (public static — reused by ClaudeService)
  //
  // Queries users/{userId}/metrics_daily/{YYYY-MM-DD} subcollection for the
  // last 7 days.  Each document holds all metrics for that day as top-level
  // fields (heart_rate, mood, sleep, steps, stress, wellness, hrv).
  //
  // Also fetches users/{userId}/preferences and
  // users/{userId}/questionaire_responses for compact user context.
  //
  // Returns null when the user has no data yet (caller shows empty state).
  // =========================================================================

  static Future<Map<String, dynamic>?> fetchRealUserPayload(
      String userId) async {
    final db = FirebaseFirestore.instance;
    final now = DateTime.now();
    final userRef = db.collection('users').doc(userId);

    // Each day's metrics live in a single merged doc at
    // users/{userId}/metrics_daily/{YYYY-MM-DD}, keyed by metric type
    // (e.g. 'heart_rate', 'resting_heart_rate', 'hrv', 'steps', 'sleep') — see
    // MetricsService._addMetric, HealthService._writeDataPoints and
    // ScanScreen._saveToFirestore.
    final dateStrings = List.generate(
        7, (i) => _fmtDate(now.subtract(Duration(days: i))));

    // Fire all Firestore reads concurrently before any await
    final metricFutures = dateStrings
        .map((d) => userRef.collection('metrics_daily').doc(d).get())
        .toList();
    final prefFuture = userRef.collection('preferences').get();
    final questFuture = userRef.collection('questionaire_responses').get();

    final metricSnaps = await Future.wait(metricFutures);
    final prefSnap = await prefFuture;
    final questSnap = await questFuture;

    // Build daily data map: dateStr → {field → value} from the single day doc
    final dailyData = <String, Map<String, dynamic>>{};
    for (int i = 0; i < dateStrings.length; i++) {
      final data = metricSnaps[i].data();
      if (data == null) continue;
      dailyData[dateStrings[i]] = data;
    }

    if (dailyData.isEmpty) return null;

    // HR baseline: 7-day average, preferring resting_heart_rate over heart_rate.
    final hrValues = dailyData.values
        .map((d) =>
            (d['resting_heart_rate']?['avg'] as num?)?.toDouble() ??
            (d['heart_rate']?['avg'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    final baselineHr = hrValues.isEmpty
        ? 65.0
        : hrValues.reduce((a, b) => a + b) / hrValues.length;

    final hrvValues = dailyData.values
        .map((d) => (d['hrv']?['avg'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    final baselineHrv = hrvValues.isEmpty
        ? 52.0
        : hrvValues.reduce((a, b) => a + b) / hrvValues.length;

    final sortedDates = dailyData.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    final latestDate = sortedDates.first;
    final latestData = dailyData[latestDate]!;

    final todaySleepHrs =
        (latestData['sleep']?['avg'] as num?)?.toDouble() ?? 0.0;
    final sleepQuality = todaySleepHrs >= 8
        ? 80.0
        : todaySleepHrs >= 7
            ? 65.0
            : todaySleepHrs >= 6
                ? 45.0
                : todaySleepHrs > 0
                    ? 25.0
                    : 0.0;

    final samplesChronological = sortedDates.reversed.map((dateStr) {
      final d = dailyData[dateStr]!;
      final hrMax = (d['heart_rate']?['max'] as num?)?.toDouble() ??
          (d['heart_rate']?['avg'] as num?)?.toDouble() ??
          baselineHr;
      final hrv = (d['hrv']?['avg'] as num?)?.toDouble() ?? baselineHrv;
      final steps = (d['steps']?['sum'] as num?)?.toDouble() ?? 0.0;
      final stress = (d['stress']?['avg'] as num?)?.toInt();
      return <String, dynamic>{
        't': '${dateStr}T12:00:00',
        'hr': hrMax.round(),
        'hrv': hrv.round(),
        'steps': steps.round(),
        'activity': steps > 8000
            ? 'active'
            : steps > 3000
                ? 'light'
                : 'sedentary',
        'stress': ?stress,
        'tag': '',
      };
    }).toList();

    final windowStart = DateTime.parse('${sortedDates.last}T00:00:00');
    final windowEnd = DateTime.parse('${latestDate}T23:59:59');

    // Compact user setup from preferences + questionnaire (scalar values only,
    // max 10 fields) — keeps token overhead under ~100 tokens.
    final userSetup = <String, dynamic>{};
    const metaKeys = {
      'createdAt', 'updatedAt', 'userId', 'id', 'timestamp',
    };
    for (final doc in [...prefSnap.docs, ...questSnap.docs]) {
      for (final entry in doc.data().entries) {
        if (userSetup.length >= 10) break;
        if (metaKeys.contains(entry.key)) continue;
        final v = entry.value;
        if (v is String || v is num || v is bool) {
          userSetup[entry.key] = v;
        }
      }
    }

    return {
      'user_profile': {
        'timezone': 'UTC',
        'age_range': 'adult',
        'resting_hr_typical': baselineHr,
        'hrv_rmssd_typical': baselineHrv,
        if (userSetup.isNotEmpty) 'user_setup': userSetup,
      },
      'data_window': {
        'start': windowStart.toIso8601String(),
        'end': windowEnd.toIso8601String(),
      },
      'samples_5min': samplesChronological,
      'events': <Map<String, dynamic>>[],
      if (todaySleepHrs > 0)
        'sleep_summary': {
          'total_hours': todaySleepHrs,
          'sleep_quality': sleepQuality,
        },
      'demo_user': {
        'userId': userId,
        'hrv': baselineHrv,
      },
    };
  }

  /// Graceful empty-state session when the user has no metrics yet.
  static PandaSessionData emptyStateSession(String name) {
    return PandaSessionData(
      openerMessage:
          'Hey $name! 👋 I don\'t have any health data to analyze yet. '
          'Once you start tracking your metrics, I\'ll be able to surface '
          'personalized stress insights here. For now, feel free to chat with '
          'me about anything on your mind 💜',
      questions: [],
      overallNotes: '',
      rawSpikes: [],
    );
  }

  /// Rough token estimate: 1 token ≈ 4 chars for English text.
  /// Intentionally conservative (over-counts) — the safe direction for budget checks.
  /// Used by both GeminiService and ClaudeService before every API call.
  static int estimateTokens(String text) => (text.length / 4).ceil();

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // =========================================================================
  // Prompt builders  (public static — reused by ClaudeService)
  // =========================================================================

  /// Builds the user-role prompt for spike analysis.
  /// [compact] must already contain user_context and _variability_seed.
  static String buildSpikeUserPrompt(Map<String, dynamic> compact) {
    return '''
Use ONLY the heart rate spikes detected in DATA. Do NOT invent symptoms, events, journal entries, goals, or any context not present in DATA.

If DATA.user_context is non-empty, mention it briefly in summary.overall_notes.

For each question, generate 2–3 depth_prompts (open-ended follow-ups that
encourage the user to elaborate further if they want to go deeper).

Vary the question phrasing — do not reuse wording from previous calls.
(Hint: _variability_seed = ${compact["_variability_seed"]})

Include every schema key (use "", 0, [] for unknowns).

DATA: ${jsonEncode(compact)}
''';
  }

  /// Builds the full dialogue prompt for a single conversation turn.
  /// Caps history to the last 6 items (≈3 exchanges, ≤350 tokens) and
  /// trims spike context automatically.
  ///
  /// [embedSpikeContext] — pass false when the caller already provides spike
  /// context in a cached system block (ClaudeService), to avoid sending it
  /// twice and wasting ~40–60 uncached tokens per turn.
  ///
  /// [embedPersona] — pass false when the persona intro ("You are Panda 🐼…")
  /// is already in a cached system block, saving ~17 uncached tokens per turn.
  ///
  /// [embedTaskInstructions] — pass false when the TASKS section is already
  /// in a cached system block, saving ~90 uncached tokens per turn.
  static String buildDialoguePrompt({
    required String userMessage,
    required List<Map<String, String>> conversationHistory,
    required List<Map<String, dynamic>> spikeContext,
    required bool isOnPredefinedPath,
    required bool isInDigression,
    required int digressionTurnCount,
    String? pendingQuestionId,
    String? pendingQuestionPrompt,
    String? digressionTopic,
    Map<String, String>? accumulatedSlots,
    bool embedSpikeContext = true,
    bool embedPersona = true,
    bool embedTaskInstructions = true,
  }) {
    final cappedHistory = conversationHistory.length > 6
        ? conversationHistory.sublist(conversationHistory.length - 6)
        : conversationHistory;

    final historyText = cappedHistory
        .map((t) =>
            "${t['role'] == 'user' ? 'User' : 'Panda'}: ${t['text']}")
        .join('\n');

    final StringBuffer pathCtx = StringBuffer();
    if (isInDigression) {
      pathCtx.writeln('STATE: IN_DIGRESSION');
      pathCtx.writeln(
          'Digression topic: "${digressionTopic ?? "unknown"}", depth: $digressionTurnCount turn(s).');
      pathCtx.writeln(
          'If the user seems satisfied / wrapping up, set intent = "digression_complete".');
    } else if (isOnPredefinedPath && pendingQuestionPrompt != null) {
      pathCtx.writeln('STATE: ON_PREDEFINED_PATH');
      pathCtx.writeln(
          'Current question (ID: $pendingQuestionId): "$pendingQuestionPrompt"');
    } else {
      pathCtx.writeln('STATE: FREE_CONVERSATION (predefined path complete)');
    }

    final slotsCtx = (accumulatedSlots != null && accumulatedSlots.isNotEmpty)
        ? 'SLOTS SO FAR: ${jsonEncode(accumulatedSlots)}'
        : 'SLOTS SO FAR: none';

    final spikeCtxLine = embedSpikeContext
        ? 'SPIKE CONTEXT: ${jsonEncode(trimSpikeContext(spikeContext))}\n\n'
        : '';

    final personaLine = embedPersona
        ? 'You are Panda 🐼, a warm, empathetic wellness companion in Vivordo.\n\n'
        : '';

    final tasksSection = embedTaskInstructions
        ? '\n\nTASKS:\n\n'
          '1. INTENT (pick one): "answer_label" | "want_deeper_answer" | "digress" |\n'
          '   "digression_complete" | "new_stressor" | "recommend" | "chitchat" | "skip"\n'
          '\n'
          '2. MESSAGE (2–4 sentences):\n'
          '   • Never ask the next predefined question — the app handles that automatically.\n'
          '   • Deliver advice immediately with concrete examples — never just promise it.\n'
          '   • intent=="recommend": one warm intro sentence; the app shows the rec cards.\n'
          '   • intent=="want_deeper_answer": include one probing follow-up question.\n'
          '   • Digression depth ≥ 3: warmly begin wrapping up the side conversation.\n'
          '   • Tone: warm, peer-like. Never clinical. No diagnoses; use "may be related to".\n'
          '\n'
          '3. DEPTH_FOLLOW_UP: one open-ended probe (intent=="want_deeper_answer" only).\n'
          '\n'
          '4. INJECTED_QUESTION: targeted Q + 3–5 chip options + "Something else 🙋"\n'
          '   (intent=="new_stressor" only).\n'
          '\n'
          '5. REC_HINT: comma-separated keywords for the rec engine\n'
          '   (intent=="recommend" only). E.g. "music, sleep", "breathing, anxiety".\n'
          '\n'
          '6. FILLED_SLOTS: stressor, emotion, intensity (low/medium/high),\n'
          '   physical_symptom, activity, location, time_context, coping_strategy,\n'
          '   sleep_quality, social_context, other. Use "" for anything not mentioned.\n'
        : '';

    return '$personaLine$pathCtx\n$spikeCtxLine$slotsCtx\n\nCONVERSATION:\n$historyText\n\nUSER: "$userMessage"$tasksSection';
  }

  // =========================================================================
  // Data processing  (public static — reused by ClaudeService)
  // =========================================================================

  /// Builds the compact spike-candidate payload from raw health data.
  static Map<String, dynamic> buildCompactPayload(Map<String, dynamic> raw,
      {int topK = 3}) {
    final profile = raw['user_profile'] ?? {};
    final window = raw['data_window'] ?? {};
    final events = (raw['events'] as List? ?? []).cast<Map>();
    final samples = (raw['samples_5min'] as List? ?? []).cast<Map>();
    final baselineHr = (profile['resting_hr_typical'] ?? 62).toDouble();
    final baselineHrv = (profile['hrv_rmssd_typical'] ?? 52).toDouble();

    var spikeCandidates = _detectSpikes(samples, baselineHr, baselineHrv);
    spikeCandidates.sort((a, b) =>
        _severity(b, baselineHr, baselineHrv)
            .compareTo(_severity(a, baselineHr, baselineHrv)));
    if (spikeCandidates.length > topK) {
      spikeCandidates = spikeCandidates.sublist(0, topK);
    }

    for (final s in spikeCandidates) {
      s['context'] ??= <String, dynamic>{};
      s['context']['nearby_events'] = _eventsNear(
        events: events,
        startIso: s['start'],
        endIso: s['end'],
        minutes: 90,
      );
      s['context']['confidence'] =
          (s['context']['nearby_events'] as List).isEmpty ? 0.55 : 0.75;
    }

    final userSetup = profile['user_setup'] as Map?;
    return {
      'user_profile': {
        'timezone': profile['timezone'] ?? 'UTC',
        'age_range': profile['age_range'] ?? 'adult',
        'resting_hr_typical': baselineHr,
        'hrv_rmssd_typical': baselineHrv,
        if (userSetup != null && userSetup.isNotEmpty)
          'user_setup': userSetup,
      },
      'data_window': window,
      'user_context': raw['user_context'] ?? '',
      'spike_candidates': spikeCandidates,
    };
  }

  /// Parses raw spike-analysis JSON into a PandaSessionData.
  static PandaSessionData parsePandaSession(
    String raw,
    Map<String, dynamic> rawSample, {
    String? overrideName,
  }) {
    final demo = rawSample['demo_user'] as Map<String, dynamic>?;

    final userName = overrideName?.isNotEmpty == true
        ? overrideName!
        : (demo?['userId'] as String? ?? 'there')
            .replaceAll(RegExp(r'[_\-]'), ' ')
            .split(' ')
            .first;

    final obj = _extractJson(raw);

    if (obj == null) {
      return _fallbackSession(userName, 'earlier today', []);
    }

    final overallNotes =
        (obj['summary']?['overall_notes'] as String? ?? '').trim();

    final spikes = obj['spikes'] as List?;
    final rawSpikes =
        spikes?.whereType<Map<String, dynamic>>().toList() ?? [];

    final sleepSummary = rawSample['sleep_summary'] as Map?;
    final sleepHours =
        (sleepSummary?['total_hours'] as num?)?.toDouble() ?? 0.0;

    final openerMessage = _buildWarmOpener(
      userName: userName,
      hasSpikes: spikes != null && spikes.isNotEmpty,
      overallNotes: overallNotes,
      sleepHours: sleepHours,
    );

    if (spikes == null || spikes.isEmpty) {
      return PandaSessionData(
        openerMessage: openerMessage,
        questions: [],
        overallNotes: overallNotes,
        rawSpikes: rawSpikes,
      );
    }

    final spike = spikes.first as Map<String, dynamic>;
    final timePhrase =
        _formatTimeRange(spike['start'] as String?, spike['end'] as String?);

    final questions = <PandaQuestion>[];
    final qs = spike['questions'] as List?;

    if (qs != null) {
      for (final q in qs) {
        if (q is! Map) continue;

        final qid =
            q['question_id']?.toString() ?? 'q_${questions.length + 1}';
        final qp = q['prompt']?.toString() ?? '';
        if (qp.isEmpty) continue;

        final opts = <String>[];
        if (q['options'] is List) {
          for (final o in q['options'] as List) {
            final t = o.toString().trim();
            if (t.isNotEmpty) opts.add(t);
          }
        }

        if (opts.isNotEmpty &&
            !opts.any((o) => o.toLowerCase().contains('other'))) {
          opts.add('Something else 🙋');
        }

        final depths = <String>[];
        if (q['depth_prompts'] is List) {
          for (final d in q['depth_prompts'] as List) {
            final t = d.toString().trim();
            if (t.isNotEmpty) depths.add(t);
          }
        }

        questions.add(PandaQuestion(
          questionId: qid,
          prompt: qp,
          options: opts,
          depthPrompts: depths,
        ));
      }
    }

    if (questions.isEmpty) {
      return _fallbackSession(userName, timePhrase, rawSpikes,
          notes: overallNotes);
    }

    return PandaSessionData(
      openerMessage: openerMessage,
      questions: questions,
      overallNotes: overallNotes,
      rawSpikes: rawSpikes,
    );
  }

  /// Parses a raw dialogue-turn JSON string into a PandaTurnReply.
  static PandaTurnReply parseTurnReply(String raw) {
    try {
      final obj = _extractJson(raw);
      if (obj == null) throw FormatException('no JSON');

      final intentStr = obj['intent']?.toString() ?? 'chitchat';
      final intent = _parseIntent(intentStr);
      final message = obj['message']?.toString().trim().isNotEmpty == true
          ? obj['message'].toString().trim()
          : 'Got it 💜';

      final depthFollowUp = (intent == PandaIntent.wantDeeperAnswer)
          ? obj['depth_follow_up']?.toString().trim()
          : null;

      PandaQuestion? injected;
      if (intent == PandaIntent.newStressor) {
        final iqRaw = obj['injected_question'];
        if (iqRaw is Map<String, dynamic>) {
          final qid = iqRaw['question_id']?.toString() ?? '';
          final qp = iqRaw['prompt']?.toString() ?? '';
          final opts = <String>[];
          if (iqRaw['options'] is List) {
            for (final o in iqRaw['options'] as List) {
              final t = o.toString().trim();
              if (t.isNotEmpty) opts.add(t);
            }
          }
          if (qid.isNotEmpty && qp.isNotEmpty && opts.isNotEmpty) {
            injected =
                PandaQuestion(questionId: qid, prompt: qp, options: opts);
          }
        }
      }

      Map<String, String>? slots;
      if (obj['filled_slots'] is Map<String, dynamic>) {
        final rawSlots = obj['filled_slots'] as Map<String, dynamic>;
        final m = <String, String>{};
        rawSlots.forEach((k, v) {
          final val = v?.toString().trim() ?? '';
          if (val.isNotEmpty) m[k] = val;
        });
        if (m.isNotEmpty) slots = m;
      }

      final recHint = (intent == PandaIntent.recommend)
          ? (obj['rec_hint']?.toString().trim().isNotEmpty == true
              ? obj['rec_hint'].toString().trim()
              : null)
          : null;

      return PandaTurnReply(
        intent: intent,
        message: message,
        depthFollowUp: depthFollowUp,
        injectedQuestion: injected,
        filledSlots: slots,
        recHint: recHint,
      );
    } catch (_) {
      return PandaTurnReply(intent: PandaIntent.chitchat, message: 'Got it 💜');
    }
  }

  /// Strips spike objects to (spike_id, window, top_hypothesis) to bound
  /// per-turn prompt token cost regardless of signal count.
  static List<Map<String, dynamic>> trimSpikeContext(
      List<Map<String, dynamic>> spikes) {
    return spikes.map((s) {
      final hypotheses = s['hypotheses'] as List? ?? [];
      final topLabel = hypotheses.isNotEmpty
          ? (hypotheses.first as Map<String, dynamic>)['label']
                  ?.toString() ??
              ''
          : '';
      return {
        'spike_id': s['spike_id'] ?? '',
        'start': s['start'] ?? '',
        'end': s['end'] ?? '',
        'top_hypothesis': topLabel,
      };
    }).toList();
  }

  // =========================================================================
  // Private static helpers
  // =========================================================================

  static Map<String, dynamic>? _extractJson(String raw) {
    var cleaned = raw
        .trim()
        .replaceAll(RegExp(r'^```[a-zA-Z]*\s*'), '')
        .replaceAll(RegExp(r'\s*```$'), '')
        .trim();
    final s = cleaned.indexOf('{');
    final e = cleaned.lastIndexOf('}');
    if (s == -1 || e == -1 || e <= s) return null;
    return jsonDecode(cleaned.substring(s, e + 1)) as Map<String, dynamic>?;
  }

  static PandaIntent _parseIntent(String s) {
    switch (s.toLowerCase().trim()) {
      case 'answer_label':
        return PandaIntent.answerLabel;
      case 'want_deeper_answer':
        return PandaIntent.wantDeeperAnswer;
      case 'digress':
        return PandaIntent.digress;
      case 'digression_complete':
        return PandaIntent.digressionComplete;
      case 'new_stressor':
        return PandaIntent.newStressor;
      case 'recommend':
        return PandaIntent.recommend;
      case 'skip':
        return PandaIntent.skip;
      default:
        return PandaIntent.chitchat;
    }
  }

  static String _buildWarmOpener({
    required String userName,
    required bool hasSpikes,
    required String overallNotes,
    double sleepHours = 0.0,
  }) {
    final spikeSnippet = hasSpikes
        ? 'I noticed some elevated heart rate patterns in your recent data — '
            'I\'ve put together a few questions to help us understand what was going on. '
        : 'Your heart rate looks fairly steady in the data I have. ';

    final sleepSnippet = sleepHours >= 6
        ? 'You got ${sleepHours.toStringAsFixed(1)}h of sleep last night. '
        : sleepHours > 0
            ? 'You only got ${sleepHours.toStringAsFixed(1)}h of sleep — that can amplify stress. '
            : '';

    const invite =
        'What would you like to explore — your patterns, how to plan today, '
        'or something else on your mind?';

    return 'Hey $userName! 💜 $spikeSnippet$sleepSnippet$invite';
  }

  static PandaSessionData _fallbackSession(
      String userName, String timePhrase, List<Map<String, dynamic>> spikes,
      {String notes = ''}) {
    return PandaSessionData(
      openerMessage:
          'Hey $userName! 🌿 Ive pulled up your health data for today. '
          'What would you like to explore — your stress patterns, how to plan your day, '
          'or something else on your mind? 💜',
      questions: [
        PandaQuestion(
          questionId: 'q_fallback',
          prompt: 'What was happening around $timePhrase?',
          options: const [
            'Work or study 📚',
            'Exercise 🏃',
            'Social situation 👥',
            'Commute 🚗',
            'Something else 🙋',
          ],
          depthPrompts: const [
            'Can you tell me more about what was stressful about that?',
            'How were you feeling physically during that time?',
          ],
        ),
      ],
      overallNotes: notes,
      rawSpikes: spikes,
    );
  }

  static String _formatTimeRange(String? startIso, String? endIso) {
    try {
      if (startIso == null) return 'earlier today';
      final start = DateTime.parse(startIso).toLocal();
      final s = _formatTime(start);
      if (endIso == null) return s;
      return '$s–${_formatTime(DateTime.parse(endIso).toLocal())}';
    } catch (_) {
      return 'earlier today';
    }
  }

  static String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  static double _severity(
      Map<String, dynamic> s, double baselineHr, double baselineHrv) {
    final hr = (s['signals']?['heart_rate']?['peak'] ?? 0).toDouble();
    final hrvMin =
        (s['signals']?['hrv']?['min'] ?? baselineHrv).toDouble();
    final steps =
        (s['signals']?['steps']?['peak_window'] ?? 0).toDouble();
    return (hr - baselineHr).clamp(0, 100) +
        (baselineHrv - hrvMin).clamp(0, 100) +
        (steps / 200.0).clamp(0, 30);
  }

  static List<Map<String, dynamic>> _detectSpikes(
      List<Map> samples, double baselineHr, double baselineHrv) {
    bool isSpike(Map s) {
      final hr = (s['hr'] ?? baselineHr).toDouble();
      final hrv = (s['hrv'] ?? baselineHrv).toDouble();
      final stress = (s['stress_score'] ?? 0).toDouble();
      return hr >= baselineHr + 25 ||
          hrv <= baselineHrv - 18 ||
          stress >= 65;
    }

    final List<Map<String, dynamic>> spikes = [];
    Map<String, dynamic>? cur;
    double peakHr = 0, minHrv = 1e9, peakSteps = 0;

    for (final s in samples) {
      final t = s['t'] as String;
      final hr = (s['hr'] ?? baselineHr).toDouble();
      final hrv = (s['hrv'] ?? baselineHrv).toDouble();
      final steps = (s['steps'] ?? 0).toDouble();

      if (isSpike(s)) {
        cur ??= {
          'spike_id': 'spk_${spikes.length + 1}',
          'start': t,
          'end': t,
          'signals': {
            'heart_rate': {'baseline': baselineHr, 'peak': baselineHr},
            'hrv': {'baseline': baselineHrv, 'min': baselineHrv},
            'steps': {'peak_window': 0.0},
          },
        };
        cur['end'] = t;
        if (hr > peakHr) peakHr = hr;
        if (hrv < minHrv) minHrv = hrv;
        if (steps > peakSteps) peakSteps = steps;
        cur['signals']['heart_rate']['peak'] = peakHr;
        cur['signals']['hrv']['min'] =
            (minHrv == 1e9) ? baselineHrv : minHrv;
        cur['signals']['steps']['peak_window'] = peakSteps;
      } else {
        if (cur != null) {
          spikes.add(cur);
          cur = null;
          peakHr = 0;
          minHrv = 1e9;
          peakSteps = 0;
        }
      }
    }
    if (cur != null) spikes.add(cur);
    return spikes;
  }

  static List<Map<String, dynamic>> _eventsNear({
    required List<Map> events,
    required String startIso,
    required String endIso,
    required int minutes,
  }) {
    final start = DateTime.parse(startIso);
    final end = DateTime.parse(endIso);
    final lo = start.subtract(Duration(minutes: minutes));
    final hi = end.add(Duration(minutes: minutes));
    final nearby = <Map<String, dynamic>>[];
    for (final e in events) {
      final t = DateTime.parse(e['time'] as String);
      if (!t.isBefore(lo) && !t.isAfter(hi)) {
        nearby.add({
          'time': e['time'],
          'type': e['type'] ?? 'unknown',
          'detail': e['detail'] ?? '',
        });
      }
    }
    return nearby;
  }

  // =========================================================================
  // User data enrichment placeholders
  // =========================================================================

  Future<void> appendEntitiesToUserData({
    required String userId,
    required Map<String, String> sessionSlots,
    required Map<String, String> labeledAnswers,
    required DateTime sessionDate,
  }) async {
    // ignore: avoid_print
    print('[PandaService] PLACEHOLDER — would write to user $userId:');
    // ignore: avoid_print
    print('  Session date : ${sessionDate.toIso8601String()}');
    // ignore: avoid_print
    print('  Slots        : $sessionSlots');
    // ignore: avoid_print
    print('  Labeled Q→A  : $labeledAnswers');
  }

  Future<void> updateLabeledAnswer({
    required String userId,
    required DateTime sessionDate,
    required String questionId,
    required String oldAnswer,
    required String newAnswer,
  }) async {
    // ignore: avoid_print
    print('[PandaService] PLACEHOLDER — updateLabeledAnswer for $userId:');
    // ignore: avoid_print
    print('  Session : ${sessionDate.toIso8601String()}');
    // ignore: avoid_print
    print('  Question: $questionId');
    // ignore: avoid_print
    print('  Old     : "$oldAnswer"');
    // ignore: avoid_print
    print('  New     : "$newAnswer"');
  }
}
