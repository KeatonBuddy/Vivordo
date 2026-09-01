import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'achievement_service.dart';
import 'stress_score_service.dart';

class MetricsService {
  static final _db = FirebaseFirestore.instance;

  // ─── VH-51 ───────────────────────────────────────────────────────
  // Saves a single mood check-in to metrics_daily. Home check-ins default to
  // now, while journal entries can supply the date the reflection belongs to.
  static Future<void> saveMoodCheckIn(
    String moodLabel, {
    double? moodScore,
    DateTime? occurredAt,
    String source = 'user_checkin',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final checkInTime = occurredAt ?? DateTime.now();
    final period = _formatDate(checkInTime);
    final resolvedMoodScore = (moodScore ?? moodScoreForLabel(moodLabel))
        .clamp(0, 100)
        .toDouble();

    await _db
        .collection('users')
        .doc(user.uid)
        .collection('metrics_daily')
        .doc(period)
        .set(
          {
            'mood': {
              'avg': resolvedMoodScore,
              'label': moodLabel,
              'unit': 'score',
              'source': source,
              // WHEN the tap happened. The BaaS decays the self-report by its
              // age (decay_self_report in baas_scorer.py); without a real
              // timestamp it had to assume every check-in landed at 09:00
              // local. For a once-daily composite that guess cost little. For
              // the intraday score it is most of the signal — whether someone
              // tapped "Awful" at 08:00 or at 22:00 changes the shape of their
              // whole day. Uses checkInTime rather than now(), so a journal
              // entry back-dated to the day it reflects on is timestamped to
              // that day rather than to when it was written.
              'checkInAt': Timestamp.fromDate(checkInTime),
              'entries': FieldValue.arrayUnion([
                {
                  'score': resolvedMoodScore,
                  'label': moodLabel,
                  'source': source,
                  'timestamp': Timestamp.fromDate(checkInTime),
                },
              ]),
              'syncedAt': FieldValue.serverTimestamp(),
            },
            'date': period,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        ); // merge so we don't overwrite if already exists

    // Reconcile in the background so Mood Keeper can unlock without making
    // the check-in sheet wait for the achievement queries to finish.
    AchievementService.reconcileAll().catchError(
      (_) => <AchievementProgress>[],
    );

    // Recompute BaaS stress score now that mood data has changed
    StressScoreService.computeAndSave(
      uid: user.uid,
      force: true,
    ).catchError((_) {});

    // Feed the check-in to the validation/learning loop. This does NOT submit
    // today — today's metrics are still incomplete (no sleep yet, steps still
    // accruing), and labelling a half-built day would train the model on
    // truncated inputs. It drains any earlier complete labelled days that
    // haven't been sent; today's tap goes up on a later launch once its day is
    // closed. See submitPendingFeedback for the full reasoning.
    StressScoreService.submitPendingFeedback(uid: user.uid).catchError((_) {});
  }

  // ─── HELPERS ──────────────────────────────────────────────────────

  static String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Keeps the familiar mood wording while allowing precise 0–100 check-ins.
  static String moodLabelForScore(num score) {
    final value = score.clamp(0, 100);
    if (value >= 80) return 'Great';
    if (value >= 60) return 'Good';
    if (value >= 40) return 'Okay';
    if (value >= 20) return 'Down';
    return 'Awful';
  }

  // Maps mood label to a 0–100 numeric score for graphing
  static double moodScoreForLabel(String label) {
    switch (label.toLowerCase()) {
      case 'great':
        return 95;
      case 'good':
        return 75;
      case 'okay':
        return 50;
      case 'down':
      case 'low':
        return 30;
      case 'awful':
        return 10;
      // additional descriptive mood labels
      case 'calm':
      case 'content':
      case 'focused':
      case 'relaxed':
      case 'motivated':
        return 75;
      case 'anxious':
      case 'overwhelmed':
      case 'tense':
      case 'irritable':
      case 'drained':
      case 'stressed':
        return 25;
      default:
        return 50;
    }
  }
}
