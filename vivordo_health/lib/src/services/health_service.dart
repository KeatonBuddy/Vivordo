import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:intl/intl.dart';

// ─── Metric definitions ──────────────────────────────────────────────────────

/// Every HealthKit metric the app supports, with UI metadata.
class HealthMetricDef {
  final String key;          // Firestore field / metricType value
  final HealthDataType type; // HealthKit data type
  final String label;        // Display label
  final String description;  // One-line description for consent UI
  const HealthMetricDef({
    required this.key,
    required this.type,
    required this.label,
    required this.description,
  });
}

const List<HealthMetricDef> kHealthMetrics = [
  HealthMetricDef(key: 'steps',           type: HealthDataType.STEPS,                         label: 'Steps',           description: 'Daily step count from your iPhone or Apple Watch'),
  HealthMetricDef(key: 'heart_rate',      type: HealthDataType.HEART_RATE,                    label: 'Heart Rate',      description: 'Resting and active heart rate readings'),
  HealthMetricDef(key: 'sleep',           type: HealthDataType.SLEEP_ASLEEP,                  label: 'Sleep',           description: 'Sleep duration tracked by Apple Watch or iPhone'),
  HealthMetricDef(key: 'hrv',             type: HealthDataType.HEART_RATE_VARIABILITY_SDNN,   label: 'HRV',             description: 'Heart Rate Variability — used to estimate your stress level'),
  HealthMetricDef(key: 'blood_oxygen',    type: HealthDataType.BLOOD_OXYGEN,                  label: 'Blood Oxygen',    description: 'SpO₂ readings from Apple Watch'),
  HealthMetricDef(key: 'active_calories', type: HealthDataType.ACTIVE_ENERGY_BURNED,          label: 'Active Calories', description: 'Calories burned during active movement'),
];

/// Convenience lookup: metricKey → HealthMetricDef
final Map<String, HealthMetricDef> kMetricByKey = {
  for (final m in kHealthMetrics) m.key: m,
};

// ─── HealthService ───────────────────────────────────────────────────────────

class HealthService {
  static final HealthService _instance = HealthService._internal();
  factory HealthService() => _instance;
  HealthService._internal();

  final Health _health = Health();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── Consent management ────────────────────────────────────────────────────

  /// Live stream of the user's consent map from Firestore.
  /// Map value: true = consented, false/missing = not consented.
  Stream<Map<String, bool>> consentStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value({});
    return _db.collection('users').doc(uid).snapshots().map((snap) {
      final raw = snap.data()?['healthKitConsent'] as Map? ?? {};
      return raw.map((k, v) => MapEntry(k.toString(), v == true));
    });
  }

  /// Read the current consent map once (non-reactive).
  Future<Map<String, bool>> getConsent() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return {};
    final doc = await _db.collection('users').doc(uid).get();
    final raw = doc.data()?['healthKitConsent'] as Map? ?? {};
    return raw.map((k, v) => MapEntry(k.toString(), v == true));
  }

  /// Request HealthKit permission for a specific metric, then sync it.
  /// Returns true if the user granted access.
  Future<bool> enableMetric(String metricKey) async {
    final def = kMetricByKey[metricKey];
    if (def == null) return false;

    await _health.configure();
    final granted = await _health.requestAuthorization(
      [def.type],
      permissions: [HealthDataAccess.READ],
    );

    // iOS returns true even if the user taps "Don't Allow" — we treat the
    // dialog completion as intent to enable and save the consent flag.
    // The actual data availability will determine if charts populate.
    await _setConsent(metricKey, true);
    if (granted) {
      await syncMetric(metricKey, daysBack: 30);
    }
    return granted;
  }

  /// Revoke consent for a metric AND delete all its Firestore data.
  Future<void> disableMetric(String metricKey) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // 1. Mark as not consented
    await _setConsent(metricKey, false);

    // 2. Delete all stored docs for this metric
    final batch = _db.batch();
    final query = await _db
        .collection('metrics_daily')
        .where('userId', isEqualTo: uid)
        .where('metricType', isEqualTo: metricKey)
        .get();
    for (final doc in query.docs) {
      batch.delete(doc.reference);
    }
    if (query.docs.isNotEmpty) await batch.commit();
  }

  /// Revoke ALL metrics and delete all HealthKit data from Firestore.
  Future<void> disableAll() async {
    for (final m in kHealthMetrics) {
      await disableMetric(m.key);
    }
  }

  // ─── Sync ──────────────────────────────────────────────────────────────────

  /// Sync a single metric for the last [daysBack] days.
  Future<void> syncMetric(String metricKey, {int daysBack = 30}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final def = kMetricByKey[metricKey];
    if (def == null) return;

    await _health.configure();
    final now = DateTime.now();
    final start = now.subtract(Duration(days: daysBack));

    try {
      final dataPoints = await _health.getHealthDataFromTypes(
        startTime: start,
        endTime: now,
        types: [def.type],
      );
      if (dataPoints.isEmpty) return;
      await _writeDataPoints(uid, def, dataPoints);
    } catch (e) {
      debugPrint('HealthService.syncMetric($metricKey): $e');
    }
  }

  /// Sync ALL consented metrics for the last [daysBack] days.
  Future<void> syncToFirestore({int daysBack = 30}) async {
    final consent = await getConsent();
    for (final m in kHealthMetrics) {
      if (consent[m.key] == true) {
        await syncMetric(m.key, daysBack: daysBack);
      }
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await _db.collection('users').doc(uid).set(
        {'lastHealthKitSync': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    }
  }

  /// Sync only today's data for all consented metrics (fast foreground call).
  Future<void> syncToday() => syncToFirestore(daysBack: 1);

  // ─── Internal helpers ──────────────────────────────────────────────────────

  Future<void> _setConsent(String metricKey, bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).set(
      {'healthKitConsent': {metricKey: value}},
      SetOptions(merge: true),
    );
  }

  Future<void> _writeDataPoints(
    String uid,
    HealthMetricDef def,
    List<HealthDataPoint> dataPoints,
  ) async {
    // Group readings by calendar day
    final Map<String, List<double>> byDay = {};
    for (final point in dataPoints) {
      if (point.value is! NumericHealthValue) continue;
      final day = _formatDate(point.dateFrom);
      final val = (point.value as NumericHealthValue).numericValue.toDouble();
      byDay.putIfAbsent(day, () => []).add(val);
    }

    // Write in one batch per metric (max 30 docs — well within 500-write limit)
    final batch = _db.batch();
    for (final entry in byDay.entries) {
      final day = entry.key;
      final vals = entry.value;
      final docId = '${uid}_${def.key}_$day';
      final ref = _db.collection('metrics_daily').doc(docId);
      batch.set(ref, {
        'userId': uid,
        'metricType': def.key,
        'period': day,
        'tags': [def.key],
        'source': 'apple_health',
        'syncedAt': FieldValue.serverTimestamp(),
        ..._buildValueMap(def.type, vals),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Map<String, dynamic> _buildValueMap(HealthDataType type, List<double> vals) {
    double sum() => vals.fold(0.0, (a, b) => a + b);
    double avg() => sum() / vals.length;
    double min() => vals.reduce((a, b) => a < b ? a : b);
    double max() => vals.reduce((a, b) => a > b ? a : b);

    switch (type) {
      case HealthDataType.STEPS:
      case HealthDataType.ACTIVE_ENERGY_BURNED:
        return {'sum': sum(), 'avg': avg(), 'unit': type == HealthDataType.STEPS ? 'steps' : 'kcal', 'dimension': 'activity'};
      case HealthDataType.HEART_RATE:
        return {'avg': avg(), 'min': min(), 'max': max(), 'unit': 'bpm', 'dimension': 'cardiovascular'};
      case HealthDataType.HEART_RATE_VARIABILITY_SDNN:
        final hrvAvg = avg();
        // Invert HRV to a 0–100 stress score: low HRV → high stress
        final stress = ((1.0 - (hrvAvg.clamp(0, 100) / 100)) * 100).clamp(0.0, 100.0);
        return {'avg': hrvAvg, 'stressScore': stress, 'unit': 'ms', 'dimension': 'stress'};
      case HealthDataType.SLEEP_ASLEEP:
      case HealthDataType.SLEEP_IN_BED:
        // Apple Health returns sleep in seconds — convert to hours
        final hours = sum() / 3600;
        return {'avg': hours, 'min': min() / 3600, 'max': max() / 3600, 'unit': 'hours', 'dimension': 'sleep'};
      case HealthDataType.BLOOD_OXYGEN:
        return {'avg': avg(), 'min': min(), 'max': max(), 'unit': '%', 'dimension': 'cardiovascular'};
      default:
        return {'avg': avg(), 'unit': '', 'dimension': 'other'};
    }
  }

  String _formatDate(DateTime dt) => DateFormat('yyyy-MM-dd').format(dt);
}
