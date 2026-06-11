import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Posts a BAAS v1 payload to https://vivordo-baas.onrender.com/baas/score
/// and saves the returned score to metrics_daily/{uid}_stress_{date}.
///
/// PAYLOAD CONTRACT (request_loader.py)
/// ─────────────────────────────────────
///   {
///     "user_id":     "firebase_uid",
///     "as_of":       "2026-06-11T14:00:00Z",   // null = now
///     "granularity": "daily",
///     "profile":     { "user_id", "age", "gender", "timezone" },
///     "samples":     [ { "metric_type", "timestamp", "value", "unit",
///                        "source", "duration_seconds" }, ... ],
///     "daily_context": [ { "date", "journal_mood", "self_reported_stress",
///                          "sleep_duration_hours", "exercise_sessions", ... } ]
///   }
///
/// RESPONSE CONTRACT (main.py / firestore_writer.py)
/// ──────────────────────────────────────────────────
///   {
///     "lean": { "score": 42.3, "band": "moderate",
///               "confidence": "high", "coverage_pct": 87.5,
///               "top_drivers": [...], "justification": "..." },
///     "breakdown": { ... },
///     "persisted": false
///   }
///
/// NOTE ON DATA QUALITY
/// ────────────────────
/// The BaaS preprocessor computes hour-matched rolling z-scores over 14 days
/// of INTRADAY samples. Until the app ships raw per-minute HealthKit readings,
/// this service reconstructs synthetic intraday samples from daily aggregates
/// stored in metrics_daily. This yields confidence="low/medium" from the BaaS
/// because baselines can only be estimated, not computed from per-hour windows.
///
/// To improve: add a getRawSamplesForBaas() method on HealthService that reads
/// raw HealthKit data points directly and passes them here instead of the
/// synthetic samples built from Firestore aggregates.
class StressScoreService {
  static const kApiUrl = 'https://vivordo-baas.onrender.com/baas/score';

/// Computes a BaaS stress score from the user's Firestore metrics and saves
  /// the result to metrics_daily/{uid}_stress_{today}.
  ///
  /// [force] — set true when fresh data was just written (mood check-in,
  ///   HealthKit sync) so the score always recomputes regardless of age.
  ///   Default false: skips the API call if a BaaS score already exists for
  ///   today and was computed within the last 30 minutes, avoiding unnecessary
  ///   cold-start hits on every home screen load.
  ///
  /// Call fire-and-forget: `StressScoreService.computeAndSave().catchError((_) {})`.
  static Future<void> computeAndSave({String? uid, bool force = false}) async {
    uid ??= FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final today = _formatDate(DateTime.now());

    if (!force) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('metrics_daily')
            .doc('${uid}_stress_$today')
            .get();
        final data = snap.data();
        if (data?['source'] == 'baas_api') {
          final computedAt = (data?['computedAt'] as Timestamp?)?.toDate();
          if (computedAt != null &&
              DateTime.now().difference(computedAt).inMinutes < 30) {
            debugPrint('StressScoreService: score is fresh '
                '(${DateTime.now().difference(computedAt).inMinutes} min old), skipping');
            return;
          }
        }
      } catch (_) {}
    }

    try {
      final payload = await _buildPayload(uid, today);
      final result  = await _callApi(payload);
      if (result != null) await _saveScore(uid, today, result);
    } catch (e, st) {
      debugPrint('StressScoreService.computeAndSave: $e\n$st');
    }
  }

  // ── Asset-based test entry point ────────────────────────────────────────────

  /// Loads a BaaS v1 payload from [assetPath], re-dates all timestamps so
  /// the most recent day maps to today, swaps in the real [uid], posts to the
  /// BaaS API, saves the result, and returns the raw response for the debug panel.
  ///
  /// Drop any *.json into assets/test_payloads/ and pass its path here.
  /// Default: assets/test_payloads/test_payload.json
  static Future<Map<String, dynamic>?> computeWithTestPayload({
    String? uid,
    String assetPath = 'assets/test_payloads/test_payload.json',
  }) async {
    uid ??= FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final today = _formatDate(DateTime.now());

    final raw     = jsonDecode(await rootBundle.loadString(assetPath)) as Map<String, dynamic>;
    final payload = _patchTestPayload(raw, uid);
    debugPrint('StressScoreService.test[$assetPath]: '
        '${(payload['samples'] as List).length} samples, '
        'shift → today=$today');

    final result = await _callApi(payload);
    if (result != null) await _saveScore(uid, today, result);
    return result;
  }

  /// Replaces user_id and shifts every timestamp/date so the most recent
  /// day in the file lands on today.  Preserves the +00:00 suffix so
  /// Python's datetime.fromisoformat() (pre-3.11) doesn't reject it.
  static Map<String, dynamic> _patchTestPayload(
      Map<String, dynamic> raw, String uid) {
    final samples = List<Map<String, dynamic>>.from(
        (raw['samples'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
    final context = List<Map<String, dynamic>>.from(
        ((raw['daily_context'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map)));

    // Collect every date mentioned in the payload to find the latest one
    DateTime? latest;
    for (final s in samples) {
      final ts = s['timestamp'] as String?;
      if (ts == null) continue;
      final d = DateTime.tryParse(ts.substring(0, 10));
      if (d != null && (latest == null || d.isAfter(latest))) latest = d;
    }
    for (final c in context) {
      final d = DateTime.tryParse((c['date'] as String?) ?? '');
      if (d != null && (latest == null || d.isAfter(latest))) latest = d;
    }

    if (latest == null) {
      return {
        ...raw,
        'user_id': uid,
        'profile': {...(raw['profile'] as Map? ?? {}), 'user_id': uid},
      };
    }

    final todayUtc   = DateTime.utc(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final latestUtc  = DateTime.utc(latest.year, latest.month, latest.day);
    final shiftDays  = todayUtc.difference(latestUtc).inDays;

    for (final s in samples) {
      final ts = s['timestamp'] as String?;
      if (ts == null) continue;
      try {
        s['timestamp'] = _fmtTimestamp(DateTime.parse(ts).add(Duration(days: shiftDays)));
      } catch (_) {}
    }
    for (final c in context) {
      final d = c['date'] as String?;
      if (d == null) continue;
      try {
        c['date'] = _formatDate(DateTime.parse(d).add(Duration(days: shiftDays)));
      } catch (_) {}
    }

    return {
      ...raw,
      'user_id':       uid,
      'as_of':         DateTime.now().toUtc().toIso8601String(),
      'profile':       {...(raw['profile'] as Map? ?? {}), 'user_id': uid},
      'samples':       samples,
      'daily_context': context,
    };
  }

  /// Formats a UTC DateTime as "YYYY-MM-DDTHH:MM:SS+00:00"
  /// (Python datetime.fromisoformat pre-3.11 rejects the bare Z suffix).
  static String _fmtTimestamp(DateTime utc) {
    utc = utc.toUtc();
    return '${_formatDate(utc)}T'
        '${utc.hour.toString().padLeft(2, '0')}:'
        '${utc.minute.toString().padLeft(2, '0')}:'
        '${utc.second.toString().padLeft(2, '0')}+00:00';
  }

  // ── Payload assembly ────────────────────────────────────────────────────────

  // Metric types that feed the BaaS. Excludes output types (stress, wellness)
  // so the scorer never reads its own previous output as input.
  static const _inputMetrics = {
    'heart_rate', 'hrv', 'resting_heart_rate', 'sleep',
    'steps', 'blood_oxygen', 'respiratory_rate', 'mood',
  };

  static Future<Map<String, dynamic>> _buildPayload(
      String uid, String today) async {
    final db     = FirebaseFirestore.instance;
    final nowUtc = DateTime.now().toUtc();

    // Single query for ALL historical metrics — no hard date cap.
    // BaaS builds rolling 14-day baselines, so more history = stronger z-scores.
    // Run in parallel with the user profile fetch.
    final results = await Future.wait([
      db.collection('metrics_daily').where('userId', isEqualTo: uid).get(),
      db.collection('users').doc(uid).get(),
    ]);

    final metricsSnap = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final userSnap    = results[1] as DocumentSnapshot<Map<String, dynamic>>;

    // Build lookup: '{date}_{metricType}' → doc data
    final docsMap = <String, Map<String, dynamic>>{};
    final dateSet = <String>{};

    for (final doc in metricsSnap.docs) {
      final data       = doc.data();
      final period     = data['period']     as String?;
      final metricType = data['metricType'] as String?;
      if (period == null || metricType == null) continue;
      if (!_inputMetrics.contains(metricType)) continue;
      docsMap['${period}_$metricType'] = data;
      dateSet.add(period);
    }

    // Sort oldest → newest so BaaS receives chronological samples
    final dates = dateSet.toList()..sort();
    debugPrint('StressScoreService._buildPayload: '
        '${dates.length} day(s) of history for $uid');

    // User profile — falls back to safe defaults if fields not yet set
    final userData = userSnap.data();
    final age      = (userData?['age']      as num?)?.toInt() ?? 30;
    final gender   = (userData?['gender']   as String?)      ?? 'Other';
    final timezone = (userData?['timezone'] as String?)      ?? 'UTC';

    // ── samples ──────────────────────────────────────────────────────────────

    final samples = <Map<String, dynamic>>[];

    for (final date in dates) {
      _addPointSample(samples, docsMap['${date}_heart_rate'],
          metricType: 'heart_rate', date: date, timeUtc: '12:00', unit: 'bpm');

      _addPointSample(samples, docsMap['${date}_hrv'],
          metricType: 'hrv', date: date, timeUtc: '06:00', unit: 'ms');

      _addPointSample(samples, docsMap['${date}_resting_heart_rate'],
          metricType: 'resting_heart_rate', date: date, timeUtc: '04:00', unit: 'bpm');

      _addPointSample(samples, docsMap['${date}_blood_oxygen'],
          metricType: 'blood_oxygen', date: date, timeUtc: '07:00', unit: '%');

      _addPointSample(samples, docsMap['${date}_respiratory_rate'],
          metricType: 'respiratory_rate', date: date, timeUtc: '05:00', unit: 'brpm');

      final sleepDoc   = docsMap['${date}_sleep'];
      final sleepHours = (sleepDoc?['avg'] as num?)?.toDouble();
      if (sleepHours != null && sleepHours > 0) {
        samples.add({
          'metric_type':      'sleep',
          'timestamp':        '${date}T23:00:00+00:00',
          'value':            sleepHours,
          'unit':             'hours',
          'source':           sleepDoc?['source'] ?? 'apple_health',
          'duration_seconds': sleepHours * 3600,
        });
      }

      // Distribute daily step total across active hours so the BaaS can
      // classify sedentary vs. active windows for the activity score.
      final stepsDoc   = docsMap['${date}_steps'];
      final stepsTotal = (stepsDoc?['sum'] as num?)?.toDouble();
      if (stepsTotal != null && stepsTotal > 0) {
        const fractions = {
          6: 0.03, 7: 0.05, 8: 0.08, 9: 0.05, 10: 0.04, 11: 0.03,
          12: 0.04, 13: 0.04, 14: 0.05, 15: 0.04, 16: 0.04,
          17: 0.15, 18: 0.20, 19: 0.08, 20: 0.05, 21: 0.05,
          22: 0.04, 23: 0.02,
        };
        for (final e in fractions.entries) {
          samples.add({
            'metric_type':      'steps',
            'timestamp':        '${date}T${e.key.toString().padLeft(2, '0')}:00:00+00:00',
            'value':            (stepsTotal * e.value).roundToDouble(),
            'unit':             'steps',
            'source':           stepsDoc?['source'] ?? 'apple_health',
            'duration_seconds': 3600,
          });
        }
      }
    }

    // ── daily_context ─────────────────────────────────────────────────────────

    final dailyContext = <Map<String, dynamic>>[];

    for (final date in dates) {
      final moodDoc  = docsMap['${date}_mood'];
      final sleepDoc = docsMap['${date}_sleep'];
      final stepsDoc = docsMap['${date}_steps'];

      if (moodDoc == null && sleepDoc == null) continue;

      final journalMood = moodDoc?['label'] as String?;
      final moodScore   = (moodDoc?['avg']  as num?)?.toDouble();
      final selfStress  = moodScore != null
          ? (100.0 - moodScore).clamp(0.0, 100.0) : null;
      final sleepHours  = (sleepDoc?['avg'] as num?)?.toDouble();
      final stepsTotal  = (stepsDoc?['sum'] as num?)?.toDouble();

      final ctx = <String, dynamic>{
        'date':              date,
        'exercise_sessions': (stepsTotal != null && stepsTotal > 6000) ? 1 : 0,
      };
      if (journalMood != null) ctx['journal_mood']         = journalMood;
      if (selfStress  != null) ctx['self_reported_stress'] = selfStress;
      if (sleepHours  != null) ctx['sleep_duration_hours'] = sleepHours;
      dailyContext.add(ctx);
    }

    return {
      'user_id':       uid,
      'as_of':         nowUtc.toIso8601String(),
      'granularity':   'daily',
      'profile': {
        'user_id':  uid,
        'age':      age,
        'gender':   gender,
        'timezone': timezone,
      },
      'samples':       samples,
      'daily_context': dailyContext,
    };
  }

  // ── HTTP call ───────────────────────────────────────────────────────────────

  // Render.com free-tier cold starts take 45-60 s; one retry handles the
  // dropped-connection case where the container wakes up mid-request.
  static const _timeoutSeconds = 65;

  static Future<Map<String, dynamic>?> _callApi(
      Map<String, dynamic> payload, {int retries = 1}) async {
    final body = jsonEncode(payload);
    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        final response = await http
            .post(
              Uri.parse(kApiUrl),
              headers: {'Content-Type': 'application/json'},
              body: body,
            )
            .timeout(const Duration(seconds: _timeoutSeconds));

        if (response.statusCode == 200) {
          final json = jsonDecode(response.body);
          if (json is Map<String, dynamic>) return json;
        }
        final preview = response.body.length > 300
            ? '${response.body.substring(0, 300)}…'
            : response.body;
        debugPrint('StressScoreService._callApi [${attempt + 1}]: '
            '${response.statusCode} — $preview');
        // 4xx = bad payload, no point retrying
        if (response.statusCode >= 400 && response.statusCode < 500) break;
      } catch (e) {
        debugPrint('StressScoreService._callApi [${attempt + 1}]: $e');
        if (attempt < retries) {
          debugPrint('StressScoreService._callApi: retrying in 5 s…');
          await Future.delayed(const Duration(seconds: 5));
        }
      }
    }
    return null;
  }

  // ── Firestore write ─────────────────────────────────────────────────────────

  /// Parses the BaaS response and persists to metrics_daily.
  ///
  /// Response shape (build_lean_doc in firestore_writer.py):
  ///   { "lean": { "score": 42.3, "band": "moderate", "confidence": "high",
  ///               "coverage_pct": 87.5, "algorithm_version": "baas-v1.0",
  ///               "top_drivers": [...], "justification": "..." } }
  static Future<void> _saveScore(
      String uid, String today, Map<String, dynamic> result) async {
    final lean  = result['lean'] as Map<String, dynamic>?;
    final score = (lean?['score'] as num?)?.toDouble();
    if (score == null) return;

    await FirebaseFirestore.instance
        .collection('metrics_daily')
        .doc('${uid}_stress_$today')
        .set({
      'userId':            uid,
      'metricType':        'stress',
      'period':            today,
      'avg':               score,
      'min':               score,
      'max':               score,
      'unit':              'score',
      'dimension':         'stress',
      'source':            'baas_api',
      'tags':              ['stress', 'baas'],
      // Richer BaaS fields for explainability
      'label':             lean?['band'],
      'confidence':        lean?['confidence'],
      'coverage_pct':      lean?['coverage_pct'],
      'algorithm_version': lean?['algorithm_version'],
      'justification':     lean?['justification'],
      'top_drivers':       lean?['top_drivers'],
      'computedAt':        FieldValue.serverTimestamp(),
      'updatedAt':         FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// Adds one point-in-time sample to [samples] using the `avg` field of [doc].
  static void _addPointSample(
    List<Map<String, dynamic>> samples,
    Map<String, dynamic>? doc, {
    required String metricType,
    required String date,
    required String timeUtc,  // "HH:MM"
    required String unit,
  }) {
    if (doc == null) return;
    final value = (doc['avg'] as num?)?.toDouble();
    if (value == null) return;
    samples.add({
      'metric_type':      metricType,
      'timestamp':        '${date}T$timeUtc:00+00:00',
      'value':            value,
      'unit':             unit,
      'source':           doc['source'] ?? 'apple_health',
      'duration_seconds': null,
    });
  }

  static String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
