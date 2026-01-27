import 'dart:convert';
import 'package:firebase_ai/firebase_ai.dart';

class GeminiService {
  GeminiService()
      : _model = FirebaseAI.googleAI().generativeModel(
          model: 'gemini-2.5-flash-lite',
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
            responseSchema: _responseSchema,
            candidateCount: 1,
            temperature: 0,
            maxOutputTokens: 900,
          ),
        );

  final GenerativeModel _model;

  static const String _systemInstruction = '''
You are Vivordo Stress Labeling Assistant.

Goal:
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
    ]);

    return response.text ?? '';
  }

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
}
