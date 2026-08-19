import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:intl/intl.dart';
import 'activity_goals_service.dart';
import 'stress_score_service.dart';
import '../utils/activity_score.dart';
import '../utils/sleep_stage_aggregation.dart';

// ─── Metric definitions ──────────────────────────────────────────────────────

/// Every HealthKit metric the app supports, with UI metadata.
class HealthMetricDef {
  final String key; // Firestore metricType value
  final HealthDataType type; // HealthKit data type
  final String label; // Display label
  final String description; // One-line description for consent UI
  const HealthMetricDef({
    required this.key,
    required this.type,
    required this.label,
    required this.description,
  });
}

/// Full list of HealthKit metrics the app can read.
/// The only requirement to activate these is purchasing the HealthKit
/// capability in your Apple Developer account and adding a real device.
/// The code is complete — no further changes needed once HealthKit is bought.
const List<HealthMetricDef> kHealthMetrics = [
  // ── Activity ────────────────────────────────────────────────────────────────
  HealthMetricDef(
    key: 'steps',
    type: HealthDataType.STEPS,
    label: 'Steps',
    description: 'Daily step count from your iPhone or Apple Watch',
  ),
  HealthMetricDef(
    key: 'active_calories',
    type: HealthDataType.ACTIVE_ENERGY_BURNED,
    label: 'Active Calories',
    description: 'Calories burned during active movement',
  ),
  HealthMetricDef(
    key: 'exercise_time',
    type: HealthDataType.EXERCISE_TIME,
    label: 'Exercise Time',
    description: 'Minutes of exercise recorded by Apple Watch',
  ),
  HealthMetricDef(
    key: 'distance',
    type: HealthDataType.DISTANCE_WALKING_RUNNING,
    label: 'Distance',
    description: 'Distance walked or run (in km)',
  ),
  // ── Heart ───────────────────────────────────────────────────────────────────
  HealthMetricDef(
    key: 'heart_rate',
    type: HealthDataType.HEART_RATE,
    label: 'Heart Rate',
    description: 'Resting and active heart rate readings (bpm)',
  ),
  HealthMetricDef(
    key: 'resting_heart_rate',
    type: HealthDataType.RESTING_HEART_RATE,
    label: 'Resting Heart Rate',
    description: 'Your daily resting heart rate (bpm)',
  ),
  HealthMetricDef(
    key: 'hrv',
    type: HealthDataType.HEART_RATE_VARIABILITY_SDNN,
    label: 'HRV',
    description: 'Heart Rate Variability — used to estimate your stress level',
  ),
  // ── Breathing / Vitals ──────────────────────────────────────────────────────
  HealthMetricDef(
    key: 'blood_oxygen',
    type: HealthDataType.BLOOD_OXYGEN,
    label: 'Blood Oxygen',
    description: 'SpO₂ readings from Apple Watch',
  ),
  HealthMetricDef(
    key: 'respiratory_rate',
    type: HealthDataType.RESPIRATORY_RATE,
    label: 'Respiratory Rate',
    description: 'Breaths per minute — elevated rates signal stress or illness',
  ),
  // ── Sleep ───────────────────────────────────────────────────────────────────
  HealthMetricDef(
    key: 'sleep',
    type: HealthDataType.SLEEP_ASLEEP,
    label: 'Sleep',
    description: 'Sleep duration tracked by Apple Watch or iPhone',
  ),
  // ── Body ────────────────────────────────────────────────────────────────────
  HealthMetricDef(
    key: 'weight',
    type: HealthDataType.WEIGHT,
    label: 'Weight',
    description: 'Body weight logged manually or via smart scale',
  ),
  HealthMetricDef(
    key: 'body_fat',
    type: HealthDataType.BODY_FAT_PERCENTAGE,
    label: 'Body Fat %',
    description: 'Body fat percentage from compatible devices',
  ),
  // ── Fitness ─────────────────────────────────────────────────────────────────
  // TODO: uncomment once HealthDataType.VO2MAX is confirmed available in this
  // version of the health package. Gave 'undefined_enum_constant' on 12.2.1 —
  // may need a newer package version or Apple Developer HealthKit capability.
  // HealthMetricDef(
  //   key: 'vo2max',
  //   type: HealthDataType.VO2MAX,
  //   label: 'VO₂ Max',
  //   description: 'Cardio fitness score from Apple Watch workouts',
  // ),
];

/// Convenience lookup: metricKey → HealthMetricDef
final Map<String, HealthMetricDef> kMetricByKey = {
  for (final m in kHealthMetrics) m.key: m,
};

/// Apple calls its light-sleep stage "Core". The health package exposes that
/// category as SLEEP_LIGHT, so it is mapped back to the Apple-facing name when
/// written to Firestore.
const List<HealthDataType> kSleepStageTypes = [
  HealthDataType.SLEEP_AWAKE,
  HealthDataType.SLEEP_LIGHT,
  HealthDataType.SLEEP_DEEP,
  HealthDataType.SLEEP_REM,
];

// ─── HealthService ───────────────────────────────────────────────────────────

class HealthService {
  static final HealthService _instance = HealthService._internal();
  factory HealthService() => _instance;
  HealthService._internal();

  final Health _health = Health();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _isRequestingAuthorization = false;
  Future<bool>? _authorizationFuture;
  bool? _authorizationResultThisSession;
  Future<void>? _activeSync;
  int _pendingSyncDays = 0;
  bool _whoopConnected = false;
  bool _fitbitConnected = false;

  Future<void> _refreshWearableConnections(String uid) async {
    final user = await _db.collection('users').doc(uid).get();
    final data = user.data();
    _whoopConnected = data?['whoopConnected'] == true;
    _fitbitConnected = data?['fitbitConnected'] == true;
  }

  // Apple Health is the fallback for metrics supplied directly by a connected
  // wearable. Steps are intentionally handled separately as Apple
  // Health-only data.
  bool _connectedWearableHasPriority(Map<String, dynamic>? day, String key) {
    final metric = day?[key] as Map?;
    final source = metric?['source'];
    if (key == 'heart_rate' && source == 'whoop_ble') {
      final raw = metric?['lastReadingAt'];
      final lastReadingAt = raw is Timestamp ? raw.toDate() : null;
      return _whoopConnected &&
          lastReadingAt != null &&
          DateTime.now().difference(lastReadingAt) <=
              const Duration(minutes: 5);
    }
    return (source == 'whoop' && _whoopConnected && key != 'heart_rate') ||
        (source == 'fitbit' && _fitbitConnected);
  }

  List<HealthDataType> get _authorizationTypes => [
    ...kHealthMetrics.map((metric) => metric.type),
    ...kSleepStageTypes,
  ];

  List<HealthDataAccess> get _authorizationAccess => List.filled(
    _authorizationTypes.length,
    HealthDataAccess.READ,
    growable: false,
  );

  // ─── Sync preferences (shared broadcast) ─────────────────────────────────

  // All callers share ONE Firestore listener via a broadcast stream.
  // Multiple listeners on the same doc caused Firestore's internal assertion error.
  Stream<Map<String, bool>>? _consentBroadcast;
  String? _consentCacheUid;

  Stream<Map<String, bool>> consentStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value({});
    if (_consentBroadcast != null && _consentCacheUid == uid) {
      return _consentBroadcast!;
    }
    _consentCacheUid = uid;
    _consentBroadcast = _db.collection('users').doc(uid).snapshots().map((
      snap,
    ) {
      final raw = snap.data()?['healthKitConsent'] as Map? ?? {};
      return raw.map((k, v) => MapEntry(k.toString(), v == true));
    }).asBroadcastStream();
    return _consentBroadcast!;
  }

  /// Clear cached stream on sign-out so the next user gets a fresh listener.
  void clearConsentCache() {
    _consentBroadcast = null;
    _consentCacheUid = null;
  }

  /// Read the user's metric sync selections once (non-reactive).
  Future<Map<String, bool>> getConsent() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return {};
    final doc = await _db.collection('users').doc(uid).get();
    final raw = doc.data()?['healthKitConsent'] as Map? ?? {};
    return raw.map((k, v) => MapEntry(k.toString(), v == true));
  }

  // ─── Permission requests ───────────────────────────────────────────────────

  /// Ensures all HealthKit read permissions used by routine sync are resolved.
  ///
  /// HealthKit deliberately reports read authorization as undetermined on iOS.
  /// Once this process has completed a request, an undetermined re-check means
  /// reads may be attempted; individual denied types will simply return no data.
  Future<bool> ensureHealthAuthorization() {
    final activeRequest = _authorizationFuture;
    if (activeRequest != null) {
      debugPrint(
        '[HealthService] Duplicate authorization request reused '
        '(requesting: $_isRequestingAuthorization).',
      );
      return activeRequest;
    }

    _isRequestingAuthorization = true;
    final request = _requestAndVerifyAuthorization();
    _authorizationFuture = request;
    return request.whenComplete(() {
      if (identical(_authorizationFuture, request)) {
        _authorizationFuture = null;
        _isRequestingAuthorization = false;
      }
    });
  }

  Future<bool> _requestAndVerifyAuthorization() async {
    final types = _authorizationTypes;
    final access = _authorizationAccess;

    try {
      await _health.configure();
      debugPrint('[HealthService] Authorization check started.');
      final current = await _health.hasPermissions(types, permissions: access);
      if (current == true) return true;

      // A READ check is always null on iOS. Do not reopen the sheet after a
      // request already completed during this app session.
      final previousResult = _authorizationResultThisSession;
      if (current == null && previousResult != null) {
        return previousResult;
      }

      debugPrint('[HealthService] Authorization request started.');
      final requested = await _health.requestAuthorization(
        types,
        permissions: access,
      );
      _authorizationResultThisSession = requested;
      debugPrint('[HealthService] Authorization request result: $requested.');
      return requested;
    } catch (error) {
      _authorizationResultThisSession = false;
      debugPrint('[HealthService] Authorization unavailable: $error');
      return false;
    }
  }

  /// Request HealthKit permission for ALL metrics at once, then do a full sync.
  /// Call this when the user taps "Connect Apple Health" for the first time.
  Future<bool> enableAll() async {
    final granted = await ensureHealthAuthorization();

    if (!granted) return false;

    // Mark all as requested/consented. On iOS, HealthKit does not disclose
    // per-type read grants after the prompt, so this records the user's app
    // intent while the actual charts still depend on real HealthKit data reads.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return granted;
    final consentMap = {for (final m in kHealthMetrics) m.key: true};
    await _db.collection('users').doc(uid).set({
      'healthKitConsent': consentMap,
    }, SetOptions(merge: true));

    // Sync the last 30 days for all metrics.
    await syncToFirestore(daysBack: 30);
    return granted;
  }

  /// Request HealthKit permission for a single metric, then sync it.
  Future<bool> enableMetric(String metricKey) async {
    final def = kMetricByKey[metricKey];
    if (def == null) return false;

    // Use the same complete type/access lists as routine sync authorization.
    // iOS presents permissions once while Firestore consent controls which
    // metrics Vivordo actually reads and stores.
    final granted = await ensureHealthAuthorization();

    await _setConsent(metricKey, granted);
    if (granted) {
      await syncMetric(metricKey, daysBack: 30);
    }
    return granted;
  }

  /// Revoke consent for a metric and remove its data from every daily doc.
  Future<void> disableMetric(String metricKey) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _setConsent(metricKey, false);

    final query = await _db
        .collection('users')
        .doc(uid)
        .collection('metrics_daily')
        .get();
    if (query.docs.isEmpty) return;

    // Firestore batches are capped at 500 ops — chunk to stay under the limit.
    const chunkSize = 400;
    for (int i = 0; i < query.docs.length; i += chunkSize) {
      final chunk = query.docs.sublist(
        i,
        (i + chunkSize).clamp(0, query.docs.length),
      );
      final batch = _db.batch();
      for (final doc in chunk) {
        batch.update(doc.reference, {metricKey: FieldValue.delete()});
      }
      await batch.commit();
    }
  }

  /// Revoke ALL metrics and delete all HealthKit data from Firestore.
  Future<void> disableAll() async {
    for (final m in kHealthMetrics) {
      await disableMetric(m.key);
    }
  }

  // ─── Sync ──────────────────────────────────────────────────────────────────

  Future<void> syncMetric(String metricKey, {int daysBack = 30}) async {
    final authorized = await ensureHealthAuthorization();
    if (!authorized) {
      debugPrint(
        '[HealthService] Health authorization unavailable; skipping sync.',
      );
      return;
    }
    await _syncMetric(metricKey, daysBack: daysBack);
  }

  Future<void> _syncMetric(
    String metricKey, {
    int daysBack = 30,
    bool refreshWearableConnections = true,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (refreshWearableConnections) await _refreshWearableConnections(uid);
    final def = kMetricByKey[metricKey];
    if (def == null) return;

    await _health.configure();

    // HealthKit intentionally does not reveal read authorization status on iOS.
    // Only explicit user actions request permission; routine syncs read the
    // selected metrics and let HealthKit return the data available to the app.

    if (metricKey == 'steps') {
      await _syncStepTotals(uid, daysBack: daysBack);
      return;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: daysBack - 1));

    try {
      if (metricKey == 'sleep') {
        await _syncSleep(uid, start: start, end: now);
        return;
      }

      if (_usesDailyTotals(def.type)) {
        final dataPoints = await _health.getHealthIntervalDataFromTypes(
          startDate: start,
          endDate: now,
          types: [def.type],
          interval: const Duration(days: 1).inSeconds,
        );

        if (dataPoints.isEmpty) {
          debugPrint(
            'HealthService.syncMetric($metricKey): no daily total data returned from Apple Health.',
          );
          await _deleteMetricForMissingDays(
            uid,
            metricKey,
            start: start,
            end: now,
            daysWithData: const {},
          );
          return;
        }

        final daysWithData = await _writeDataPoints(uid, def, dataPoints);
        await _deleteMetricForMissingDays(
          uid,
          metricKey,
          start: start,
          end: now,
          daysWithData: daysWithData,
        );
        return;
      }

      final dataPoints = await _health.getHealthDataFromTypes(
        startTime: start,
        endTime: now,
        types: [def.type],
      );

      if (metricKey == 'steps') {
        debugPrint(
          'DEBUG STEPS: Apple Health returned ${dataPoints.length} step data point(s) for $daysBack day(s).',
        );
      }

      if (dataPoints.isEmpty) {
        if (metricKey == 'steps') {
          debugPrint(
            'DEBUG STEPS: No step data returned from Apple Health. Nothing will be written to Firebase.',
          );
        }
        await _deleteMetricForMissingDays(
          uid,
          metricKey,
          start: start,
          end: now,
          daysWithData: const {},
        );
        return;
      }

      final daysWithData = await _writeDataPoints(uid, def, dataPoints);
      await _deleteMetricForMissingDays(
        uid,
        metricKey,
        start: start,
        end: now,
        daysWithData: daysWithData,
      );
    } catch (e, st) {
      debugPrint('HealthService.syncMetric($metricKey): $e\n$st');
      rethrow; // Surface Firestore/permissions errors to the caller
    }
  }

  Future<void> _syncSleep(
    String uid, {
    required DateTime start,
    required DateTime end,
  }) async {
    final points = await _health.getHealthDataFromTypes(
      startTime: start.subtract(const Duration(hours: 12)),
      endTime: end,
      types: [HealthDataType.SLEEP_ASLEEP, ...kSleepStageTypes],
    );
    final unique = _health.removeDuplicates(points);
    final intervals = <SleepInterval>[];
    for (final point in unique) {
      final stage = _sleepStageForType(point.type);
      if (stage == null || !point.dateTo.isAfter(point.dateFrom)) continue;
      intervals.add(
        SleepInterval(stage: stage, start: point.dateFrom, end: point.dateTo),
      );
    }

    final summaries = summarizeSleepByWakeDay(intervals).where((summary) {
      return !summary.date.isBefore(
            DateTime(start.year, start.month, start.day),
          ) &&
          !summary.date.isAfter(DateTime(end.year, end.month, end.day));
    }).toList();
    final daysWithData = <String>{};

    if (summaries.isNotEmpty) {
      final batch = _db.batch();
      for (final summary in summaries) {
        final day = _formatDate(summary.date);
        daysWithData.add(day);
        final hours = summary.totalAsleepMinutes / 60;
        final entries = summary.asleepIntervals
            .map(
              (interval) => {
                'start': Timestamp.fromDate(interval.start),
                'end': Timestamp.fromDate(interval.end),
                'minutes':
                    interval.end.difference(interval.start).inMilliseconds /
                    60000,
              },
            )
            .toList(growable: false);
        final ref = _db
            .collection('users')
            .doc(uid)
            .collection('metrics_daily')
            .doc(day);
        final existing = await ref.get();
        if (_connectedWearableHasPriority(existing.data(), 'sleep')) continue;
        batch.set(ref, {
          'sleep': {
            'avg': hours,
            'min': hours,
            'max': hours,
            'unit': 'hours',
            'dimension': 'sleep',
            'entries': entries,
            'stages': summary.stageMinutes,
            'bedtime': Timestamp.fromDate(summary.bedtime),
            'wakeTime': Timestamp.fromDate(summary.wakeTime),
            'source': 'apple_health',
            'syncedAt': FieldValue.serverTimestamp(),
          },
          'date': day,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
      debugPrint(
        'HealthService.syncMetric(sleep): wrote sleep totals and stages for '
        '${summaries.length} day(s).',
      );
    }

    await _deleteMetricForMissingDays(
      uid,
      'sleep',
      start: start,
      end: end,
      daysWithData: daysWithData,
    );
  }

  VivordoSleepStage? _sleepStageForType(HealthDataType type) {
    switch (type) {
      case HealthDataType.SLEEP_ASLEEP:
        return VivordoSleepStage.unspecified;
      case HealthDataType.SLEEP_AWAKE:
        return VivordoSleepStage.awake;
      case HealthDataType.SLEEP_LIGHT:
        return VivordoSleepStage.core;
      case HealthDataType.SLEEP_DEEP:
        return VivordoSleepStage.deep;
      case HealthDataType.SLEEP_REM:
        return VivordoSleepStage.rem;
      default:
        return null;
    }
  }

  Future<void> syncToFirestore({int daysBack = 30}) {
    if (daysBack > _pendingSyncDays) _pendingSyncDays = daysBack;

    final activeSync = _activeSync;
    if (activeSync != null) {
      debugPrint('[HealthService] Duplicate sync request reused.');
      return activeSync;
    }

    final worker = _drainSyncQueue();
    _activeSync = worker;
    return worker.whenComplete(() {
      if (identical(_activeSync, worker)) _activeSync = null;
    });
  }

  Future<void> _drainSyncQueue() async {
    while (_pendingSyncDays > 0) {
      final daysBack = _pendingSyncDays;
      _pendingSyncDays = 0;
      await _performSync(daysBack: daysBack);
    }
  }

  Future<void> _performSync({required int daysBack}) async {
    final authorized = await ensureHealthAuthorization();
    if (!authorized) {
      debugPrint(
        '[HealthService] Health authorization unavailable; skipping sync.',
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await _refreshWearableConnections(uid);
    final consent = await getConsent();
    for (final m in kHealthMetrics) {
      if (consent[m.key] == true) {
        try {
          await _syncMetric(
            m.key,
            daysBack: daysBack,
            refreshWearableConnections: false,
          );
        } catch (e) {
          // One metric failing (e.g. permissions) shouldn't stop the others.
          debugPrint('HealthService.syncToFirestore — skipped ${m.key}: $e');
        }
      }
    }

    // Compute and write wellness score for each day in the window
    try {
      await _computeAndWriteWellness(
        uid: FirebaseAuth.instance.currentUser?.uid,
        daysBack: daysBack,
      );
    } catch (e) {
      debugPrint('HealthService.syncToFirestore — wellness compute failed: $e');
    }

    if (uid != null) {
      try {
        await _db.collection('users').doc(uid).set({
          'lastHealthKitSync': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint(
          'HealthService.syncToFirestore — could not update lastSync: $e',
        );
      }
      // Recompute BaaS stress score now that fresh HealthKit data is in Firestore
      StressScoreService.computeAndSave(
        uid: uid,
        force: true,
      ).catchError((_) {});
    }
  }

  Future<void> syncToday() => syncToFirestore(daysBack: 1);

  /// Returns walking/running distance recorded by HealthKit in the supplied
  /// interval. HealthKit reports these samples in metres, so the public value
  /// is converted to kilometres for workout records.
  ///
  /// A null result means Health access is unavailable. A zero result means
  /// access succeeded but HealthKit has not recorded distance for the interval.
  Future<double?> readWalkingRunningDistanceKm({
    required DateTime start,
    DateTime? end,
  }) async {
    if (!await ensureHealthAuthorization()) return null;

    try {
      await _health.configure();
      final points = await _health.getHealthDataFromTypes(
        startTime: start,
        endTime: end ?? DateTime.now(),
        types: const [HealthDataType.DISTANCE_WALKING_RUNNING],
      );
      final uniquePoints = _health.removeDuplicates(points);
      var metres = 0.0;
      for (final point in uniquePoints) {
        if (point.value is! NumericHealthValue) continue;
        metres += (point.value as NumericHealthValue).numericValue.toDouble();
      }
      return metres / 1000;
    } catch (error) {
      debugPrint(
        '[HealthService] Could not read workout distance from HealthKit: $error',
      );
      return null;
    }
  }

  /// Rebuilds the computed wellness score from data already stored in
  /// Firestore. This is used after a camera scan so Wellness immediately uses
  /// the same `heart_rate_scan` average shown by the Heart Rate key metric.
  Future<void> recomputeWellness({int daysBack = 1}) =>
      _computeAndWriteWellness(
        uid: FirebaseAuth.instance.currentUser?.uid,
        daysBack: daysBack,
      );

  // ─── Raw intraday samples for the BaaS ─────────────────────────────────────

  /// Metrics the BaaS actually reads, with the unit string its loader expects.
  /// Anything not in this map is not worth the payload bytes.
  static const _baasRawMetrics = <String, String>{
    'heart_rate': 'bpm',
    'resting_heart_rate': 'bpm',
    'hrv': 'ms',
    'respiratory_rate': 'brpm',
    'blood_oxygen': '%',
    'steps': 'steps',
    'mindfulness': 'min',
    'exercise_time': 'min',
    'sleep': 'hours',
  };

  /// Metrics where the hour's value is a TOTAL, not a reading.
  ///
  /// These must be summed per hour, never subsampled. The BaaS does
  /// `steps_sum = sum(values in the window)`, so handing it 6 of an hour's 120
  /// step samples would not thin the data, it would silently report a
  /// twentieth of the user's activity — and the activity channel is
  /// protective, so under-reporting movement inflates the stress score.
  /// Point-in-time metrics (HR, HRV, SpO2, RR) have the opposite requirement:
  /// summing them is meaningless, and the spread within the hour is real
  /// signal, so those get thinned instead.
  static const _cumulativeMetrics = {
    'steps',
    'mindfulness',
    'exercise_time',
    'active_calories',
  };

  /// Cap on samples kept per metric per hour.
  ///
  /// Not arbitrary: the BaaS preprocessor buckets everything into one-hour
  /// windows, requires >= 3 HR samples/hour to pass its quality gate, and
  /// derives its sleep-fragmentation channel from the SD of HR *within* the
  /// hour. Six preserves both — a real SD and a comfortable margin over the
  /// gate — while cutting an Apple Watch's ~120 readings/hour by 20x.
  /// Collapsing to one sample per hour would silently kill the fragmentation
  /// channel, because SD is undefined for a single value.
  static const _maxSamplesPerHour = 6;

  /// Reads raw intraday HealthKit points and returns them in the BaaS sample
  /// shape, sorted oldest first.
  ///
  /// WHY THIS EXISTS
  /// ───────────────
  /// `_writeDataPoints` aggregates every reading into one daily bucket and
  /// throws the timestamps away, so StressScoreService had to *reconstruct*
  /// fake intraday samples from those daily averages — one HR point pinned at
  /// 12:00, HRV at 06:00, steps smeared across the day by fixed fractions.
  /// That was survivable while the score was a single daily composite. It is
  /// fatal to an intraday score: scoring at 09:00 and at 21:00 produced
  /// byte-identical payloads, so an accumulating score would have had nothing
  /// to accumulate. The raw points were always there — HealthKit returns them
  /// on the very same call the aggregator uses — they were just discarded.
  ///
  /// Only [daysBack] days are read. Raw resolution matters for the days being
  /// scored; the older history behind it exists purely to seed 14-day rolling
  /// baselines, and daily aggregates are sufficient for that (see
  /// StressScoreService._buildPayload, which stitches the two together).
  Future<List<Map<String, dynamic>>> getRawSamplesForBaas({
    int daysBack = 3,
  }) async {
    final consent = await getConsent();
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: daysBack - 1));

    try {
      await _health.configure();
    } catch (e) {
      debugPrint('[HealthService] getRawSamplesForBaas configure failed: $e');
      return [];
    }

    final out = <Map<String, dynamic>>[];

    for (final entry in _baasRawMetrics.entries) {
      final def = kMetricByKey[entry.key];
      if (def == null) continue;
      if (consent[entry.key] != true) continue;

      List<HealthDataPoint> points;
      try {
        points = await _health.getHealthDataFromTypes(
          startTime: start,
          endTime: now,
          types: entry.key == 'sleep'
              ? [HealthDataType.SLEEP_ASLEEP, ...kSleepStageTypes]
              : [def.type],
        );
      } catch (e) {
        // One metric failing must not cost us the rest of the payload.
        debugPrint('[HealthService] getRawSamplesForBaas(${entry.key}): $e');
        continue;
      }
      if (points.isEmpty) continue;

      final unique = _health.removeDuplicates(points);
      if (entry.key == 'sleep') {
        out.addAll(_sleepPointsToBaasSamples(unique, entry.value));
      } else {
        out.addAll(_pointsToBaasSamples(entry.key, entry.value, unique));
      }
    }

    out.sort(
      (a, b) => (a['timestamp'] as String).compareTo(b['timestamp'] as String),
    );
    debugPrint(
      '[HealthService] getRawSamplesForBaas: ${out.length} raw sample(s) '
      'across $daysBack day(s)',
    );
    return out;
  }

  List<Map<String, dynamic>> _sleepPointsToBaasSamples(
    List<HealthDataPoint> points,
    String unit,
  ) {
    final intervals = <SleepInterval>[];
    for (final point in points) {
      final stage = _sleepStageForType(point.type);
      if (stage == null || !point.dateTo.isAfter(point.dateFrom)) continue;
      intervals.add(
        SleepInterval(stage: stage, start: point.dateFrom, end: point.dateTo),
      );
    }

    return summarizeSleepByWakeDay(intervals)
        .expand(
          (summary) => summary.asleepIntervals.map((interval) {
            final duration = interval.end
                .difference(interval.start)
                .inSeconds
                .toDouble();
            return {
              'metric_type': 'sleep',
              'timestamp': _fmtUtcTimestamp(interval.start),
              'value': duration / 3600,
              'unit': unit,
              'source': 'apple_health',
              'duration_seconds': duration,
              // Used only while assembling the stress payload. A sleep
              // interval can start before midnight, while its canonical daily
              // metric is keyed by the day on which the user woke up.
              '_metric_date': _formatDate(summary.date),
            };
          }),
        )
        .toList(growable: false);
  }

  /// Converts HealthKit points for one metric into BaaS samples: summed per
  /// hour for cumulative metrics, thinned per hour for point-in-time ones, and
  /// passed through intact for sleep intervals.
  List<Map<String, dynamic>> _pointsToBaasSamples(
    String metricKey,
    String unit,
    List<HealthDataPoint> points,
  ) {
    // Group by UTC hour so the per-window rules apply per window, rather than
    // letting a busy morning starve the evening of samples.
    final byHour = <DateTime, List<HealthDataPoint>>{};

    for (final p in points) {
      if (p.value is! NumericHealthValue) continue;
      final from = p.dateFrom.toUtc();
      final hour = DateTime.utc(from.year, from.month, from.day, from.hour);
      byHour.putIfAbsent(hour, () => []).add(p);
    }

    double valueOf(HealthDataPoint p) =>
        (p.value as NumericHealthValue).numericValue.toDouble();

    final samples = <Map<String, dynamic>>[];
    final hours = byHour.keys.toList()..sort();

    for (final hour in hours) {
      final bucket = byHour[hour]!
        ..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));

      // ── Cumulative: one summed sample per hour ──────────────────────────
      if (_cumulativeMetrics.contains(metricKey)) {
        final total = bucket.fold<double>(0.0, (a, p) => a + valueOf(p));
        if (total <= 0) continue;
        samples.add({
          'metric_type': metricKey,
          'timestamp': _fmtUtcTimestamp(hour),
          'value': total,
          'unit': unit,
          'source': 'apple_health',
          'duration_seconds': 3600.0,
        });
        continue;
      }

      // ── Sleep: intervals pass through intact ────────────────────────────
      // The BaaS derives which hours count as sleep windows from
      // timestamp + duration_seconds, and a night is only a handful of
      // intervals, so there is nothing here worth thinning.
      if (metricKey == 'sleep') {
        for (final p in bucket) {
          final secs = p.dateTo.difference(p.dateFrom).inSeconds.toDouble();
          final duration = secs > 0 ? secs : valueOf(p) * 60.0;
          samples.add({
            'metric_type': metricKey,
            'timestamp': _fmtUtcTimestamp(p.dateFrom),
            'value': duration / 3600.0, // hours, matching the unit
            'unit': unit,
            'source': 'apple_health',
            'duration_seconds': duration,
          });
        }
        continue;
      }

      // ── Point-in-time: thin, preserving the within-hour spread ──────────
      for (final p in _thin(bucket, _maxSamplesPerHour)) {
        var value = valueOf(p);
        if (metricKey == 'blood_oxygen') {
          // Mirrors _buildValueMap: HealthKit reports SpO2 as a 0-1 fraction
          // on some sources and 0-100 on others. The BaaS range-checks this
          // against 70-100 and would silently drop every fractional reading.
          value = value <= 1 ? value * 100 : value;
        }
        samples.add({
          'metric_type': metricKey,
          'timestamp': _fmtUtcTimestamp(p.dateFrom),
          'value': value,
          'unit': unit,
          'source': 'apple_health',
          'duration_seconds': null,
        });
      }
    }

    return samples;
  }

  /// Evenly spaced subsample of [items], preserving the first element.
  List<T> _thin<T>(List<T> items, int max) {
    if (items.length <= max) return items;
    final step = items.length / max;
    final out = <T>[];
    for (var i = 0; i < max; i++) {
      out.add(items[(i * step).floor().clamp(0, items.length - 1)]);
    }
    return out;
  }

  /// "YYYY-MM-DDTHH:MM:SS+00:00" — Python's datetime.fromisoformat rejects a
  /// bare "Z" before 3.11, and the BaaS payload contract predates its move
  /// to 3.12.
  static String _fmtUtcTimestamp(DateTime dt) {
    final u = dt.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${u.year}-${two(u.month)}-${two(u.day)}T'
        '${two(u.hour)}:${two(u.minute)}:${two(u.second)}+00:00';
  }

  // ─── Internal helpers ──────────────────────────────────────────────────────

  bool _usesDailyTotals(HealthDataType type) {
    return type == HealthDataType.ACTIVE_ENERGY_BURNED ||
        type == HealthDataType.DISTANCE_WALKING_RUNNING;
  }

  Future<void> _syncStepTotals(String uid, {int daysBack = 30}) async {
    // Apple Health is the single canonical step source, including steps that
    // a wearable may have contributed to HealthKit.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final batch = _db.batch();
    final daysWithData = <String>{};
    var daysWritten = 0;

    for (var i = 0; i < daysBack; i++) {
      final day = today.subtract(Duration(days: i));
      final end = i == 0 ? now : day.add(const Duration(days: 1));
      var total = (await _health.getTotalStepsInInterval(day, end))?.toDouble();

      if (total == null) {
        debugPrint(
          'HealthService.syncMetric(steps): total API returned null for ${_formatDate(day)}. Trying raw step samples.',
        );
        total = await _readRawStepTotal(day, end);
        if (total == null) {
          debugPrint(
            'HealthService.syncMetric(steps): no raw step data returned for ${_formatDate(day)}',
          );
          continue;
        }
      }

      final dayKey = _formatDate(day);
      daysWithData.add(dayKey);
      final ref = _db
          .collection('users')
          .doc(uid)
          .collection('metrics_daily')
          .doc(dayKey);
      batch.set(ref, {
        'steps': {
          'sum': total,
          'avg': total,
          'unit': 'steps',
          'dimension': 'activity',
          'source': 'apple_health',
          'syncedAt': FieldValue.serverTimestamp(),
        },
        'date': dayKey,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      daysWritten++;
    }

    if (daysWritten == 0) return;
    await batch.commit();
    await _deleteMetricForMissingDays(
      uid,
      'steps',
      start: today.subtract(Duration(days: daysBack - 1)),
      end: now,
      daysWithData: daysWithData,
    );
    debugPrint(
      'HealthService.syncMetric(steps): wrote Apple Health step totals for $daysWritten day(s).',
    );
  }

  Future<double?> _readRawStepTotal(DateTime start, DateTime end) async {
    final points = await _health.getHealthDataFromTypes(
      startTime: start,
      endTime: end,
      types: [HealthDataType.STEPS],
    );

    var total = 0.0;
    for (final point in points) {
      if (point.value is! NumericHealthValue) continue;
      total += (point.value as NumericHealthValue).numericValue.toDouble();
    }

    return points.isEmpty ? null : total;
  }

  Future<void> _deleteMetricForMissingDays(
    String uid,
    String metricKey, {
    required DateTime start,
    required DateTime end,
    required Set<String> daysWithData,
  }) async {
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    final days = endDay.difference(startDay).inDays + 1;
    if (days <= 0) return;

    final batch = _db.batch();
    var deletes = 0;

    for (var i = 0; i < days; i++) {
      final dayKey = _formatDate(startDay.add(Duration(days: i)));
      if (daysWithData.contains(dayKey)) continue;

      final ref = _db
          .collection('users')
          .doc(uid)
          .collection('metrics_daily')
          .doc(dayKey);
      final snapshot = await ref.get();
      if (metricKey != 'steps' &&
          _connectedWearableHasPriority(snapshot.data(), metricKey)) {
        continue;
      }
      if (metricKey == 'exercise_time') {
        final exerciseTime =
            snapshot.data()?['exercise_time'] as Map<String, dynamic>?;
        final workoutMinutes =
            (exerciseTime?['workoutMinutes'] as num?)?.toDouble() ?? 0;
        if (workoutMinutes > 0) {
          batch.set(ref, {
            'exercise_time': {
              ...?exerciseTime,
              'healthSum': 0,
              'workoutMinutes': workoutMinutes,
              'sum': workoutMinutes,
              'unit': 'min',
              'dimension': 'activity',
            },
            'date': dayKey,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } else {
          batch.set(ref, {
            metricKey: FieldValue.delete(),
          }, SetOptions(merge: true));
        }
      } else {
        batch.set(ref, {
          metricKey: FieldValue.delete(),
        }, SetOptions(merge: true));
      }
      deletes++;
    }

    if (deletes == 0) return;

    try {
      await batch.commit();
    } catch (e) {
      debugPrint(
        'HealthService.syncMetric($metricKey): stale-day cleanup skipped: $e',
      );
    }
  }

  Future<void> _setConsent(String metricKey, bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({
      'healthKitConsent.$metricKey': value,
    });
  }

  Future<Set<String>> _writeDataPoints(
    String uid,
    HealthMetricDef def,
    List<HealthDataPoint> dataPoints,
  ) async {
    final Map<String, List<double>> byDay = {};
    final Map<String, List<Map<String, dynamic>>> heartRateEntriesByDay = {};
    final Map<String, List<Map<String, dynamic>>> sleepEntriesByDay = {};
    for (final point in dataPoints) {
      if (point.value is! NumericHealthValue) continue;
      final day = _formatDate(point.dateFrom);
      final val = (point.value as NumericHealthValue).numericValue.toDouble();
      byDay.putIfAbsent(day, () => []).add(val);
      if (def.type == HealthDataType.HEART_RATE) {
        heartRateEntriesByDay.putIfAbsent(day, () => []).add({
          'bpm': val,
          'timestamp': Timestamp.fromDate(point.dateFrom),
        });
      }
      if (def.type == HealthDataType.SLEEP_ASLEEP) {
        sleepEntriesByDay.putIfAbsent(day, () => []).add({
          'start': Timestamp.fromDate(point.dateFrom),
          'end': Timestamp.fromDate(point.dateTo),
          'minutes': val,
        });
      }
    }

    if (byDay.isEmpty) return {};

    final batch = _db.batch();
    final daysWithData = <String>{};
    final appleHeartRatePayloads = <String, Map<String, dynamic>>{};
    for (final entry in byDay.entries) {
      final day = entry.key;
      daysWithData.add(day);
      final vals = entry.value;
      final ref = _db
          .collection('users')
          .doc(uid)
          .collection('metrics_daily')
          .doc(day);
      final existingSnapshot = await ref.get();
      final payload = _buildValueMap(def.type, vals);
      if (def.type == HealthDataType.EXERCISE_TIME) {
        final existingExerciseTime =
            existingSnapshot.data()?['exercise_time'] as Map<String, dynamic>?;
        final healthMinutes = (payload['sum'] as num?)?.toDouble() ?? 0;
        final workoutMinutes =
            (existingExerciseTime?['workoutMinutes'] as num?)?.toDouble() ?? 0;
        payload['healthSum'] = healthMinutes;
        payload['workoutMinutes'] = workoutMinutes;
        payload['sum'] = healthMinutes + workoutMinutes;
      }
      if (def.type == HealthDataType.HEART_RATE) {
        final entries = heartRateEntriesByDay[day] ?? const [];
        entries.sort((a, b) {
          final aTime = a['timestamp'] as Timestamp;
          final bTime = b['timestamp'] as Timestamp;
          return aTime.compareTo(bTime);
        });
        payload['entries'] = entries;
        batch.set(ref, {
          'heart_rate_sources': {
            'apple_health': {
              ...payload,
              'source': 'apple_health',
              'syncedAt': FieldValue.serverTimestamp(),
            },
          },
        }, SetOptions(merge: true));
        appleHeartRatePayloads[day] = Map<String, dynamic>.from(payload);
        continue;
      }
      if (_connectedWearableHasPriority(existingSnapshot.data(), def.key)) {
        continue;
      }
      if (def.type == HealthDataType.SLEEP_ASLEEP) {
        final entries = sleepEntriesByDay[day] ?? const [];
        entries.sort((a, b) {
          final aTime = a['start'] as Timestamp;
          final bTime = b['start'] as Timestamp;
          return aTime.compareTo(bTime);
        });
        if (entries.isNotEmpty) {
          payload['entries'] = entries;
          payload['bedtime'] = entries.first['start'];
          payload['wakeTime'] = entries
              .map((entry) => entry['end'] as Timestamp)
              .reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
        }
      }

      if (def.key == 'steps') {
        debugPrint('DEBUG STEPS: Preparing Firebase write for $day');
        debugPrint('DEBUG STEPS: Values = $vals');
        debugPrint('DEBUG STEPS: Payload = $payload');
      }

      batch.set(ref, {
        def.key: {
          ...payload,
          'source': 'apple_health',
          'syncedAt': FieldValue.serverTimestamp(),
        },
        'date': day,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    try {
      await batch.commit();
      for (final entry in appleHeartRatePayloads.entries) {
        await _promoteAppleHeartRateIfBleStale(uid, entry.key, entry.value);
      }
      debugPrint(
        'DEBUG: Firestore batch commit succeeded for ${def.key}. Days written: ${byDay.length}',
      );
      return daysWithData;
    } catch (e, st) {
      debugPrint('DEBUG: Firestore batch commit FAILED for ${def.key}: $e');
      debugPrint(st.toString());
      rethrow;
    }
  }

  Future<void> _promoteAppleHeartRateIfBleStale(
    String uid,
    String day,
    Map<String, dynamic> payload,
  ) async {
    final reference = _db
        .collection('users')
        .doc(uid)
        .collection('metrics_daily')
        .doc(day);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      final sources = snapshot.data()?['heart_rate_sources'] as Map?;
      final whoopBle = sources?['whoop_ble'] as Map?;
      final rawLastReading = whoopBle?['lastReadingAt'];
      final lastReadingAt = rawLastReading is Timestamp
          ? rawLastReading.toDate()
          : null;
      final bluetoothIsFresh =
          lastReadingAt != null &&
          DateTime.now().difference(lastReadingAt) <=
              const Duration(minutes: 5);
      if (bluetoothIsFresh) return;
      transaction.set(reference, {
        'heart_rate': {
          ...payload,
          'source': 'apple_health',
          'syncedAt': FieldValue.serverTimestamp(),
        },
        'date': day,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Map<String, dynamic> _buildValueMap(HealthDataType type, List<double> vals) {
    double sum() => vals.fold(0.0, (a, b) => a + b);
    double avg() => sum() / vals.length;
    double min() => vals.reduce((a, b) => a < b ? a : b);
    double max() => vals.reduce((a, b) => a > b ? a : b);
    double normalizePercent(double value) => value <= 1 ? value * 100 : value;

    switch (type) {
      // ── Cumulative (sum is meaningful) ──────────────────────────────────────
      case HealthDataType.STEPS:
        return {
          'sum': sum(),
          'avg': avg(),
          'unit': 'steps',
          'dimension': 'activity',
        };
      case HealthDataType.ACTIVE_ENERGY_BURNED:
        return {
          'sum': sum(),
          'avg': avg(),
          'unit': 'kcal',
          'dimension': 'activity',
        };
      case HealthDataType.EXERCISE_TIME:
        return {
          'sum': sum(),
          'avg': avg(),
          'unit': 'min',
          'dimension': 'activity',
        };
      case HealthDataType.DISTANCE_WALKING_RUNNING:
        return {
          'sum': sum() / 1000,
          'avg': avg() / 1000,
          'unit': 'km',
          'dimension': 'activity',
        };
      // ── Point-in-time averages ───────────────────────────────────────────────
      case HealthDataType.HEART_RATE:
      case HealthDataType.RESTING_HEART_RATE:
        return {
          'avg': avg(),
          'min': min(),
          'max': max(),
          'unit': 'bpm',
          'dimension': 'cardiovascular',
        };

      case HealthDataType.HEART_RATE_VARIABILITY_SDNN:
        final hrvAvg = avg();
        final stress = ((1.0 - (hrvAvg.clamp(0, 100) / 100)) * 100).clamp(
          0.0,
          100.0,
        );
        return {
          'avg': hrvAvg,
          'stressScore': stress,
          'unit': 'ms',
          'dimension': 'stress',
        };

      case HealthDataType.BLOOD_OXYGEN:
        return {
          'avg': normalizePercent(avg()),
          'min': normalizePercent(min()),
          'max': normalizePercent(max()),
          'unit': '%',
          'dimension': 'cardiovascular',
        };

      case HealthDataType.RESPIRATORY_RATE:
        return {
          'avg': avg(),
          'min': min(),
          'max': max(),
          'unit': 'brpm',
          'dimension': 'respiratory',
        };

      // ── Sleep (health package returns minutes for interval-based sleep data) ─
      case HealthDataType.SLEEP_ASLEEP:
      case HealthDataType.SLEEP_IN_BED:
        final hours = sum() / 60;
        return {
          'avg': hours,
          'min': min() / 60,
          'max': max() / 60,
          'unit': 'hours',
          'dimension': 'sleep',
        };

      // ── Body metrics ─────────────────────────────────────────────────────────
      case HealthDataType.WEIGHT:
        return {'avg': avg(), 'unit': 'kg', 'dimension': 'body'};
      case HealthDataType.BODY_FAT_PERCENTAGE:
        return {
          'avg': normalizePercent(avg()),
          'unit': '%',
          'dimension': 'body',
        };
      // case HealthDataType.VO2MAX:
      //   return {'avg': avg(), 'unit': 'ml/kg/min', 'dimension': 'fitness'};

      default:
        return {'avg': avg(), 'unit': '', 'dimension': 'other'};
    }
  }

  String _formatDate(DateTime dt) => DateFormat('yyyy-MM-dd').format(dt);

  double _heartRateWellnessScore(double bpm) {
    if (bpm >= 60 && bpm <= 80) return 100;
    final distanceFromOptimal = bpm < 60 ? 60 - bpm : bpm - 80;
    return (100 - distanceFromOptimal * 2.5).clamp(0.0, 100.0);
  }

  Future<void> _computeAndWriteWellness({
    String? uid,
    int daysBack = 30,
  }) async {
    if (uid == null) return;
    final now = DateTime.now();
    final batch = _db.batch();
    final userSnapshot = await _db.collection('users').doc(uid).get();
    final activityGoals = ActivityGoals.fromUserData(userSnapshot.data());

    for (int i = 0; i < daysBack; i++) {
      final day = now.subtract(Duration(days: i));
      final period = _formatDate(day);

      final snap = await _db
          .collection('users')
          .doc(uid)
          .collection('metrics_daily')
          .doc(period)
          .get();
      final data = snap.data();

      final stress = (data?['stress']?['avg'] as num?)?.toDouble();
      final sleep = (data?['sleep']?['avg'] as num?)?.toDouble();
      final steps = (data?['steps']?['sum'] as num?)?.toDouble();
      final exerciseMinutes = (data?['exercise_time']?['sum'] as num?)
          ?.toDouble();
      final activeCalories = (data?['active_calories']?['sum'] as num?)
          ?.toDouble();
      final heartRate = (data?['heart_rate_scan']?['avg'] as num?)?.toDouble();
      final activity = calculateActivityScore(
        steps: steps,
        exerciseMinutes: exerciseMinutes,
        activeCalories: activeCalories,
        stepsGoal: activityGoals.steps.toDouble(),
        exerciseMinutesGoal: activityGoals.exerciseMinutes.toDouble(),
        activeCaloriesGoal: activityGoals.activeCalories.toDouble(),
      );

      if (stress == null &&
          sleep == null &&
          activity == null &&
          heartRate == null) {
        continue;
      }

      double wellness = 0;
      int weight = 0;

      if (stress != null) {
        wellness += (100 - stress) * 0.35;
        weight += 35;
      }
      if (sleep != null) {
        final sleepScore = ((sleep / 8.0) * 100).clamp(0.0, 100.0);
        wellness += sleepScore * 0.30;
        weight += 30;
      }
      if (activity != null) {
        wellness += activity.score * 0.20;
        weight += 20;
      }
      if (heartRate != null) {
        wellness += _heartRateWellnessScore(heartRate) * 0.15;
        weight += 15;
      }

      final finalWellness = weight > 0
          ? (wellness / weight * 100).clamp(0.0, 100.0)
          : 0.0;

      final ref = _db
          .collection('users')
          .doc(uid)
          .collection('metrics_daily')
          .doc(period);
      batch.set(ref, {
        'wellness': {
          'avg': finalWellness,
          'unit': 'score',
          'source': 'computed',
          'computedAt': FieldValue.serverTimestamp(),
        },
        'date': period,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }
}
