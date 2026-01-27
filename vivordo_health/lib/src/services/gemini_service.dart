import 'dart:convert';
import 'package:firebase_ai/firebase_ai.dart';

class GeminiService {
  GeminiService()
      : _model = FirebaseAI.googleAI().generativeModel(
<<<<<<< HEAD
          model: 'gemini-2.5-flash-lite',
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
            responseSchema: _responseSchema,
            candidateCount: 1,
            temperature: 0,
            maxOutputTokens: 900,
          ),
=======
          model: 'gemini-2.5-flash',
>>>>>>> edcdc98 (Extracted out the Gemini logic into a service, created Testing page and established connection with mock json data to test I/O)
        );

  final GenerativeModel _model;

<<<<<<< HEAD
=======
  /// System instruction: what the assistant *is* and how it must behave.
>>>>>>> edcdc98 (Extracted out the Gemini logic into a service, created Testing page and established connection with mock json data to test I/O)
  static const String _systemInstruction = '''
You are Vivordo Stress Labeling Assistant.

Goal:
<<<<<<< HEAD
Given pre-detected spike candidates + nearby events, propose likely causes (wellness only)
and ask short targeted questions to collect ML labels.

Constraints:
- Do NOT provide medical diagnosis or medical instructions.
- Use “may be related” language.
- Ask at most 5 questions per spike; prefer multiple-choice + “Other”.
- Be specific about time windows and what you observed.
- If data is missing/uncertain, ask clarifying questions.

Return ONLY valid JSON matching the response schema. No extra text.
''';

  /// NOTE: This schema is intentionally compact for speed.
  /// (You can expand later—bigger schema = more output tokens = slower.)
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
        requiredProperties: ["data_window_start", "data_window_end", "overall_notes"],
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
                  requiredProperties: ["baseline", "peak"],
                ),
                "hrv": Schema(
                  SchemaType.object,
                  properties: {
                    "baseline": Schema(SchemaType.number),
                    "min": Schema(SchemaType.number),
                  },
                  requiredProperties: ["baseline", "min"],
                ),
                "steps": Schema(
                  SchemaType.object,
                  properties: {
                    "peak_window": Schema(SchemaType.number),
                  },
                  requiredProperties: ["peak_window"],
                ),
              },
              requiredProperties: ["heart_rate", "hrv", "steps"],
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
                    requiredProperties: ["time", "type", "detail"],
                  ),
                ),
                "confidence": Schema(SchemaType.number),
              },
              requiredProperties: ["nearby_events", "confidence"],
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
                requiredProperties: ["label", "reason", "confidence"],
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
                  "options": Schema(SchemaType.array, items: Schema(SchemaType.string)),
                },
                requiredProperties: ["question_id", "prompt", "type", "options"],
              ),
            ),
            "ml_labels_to_collect": Schema(
              SchemaType.array,
              items: Schema(SchemaType.string),
            ),
          },
          requiredProperties: ["spike_id", "start", "end", "signals", "context", "hypotheses", "questions", "ml_labels_to_collect"],
        ),
      ),
    },
    requiredProperties: ["summary", "spikes"],
  );

  /// PUBLIC: call this from UI
  Future<String> analyzeStressSpikes({
    required Map<String, dynamic> data,
    String? extraUserContext,
  }) async {
    // 1) locally compress -> spike candidates + nearby events only
    final compact = _buildCompactPayload(data);

    final userPrompt = '''
Use the spike candidates and nearby events below.
For each spike:
- give 1–3 hypotheses with confidence
- ask up to 5 questions (mostly multiple-choice + Other)
- keep it short and ML-ready

Optional user context:
${extraUserContext?.trim().isNotEmpty == true ? extraUserContext!.trim() : "(none)"}

DATA (JSON):
${jsonEncode(compact)}
''';

    // 2) Send only system + compact user prompt
    final response = await _model.generateContent([
      Content.text(_systemInstruction),
      Content.text(userPrompt),
=======
Detect likely stress spikes/anomalies in wearable and context data, relate them to nearby events (activity, sleep, schedule/context markers), and ask the user short targeted questions to collect labels for future machine learning.

Constraints:
- Do NOT provide medical diagnosis or medical instructions.
- Treat outputs as wellness insights only; use “may be related” language.
- Ask at most 5 questions per spike; prefer multiple-choice + “Other”.
- Be specific about time windows and what you observed in the data.
- If data is missing/uncertain, ask clarifying questions.

Output format:
Return ONLY valid JSON that matches the schema provided.
No extra text.
''';

  /// The schema we want Gemini to follow (ML-ready).
  static const String _outputSchema = r'''
{
  "summary": {
    "data_window_start": "ISO8601",
    "data_window_end": "ISO8601",
    "overall_notes": "string"
  },
  "spikes": [
    {
      "spike_id": "string",
      "start": "ISO8601",
      "end": "ISO8601",
      "signals": {
        "heart_rate": {"baseline": number, "peak": number},
        "hrv": {"baseline": number, "min": number},
        "steps": {"baseline": number, "peak_window": number},
        "sleep_debt": {"minutes": number}
      },
      "context": {
        "nearby_events": [
          {"time": "ISO8601", "type": "activity|sleep|caffeine|meal|work|commute|social|unknown", "detail": "string"}
        ],
        "confidence": 0-1
      },
      "hypotheses": [
        {"label": "exercise|caffeine|sleep_debt|work_stress|social_stress|illness|unknown", "reason": "string", "confidence": 0-1}
      ],
      "questions": [
        {
          "question_id": "string",
          "prompt": "string",
          "type": "single_choice|multi_choice|scale_1_5|free_text",
          "options": ["string"]
        }
      ],
      "ml_labels_to_collect": [
        "trigger_type",
        "perceived_stress_1_5",
        "mood",
        "location_context",
        "social_context",
        "caffeine_amount_mg",
        "notes"
      ]
    }
  ]
}
''';

  /// Sample data for testing (you can swap this out later).
  Map<String, dynamic> getSampleData() {
    return {
      "user_profile": {
        "timezone": "America/Toronto",
        "age_range": "teen",
        "resting_hr_typical": 62,
        "hrv_rmssd_typical": 52
      },
      "data_window": {
        "start": "2026-01-18T18:00:00-05:00",
        "end": "2026-01-19T18:00:00-05:00"
      },
      "samples_5min": [
        {
          "t": "2026-01-18T23:00:00-05:00",
          "hr": 64,
          "hrv": 55,
          "steps": 10,
          "stress_score": 12,
          "activity": "sedentary",
          "tag": ""
        },
        {
          "t": "2026-01-18T23:30:00-05:00",
          "hr": 66,
          "hrv": 50,
          "steps": 0,
          "stress_score": 18,
          "activity": "sedentary",
          "tag": "screen_time"
        },
        {
          "t": "2026-01-19T00:00:00-05:00",
          "hr": 63,
          "hrv": 58,
          "steps": 0,
          "stress_score": 10,
          "activity": "sleep",
          "tag": "sleep_start"
        },
        {
          "t": "2026-01-19T02:00:00-05:00",
          "hr": 72,
          "hrv": 42,
          "steps": 0,
          "stress_score": 35,
          "activity": "sleep",
          "tag": "restless"
        },
        {
          "t": "2026-01-19T07:00:00-05:00",
          "hr": 68,
          "hrv": 48,
          "steps": 30,
          "stress_score": 22,
          "activity": "awake",
          "tag": "wake"
        },
        {
          "t": "2026-01-19T08:00:00-05:00",
          "hr": 78,
          "hrv": 40,
          "steps": 120,
          "stress_score": 44,
          "activity": "light",
          "tag": "commute"
        },
        {
          "t": "2026-01-19T09:10:00-05:00",
          "hr": 102,
          "hrv": 28,
          "steps": 60,
          "stress_score": 72,
          "activity": "sedentary",
          "tag": "class_start"
        },
        {
          "t": "2026-01-19T09:20:00-05:00",
          "hr": 110,
          "hrv": 24,
          "steps": 55,
          "stress_score": 80,
          "activity": "sedentary",
          "tag": "class"
        },
        {
          "t": "2026-01-19T09:30:00-05:00",
          "hr": 96,
          "hrv": 30,
          "steps": 40,
          "stress_score": 65,
          "activity": "sedentary",
          "tag": "class"
        },
        {
          "t": "2026-01-19T10:30:00-05:00",
          "hr": 74,
          "hrv": 46,
          "steps": 80,
          "stress_score": 28,
          "activity": "light",
          "tag": "break"
        },
        {
          "t": "2026-01-19T12:00:00-05:00",
          "hr": 82,
          "hrv": 44,
          "steps": 300,
          "stress_score": 40,
          "activity": "walking",
          "tag": "lunch"
        },
        {
          "t": "2026-01-19T14:00:00-05:00",
          "hr": 88,
          "hrv": 38,
          "steps": 90,
          "stress_score": 55,
          "activity": "sedentary",
          "tag": "deadline"
        },
        {
          "t": "2026-01-19T14:10:00-05:00",
          "hr": 97,
          "hrv": 32,
          "steps": 70,
          "stress_score": 64,
          "activity": "sedentary",
          "tag": "deadline"
        },
        {
          "t": "2026-01-19T14:20:00-05:00",
          "hr": 92,
          "hrv": 35,
          "steps": 60,
          "stress_score": 58,
          "activity": "sedentary",
          "tag": "deadline"
        },
        {
          "t": "2026-01-19T16:30:00-05:00",
          "hr": 118,
          "hrv": 26,
          "steps": 900,
          "stress_score": 76,
          "activity": "workout",
          "tag": "gym"
        },
        {
          "t": "2026-01-19T16:40:00-05:00",
          "hr": 142,
          "hrv": 20,
          "steps": 1100,
          "stress_score": 83,
          "activity": "workout",
          "tag": "gym"
        },
        {
          "t": "2026-01-19T17:00:00-05:00",
          "hr": 98,
          "hrv": 34,
          "steps": 450,
          "stress_score": 52,
          "activity": "cooldown",
          "tag": ""
        },
        {
          "t": "2026-01-19T17:30:00-05:00",
          "hr": 76,
          "hrv": 49,
          "steps": 120,
          "stress_score": 20,
          "activity": "sedentary",
          "tag": "home"
        }
      ],
      "events": [
        {"time": "2026-01-19T07:40:00-05:00", "type": "caffeine", "detail": "coffee (unknown size)"},
        {"time": "2026-01-19T09:00:00-05:00", "type": "work", "detail": "class / meeting start"},
        {"time": "2026-01-19T14:00:00-05:00", "type": "work", "detail": "assignment deadline / high focus"},
        {"time": "2026-01-19T16:30:00-05:00", "type": "activity", "detail": "gym workout started"}
      ],
      "sleep_summary": {
        "sleep_start": "2026-01-19T00:00:00-05:00",
        "sleep_end": "2026-01-19T07:00:00-05:00",
        "total_minutes": 420,
        "restless_minutes": 55
      }
    };
  }

  /// Main method you’ll call from your UI.
  /// You can pass your real data later; for now you can pass getSampleData().
  Future<String> analyzeStressSpikes({
    required Map<String, dynamic> data,
    String? extraUserContext, // optional text from the user
  }) async {
    final payloadJson = jsonEncode(data);

    final userPrompt = '''
Analyze the following time-series data and detect stress spikes.

Definitions:
- “Spike”: heart rate and/or stress score noticeably above baseline for that time of day, OR HRV notably below baseline, lasting >= 5 minutes.
- “Baseline”: use the user’s recent rolling baseline (use what is available in data; otherwise infer from the last 24h).
- Correlate spikes with events within +/- 90 minutes (activity, sleep, caffeine, calendar tags, location tags, manual notes).

Return ONLY valid JSON matching this schema:
$_outputSchema

Optional user context (may be empty):
${extraUserContext?.trim().isNotEmpty == true ? extraUserContext!.trim() : "(none)"}

Here is the data (JSON):
$payloadJson
''';

    // Note: If your SDK supports system instructions directly, you can wire it there.
    // This approach keeps it simple and still works: put system + user in the content list.
    final response = await _model.generateContent([
      Content.text("SYSTEM:\n$_systemInstruction"),
      Content.text("USER:\n$userPrompt"),
>>>>>>> edcdc98 (Extracted out the Gemini logic into a service, created Testing page and established connection with mock json data to test I/O)
    ]);

    return response.text ?? '';
  }
<<<<<<< HEAD

  // -------------------------
  // Local preprocessing (fast)
  // -------------------------

  Map<String, dynamic> _buildCompactPayload(Map<String, dynamic> raw) {
    final profile = raw["user_profile"] ?? {};
    final window = raw["data_window"] ?? {};
    final events = (raw["events"] as List? ?? []).cast<Map>();

    final samples = (raw["samples_5min"] as List? ?? []).cast<Map>();
    final baselineHr = (profile["resting_hr_typical"] ?? 62).toDouble();
    final baselineHrv = (profile["hrv_rmssd_typical"] ?? 52).toDouble();

    final spikeCandidates = _detectSpikes(samples, baselineHr, baselineHrv);

    // attach nearby events (+/- 90 min)
    for (final s in spikeCandidates) {
      s["nearby_events"] = _eventsNear(
        events: events,
        startIso: s["start"],
        endIso: s["end"],
        minutes: 90,
      );
    }

    return {
      "user_profile": {
        "timezone": profile["timezone"] ?? "America/Toronto",
        "age_range": profile["age_range"] ?? "teen",
        "resting_hr_typical": baselineHr,
        "hrv_rmssd_typical": baselineHrv,
      },
      "data_window": window,
      "spike_candidates": spikeCandidates,
    };
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

      // Simple rules for sample data (tune later):
      final hrHigh = hr >= baselineHr + 25;       // e.g., +25 bpm
      final hrvLow = hrv <= baselineHrv - 18;     // e.g., -18 RMSSD
      final stressHigh = stress >= 65;            // stress spike
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
          "hr_baseline": baselineHr,
          "hrv_baseline": baselineHrv,
        };
        cur["end"] = t;

        peakHr = peakHr > hr ? peakHr : hr;
        minHrv = minHrv < hrv ? minHrv : hrv;
        peakSteps = peakSteps > steps ? peakSteps : steps;
      } else {
        if (cur != null) {
          spikes.add({
            "spike_id": cur["spike_id"],
            "start": cur["start"],
            "end": cur["end"],
            "signals": {
              "heart_rate": {"baseline": cur["hr_baseline"], "peak": peakHr},
              "hrv": {"baseline": cur["hrv_baseline"], "min": minHrv == 1e9 ? baselineHrv : minHrv},
              "steps": {"peak_window": peakSteps},
            },
          });
          cur = null;
          peakHr = 0;
          minHrv = 1e9;
          peakSteps = 0;
        }
      }
    }

    // flush
    if (cur != null) {
      spikes.add({
        "spike_id": cur["spike_id"],
        "start": cur["start"],
        "end": cur["end"],
        "signals": {
          "heart_rate": {"baseline": cur["hr_baseline"], "peak": peakHr},
          "hrv": {"baseline": cur["hrv_baseline"], "min": minHrv == 1e9 ? baselineHrv : minHrv},
          "steps": {"peak_window": peakSteps},
        },
      });
    }

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
=======
>>>>>>> edcdc98 (Extracted out the Gemini logic into a service, created Testing page and established connection with mock json data to test I/O)
}
