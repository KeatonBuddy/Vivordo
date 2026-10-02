// ignore_for_file: avoid_print

// =============================================================================
// panda_spike_test.dart
//
// Confirms the full spike → question → insight flow using the pure-logic
// static helpers on PandaPrompts.
//
// These tests do NOT need Firebase — they exercise only the in-process
// data-processing pipeline.  Run with:
//
//   flutter test test/panda_spike_test.dart
//
// The test user is gbupweX0Wbe5hr5S86nHohhHYFd2.
// To also verify end-to-end (Firestore fetch + LLM call), seed Firestore
// with the script at test/seed_spike_data.js, then open the Panda screen
// on a device logged in as that user.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/panda_prompts.dart';

// ---------------------------------------------------------------------------
// Test fixture: simulated fetchRealUserPayload output for a user who has
// 7 days of heart_rate data with a spike on the most recent day.
// Mirrors the exact map shape that fetchRealUserPayload returns.
// ---------------------------------------------------------------------------

const _testUserId = 'gbupweX0Wbe5hr5S86nHohhHYFd2';

Map<String, dynamic> _buildSpikePayload() {
  // Baseline resting HR ≈ 62 bpm → spike threshold = 69 bpm.
  // Day 7 (today): resting HR = 74 bpm → exceeds threshold → spike detected.
  final today = DateTime.now();
  final samples = <Map<String, dynamic>>[];

  for (int i = 6; i >= 0; i--) {
    final day = today.subtract(Duration(days: i));
    final dateStr =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    final isSpike = i == 0; // only the most recent day has a spike
    samples.add({
      't': '${dateStr}T12:00:00',
      'hr': isSpike ? 74 : 63, // daily resting HR: spike 74, normal 63
      'hrv': 52,
      'steps': isSpike ? 2200 : 5400,
      'activity': isSpike ? 'work_focus' : 'light',
      'tag': '',
    });
  }

  final today0 = today;
  final week0 = today.subtract(const Duration(days: 6));

  return {
    'user_profile': {
      'timezone': 'UTC',
      'age_range': 'adult',
      'resting_hr_typical': 62.0, // 7-day avg of normal readings
      'hrv_rmssd_typical': 52.0,
    },
    'data_window': {
      'start': '${week0.year}-${week0.month.toString().padLeft(2, '0')}-${week0.day.toString().padLeft(2, '0')}T00:00:00',
      'end': '${today0.year}-${today0.month.toString().padLeft(2, '0')}-${today0.day.toString().padLeft(2, '0')}T23:59:59',
    },
    'samples_5min': samples,
    'events': <Map<String, dynamic>>[],
    'demo_user': {'userId': _testUserId},
  };
}

// ---------------------------------------------------------------------------
// Minimal spike-analysis JSON that would be returned by the LLM.
// Used to test parsePandaSession without a real LLM call.
// ---------------------------------------------------------------------------

const _mockSpikeJson = '''
{
  "summary": {
    "data_window_start": "2026-06-09T00:00:00",
    "data_window_end": "2026-06-16T23:59:59",
    "overall_notes": "Heart rate reached 115 bpm — notably above your baseline."
  },
  "spikes": [
    {
      "spike_id": "spk_1",
      "start": "2026-06-16T12:00:00",
      "end": "2026-06-16T12:00:00",
      "signals": {
        "heart_rate": { "baseline": 62.0, "peak": 115.0 },
        "hrv": { "baseline": 52.0, "min": 52.0 },
        "steps": { "peak_window": 2200.0 }
      },
      "context": { "nearby_events": [], "confidence": 0.55 },
      "hypotheses": [
        { "label": "work_stress", "reason": "Elevated HR mid-day", "confidence": 0.7 }
      ],
      "questions": [
        {
          "question_id": "q_1",
          "prompt": "What were you doing when your heart rate spiked this afternoon?",
          "type": "multiple_choice",
          "options": ["Work / study 📚", "Exercise 🏃", "Social situation 👥", "Commute 🚗"],
          "depth_prompts": [
            "Can you tell me more about what made that stressful?",
            "How were you feeling physically during that time?"
          ]
        },
        {
          "question_id": "q_2",
          "prompt": "How stressed did you feel in the hour leading up to it?",
          "type": "multiple_choice",
          "options": ["Very stressed 😰", "Somewhat stressed 😕", "Not really 😌", "Hard to say 🤔"],
          "depth_prompts": [
            "What was the main thing on your mind?",
            "Did anything help you calm down afterwards?"
          ]
        }
      ],
      "ml_labels_to_collect": ["stressor_type", "stress_intensity"]
    }
  ]
}
''';

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Spike detection — buildCompactPayload', () {
    test('detects spike when resting HR exceeds baseline + 7', () {
      final payload = _buildSpikePayload();
      final compact = PandaPrompts.buildCompactPayload(payload, topK: 3);

      final spikes = compact['spike_candidates'] as List;
      expect(spikes, isNotEmpty,
          reason: 'Resting HR of 74 bpm against a 62 bpm baseline should produce a spike');

      final spike = spikes.first as Map<String, dynamic>;
      final peakHr = spike['signals']['heart_rate']['peak'] as num;
      expect(peakHr, greaterThanOrEqualTo(69),
          reason: 'Spike resting HR must be >= baseline (62) + 7');
    });

    test('no spikes when all HR readings are within normal range', () {
      final payload = _buildSpikePayload();
      // Overwrite samples with all-normal readings
      final normalSamples = (payload['samples_5min'] as List<Map<String, dynamic>>)
          .map((s) => {...s, 'hr': 66})
          .toList();
      payload['samples_5min'] = normalSamples;

      final compact = PandaPrompts.buildCompactPayload(payload, topK: 3);
      final spikes = compact['spike_candidates'] as List;
      expect(spikes, isEmpty,
          reason: 'Resting HR at 66 bpm against 62 bpm baseline is below the 7-bpm threshold');
    });

    test('a high stress score alone flags the day', () {
      final payload = _buildSpikePayload();
      final samples = payload['samples_5min'] as List<Map<String, dynamic>>;
      payload['samples_5min'] = [
        for (final (i, s) in samples.indexed)
          {...s, 'hr': 63, if (i == 3) 'stress': 72},
      ];
      final spikes =
          PandaPrompts.buildCompactPayload(payload, topK: 3)['spike_candidates']
              as List;
      expect(spikes, hasLength(1));
    });

    test('a workout day is not a spike: max HR and steps are ignored', () {
      final sample = PandaPrompts.dailySample(
        '2026-09-30',
        {
          'heart_rate': {'avg': 88, 'max': 171},
          'resting_heart_rate': {'avg': 61},
          'hrv': {'avg': 50},
          'steps': {'sum': 18000},
        },
        baselineHr: 62,
        baselineHrv: 52,
      );
      expect(sample['hr'], 61);
      final payload = _buildSpikePayload();
      payload['samples_5min'] = [sample];
      expect(
        PandaPrompts.buildCompactPayload(payload, topK: 3)['spike_candidates'],
        isEmpty,
      );
    });

    test('daily sample falls back to average HR and reads stress', () {
      final sample = PandaPrompts.dailySample(
        '2026-09-30',
        {
          'heart_rate': {'avg': 70, 'max': 150},
          'stress': {'avg': 66.4},
        },
        baselineHr: 62,
        baselineHrv: 52,
      );
      expect(sample['hr'], 70);
      expect(sample['stress'], 66);
    });

    test('spike days are date-only and de-duplicated', () {
      expect(
        PandaPrompts.spikeDays([
          {'start': '2026-09-29'},
          {'start': '2026-09-29T12:00:00'},
          {'start': ''},
        ]),
        ['2026-09-29'],
      );
    });

    test('compact payload contains no journal or goals keys', () {
      final payload = _buildSpikePayload();
      final compact = PandaPrompts.buildCompactPayload(payload, topK: 3);

      expect(compact.containsKey('journal'), isFalse,
          reason: 'Journal does not exist and must never be sent to the LLM');
      expect(compact.containsKey('goals'), isFalse,
          reason: 'Goals do not exist and must never be sent to the LLM');
    });
  });

  group('Spike session parsing — parsePandaSession', () {
    test('parses questions from valid LLM JSON', () {
      final payload = _buildSpikePayload();
      final session = PandaPrompts.parsePandaSession(
        _mockSpikeJson,
        payload,
        overrideName: 'TestUser',
      );

      expect(session.questions, isNotEmpty,
          reason: 'Spike JSON contains 2 questions — both must be parsed');
      expect(session.questions.length, equals(2));
      expect(session.questions.first.questionId, equals('q_1'));
      expect(session.questions.first.options, contains('Work / study 📚'));
    });

    test('opener mentions heart rate spike, not journal or mood', () {
      final payload = _buildSpikePayload();
      final session = PandaPrompts.parsePandaSession(
        _mockSpikeJson,
        payload,
        overrideName: 'TestUser',
      );

      final opener = session.openerMessage.toLowerCase();
      expect(opener.contains('heart rate'), isTrue,
          reason: 'Opener must reference heart rate — the only data source');
      expect(opener.contains('journal'), isFalse);
      expect(opener.contains('mood'), isFalse);
      expect(opener.contains('stress score'), isFalse);
    });

    test('empty-state session returned when no LLM JSON', () {
      final payload = _buildSpikePayload();
      final session = PandaPrompts.parsePandaSession(
        'not json at all',
        payload,
        overrideName: 'TestUser',
      );

      // Fallback session: still has at least one question to keep the flow alive
      expect(session.questions, isNotEmpty,
          reason: 'Fallback session must include a question so the path does not dead-end');
    });
  });

  group('Insight persistence contract', () {
    test('spike → questions exist → session can be completed', () {
      final payload = _buildSpikePayload();
      final compact = PandaPrompts.buildCompactPayload(payload, topK: 1);

      expect((compact['spike_candidates'] as List).isNotEmpty, isTrue);

      // Simulate what PandaScreen does: if questions are generated from a real
      // LLM call, _persistCompletedSession is called.  We verify the precondition
      // (questions exist) so the code path that calls saveSessionInsight is reached.
      final session = PandaPrompts.parsePandaSession(
        _mockSpikeJson,
        payload,
        overrideName: 'TestUser',
      );

      expect(session.questions.isNotEmpty, isTrue,
          reason: 'With a spike detected, parsePandaSession must produce questions; '
              'PandaScreen then calls _persistCompletedSession once all are answered');
    });
  });
}
