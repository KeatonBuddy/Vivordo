import 'dart:convert';
import 'package:firebase_ai/firebase_ai.dart';

class GeminiService {
  GeminiService()
      : _model = FirebaseAI.googleAI().generativeModel(
          model: 'gemini-2.5-flash',
        );

  final GenerativeModel _model;

  /// System instruction: what the assistant *is* and how it must behave.
  static const String _systemInstruction = '''
You are Vivordo Stress Labeling Assistant.

Goal:
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
    ]);

    return response.text ?? '';
  }
}
