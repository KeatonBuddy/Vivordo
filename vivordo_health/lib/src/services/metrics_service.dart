import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../demo/demo_user_repository.dart';

class MetricsService {
  static final _db = FirebaseFirestore.instance;

  // ─── VH-62 + VH-16 ───────────────────────────────────────────────
  // Seeds 30 days of realistic demo data for the current user.
  // Writes to metrics_daily using the correct document ID pattern:
  //   userId_metricType_YYYY-MM-DD
  // Metric types written: stress, heart_rate, steps, sleep, mood, wellness
  static Future<void> seedDemoData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('No user logged in');

    final repo = DemoUserRepository();
    final batch = _db.batch();
    final now = DateTime.now();

    for (int i = 0; i < 30; i++) {
      final day = now.subtract(Duration(days: i));
      final period = _formatDate(day);
      final demo = repo.getRandomDemoUser();

      // stress
      _addMetric(batch, user.uid, 'stress', period, {
        'avg': demo.dailyStressLevel.toDouble(),
        'min': (demo.dailyStressLevel - demo.stressVariability / 2).clamp(0, 100),
        'max': (demo.dailyStressLevel + demo.stressVariability / 2).clamp(0, 100),
        'unit': 'score',
        'dimension': 'stress',
        'source': 'demo',
      });

      // heart_rate
      _addMetric(batch, user.uid, 'heart_rate', period, {
        'avg': demo.restingHeartRate.toDouble(),
        'min': (demo.restingHeartRate - 5).toDouble(),
        'max': (demo.restingHeartRate + 12).toDouble(),
        'unit': 'bpm',
        'dimension': 'cardiovascular',
        'source': 'demo',
      });

      // steps
      _addMetric(batch, user.uid, 'steps', period, {
        'sum': demo.stepsCount.toDouble(),
        'avg': (demo.stepsCount / 24).roundToDouble(),
        'unit': 'count',
        'dimension': 'activity',
        'source': 'demo',
      });

      // sleep
      _addMetric(batch, user.uid, 'sleep', period, {
        'avg': demo.sleepDurationHours,
        'min': (demo.sleepDurationHours - 0.5).clamp(0, 12),
        'max': (demo.sleepDurationHours + 0.3).clamp(0, 12),
        'unit': 'hours',
        'dimension': 'sleep',
        'source': 'demo',
      });

      // mood  (VH-51 compatible format)
      _addMetric(batch, user.uid, 'mood', period, {
        'avg': _moodToScore(demo.journalMood),
        'label': demo.journalMood,
        'unit': 'score',
        'dimension': 'mood',
        'source': 'demo',
      });

      // wellness score  (VH-16)
      final wellness = ((100 - demo.dailyStressLevel) * 0.4 +
              demo.sleepQualityScore * 0.3 +
              (demo.stepsCount / 10000 * 100).clamp(0, 100) * 0.3)
          .roundToDouble();
      _addMetric(batch, user.uid, 'wellness', period, {
        'avg': wellness,
        'unit': 'score',
        'dimension': 'wellness',
        'source': 'demo',
      });
    }

    await batch.commit();
  }

  // ─── VH-51 ───────────────────────────────────────────────────────
  // Saves a single mood check-in to metrics_daily for today.
  // Called from home_screen.dart when user picks a mood.
  static Future<void> saveMoodCheckIn(String moodLabel) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final period = _formatDate(DateTime.now());
    final docId = '${user.uid}_mood_$period';

    await _db.collection('metrics_daily').doc(docId).set({
      'userId': user.uid,
      'metricType': 'mood',
      'period': period,
      'avg': _moodToScore(moodLabel),
      'label': moodLabel,
      'unit': 'score',
      'dimension': 'mood',
      'source': 'user_checkin',
      'tags': ['mood', 'checkin'],
      'computedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)); // merge so we don't overwrite if already exists
  }

  // ─── HELPERS ──────────────────────────────────────────────────────

  static void _addMetric(
    WriteBatch batch,
    String userId,
    String metricType,
    String period,
    Map<String, dynamic> values,
  ) {
    // Document ID follows design spec: userId_metricType_period
    final docId = '${userId}_${metricType}_$period';
    final ref = _db.collection('metrics_daily').doc(docId);

    batch.set(ref, {
      'userId': userId,
      'metricType': metricType,
      'period': period,
      'tags': [metricType],
      'computedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      ...values,
    }, SetOptions(merge: true));
  }

  static String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // Maps mood label to a 0–100 numeric score for graphing
  static double _moodToScore(String label) {
    switch (label.toLowerCase()) {
      case 'great': return 95;
      case 'good':  return 75;
      case 'okay':  return 50;
      case 'down':  return 30;
      case 'awful': return 10;
      // demo generator moods
      case 'calm': case 'content': case 'focused':
      case 'relaxed': case 'motivated': return 75;
      case 'anxious': case 'overwhelmed': case 'tense':
      case 'irritable': case 'drained': case 'stressed': return 25;
      default: return 50;
    }
  }
}