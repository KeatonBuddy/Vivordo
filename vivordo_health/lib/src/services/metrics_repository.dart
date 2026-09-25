import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/fitness_activity_history.dart';
import '../utils/performance_trace.dart';
import '../utils/screen_metric_projection.dart';
export '../utils/screen_metric_projection.dart' show MetricsProjection;

/// Immutable cached data plus transport state. Measurement timestamps remain
/// in each metric; receiving a snapshot does not make old measurements fresh.
class MetricWindow {
  const MetricWindow({
    required this.days,
    this.isFromCache = true,
    this.hasPendingWrites = false,
    this.refreshing = false,
    this.error,
  });
  final Map<String, Map<String, dynamic>> days;
  final bool isFromCache;
  final bool hasPendingWrites;
  final bool refreshing;
  final Object? error;
}

/// Shares exact query/projection windows, with reference-counted subscriptions.
/// Detailed readers remain on the legacy source until parity is proven.
class MetricsRepository {
  MetricsRepository({
    required FirebaseFirestore firestore,
    required String? uid,
    Stream<String?>? accounts,
  }) : _db = firestore,
       _uid = uid {
    _auth = accounts?.listen(switchAccount);
  }

  static MetricsRepository? _instance;
  static MetricsRepository get instance => _instance ??= MetricsRepository(
    firestore: FirebaseFirestore.instance,
    uid: FirebaseAuth.instance.currentUser?.uid,
    accounts: FirebaseAuth.instance.authStateChanges().map((user) => user?.uid),
  );
  final FirebaseFirestore _db;
  String? _uid;
  bool _disposed = false;
  StreamSubscription<String?>? _auth;
  final _windows = <Object, _SharedWindow>{};

  int get activeSubscriptions => _windows.values.where((w) => w.active).length;

  /// Summary rollout requires BOTH an opt-in build and a server-owned marker
  /// created only after deployment/backfill verification. Default is legacy.
  Stream<MetricWindow> watchActivity({
    required String uid,
    required String startDay,
    required String endDay,
    bool allowSummaries = const bool.fromEnvironment(
      'VIVORDO_ACTIVITY_SUMMARIES',
    ),
  }) {
    if (!allowSummaries) {
      return watch(
        uid: uid,
        startDay: startDay,
        endDay: endDay,
        projection: MetricsProjection.activity,
      );
    }
    return Stream.multi((controller) {
      StreamSubscription<MetricWindow>? subscription;
      var cancelled = false;
      var fallingBack = false;
      Future<void> connect(bool summaries) async {
        await subscription?.cancel();
        if (cancelled || _disposed || uid != _uid) {
          controller.close();
          return;
        }
        subscription =
            watch(
              uid: uid,
              startDay: startDay,
              endDay: endDay,
              projection: MetricsProjection.activity,
              useSummaries: summaries,
            ).listen(
              (value) {
                if (cancelled) return;
                if (summaries && value.error != null && !fallingBack) {
                  fallingBack = true;
                  unawaited(connect(false));
                  return;
                }
                controller.add(value);
              },
              onDone: controller.close,
              onError: controller.addError,
            );
      }

      unawaited(() async {
        var ready = false;
        try {
          final marker = await _db
              .doc('users/$uid/metrics_summary_migrations/v1')
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 3));
          final data = marker.data();
          ready =
              data?['enabled'] == true &&
              data?['schemaVersion'] == 1 &&
              data?['status'] == 'complete' &&
              data?['startDay'] is String &&
              (data!['startDay'] as String).compareTo(startDay) <= 0 &&
              data['endDay'] is String &&
              (data['endDay'] as String).compareTo(endDay) >= 0;
        } catch (_) {
          /* Offline or not deployed: use the established source. */
        }
        if (!cancelled) await connect(ready);
      }());
      controller.onCancel = () {
        cancelled = true;
        return subscription?.cancel();
      };
    });
  }

  void switchAccount(String? uid) {
    if (_uid == uid) return;
    _uid = uid;
    for (final window in _windows.values) {
      window.close();
    }
    _windows.clear();
  }

  Stream<MetricWindow> watch({
    required String uid,
    required String startDay,
    required String endDay,
    required MetricsProjection projection,
    bool useSummaries = false,
  }) {
    // Only activity has a verified compact contract so far. Historical capacity
    // and source-aware heart-rate calculations must still see detailed inputs.
    if (useSummaries && projection != MetricsProjection.activity) {
      throw ArgumentError('Only activity summary reads are supported');
    }
    final key = (uid, startDay, endDay, projection, useSummaries);
    return Stream.multi((controller) {
      if (_disposed || uid != _uid) {
        controller.add(const MetricWindow(days: {}));
        controller.close();
        return;
      }
      var window = _windows[key];
      if (window == null) {
        // Bound retained inactive windows (day changes, navigations, etc.). Active
        // consumers are never evicted. No persistent health cache is added here.
        while (_windows.values.where((w) => !w.active).length >= 6) {
          final oldest = _windows.entries.firstWhere((e) => !e.value.active);
          oldest.value.close();
          _windows.remove(oldest.key);
        }
        final source = _db
            .collection('users')
            .doc(uid)
            .collection(
              useSummaries ? 'metric_summaries_daily' : 'metrics_daily',
            )
            .where(FieldPath.documentId, isGreaterThanOrEqualTo: startDay)
            .where(FieldPath.documentId, isLessThanOrEqualTo: endDay)
            .orderBy(FieldPath.documentId)
            .snapshots(includeMetadataChanges: true);
        window = _SharedWindow(source, projection, useSummaries, endDay);
        _windows[key] = window;
      }
      final subscription = window.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = subscription.cancel;
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    await _auth?.cancel();
    for (final window in _windows.values) {
      window.close();
    }
    _windows.clear();
  }
}

class _SharedWindow {
  _SharedWindow(this.source, this.projection, this.summarySource, this.endDay);
  final Stream<QuerySnapshot<Map<String, dynamic>>> source;
  final MetricsProjection projection;
  final bool summarySource;
  final String endDay;
  final _hearts = <String, PreparedHeartRate>{};
  String? _heartDay;
  final _listeners = <MultiStreamController<MetricWindow>>{};
  var _activity = FitnessActivityHistory();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  MetricWindow? _latest;
  bool _closed = false;
  int _generation = 0;
  bool get active => _listeners.isNotEmpty;

  late final Stream<MetricWindow> stream = Stream.multi((controller) {
    if (_closed) {
      controller.close();
      return;
    }
    _listeners.add(controller);
    final latest = _latest;
    if (latest != null) {
      controller.add(
        MetricWindow(
          days: latest.days,
          isFromCache: latest.isFromCache,
          hasPendingWrites: latest.hasPendingWrites,
          refreshing: _subscription == null || latest.refreshing,
          error: latest.error,
        ),
      );
    }
    controller.onCancel = () {
      _listeners.remove(controller);
      if (_listeners.isEmpty) {
        ++_generation;
        final cached = _latest;
        if (cached != null) {
          _latest = MetricWindow(
            days: cached.days,
            isFromCache: true,
            hasPendingWrites: cached.hasPendingWrites,
            refreshing: true,
            error: cached.error,
          );
        }
        final sub = _subscription;
        _subscription = null;
        return sub?.cancel();
      }
    };
    if (_subscription != null) return;
    final generation = ++_generation;
    _subscription = source.listen(
      (snapshot) {
        if (_closed || generation != _generation) return;
        try {
          final days = PerformanceTrace.measure(
            'metrics.project.${projection.name}',
            () => _project(snapshot),
          );
          final next = MetricWindow(
            days: days,
            isFromCache: snapshot.metadata.isFromCache,
            hasPendingWrites: snapshot.metadata.hasPendingWrites,
          );
          final old = _latest;
          if (old != null &&
              identical(old.days, days) &&
              old.isFromCache == next.isFromCache &&
              old.hasPendingWrites == next.hasPendingWrites &&
              old.error == null &&
              !old.refreshing) {
            return;
          }
          _emit(next);
        } catch (error) {
          _error(error);
        }
      },
      onError: (Object error) {
        if (!_closed && generation == _generation) _error(error);
      },
    );
  });

  void _error(Object error) => _emit(
    MetricWindow(
      days: _latest?.days ?? const {},
      isFromCache: true,
      error: error,
    ),
  );

  void _emit(MetricWindow value) {
    _latest = value;
    for (final listener in _listeners.toList()) {
      listener.add(value);
    }
  }

  Map<String, Map<String, dynamic>> _project(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (projection == MetricsProjection.activity) {
      if (summarySource &&
          snapshot.docs.any((doc) => _field(doc, 'schemaVersion') != 1)) {
        throw StateError('Unsupported metrics summary schema');
      }
      return _activity.update(snapshot.docs.map((doc) => doc.id), {
        for (final change in snapshot.docChanges)
          if (change.type != DocumentChangeType.removed)
            change.doc.id: (
              steps: _total(change.doc, 'steps'),
              calories: _total(change.doc, 'active_calories'),
              minutes: _total(change.doc, 'exercise_time'),
            ),
      });
    }
    final previous = _latest?.days ?? const <String, Map<String, dynamic>>{};
    final docs = snapshot.docs;
    final ids = docs.map((doc) => doc.id).toSet();
    final next = {...previous}..removeWhere((id, _) => !ids.contains(id));
    final changedIds = snapshot.docChanges
        .map((change) => change.doc.id)
        .toSet();
    _hearts.removeWhere(
      (id, _) => !ids.contains(id) || changedIds.contains(id),
    );
    for (final doc in docs) {
      if (!changedIds.contains(doc.id) && previous.containsKey(doc.id)) {
        continue;
      }
      final data = projectScreenFields(
        (path) => _field(doc, path),
        projection,
        isToday: doc.id == endDay,
      );
      if (projection == MetricsProjection.dailyBrief && doc.id == endDay) {
        next[doc.id] = Map.unmodifiable({
          ...data,
          preparedHeartKey: projectHeartRate(
            (path) => _field(doc, path),
            doc.id,
          ),
        });
      } else {
        next[doc.id] = data;
      }
    }
    if (projection == MetricsProjection.homeHistory) {
      String? heartDay;
      PreparedHeartRate? heart;
      // A 90-day stress window does not need 90 days of decoded heart arrays.
      // Match Home's newest-day-first fallback, stopping on the first usable day.
      for (final doc in docs.reversed) {
        final candidate = _hearts.putIfAbsent(
          doc.id,
          () => projectHeartRate((path) => _field(doc, path), doc.id),
        );
        if (candidate.latest == null) continue;
        heartDay = doc.id;
        heart = candidate;
        break;
      }
      if (_heartDay != heartDay && next.containsKey(_heartDay)) {
        next[_heartDay!] = Map.unmodifiable(
          {...next[_heartDay]!}..remove(preparedHeartKey),
        );
      }
      if (heartDay != null) {
        next[heartDay] = Map.unmodifiable({
          ...next[heartDay]!,
          preparedHeartKey: heart,
        });
      }
      _heartDay = heartDay;
    }
    // Compare compact results, never raw sensor maps/lists. Unchanged days keep
    // their prepared objects, and unrelated writes do not rebuild consumers.
    final unchanged = PerformanceTrace.measure(
      'metrics.compare.${projection.name}',
      () => const DeepCollectionEquality().equals(previous, next),
    );
    return unchanged ? previous : Map.unmodifiable(next);
  }

  static dynamic _field(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String key,
  ) {
    try {
      return doc.get(key);
    } on StateError {
      return null;
    }
  }

  static num? _total(DocumentSnapshot<Map<String, dynamic>> doc, String key) {
    final value = _field(doc, '$key.sum');
    return value is num && value.isFinite && value >= 0 ? value : null;
  }

  void close() {
    _closed = true;
    ++_generation;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _latest = null;
    _activity = FitnessActivityHistory();
    _hearts.clear();
    _heartDay = null;
    for (final listener in _listeners.toList()) {
      listener.add(const MetricWindow(days: {}));
      listener.close();
    }
    _listeners.clear();
  }
}
