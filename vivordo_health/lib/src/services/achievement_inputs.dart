import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';

import '../utils/performance_trace.dart';
import 'activity_goals_service.dart';

typedef AchievementFieldReader = Object? Function(String path);
typedef AchievementMetricDay = ({
  int scans,
  int moods,
  num? steps,
  num? calories,
  num? minutes,
});

AchievementMetricDay projectAchievementDay(AchievementFieldReader read) {
  int count(String metric, bool Function() legacy) {
    final entries = read('$metric.entries');
    return entries is List && entries.isNotEmpty
        ? entries.length
        : legacy()
        ? 1
        : 0;
  }

  return (
    scans: count(
      'heart_rate_scan',
      () =>
          read('heart_rate_scan.source') == 'camera_ppg' ||
          read('heart_rate_scan.avg') is num,
    ),
    moods: count(
      'mood',
      () => read('mood.avg') is num || read('mood.label') is String,
    ),
    steps: read('steps.sum') as num?,
    calories: read('active_calories.sum') as num?,
    minutes: read('exercise_time.sum') as num?,
  );
}

/// Server-projected summary day (functions/metrics_summary.js), or null when
/// the document predates the scan/mood counts.
AchievementMetricDay? projectAchievementSummary(AchievementFieldReader read) {
  final scans = read('scans');
  final moods = read('moods');
  if (scans is! int || moods is! int) return null;
  return (
    scans: scans,
    moods: moods,
    steps: read('steps.sum') as num?,
    calories: read('active_calories.sum') as num?,
    minutes: read('exercise_time.sum') as num?,
  );
}

bool projectAchievementWorkout(AchievementFieldReader read) {
  final category = read('activityCategory');
  if (category == 'Cardio' || category == 'Sports') return true;
  final exercises = (read('exercises') as List? ?? const [])
      .whereType<Map>()
      .toList(growable: false);
  return exercises.isNotEmpty &&
      exercises.every(
        (exercise) =>
            exercise['category'] == 'Cardio' ||
            exercise['category'] == 'Sports',
      );
}

class AchievementInputs {
  AchievementInputs(
    Map<String, AchievementMetricDay> days,
    Map<String, bool> workouts,
  ) : days = Map.unmodifiable(days),
      workoutCount = workouts.length,
      cardioCount = workouts.values.where((cardio) => cardio).length;

  final Map<String, AchievementMetricDay> days;
  final int workoutCount;
  final int cardioCount;
  int get scans => days.values.fold(0, (total, day) => total + day.scans);
  int get moods => days.values.fold(0, (total, day) => total + day.moods);
  int ringDays(ActivityGoals goals) => days.values
      .where(
        (day) =>
            day.steps != null &&
            day.calories != null &&
            day.minutes != null &&
            day.steps! >= goals.steps &&
            day.calories! >= goals.activeCalories &&
            day.minutes! >= goals.exerciseMinutes,
      )
      .length;
}

/// One lifetime-history subscription per input, shared by the monitor and UI.
/// Keeps only small derived records.
///
/// Metrics come from the compact `metric_summaries_daily` projection once the
/// account's lifetime backfill is verified and enabled
/// (functions/scripts/backfill_achievement_summaries.js); otherwise from full
/// `metrics_daily` documents, whose every change re-sends the whole history
/// over the platform channel.
class AchievementInputsRepository {
  AchievementInputsRepository(FirebaseFirestore db, this.uid) {
    final user = _user = db.collection('users').doc(uid);
    unawaited(_connectMetrics());
    _subscriptions.add(
      user
          .collection('workouts')
          .snapshots()
          .listen(
            (snapshot) => _accept(snapshot, false),
            onError: (Object error) => _fail(error, false),
          ),
    );
  }

  final String uid;
  final _days = <String, AchievementMetricDay>{};
  final _workouts = <String, bool>{};
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _events = StreamController<bool>.broadcast();
  bool _metricsReady = false, _workoutsReady = false, _closed = false;
  Object? _metricsError, _workoutsError;
  AchievementInputs? _cached;
  late final DocumentReference<Map<String, dynamic>> _user;
  StreamSubscription<dynamic>? _metrics;
  bool _summaries = false;
  Stream<bool> get changes => _events.stream;

  Future<void> _connectMetrics() async {
    var enabled = false;
    try {
      final marker = await _user
          .collection('metrics_summary_migrations')
          .doc('achievements')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 3));
      enabled =
          marker.data()?['enabled'] == true &&
          marker.data()?['status'] == 'complete';
    } catch (_) {
      /* Offline or not rolled out: full history. */
    }
    if (!_closed) _listenMetrics(enabled);
  }

  void _listenMetrics(bool summaries) {
    _summaries = summaries;
    _metrics = _user
        .collection(summaries ? 'metric_summaries_daily' : 'metrics_daily')
        .snapshots()
        .listen(
          (snapshot) => _accept(snapshot, true),
          onError: (Object error) =>
              summaries ? _fallBack() : _fail(error, true),
        );
  }

  /// A summary the reader cannot trust (unprojected, or unreadable) drops the
  /// session back to full documents rather than undercounting.
  void _fallBack() {
    if (_closed || !_summaries) return;
    unawaited(_metrics?.cancel());
    _days.clear();
    _metricsReady = false;
    _cached = null;
    _listenMetrics(false);
  }

  void _accept(QuerySnapshot<Map<String, dynamic>> snapshot, bool metrics) {
    if (_closed) return;
    if (metrics &&
        _summaries &&
        snapshot.docChanges.any(
          (change) =>
              change.type != DocumentChangeType.removed &&
              projectAchievementSummary((p) => _field(change.doc, p)) == null,
        )) {
      _fallBack();
      return;
    }
    try {
      PerformanceTrace.measure(
        'achievements.project.${metrics ? 'metrics' : 'workouts'}',
        () {
          var changed = metrics
              ? !_metricsReady || _metricsError != null
              : !_workoutsReady || _workoutsError != null;
          for (final change in snapshot.docChanges) {
            final id = change.doc.id;
            if (change.type == DocumentChangeType.removed) {
              final removed = metrics ? _days.remove(id) : _workouts.remove(id);
              changed = removed != null || changed;
            } else if (metrics) {
              AchievementMetricDay read(AchievementFieldReader field) =>
                  _summaries
                  ? projectAchievementSummary(field)!
                  : projectAchievementDay(field);
              final day = read((path) => _field(change.doc, path));
              if (_days[id] != day) {
                _days[id] = day;
                changed = true;
              }
            } else {
              final cardio = projectAchievementWorkout(
                (path) => _field(change.doc, path),
              );
              if (_workouts[id] != cardio) {
                _workouts[id] = cardio;
                changed = true;
              }
            }
          }
          if (metrics) {
            _metricsReady = true;
            _metricsError = null;
          } else {
            _workoutsReady = true;
            _workoutsError = null;
          }
          if (changed) _cached = null;
          _events.add(changed);
        },
      );
    } catch (error) {
      if (metrics && _summaries) {
        _fallBack();
      } else {
        _fail(error, metrics);
      }
    }
  }

  void _fail(Object error, bool metrics) {
    if (_closed) return;
    if (metrics) {
      _metricsError = error;
    } else {
      _workoutsError = error;
    }
    _events.add(false);
  }

  Future<AchievementInputs> load() async {
    if (!_closed &&
        _metricsError == null &&
        _workoutsError == null &&
        !(_metricsReady && _workoutsReady)) {
      await changes
          .firstWhere(
            (_) =>
                _closed ||
                _metricsError != null ||
                _workoutsError != null ||
                (_metricsReady && _workoutsReady),
          )
          .timeout(const Duration(seconds: 15));
    }
    if (_closed) throw StateError('Achievement inputs disposed');
    final error = _metricsError ?? _workoutsError;
    if (error != null) throw error;
    return _cached ??= AchievementInputs(_days, _workouts);
  }

  static Object? _field(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String path,
  ) {
    try {
      return doc.get(path);
    } on StateError {
      return null;
    }
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _days.clear();
    _workouts.clear();
    _cached = null;
    _events.add(false);
    await Future.wait([..._subscriptions, ?_metrics].map((s) => s.cancel()));
    await _events.close();
  }
}

/// Requests during a run collapse into one trailing run; no update is lost.
class AchievementReconciliationQueue<T> {
  AchievementReconciliationQueue(this._run);
  final Future<T> Function() _run;
  Future<T>? _active;
  bool _dirty = false;
  bool valid = true;

  void markDirty() {
    if (_active != null && valid) _dirty = true;
  }

  Future<T> request() {
    if (!valid) return Future.error(StateError('Achievement session ended'));
    _dirty = true;
    return _active ??= Future<T>.microtask(() async {
      try {
        late T result;
        do {
          _dirty = false;
          try {
            result = await _run();
          } catch (_) {
            // A fresh request received during a failed run still gets its turn.
            if (_dirty && valid) continue;
            rethrow;
          }
        } while (_dirty && valid);
        return result;
      } finally {
        _active = null;
      }
    });
  }
}

/// Compare only fields we write; server timestamps and unrelated fields do not
/// make an otherwise unchanged achievement dirty.
bool achievementFieldsChanged(
  Map<String, dynamic>? saved,
  Map<String, dynamic> next,
) =>
    saved == null ||
    next.entries.any(
      (entry) =>
          !const DeepCollectionEquality().equals(saved[entry.key], entry.value),
    );
