import 'dart:convert';
import 'package:firebase_ai/firebase_ai.dart';

import '../demo/demo_user_repository.dart';
import '../demo/demo_user_data.dart';

class GeminiService {
  GeminiService()
      : _model = FirebaseAI.googleAI().generativeModel(
          model: 'gemini-2.5-flash-lite',
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
            responseSchema: _responseSchema,
            candidateCount: 1,
            temperature: 0,
            maxOutputTokens: 1500
          ),
        );

  final GenerativeModel _model;

  // Sticky demo user (same user per run until switched)
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

  static const String _systemInstruction = '''
You are Vivordo Stress Labeling Assistant.

Goal:
Given pre-detected spike candidates + nearby events, propose likely causes (wellness only)
and ask short targeted questions to collect ML labels.

Constraints:
- Do NOT provide medical diagnosis or medical instructions.
- Use “may be related” language.
- Ask at most 3 questions per spike; prefer multiple-choice + “Other”.
- Keep it short.
- Be specific about time windows and what you observed.
- If data is missing/uncertain, ask clarifying questions.

Return ONLY valid JSON matching the response schema. No extra text.
''';

  // NOTE:
  // firebase_ai 3.6.1 Schema does NOT accept `requiredProperties` or `required`.
  // So we enforce "include all fields" in the prompt instead.
  static final Schema _responseSchema = Schema(
    SchemaType.object,
    properties: {
      "summary": Schema(
        SchemaType.object,
        properties: {
          "data_window_start": Schema(SchemaType.string),
          "data_window_end": Schema(SchemaType.string),
          "overall_notes": Schema(SchemaType.string),
        },
      ),
      "spikes": Schema(
        SchemaType.array,
        items: Schema(
          SchemaType.object,
          properties: {
            "spike_id": Schema(SchemaType.string),
            "start": Schema(SchemaType.string),
            "end": Schema(SchemaType.string),
            "signals": Schema(
              SchemaType.object,
              properties: {
                "heart_rate": Schema(
                  SchemaType.object,
                  properties: {
                    "baseline": Schema(SchemaType.number),
                    "peak": Schema(SchemaType.number),
                  },
                ),
                "hrv": Schema(
                  SchemaType.object,
                  properties: {
                    "baseline": Schema(SchemaType.number),
                    "min": Schema(SchemaType.number),
                  },
                ),
                "steps": Schema(
                  SchemaType.object,
                  properties: {
                    "peak_window": Schema(SchemaType.number),
                  },
                ),
              },
            ),
            "context": Schema(
              SchemaType.object,
              properties: {
                "nearby_events": Schema(
                  SchemaType.array,
                  items: Schema(
                    SchemaType.object,
                    properties: {
                      "time": Schema(SchemaType.string),
                      "type": Schema(SchemaType.string),
                      "detail": Schema(SchemaType.string),
                    },
                  ),
                ),
                "confidence": Schema(SchemaType.number),
              },
            ),
            "hypotheses": Schema(
              SchemaType.array,
              items: Schema(
                SchemaType.object,
                properties: {
                  "label": Schema(SchemaType.string),
                  "reason": Schema(SchemaType.string),
                  "confidence": Schema(SchemaType.number),
                },
              ),
            ),
            "questions": Schema(
              SchemaType.array,
              items: Schema(
                SchemaType.object,
                properties: {
                  "question_id": Schema(SchemaType.string),
                  "prompt": Schema(SchemaType.string),
                  "type": Schema(SchemaType.string),
                  "options": Schema(
                    SchemaType.array,
                    items: Schema(SchemaType.string),
                  ),
                },
              ),
            ),
            "ml_labels_to_collect": Schema(
              SchemaType.array,
              items: Schema(SchemaType.string),
            ),
          },
        ),
      ),
    },
  );

  // ---- public helpers for the test page ----
  DemoUserData peekDemoUser() => getActiveDemoUser();
  DemoUserData pickNewDemoUser() => switchDemoUser();

  Map<String, dynamic> buildCompactPayloadForTest(
    Map<String, dynamic> raw, {
    int topK = 3,
  }) {
    return _buildCompactPayload(raw, topK: topK);
  }

  /// Uses DemoUserRepository and ONLY maps fields (no extra generator logic)
  Map<String, dynamic> getSampleData() {
    final demo = getActiveDemoUser();

    final day = DateTime.tryParse(demo.date) ?? DateTime.now();
    final start = DateTime(day.year, day.month, day.day, 18, 0); // 6pm
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
        "time": start.add(const Duration(hours: 13, minutes: 40)).toIso8601String(),
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

Future<String> analyzeStressSpikes({
  required Map<String, dynamic> data,
  String? extraUserContext,
}) async {
  // Always work with a mutable map so we can inject context/journal
  final Map<String, dynamic> compact = (data.containsKey("spike_candidates"))
      ? Map<String, dynamic>.from(data)
      : _buildCompactPayload(data, topK: 3);

  // Inject UI context into DATA so the model treats it as "ground truth"
  compact["user_context"] = extraUserContext?.trim() ?? "";

  final userPrompt = '''
Use ONLY the spikes/events/context provided in DATA.
Do NOT invent symptoms, injuries, diagnoses, or events.

You MUST use BOTH:
1) DATA.user_context (if non-empty)
2) DATA.journal (mood/summary/keyword/stressed)
in your output:
- Mention them briefly in summary.overall_notes
- And at least ONE question per spike must explicitly reference user_context OR journal.

Formatting rules:
- Return ONLY valid JSON (no markdown, no backticks, no extra text).
- Include EVERY key from the schema even if unknown (use "", 0, [], or "unknown").
- spikes: exactly the spikes provided (max 3)
- hypotheses: 1-2 per spike
- questions: 1-3 per spike
- Keep strings short: overall_notes <= 140 chars, each question prompt <= 90 chars.

DATA (JSON):
${jsonEncode(compact)}
''';

  final response = await _model.generateContent([
    Content.text(_systemInstruction),
    Content.text(userPrompt),
  ]);

  return response.text ?? '';
}


  // -------------------------
  // Local preprocessing
  // -------------------------
Map<String, dynamic> _buildCompactPayload(Map<String, dynamic> raw, {int topK = 3}) {
  final profile = raw["user_profile"] ?? {};
  final window = raw["data_window"] ?? {};
  final events = (raw["events"] as List? ?? []).cast<Map>();

  final samples = (raw["samples_5min"] as List? ?? []).cast<Map>();
  final baselineHr = (profile["resting_hr_typical"] ?? 62).toDouble();
  final baselineHrv = (profile["hrv_rmssd_typical"] ?? 52).toDouble();

  var spikeCandidates = _detectSpikes(samples, baselineHr, baselineHrv);

  spikeCandidates.sort((a, b) =>
      _severity(b, baselineHr, baselineHrv).compareTo(_severity(a, baselineHr, baselineHrv)));

  if (spikeCandidates.length > topK) {
    spikeCandidates = spikeCandidates.sublist(0, topK);
  }

  for (final s in spikeCandidates) {
    s["context"] ??= <String, dynamic>{};
    s["context"]["nearby_events"] = _eventsNear(
      events: events,
      startIso: s["start"],
      endIso: s["end"],
      minutes: 90,
    );
    s["context"]["confidence"] =
        (s["context"]["nearby_events"] as List).isEmpty ? 0.55 : 0.75;
  }

  // Pull journal from demo_user if present (since getSampleData includes it)
  final demoUser = raw["demo_user"] as Map<String, dynamic>?;

  final journal = demoUser == null
      ? {
          "mood": "unknown",
          "summary": "",
          "keyword": "",
          "stressed": false,
        }
      : {
          "mood": demoUser["journalMood"] ?? "unknown",
          "summary": demoUser["journalEntrySummary"] ?? "",
          "keyword": demoUser["keyword"] ?? "",
          "stressed": demoUser["stressed"] ?? false,
        };

  return {
    "user_profile": {
      "timezone": profile["timezone"] ?? "America/Edmonton",
      "age_range": profile["age_range"] ?? "adult",
      "resting_hr_typical": baselineHr,
      "hrv_rmssd_typical": baselineHrv,
    },
    "data_window": window,

    "journal": journal,
    "user_context": raw["user_context"] ?? "",

    "spike_candidates": spikeCandidates,
  };
}


  double _severity(Map<String, dynamic> s, double baselineHr, double baselineHrv) {
    final hr = (s["signals"]?["heart_rate"]?["peak"] ?? 0).toDouble();
    final hrvMin = (s["signals"]?["hrv"]?["min"] ?? baselineHrv).toDouble();
    final steps = (s["signals"]?["steps"]?["peak_window"] ?? 0).toDouble();
    final hrScore = (hr - baselineHr).clamp(0, 100);
    final hrvScore = (baselineHrv - hrvMin).clamp(0, 100);
    final stepScore = (steps / 200.0).clamp(0, 30);
    return hrScore + hrvScore + stepScore;
  }

  List<Map<String, dynamic>> _detectSpikes(
    List<Map> samples,
    double baselineHr,
    double baselineHrv,
  ) {
    bool isSpike(Map s) {
      final hr = (s["hr"] ?? baselineHr).toDouble();
      final hrv = (s["hrv"] ?? baselineHrv).toDouble();
      final stress = (s["stress_score"] ?? 0).toDouble();

      final hrHigh = hr >= baselineHr + 25;
      final hrvLow = hrv <= baselineHrv - 18;
      final stressHigh = stress >= 65;
      return hrHigh || hrvLow || stressHigh;
    }

    final List<Map<String, dynamic>> spikes = [];
    Map<String, dynamic>? cur;

    double peakHr = 0, minHrv = 1e9, peakSteps = 0;

    for (final s in samples) {
      final t = s["t"] as String;
      final hr = (s["hr"] ?? baselineHr).toDouble();
      final hrv = (s["hrv"] ?? baselineHrv).toDouble();
      final steps = (s["steps"] ?? 0).toDouble();

      if (isSpike(s)) {
        cur ??= {
          "spike_id": "spk_${spikes.length + 1}",
          "start": t,
          "end": t,
          "signals": {
            "heart_rate": {"baseline": baselineHr, "peak": baselineHr},
            "hrv": {"baseline": baselineHrv, "min": baselineHrv},
            "steps": {"peak_window": 0},
          },
        };
        cur["end"] = t;

        peakHr = peakHr > hr ? peakHr : hr;
        minHrv = minHrv < hrv ? minHrv : hrv;
        peakSteps = peakSteps > steps ? peakSteps : steps;

        cur["signals"]["heart_rate"]["peak"] = peakHr;
        cur["signals"]["hrv"]["min"] = (minHrv == 1e9) ? baselineHrv : minHrv;
        cur["signals"]["steps"]["peak_window"] = peakSteps;
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

  List<Map<String, dynamic>> _eventsNear({
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
      final t = DateTime.parse(e["time"] as String);
      if (!t.isBefore(lo) && !t.isAfter(hi)) {
        nearby.add({
          "time": e["time"],
          "type": e["type"] ?? "unknown",
          "detail": e["detail"] ?? "",
        });
      }
    }
    return nearby;
  }
}
