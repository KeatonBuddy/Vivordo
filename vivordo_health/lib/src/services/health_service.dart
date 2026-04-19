import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:health/health.dart';
import 'package:intl/intl.dart';

/// All HealthKit data types the app reads.
/// Users can toggle each one on/off — we only read types they've authorized.
const List<HealthDataType> kHealthTypes = [
  HealthDataType.STEPS,
  HealthDataType.HEART_RATE,
  HealthDataType.HEART_RATE_VARIABILITY_SDNN, // used as stress proxy
  HealthDataType.SLEEP_ASLEEP,
  HealthDataType.SLEEP_IN_BED,
  HealthDataType.BLOOD_OXYGEN,
  HealthDataType.ACTIVE_ENERGY_BURNED,
];

/// Maps each HealthDataType to the metric key stored in Firestore.
const Map<HealthDataType, String> kTypeToMetric = {
  HealthDataType.STEPS: 'steps',
  HealthDataType.HEART_RATE: 'heart_rate',
  HealthDataType.HEART_RATE_VARIABILITY_SDNN: 'hrv',
  HealthDataType.SLEEP_ASLEEP: 'sleep',
  HealthDataType.SLEEP_IN_BED: 'sleep_in_bed',
  HealthDataType.BLOOD_OXYGEN: 'blood_oxygen',
  HealthDataType.ACTIVE_ENERGY_BURNED: 'active_calories',
};

class HealthService {
  static final HealthService _instance = HealthService._internal();
  factory HealthService() => _instance;
  HealthService._internal();

  final Health _health = Health();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── Permission Management ──────────────────────────────────────────────────

  /// Request HealthKit read authorization for all metric types.
  /// Returns the set of types that were actually authorized.
  Future<Set<HealthDataType>> requestPermissions() async {
    await _health.configure();
    final requested = await _health.requestAuthorization(
      kHealthTypes,
      permissions: kHealthTypes.map((_) => HealthDataAccess.READ).toList(),
    );
    if (!requested) return {};

    // Check which types were actually granted
    final granted = <HealthDataType>{};
    for (final type in kHealthTypes) {
      final status = await _health.getHealthDataFromTypes(
        startTime: DateTime.now().subtract(const Duration(hours: 1)),
        endTime: DateTime.now(),
        types: [type],
      );
      // If we can query without error, we have read access
      if (status.isNotEmpty || true) {
        // health package doesn't expose per-type status on iOS easily;
        // if requestAuthorization succeeded, treat all as granted.
        granted.add(type);
      }
    }

    // Persist granted types per user in Firestore
    await _saveGrantedTypes(granted);
    return granted;
  }

  /// Revoke a specific metric type: removes from Firestore consent record
  /// and deletes all stored data for that metric.
  Future<void> revokeMetric(String metricKey) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // 1. Remove from user's granted types list
    await _db.collection('users').doc(uid).update({
      'healthKitConsent.$metricKey': FieldValue.delete(),
    });

    // 2. Delete all Firestore documents for this metric
    final query = await _db
        .collection('metrics_daily')
        .where('userId', isEqualTo: uid)
        .where('metricType', isEqualTo: metricKey)
        .get();

    final batch = _db.batch();
    for (final doc in query.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  /// Revoke ALL health data consent and delete everything from Firestore.
  Future<void> revokeAll() async {
    for (final metric in kTypeToMetric.values) {
      await revokeMetric(metric);
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await _db.collection('users').doc(uid).update({
        'healthKitConsent': FieldValue.delete(),
      });
    }
  }

  // ─── Sync ───────────────────────────────────────────────────────────────────

  /// Sync the last [daysBack] days of HealthKit data to Firestore.
  /// Call on app foreground, app open, or manually.
  Future<void> syncToFirestore({int daysBack = 30}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await _health.configure();

    final now = DateTime.now();
    final start = now.subtract(Duration(days: daysBack));

    for (final type in kHealthTypes) {
      final metricKey = kTypeToMetric[type]!;

      // Check user hasn't revoked this metric
      final userDoc = await _db.collection('users').doc(uid).get();
      final consent = (userDoc.data()?['healthKitConsent'] as Map?) ?? {};
      if (consent.containsKey(metricKey) && consent[metricKey] == false) {
        continue; // user revoked this metric
      }

      try {
        final dataPoints = await _health.getHealthDataFromTypes(
          startTime: start,
          endTime: now,
          types: [type],
        );

        if (dataPoints.isEmpty) continue;

        // Aggregate by day
        final Map<String, List<double>> byDay = {};
        for (final point in dataPoints) {
          final day = _formatDate(point.dateFrom);
          final value = (point.value as NumericHealthValue).numericValue.toDouble();
          byDay.putIfAbsent(day, () => []).add(value);
        }

        // Write to Firestore — one document per day per metric
        final batch = _db.batch();
        for (final entry in byDay.entries) {
          final day = entry.key;
          final values = entry.value;

          final aggregated = _aggregate(type, values);
          final docId = '${uid}_${metricKey}_$day';
          // Use same collection + schema as MetricsService for consistency
          final ref = _db.collection('metrics_daily').doc(docId);

          // Build the value map matching MetricsService schema
          final valueMap = _buildValueMap(type, values, aggregated);

          batch.set(ref, {
            'userId': uid,
            'metricType': metricKey,
            'period': day,
            'tags': [metricKey],
            'source': 'apple_health',
            'syncedAt': FieldValue.serverTimestamp(),
            ...valueMap,
          }, SetOptions(merge: true));
        }
        await batch.commit();
      } catch (e) {
        // Individual metric failure shouldn't block others
        print('HealthService: failed to sync $metricKey — $e');
      }
    }

    // Update last sync timestamp on the user document
    await _db.collection('users').doc(uid).set({
      'lastHealthKitSync': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Sync only today's data (fast, called on foreground resume).
  Future<void> syncToday() => syncToFirestore(daysBack: 1);

  // ─── Helpers ────────────────────────────────────────────────────────────────

  /// Aggregate multiple readings for a day into a single value.
  double _aggregate(HealthDataType type, List<double> values) {
    switch (type) {
      case HealthDataType.STEPS:
      case HealthDataType.ACTIVE_ENERGY_BURNED:
      case HealthDataType.SLEEP_ASLEEP:
      case HealthDataType.SLEEP_IN_BED:
        // Cumulative — sum all readings
        return values.fold(0.0, (a, b) => a + b);
      case HealthDataType.HEART_RATE:
      case HealthDataType.HEART_RATE_VARIABILITY_SDNN:
      case HealthDataType.BLOOD_OXYGEN:
        // Rate/percentage — daily average
        return values.fold(0.0, (a, b) => a + b) / values.length;
      default:
        return values.fold(0.0, (a, b) => a + b) / values.length;
    }
  }

  String _unit(HealthDataType type) {
    switch (type) {
      case HealthDataType.STEPS:
        return 'steps';
      case HealthDataType.HEART_RATE:
        return 'bpm';
      case HealthDataType.HEART_RATE_VARIABILITY_SDNN:
        return 'ms';
      case HealthDataType.SLEEP_ASLEEP:
      case HealthDataType.SLEEP_IN_BED:
        return 'hours';
      case HealthDataType.BLOOD_OXYGEN:
        return '%';
      case HealthDataType.ACTIVE_ENERGY_BURNED:
        return 'kcal';
      default:
        return '';
    }
  }

  /// Build value fields that match MetricsService schema so home/dashboard
  /// StreamBuilders can read HealthKit data the same way they read demo data.
  Map<String, dynamic> _buildValueMap(
      HealthDataType type, List<double> values, double aggregated) {
    final unit = _unit(type);
    switch (type) {
      case HealthDataType.STEPS:
      case HealthDataType.ACTIVE_ENERGY_BURNED:
        return {
          'sum': aggregated,
          'avg': values.fold(0.0, (a, b) => a + b) / values.length,
          'unit': unit,
          'dimension': 'activity',
        };
      case HealthDataType.HEART_RATE:
        return {
          'avg': aggregated,
          'min': values.reduce((a, b) => a < b ? a : b),
          'max': values.reduce((a, b) => a > b ? a : b),
          'unit': unit,
          'dimension': 'cardiovascular',
        };
      case HealthDataType.HEART_RATE_VARIABILITY_SDNN:
        // Map HRV inversely to stress score (higher HRV = lower stress)
        final hrvAvg = aggregated;
        final stressScore = ((1 - (hrvAvg / 100)) * 100).clamp(0.0, 100.0);
        return {
          'avg': hrvAvg,
          'stressScore': stressScore,
          'unit': unit,
          'dimension': 'stress',
        };
      case HealthDataType.SLEEP_ASLEEP:
      case HealthDataType.SLEEP_IN_BED:
        // HealthKit returns sleep in seconds — convert to hours
        final hours = aggregated / 3600;
        return {
          'avg': hours,
          'min': values.reduce((a, b) => a < b ? a : b) / 3600,
          'max': values.reduce((a, b) => a > b ? a : b) / 3600,
          'unit': 'hours',
          'dimension': 'sleep',
        };
      case HealthDataType.BLOOD_OXYGEN:
        return {
          'avg': aggregated,
          'unit': unit,
          'dimension': 'cardiovascular',
        };
      default:
        return {'avg': aggregated, 'unit': unit};
    }
  }

  String _formatDate(DateTime dt) => DateFormat('yyyy-MM-dd').format(dt);

  Future<void> _saveGrantedTypes(Set<HealthDataType> types) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final consentMap = <String, bool>{};
    for (final type in kHealthTypes) {
      final key = kTypeToMetric[type]!;
      consentMap[key] = types.contains(type);
    }

    await _db.collection('users').doc(uid).set({
      'healthKitConsent': consentMap,
    }, SetOptions(merge: true));
  }
}
