import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show listEquals, setEquals;
import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vivordo_health/src/services/health_service.dart';
import 'package:vivordo_health/src/utils/heart_rate_history.dart';
import 'profile_screen.dart';
import 'heart_rate_detail_screen.dart';
import 'active_calories_detail_screen.dart';
import 'exercise_detail_screen.dart';
import 'mood_detail_screen.dart';
import 'sleep_detail_screen.dart';
import 'steps_detail_screen.dart';
import 'wellness_detail_screen.dart';
import 'package:vivordo_health/widgets/whoop_source_badge.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DashboardScreen
//
// Uses ONE combined Firestore listener for all metrics (instead of 9 separate
// ones) to avoid Firestore's internal watch-stream assertion errors that occur
// when too many concurrent listeners are open at the same time.
//
// Consent is a second listener on the users/ doc (already open app-wide).
// Total listeners: 2 instead of the previous ~13.
// ─────────────────────────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onScanTap;
  final bool isActive;
  const DashboardScreen({super.key, this.onScanTap, this.isActive = true});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const Color accentPurple = Color(0xFF7B6EF6);
  static const Color greenColor = Color(0xFF34C759);
  static const Color textGrey = Color(0xFF8E8E93);
  static const List<String> _defaultMetricOrder = [
    'mood',
    'steps',
    'active_calories',
    'exercise_time',
    'heart_rate_scan',
    'sleep',
  ];

  // 0 = Day (default), 1 = Week, 2 = Month
  int _filterIndex = 0;
  static const _filterLabels = ['Day', 'Week', 'Month'];
  int get _daysBack => _filterIndex == 0
      ? 1
      : _filterIndex == 1
      ? 7
      : 30;

  // ── ONE combined stream for all metrics_daily docs in the date window ──────
  late Stream<QuerySnapshot<Map<String, dynamic>>> _allMetricsStream;
  bool _refreshingHealthMetrics = false;
  bool _automaticRefreshRequested = false;
  bool _automaticRefreshScheduled = false;
  Timer? _automaticRefreshTimer;
  DateTime? _lastManualHealthRefresh;
  static const List<String> _defaultKeyMetrics = [
    'mood',
    'steps',
    'active_calories',
    'exercise_time',
    'heart_rate_scan',
    'sleep',
  ];
  Set<String> _enabledKeyMetrics = {..._defaultKeyMetrics};
  List<String> _keyMetricOrder = [..._defaultMetricOrder];
  bool _isLoadingMetricOrder = true;

  @override
  void initState() {
    super.initState();
    _rebuildStreams();
    _loadMetricOrder();
    _requestAutomaticRefreshIfActive();
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) {
      _automaticRefreshTimer?.cancel();
      _automaticRefreshTimer = null;
      _automaticRefreshScheduled = false;
    }
    if (!oldWidget.isActive && widget.isActive) {
      _requestAutomaticRefreshIfActive();
    }
  }

  void _requestAutomaticRefreshIfActive() {
    if (!widget.isActive ||
        _automaticRefreshRequested ||
        _automaticRefreshScheduled) {
      return;
    }
    _automaticRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isActive) {
        _automaticRefreshScheduled = false;
        return;
      }
      _automaticRefreshTimer = Timer(const Duration(milliseconds: 220), () {
        _automaticRefreshTimer = null;
        _automaticRefreshScheduled = false;
        if (!mounted || !widget.isActive || _automaticRefreshRequested) return;
        _automaticRefreshRequested = true;
        _refreshHealthMetricsFromHealth();
      });
    });
  }

  @override
  void dispose() {
    _automaticRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadMetricOrder() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _isLoadingMetricOrder = false);
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final preferences = snapshot.data()?['preferences'] as Map?;
      final savedKeyMetrics = preferences?['dashboardKeyMetrics'] as List?;
      final savedOrder = preferences?['dashboardKeyMetricOrder'] as List?;
      if (mounted) {
        setState(() {
          if (savedKeyMetrics != null) {
            _enabledKeyMetrics = savedKeyMetrics
                .whereType<String>()
                .map((metric) => metric == 'wellness' ? 'stress' : metric)
                .where(_defaultMetricOrder.contains)
                .toSet();
          }
          final validOrder =
              savedOrder
                  ?.whereType<String>()
                  .where(_defaultMetricOrder.contains)
                  .toList() ??
              savedKeyMetrics
                  ?.whereType<String>()
                  .where(_defaultMetricOrder.contains)
                  .toList() ??
              const <String>[];
          _keyMetricOrder = [
            ...validOrder,
            ..._defaultMetricOrder.where(
              (metric) => !validOrder.contains(metric),
            ),
          ];
        });
      }
    } catch (e) {
      debugPrint('DashboardScreen: failed to load metric order: $e');
    } finally {
      if (mounted) setState(() => _isLoadingMetricOrder = false);
    }
  }

  Future<void> _saveKeyMetrics(Set<String> metrics, List<String> order) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ordered = order.where(metrics.contains).toList(growable: false);
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'preferences': {
        'dashboardKeyMetrics': ordered,
        'dashboardKeyMetricOrder': order,
      },
    }, SetOptions(merge: true));
  }

  void _rebuildStreams() {
    _allMetricsStream = _buildCombinedStream();
  }

  Future<void> _refreshHealthMetricsFromHealth({
    bool showFeedback = false,
  }) async {
    if (_refreshingHealthMetrics) return;
    if (mounted) setState(() => _refreshingHealthMetrics = true);

    try {
      await HealthService().syncToFirestore(daysBack: _daysBack);
      if (!mounted) return;
      setState(() => _lastManualHealthRefresh = DateTime.now());
      if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Apple Health metrics refreshed.')),
        );
      }
    } catch (e) {
      debugPrint(
        'DashboardScreen: failed to refresh metrics from Apple Health: $e',
      );
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Apple Health refresh failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshingHealthMetrics = false);
    }
  }

  String _manualRefreshLabel() {
    final refreshed = _lastManualHealthRefresh;
    if (refreshed == null) return 'Refresh';
    final hour = refreshed.hour % 12 == 0 ? 12 : refreshed.hour % 12;
    final minute = refreshed.minute.toString().padLeft(2, '0');
    final suffix = refreshed.hour >= 12 ? 'PM' : 'AM';
    return 'Updated $hour:$minute $suffix';
  }

  /// Single Firestore query that fetches all daily docs in the date window from
  /// the user's subcollection. Each doc holds all metrics for that day.
  Stream<QuerySnapshot<Map<String, dynamic>>> _buildCombinedStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    final now = DateTime.now();
    final oldest = now.subtract(Duration(days: _daysBack - 1));
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('metrics_daily')
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: fmt(oldest))
        .where(FieldPath.documentId, isLessThanOrEqualTo: fmt(now))
        .orderBy(FieldPath.documentId)
        .snapshots();
  }

  // ── Per-metric helpers ─────────────────────────────────────────────────────

  /// Filter docs by metricType from the combined daily snapshot.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docsFor(
    QuerySnapshot<Map<String, dynamic>>? snap,
    String metricType,
  ) {
    if (snap == null) return [];
    return snap.docs.where((d) => d.data().containsKey(metricType)).toList();
  }

  List<double> _vals(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String metricType,
    String field,
  ) => docs
      .map(
        (d) =>
            ((d.data()[metricType] as Map?)?[field] as num?)?.toDouble() ?? 0.0,
      )
      .toList();

  double? _todayMetricValue(
    QuerySnapshot<Map<String, dynamic>>? snap,
    String metricType,
    String field,
  ) {
    if (snap == null) return null;
    final now = DateTime.now();
    final todayKey =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    for (final doc in snap.docs) {
      if (doc.id != todayKey) continue;
      return ((doc.data()[metricType] as Map?)?[field] as num?)?.toDouble();
    }
    return null;
  }

  List<String> _dayLabels(
    QuerySnapshot<Map<String, dynamic>>? snap,
    String metricType,
  ) {
    if (snap == null) return [];
    return snap.docs.where((d) => d.data().containsKey(metricType)).map((d) {
      final dt = DateTime.tryParse(d.id);
      if (dt == null) return '';
      const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return names[dt.weekday - 1];
    }).toList();
  }

  /// Month view: only label Mondays to avoid x-axis crowding.
  List<String> _monthLabels(
    QuerySnapshot<Map<String, dynamic>>? snap,
    String metricType,
  ) {
    if (snap == null) return [];
    return snap.docs.where((d) => d.data().containsKey(metricType)).map((d) {
      final dt = DateTime.tryParse(d.id);
      if (dt == null || dt.weekday != DateTime.monday) return '';
      return '${dt.day}/${dt.month}';
    }).toList();
  }

  // ── Daily mood helpers ─────────────────────────────────────────────────────
  List<Map<String, dynamic>> _dailyMoodPoints(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final points = <Map<String, dynamic>>[];

    for (final doc in docs) {
      final moodMap = doc.data()['mood'] as Map?;
      if (moodMap == null) continue;
      final period = doc.id;
      final entries = moodMap['entries'];
      final scores = <double>[];

      if (entries is List && entries.isNotEmpty) {
        for (final entry in entries) {
          if (entry is! Map) continue;
          final score = entry['score'];
          if (score is num) scores.add(score.toDouble());
        }
      }

      if (scores.isEmpty) {
        final avg = moodMap['avg'];
        if (avg is num) scores.add(avg.toDouble());
      }

      if (scores.isEmpty) continue;
      points.add({
        'score': _avg(scores),
        'dateTime':
            DateTime.tryParse(period) ?? DateTime.fromMillisecondsSinceEpoch(0),
      });
    }

    points.sort(
      (a, b) =>
          (a['dateTime'] as DateTime).compareTo(b['dateTime'] as DateTime),
    );
    return points;
  }

  List<double> _dailyMoodValues(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) => _dailyMoodPoints(docs).map((point) => point['score'] as double).toList();

  List<String> _dailyMoodLabels(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final points = _dailyMoodPoints(docs);
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return points.map((point) {
      final dateTime = point['dateTime'] as DateTime;

      if (_filterIndex == 2 && dateTime.weekday != DateTime.monday) {
        return '';
      }

      return dayNames[dateTime.weekday - 1];
    }).toList();
  }

  List<Map<String, dynamic>> _todayMoodEntries(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final entries = <Map<String, dynamic>>[];

    for (final doc in docs) {
      final moodMap = doc.data()['mood'] as Map?;
      final rawEntries = moodMap?['entries'];
      if (rawEntries is! List) continue;

      for (final entry in rawEntries) {
        if (entry is! Map || entry['score'] is! num) continue;
        final timestamp = entry['timestamp'];
        entries.add({
          'score': (entry['score'] as num).toDouble(),
          'dateTime': timestamp is Timestamp
              ? timestamp.toDate()
              : DateTime.tryParse(doc.id),
        });
      }
    }

    entries.sort((a, b) {
      final aTime = a['dateTime'] as DateTime?;
      final bTime = b['dateTime'] as DateTime?;
      if (aTime == null) return -1;
      if (bTime == null) return 1;
      return aTime.compareTo(bTime);
    });
    return entries;
  }

  String _formatMoodEntryTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final suffix = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _heartRateDocs(
    QuerySnapshot<Map<String, dynamic>>? snapshot,
  ) {
    if (snapshot == null) return [];
    return snapshot.docs.where((doc) {
      final data = doc.data();
      return data.containsKey('heart_rate') ||
          data.containsKey('heart_rate_scan') ||
          data.containsKey('heart_rate_sources');
    }).toList();
  }

  List<Map<String, dynamic>> _heartRateEntries(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final points = <Map<String, dynamic>>[];
    for (final doc in docs) {
      final fallbackDate = DateTime.tryParse(doc.id);
      if (fallbackDate == null) continue;
      for (final reading in mergedHeartRateHistory(
        doc.data(),
        fallbackDate: fallbackDate,
      )) {
        points.add({
          'bpm': reading.bpm,
          'dateTime': reading.timestamp,
          'source': reading.source,
        });
      }
    }
    points.sort((a, b) {
      final aTime = a['dateTime'] as DateTime?;
      final bTime = b['dateTime'] as DateTime?;
      if (aTime == null) return -1;
      if (bTime == null) return 1;
      return aTime.compareTo(bTime);
    });
    return points;
  }

  List<Map<String, dynamic>> _dailyBpmPoints(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final points = <Map<String, dynamic>>[];
    for (final doc in docs) {
      final entries = _heartRateEntries([doc]);
      if (entries.isEmpty) continue;
      points.add({
        'bpm': _avg(entries.map((entry) => entry['bpm'] as double).toList()),
        'dateTime': DateTime.tryParse(doc.id),
      });
    }
    return points;
  }

  double _avg(List<double> vals) =>
      vals.isEmpty ? 0 : vals.reduce((a, b) => a + b) / vals.length;

  bool _hasVisibleWhoopData(QuerySnapshot<Map<String, dynamic>>? snapshot) {
    if (snapshot == null) return false;
    if (_enabledKeyMetrics.contains('sleep')) {
      final sleepDocs = _docsFor(snapshot, 'sleep');
      if (sleepDocs.isNotEmpty &&
          (sleepDocs.last.data()['sleep'] as Map?)?['source'] == 'whoop') {
        return true;
      }
    }
    if (_enabledKeyMetrics.contains('heart_rate_scan')) {
      final entries = _heartRateEntries(_heartRateDocs(snapshot));
      if (entries.isNotEmpty && entries.last['source'] == 'whoop_ble') {
        return true;
      }
    }
    return false;
  }

  String _trend(List<double> vals) {
    if (vals.length < 2) return '';
    final half = vals.length ~/ 2;
    final old = _avg(vals.sublist(0, half));
    final recent = _avg(vals.sublist(half));
    if (old == 0) return '';
    final pct = ((recent - old) / old * 100).round();
    return pct >= 0 ? '+$pct%' : '$pct%';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.vivordoColors.page,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 26),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Metrics',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            color: context.vivordoColors.textPrimary,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: _allMetricsStream,
                          builder: (context, snapshot) => Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 7,
                            runSpacing: 4,
                            children: [
                              Text(
                                '${_lastManualHealthRefresh == null ? 'Synced automatically' : _manualRefreshLabel().replaceFirst('Updated', 'Synced')}${_hasVisibleWhoopData(snapshot.data) ? ' · Data includes' : ''}',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: context.vivordoColors.textSecondary,
                                ),
                              ),
                              if (_hasVisibleWhoopData(snapshot.data))
                                const WhoopSourceBadge(compact: true),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh Apple Health',
                    onPressed: _refreshingHealthMetrics
                        ? null
                        : () => _refreshHealthMetricsFromHealth(
                            showFeedback: true,
                          ),
                    icon: _refreshingHealthMetrics
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : const Icon(Icons.refresh_rounded),
                    color: accentPurple,
                  ),
                  TextButton.icon(
                    onPressed: _isLoadingMetricOrder ? null : _showLayoutEditor,
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('Customize'),
                    style: TextButton.styleFrom(
                      foregroundColor: accentPurple,
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _allMetricsStream,
                builder: (_, metricsSnap) => _buildMetricsOverview(
                  metricsSnap.data,
                  loading:
                      metricsSnap.connectionState == ConnectionState.waiting,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricsOverview(
    QuerySnapshot<Map<String, dynamic>>? snap, {
    required bool loading,
  }) {
    if (loading && snap == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final steps = _vals(_docsFor(snap, 'steps'), 'steps', 'sum');
    final stress = _vals(_docsFor(snap, 'stress'), 'stress', 'avg');
    final wellness = _vals(_docsFor(snap, 'wellness'), 'wellness', 'avg');
    final stepLabels = _dayLabels(snap, 'steps');
    final latestWellness = wellness.isEmpty ? null : wellness.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildWellnessHero(wellness),
        const SizedBox(height: 24),
        const Text(
          'Key metrics',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        if (_enabledKeyMetrics.isEmpty)
          _buildNoKeyMetricsCard()
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _keyMetricOrder
                    .where(_enabledKeyMetrics.contains)
                    .map(
                      (metric) => SizedBox(
                        width: tileWidth,
                        child: _buildKeyMetricFor(metric, snap),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        const SizedBox(height: 28),
        const Text(
          'Insights',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        _buildInsightsCard(
          steps: steps,
          stress: stress,
          wellness: latestWellness,
          labels: stepLabels,
        ),
        if (snap == null || snap.docs.isEmpty) ...[
          const SizedBox(height: 18),
          _buildEmptyState(),
        ],
        const SizedBox(height: 120),
      ],
    );
  }

  Widget _buildWellnessHero(List<double> values) {
    final score = values.isEmpty ? null : values.last.clamp(0, 100);
    final previous = values.length < 2 ? null : values[values.length - 2];
    final change = score == null || previous == null || previous == 0
        ? null
        : ((score - previous) / previous * 100).round();
    final status = score == null
        ? 'Not enough data'
        : score >= 75
        ? 'Doing well'
        : score >= 50
        ? 'Fair'
        : 'Needs attention';
    final color = score == null
        ? context.vivordoColors.textSecondary
        : score >= 75
        ? greenColor
        : score >= 50
        ? const Color(0xFFFF9500)
        : const Color(0xFFE91F3D);
    final explanation = score == null
        ? 'Sync your health data to calculate your wellness score.'
        : score >= 75
        ? 'Your recent health signals indicate strong overall wellness.'
        : score >= 50
        ? 'Your wellness is fair. Small improvements can raise your score.'
        : 'Your recent health signals suggest that recovery needs attention.';

    return Material(
      color: context.vivordoColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: context.vivordoColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const WellnessDetailScreen())),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WELLNESS SCORE',
                      style: TextStyle(
                        color: context.vivordoColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        Text(
                          score == null ? '--' : score.round().toString(),
                          style: const TextStyle(
                            fontSize: 46,
                            height: 1,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (change != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${change >= 0 ? '↑' : '↓'} ${change.abs()}%',
                        style: TextStyle(
                          color: change >= 0
                              ? greenColor
                              : const Color(0xFFE91F3D),
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      explanation,
                      style: TextStyle(
                        color: context.vivordoColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 92,
                height: 92,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: score == null ? 0 : score / 100,
                      strokeWidth: 10,
                      strokeCap: StrokeCap.round,
                      color: color,
                      backgroundColor: context.vivordoColors.cardMuted,
                    ),
                    Container(
                      width: 45,
                      height: 45,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: .1),
                      ),
                      child: Icon(Icons.spa_rounded, color: color),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "52–71 across 8 readings today" for the most recent BaaS-scored day.
  ///
  /// The stress score now accumulates through the day and resets each morning
  /// to the user's personal anchor, so a single number throws away most of
  /// what happened. `min`/`max`/`readings` have been on this document since
  /// v1, but every one of them held the same value because there was only
  /// ever one score per day — see StressScoreService._saveScore.
  ///
  /// Returns null when the day has fewer than two readings or no real spread,
  /// so pre-intraday history falls through to the usual comparison text
  /// instead of rendering a meaningless "61–61".
  String? _stressIntradayDetail(QuerySnapshot<Map<String, dynamic>>? snap) {
    final docs = _docsFor(snap, 'stress');
    if (docs.isEmpty) return null;

    final stress = docs.last.data()['stress'] as Map?;
    if (stress == null) return null;

    final lo = (stress['min'] as num?)?.toDouble();
    final hi = (stress['max'] as num?)?.toDouble();
    final n = (stress['readings'] as num?)?.toInt() ?? 0;
    if (lo == null || hi == null || n < 2) return null;
    if (hi - lo < 1.0) return 'Steady across $n readings today';

    return '${lo.round()}–${hi.round()} across $n readings today';
  }

  Widget _buildKeyMetricFor(
    String metric,
    QuerySnapshot<Map<String, dynamic>>? snap,
  ) {
    List<double> values;
    if (metric == 'heart_rate_scan') {
      values = _heartRateEntries(
        _heartRateDocs(snap),
      ).map((entry) => entry['bpm'] as double).toList();
    } else if (metric == 'mood') {
      values = _dailyMoodValues(_docsFor(snap, metric));
    } else {
      values = _vals(_docsFor(snap, metric), metric, _metricField(metric));
    }

    // Key metric tiles describe the current day. Resolve summed daily metrics
    // by today's document ID so a missing sync never falls back to yesterday.
    final todaySummedValue =
        metric == 'exercise_time' || metric == 'active_calories'
        ? _todayMetricValue(snap, metric, 'sum') ?? 0
        : null;

    final title = switch (metric) {
      'steps' => 'Steps',
      'active_calories' => 'Active calories',
      'exercise_time' => 'Exercise',
      'heart_rate_scan' => 'Heart rate',
      'resting_heart_rate' => 'Resting heart rate',
      'blood_oxygen' => 'Blood oxygen',
      'respiratory_rate' => 'Respiratory rate',
      'body_fat' => 'Body fat',
      'vo2max' => 'VO₂ max',
      _ => _metricTitle(metric),
    };
    final value = todaySummedValue != null
        ? _formatMetricValue(metric, todaySummedValue)
        : values.isEmpty
        ? 'No data'
        : metric == 'steps'
        ? _formatCount(values.last)
        : _formatMetricValue(metric, values.last);
    final detail = todaySummedValue != null
        ? todaySummedValue > 0
              ? _comparisonText(values, lowerIsBetter: false)
              : metric == 'active_calories'
              ? 'No active calories recorded today'
              : 'No exercise recorded today'
        : values.isEmpty
        ? 'Not synced recently'
        : metric == 'heart_rate_scan' || metric == 'resting_heart_rate'
        ? _heartRateStatus(values.last)
        : metric == 'stress'
        ? (_stressIntradayDetail(snap) ??
              _comparisonText(values, lowerIsBetter: true))
        : _comparisonText(values, lowerIsBetter: metric == 'stress');
    return _buildKeyMetricTile(
      title: title,
      value: value,
      detail: detail,
      icon: _metricIcon(metric),
      color: _metricColor(metric),
      onTap: switch (metric) {
        'steps' => () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const StepsDetailScreen())),
        'heart_rate_scan' => () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const HeartRateDetailScreen()),
        ),
        'active_calories' => () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ActiveCaloriesDetailScreen()),
        ),
        'exercise_time' => () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ExerciseDetailScreen())),
        'mood' => () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const MoodDetailScreen())),
        'sleep' => () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SleepDetailScreen())),
        _ => null,
      },
    );
  }

  Widget _buildNoKeyMetricsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.vivordoColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.vivordoColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.tune_rounded, color: accentPurple),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Use Customize to choose the metrics shown here.',
              style: TextStyle(color: context.vivordoColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyMetricTile({
    required String title,
    required String value,
    required String detail,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: context.vivordoColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: context.vivordoColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 160,
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 43,
                  height: 43,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 23),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, height: 1.2),
                      ),
                      const SizedBox(height: 5),
                      SizedBox(
                        height: 31,
                        width: double.infinity,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              value,
                              maxLines: 1,
                              style: TextStyle(
                                color: color,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.vivordoColors.textSecondary,
                          fontSize: 12,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInsightsCard({
    required List<double> steps,
    required List<double> stress,
    required double? wellness,
    required List<String> labels,
  }) {
    String activityInsight;
    if (steps.isEmpty) {
      activityInsight = 'Sync steps to reveal your activity pattern';
    } else {
      var peak = 0;
      for (var i = 1; i < steps.length; i++) {
        if (steps[i] > steps[peak]) peak = i;
      }
      final day = labels.length == steps.length ? labels[peak] : 'recently';
      activityInsight = 'Activity peaked on $day';
    }

    String recoveryInsight;
    if (stress.length >= 3 &&
        stress.last > stress[stress.length - 2] &&
        stress[stress.length - 2] > stress[stress.length - 3]) {
      recoveryInsight = 'Stress has increased for 3 days';
    } else if (wellness != null && wellness < 50) {
      recoveryInsight = 'Your wellness signals need attention';
    } else {
      recoveryInsight = 'Your recent stress trend is stable';
    }

    return Container(
      decoration: BoxDecoration(
        color: context.vivordoColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.vivordoColors.border),
      ),
      child: Column(
        children: [
          _insightRow(
            icon: Icons.trending_up_rounded,
            color: const Color(0xFF16B877),
            text: activityInsight,
          ),
          Divider(height: 1, indent: 68, color: context.vivordoColors.border),
          _insightRow(
            icon: Icons.psychology_rounded,
            color: accentPurple,
            text: recoveryInsight,
          ),
        ],
      ),
    );
  }

  Widget _insightRow({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
        ],
      ),
    );
  }

  String _formatCount(double value) {
    final digits = value.round().toString();
    return digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  }

  String _comparisonText(List<double> values, {required bool lowerIsBetter}) {
    if (values.length < 2) return 'Today';
    final usual = _avg(values.sublist(0, values.length - 1));
    if (usual == 0) return 'Today';
    final percent = ((values.last - usual) / usual * 100).round();
    if (percent == 0) return 'About usual';
    final favorable = lowerIsBetter ? percent < 0 : percent > 0;
    return '${percent > 0 ? '↑' : '↓'} ${percent.abs()}% vs usual${favorable ? '' : ''}';
  }

  String _heartRateStatus(double? bpm) {
    if (bpm == null) return 'No recent reading';
    if (bpm < 60) return 'Below typical resting range';
    if (bpm <= 100) return 'Within typical resting range';
    return 'Above typical resting range';
  }

  bool _isManualMetric(String key) =>
      key == 'stress' ||
      key == 'mood' ||
      key == 'wellness' ||
      key == 'heart_rate_scan';

  String _metricTitle(String key) {
    switch (key) {
      case 'stress':
        return 'Stress Levels';
      case 'mood':
        return 'Mood';
      case 'wellness':
        return 'Wellness';
      case 'steps':
        return 'Daily Steps';
      case 'active_calories':
        return 'Active Calories (kcal)';
      case 'exercise_time':
        return 'Exercise Time (min)';
      case 'heart_rate':
        return 'Heart Rate (bpm)';
      case 'heart_rate_scan':
        return 'Heart Rate';
      case 'resting_heart_rate':
        return 'Resting Heart Rate (bpm)';
      case 'hrv':
        return 'HRV (ms)';
      case 'blood_oxygen':
        return 'Blood Oxygen SpO2 (%)';
      case 'respiratory_rate':
        return 'Respiratory Rate (brpm)';
      case 'sleep':
        return 'Sleep (hours)';
      case 'weight':
        return 'Weight (kg)';
      case 'body_fat':
        return 'Body Fat (%)';
      case 'vo2max':
        return 'VO2 Max (ml/kg/min)';
      default:
        return key;
    }
  }

  Color _metricColor(String key) {
    switch (key) {
      case 'stress':
        return accentPurple;
      case 'mood':
        return const Color(0xFFF97316);
      case 'wellness':
        return Colors.teal;
      case 'steps':
        return Colors.blueAccent;
      case 'active_calories':
        return const Color(0xFFF97316);
      case 'exercise_time':
        return const Color(0xFFFF9500);
      case 'heart_rate':
      case 'heart_rate_scan':
        return Colors.redAccent;
      case 'resting_heart_rate':
        return const Color(0xFFFF6B6B);
      case 'hrv':
        return greenColor;
      case 'blood_oxygen':
        return const Color(0xFF06B6D4);
      case 'respiratory_rate':
        return const Color(0xFF0EA5E9);
      case 'sleep':
        return const Color(0xFF8B5CF6);
      case 'weight':
        return const Color(0xFFA78BFA);
      case 'body_fat':
        return const Color(0xFFFBBF24);
      case 'vo2max':
        return greenColor;
      default:
        return accentPurple;
    }
  }

  String _metricField(String key) {
    const summed = {'steps', 'active_calories', 'exercise_time'};
    return summed.contains(key) ? 'sum' : 'avg';
  }

  double _metricMaxY(String key) {
    switch (key) {
      case 'stress':
      case 'mood':
      case 'wellness':
      case 'blood_oxygen':
        return 100;
      case 'steps':
        return 20000;
      case 'active_calories':
        return 1000;
      case 'exercise_time':
      case 'resting_heart_rate':
      case 'hrv':
        return 120;
      case 'heart_rate':
      case 'heart_rate_scan':
        return 200;
      case 'respiratory_rate':
        return 30;
      case 'sleep':
        return 12;
      case 'body_fat':
        return 50;
      case 'vo2max':
        return 70;
      default:
        return 0;
    }
  }

  Widget _buildOrderedMetric(
    QuerySnapshot<Map<String, dynamic>>? snap,
    Map<String, bool> consent,
    String metric,
  ) {
    final hasData = metric == 'heart_rate_scan'
        ? _heartRateDocs(snap).isNotEmpty
        : _docsFor(snap, metric).isNotEmpty;
    return KeyedSubtree(
      key: ValueKey('dashboard-metric-$metric'),
      child: !_isManualMetric(metric) && consent[metric] != true && !hasData
          ? const SizedBox.shrink()
          : _maybeChart(
              snap,
              metric,
              _metricTitle(metric),
              _metricColor(metric),
              _metricField(metric),
              _metricMaxY(metric),
            ),
    );
  }

  Future<void> _showLayoutEditor() async {
    final draft = {..._enabledKeyMetrics};
    final draftOrder = [..._keyMetricOrder];
    final result = await showModalBottomSheet<_KeyMetricPreferences>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Material(
          color: context.vivordoColors.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.82,
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: context.vivordoColors.border,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Customize key metrics',
                                style: TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Toggle metrics or hold and drag to reorder.',
                                style: TextStyle(fontSize: 13, color: textGrey),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(
                            context,
                            _KeyMetricPreferences(draft, draftOrder),
                          ),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      itemCount: draftOrder.length,
                      onReorderItem: (oldIndex, newIndex) => setModalState(() {
                        final metric = draftOrder.removeAt(oldIndex);
                        draftOrder.insert(newIndex, metric);
                      }),
                      itemBuilder: (context, index) {
                        final metric = draftOrder[index];
                        final color = _metricColor(metric);
                        final enabled = draft.contains(metric);
                        return Material(
                          key: ValueKey('customize-$metric'),
                          color: context.vivordoColors.card,
                          child: Column(
                            children: [
                              ReorderableDelayedDragStartListener(
                                index: index,
                                child: SwitchListTile.adaptive(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  value: enabled,
                                  onChanged: (value) => setModalState(() {
                                    if (value) {
                                      draft.add(metric);
                                    } else {
                                      draft.remove(metric);
                                    }
                                  }),
                                  activeTrackColor: accentPurple,
                                  secondary: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    child: Icon(
                                      _metricIcon(metric),
                                      size: 20,
                                      color: color,
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _customizeMetricTitle(metric),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.drag_indicator_rounded,
                                        color:
                                            context.vivordoColors.textSecondary,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Divider(
                                height: 1,
                                indent: 64,
                                color: context.vivordoColors.border,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (!mounted) return;
    if (result == null) return;
    final enabledChanged = !setEquals(result.enabled, _enabledKeyMetrics);
    final orderChanged = !listEquals(result.order, _keyMetricOrder);
    if (!enabledChanged && !orderChanged) return;
    setState(() {
      _enabledKeyMetrics = {...result.enabled};
      _keyMetricOrder = [...result.order];
    });
    try {
      await _saveKeyMetrics(result.enabled, result.order);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save metric preferences.')),
      );
    }
  }

  String _customizeMetricTitle(String metric) => switch (metric) {
    'stress' => 'Stress',
    'mood' => 'Mood',
    'wellness' => 'Wellness',
    'steps' => 'Steps',
    'active_calories' => 'Active calories',
    'exercise_time' => 'Exercise minutes',
    'heart_rate_scan' => 'Heart rate',
    'resting_heart_rate' => 'Resting heart rate',
    'hrv' => 'Heart rate variability',
    'blood_oxygen' => 'Blood oxygen',
    'respiratory_rate' => 'Respiratory rate',
    'sleep' => 'Sleep',
    'weight' => 'Weight',
    'body_fat' => 'Body fat',
    'vo2max' => 'VO₂ max',
    _ => metric,
  };

  /// Returns a chart card if the metric has data, otherwise SizedBox.shrink().
  Widget _maybeChart(
    QuerySnapshot<Map<String, dynamic>>? snap,
    String metricType,
    String title,
    Color color,
    String field,
    double maxY,
  ) {
    final docs = metricType == 'heart_rate_scan'
        ? _heartRateDocs(snap)
        : _docsFor(snap, metricType);
    if (metricType == 'heart_rate_scan') {
      final points = _filterIndex == 0
          ? _heartRateEntries(docs)
          : _dailyBpmPoints(docs);
      if (points.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: _buildChartCard(
          title: title,
          icon: _metricIcon(metricType),
          color: color,
          values: points.map((point) => point['bpm'] as double).toList(),
          maxY: maxY,
          labels: points.map((point) {
            final dateTime = point['dateTime'] as DateTime?;
            if (_filterIndex == 0) return _formatMoodEntryTime(dateTime);
            if (dateTime == null) return '';
            if (_filterIndex == 2 && dateTime.weekday != DateTime.monday) {
              return '';
            }
            const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
            return names[dateTime.weekday - 1];
          }).toList(),
        ),
      );
    }
    if (metricType == 'mood' && _filterIndex == 0) {
      final entries = _todayMoodEntries(docs);
      if (entries.isEmpty) return const SizedBox.shrink();

      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: _buildChartCard(
          title: title,
          icon: _metricIcon(metricType),
          color: color,
          values: entries.map((entry) => entry['score'] as double).toList(),
          maxY: maxY,
          labels: entries
              .map(
                (entry) => _formatMoodEntryTime(entry['dateTime'] as DateTime?),
              )
              .toList(),
        ),
      );
    }

    final values = metricType == 'mood'
        ? _dailyMoodValues(docs)
        : _vals(docs, metricType, field);
    final labels = metricType == 'mood'
        ? _dailyMoodLabels(docs)
        : _filterIndex == 2
        ? _monthLabels(snap, metricType)
        : _dayLabels(snap, metricType);
    if (values.isEmpty) return const SizedBox.shrink();

    if (_filterIndex == 0) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: _buildDailyMetricTile(
          title: title,
          icon: _metricIcon(metricType),
          color: color,
          metricType: metricType,
          field: field,
          values: values,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _buildChartCard(
        title: title,
        icon: _metricIcon(metricType),
        color: color,
        values: values,
        maxY: maxY > 0
            ? maxY
            : (values.reduce((a, b) => a > b ? a : b) * 1.2).clamp(
                1,
                double.infinity,
              ),
        labels: labels,
      ),
    );
  }

  Widget _buildDailyMetricTile({
    required String title,
    required IconData icon,
    required Color color,
    required String metricType,
    required String field,
    required List<double> values,
  }) {
    final primaryValue = field == 'sum'
        ? values.fold<double>(0, (total, value) => total + value)
        : values.last;
    final avgValue = _avg(values);
    final hasMultipleValues = values.length > 1;

    final primaryLabel = _formatMetricValue(metricType, primaryValue);
    final subtitle = hasMultipleValues
        ? field == 'sum'
              ? '${values.length} entries today'
              : 'avg ${_formatMetricValue(metricType, avgValue)} today'
        : 'today';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: context.vivordoColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.vivordoColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.vivordoColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: textGrey),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            primaryLabel,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _formatMetricValue(String metricType, double value) {
    String number({int decimals = 0}) => decimals == 0
        ? value.round().toString()
        : value.toStringAsFixed(decimals);

    switch (metricType) {
      case 'steps':
        return number();
      case 'active_calories':
        return '${number()} kcal';
      case 'exercise_time':
        return '${number(decimals: value >= 10 ? 1 : 2)} min';
      case 'heart_rate':
      case 'heart_rate_scan':
      case 'resting_heart_rate':
        return '${number()} bpm';
      case 'hrv':
        return '${number()} ms';
      case 'blood_oxygen':
        return '${number()}%';
      case 'respiratory_rate':
        return '${number()} brpm';
      case 'sleep':
        return '${number(decimals: 1)}h';
      case 'weight':
        return '${number(decimals: 1)} kg';
      case 'body_fat':
        return '${number(decimals: 1)}%';
      case 'vo2max':
        return number(decimals: 1);
      case 'stress':
      case 'mood':
      case 'wellness':
        return number();
      default:
        return value == value.roundToDouble() ? number() : number(decimals: 1);
    }
  }

  IconData _metricIcon(String key) {
    switch (key) {
      case 'steps':
        return Icons.directions_walk_rounded;
      case 'active_calories':
        return Icons.local_fire_department_rounded;
      case 'exercise_time':
        return Icons.fitness_center_rounded;
      case 'heart_rate':
      case 'heart_rate_scan':
        return Icons.favorite_rounded;
      case 'resting_heart_rate':
        return Icons.favorite_border_rounded;
      case 'hrv':
        return Icons.show_chart_rounded;
      case 'blood_oxygen':
        return Icons.air_rounded;
      case 'respiratory_rate':
        return Icons.wind_power_rounded;
      case 'sleep':
        return Icons.bedtime_rounded;
      case 'weight':
        return Icons.monitor_weight_rounded;
      case 'body_fat':
        return Icons.percent_rounded;
      case 'vo2max':
        return Icons.speed_rounded;
      case 'stress':
        return Icons.psychology_rounded;
      case 'mood':
        return Icons.mood_rounded;
      case 'wellness':
        return Icons.spa_rounded;
      default:
        return Icons.monitor_heart_outlined;
    }
  }

  // ── Filter chips ───────────────────────────────────────────────────────────

  Widget _buildFilter() {
    return Row(
      children: List.generate(_filterLabels.length, (i) {
        final active = _filterIndex == i;
        return Padding(
          padding: EdgeInsets.only(right: i < _filterLabels.length - 1 ? 8 : 0),
          child: GestureDetector(
            onTap: () {
              setState(() {
                _filterIndex = i;
                _rebuildStreams();
              });
              _refreshHealthMetricsFromHealth();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: active ? accentPurple : context.vivordoColors.cardMuted,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? accentPurple : context.vivordoColors.border,
                ),
              ),
              child: Text(
                _filterLabels[i],
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : textGrey,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  // ── Shared UI widgets (from dev — unchanged) ──────────────────────────────

  Widget _buildStatCard({
    required String label,
    required String value,
    required String change,
    required bool trendUp,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: context.vivordoColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.vivordoColors.border),
      ),
      child: Column(
        children: [
          Text(
            label.toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9,
              color: textGrey,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: context.vivordoColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          if (change.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  change.startsWith('+')
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  size: 13,
                  color: trendUp ? greenColor : const Color(0xFFFF3B30),
                ),
                const SizedBox(width: 3),
                Text(
                  change,
                  style: TextStyle(
                    fontSize: 10,
                    color: trendUp ? greenColor : const Color(0xFFFF3B30),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildWellnessCard(List<double> vals) {
    final avg = vals.isEmpty ? null : _avg(vals);
    final trend = _trend(vals);

    Color labelColor;
    String labelText;
    if (avg == null) {
      labelColor = textGrey;
      labelText = 'No data yet';
    } else if (avg >= 70) {
      labelColor = greenColor;
      labelText = 'Good';
    } else if (avg >= 50) {
      labelColor = const Color(0xFFFF9500);
      labelText = 'Fair';
    } else {
      labelColor = const Color(0xFFFF3B30);
      labelText = 'Needs attention';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.vivordoColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.vivordoColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: labelColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.spa_rounded, size: 18, color: labelColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'WELLNESS SCORE',
                  style: TextStyle(
                    fontSize: 9,
                    color: textGrey,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      avg == null ? '--' : avg.toInt().toString(),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: context.vivordoColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: labelColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        labelText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: labelColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (trend.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  trend.startsWith('+')
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  size: 16,
                  color: trend.startsWith('+')
                      ? greenColor
                      : const Color(0xFFFF3B30),
                ),
                const SizedBox(width: 4),
                Text(
                  trend,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: trend.startsWith('+')
                        ? greenColor
                        : const Color(0xFFFF3B30),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.vivordoColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.vivordoColors.border),
      ),
      child: Column(
        children: [
          Icon(
            Icons.bar_chart_rounded,
            size: 48,
            color: context.vivordoColors.textSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            'No data for this period',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.vivordoColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Complete a scan, log your mood, or connect Apple Health to see your metrics here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: textGrey, height: 1.5),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                  icon: const Icon(Icons.health_and_safety_outlined, size: 16),
                  label: const Text('Connect Health'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accentPurple,
                    side: const BorderSide(color: accentPurple),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHealthConsentLoadingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.vivordoColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.vivordoColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: accentPurple,
            ),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Checking Apple Health permissions',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.vivordoColors.textPrimary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Loading your connected health data…',
                  style: TextStyle(fontSize: 12, color: textGrey, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectCard() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.vivordoColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.vivordoColors.border),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.health_and_safety_outlined,
              size: 36,
              color: Color(0xFF7B6EF6),
            ),
            const SizedBox(height: 12),
            Text(
              'Apple Health not connected',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: context.vivordoColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tap to go to App Settings → Health Data Permissions',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: textGrey, height: 1.5),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: accentPurple,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Enable Health Data',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartCard({
    required String title,
    required Color color,
    required List<double> values,
    required double maxY,
    required List<String> labels,
    IconData? icon,
  }) {
    // Compute a quick summary value for the subtitle
    final avg = values.isEmpty
        ? 0.0
        : values.reduce((a, b) => a + b) / values.length;
    final latest = values.isNotEmpty ? values.last : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      decoration: BoxDecoration(
        color: context.vivordoColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.vivordoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.vivordoColors.textPrimary,
                  ),
                ),
              ),
              // Latest value badge
              Text(
                latest == latest.roundToDouble()
                    ? latest.toInt().toString()
                    : latest.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          if (values.length > 1) ...[
            const SizedBox(height: 2),
            Padding(
              padding: EdgeInsets.only(left: icon != null ? 42 : 0),
              child: Text(
                'avg ${avg == avg.roundToDouble() ? avg.toInt() : avg.toStringAsFixed(1)}',
                style: const TextStyle(fontSize: 11, color: textGrey),
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            height: 160,
            child: _AreaChart(
              values: values,
              maxY: maxY,
              color: color,
              labels: labels,
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyMetricPreferences {
  const _KeyMetricPreferences(this.enabled, this.order);

  final Set<String> enabled;
  final List<String> order;
}

// ─────────────────────────────────────────────────────────────────────────────
// _AreaChart — from dev, unchanged
// ─────────────────────────────────────────────────────────────────────────────

class _AreaChart extends StatefulWidget {
  final List<double> values;
  final double maxY;
  final Color color;
  final List<String> labels;

  const _AreaChart({
    required this.values,
    required this.maxY,
    required this.color,
    required this.labels,
  });

  @override
  State<_AreaChart> createState() => _AreaChartState();
}

class _AreaChartState extends State<_AreaChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(_AreaChart old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.values, widget.values)) {
      if (_selectedIndex != null && _selectedIndex! >= widget.values.length) {
        _selectedIndex = null;
      }
      _controller.forward(from: 0);
    }
  }

  void _selectPoint(double localX, double width) {
    if (widget.values.isEmpty) return;
    const leftPad = _AreaChartPainter.leftPad;
    final chartWidth = width - leftPad;
    final index = widget.values.length == 1
        ? 0
        : (((localX - leftPad) / chartWidth) * (widget.values.length - 1))
              .round()
              .clamp(0, widget.values.length - 1);
    if (index != _selectedIndex) setState(() => _selectedIndex = index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) =>
            _selectPoint(details.localPosition.dx, constraints.maxWidth),
        onHorizontalDragStart: (details) =>
            _selectPoint(details.localPosition.dx, constraints.maxWidth),
        onHorizontalDragUpdate: (details) =>
            _selectPoint(details.localPosition.dx, constraints.maxWidth),
        child: AnimatedBuilder(
          animation: _animation,
          builder: (_, __) => CustomPaint(
            painter: _AreaChartPainter(
              values: widget.values,
              maxY: widget.maxY,
              color: widget.color,
              labels: widget.labels,
              progress: _animation.value,
              selectedIndex: _selectedIndex,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _AreaChartPainter extends CustomPainter {
  final List<double> values;
  final double maxY;
  final Color color;
  final List<String> labels;
  final double progress;
  final int? selectedIndex;

  static const double labelHeight = 22;
  static const double leftPad = 36;

  _AreaChartPainter({
    required this.values,
    required this.maxY,
    required this.color,
    required this.labels,
    required this.progress,
    required this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final chartH = size.height - labelHeight;
    final chartW = size.width - leftPad;

    // Grid lines — light translucent for a modern look
    final gridPaint = Paint()
      ..color = Colors.black.withOpacity(0.06)
      ..strokeWidth = 0.8;
    const gridLines = 4;
    for (int i = 0; i <= gridLines; i++) {
      final y = chartH * i / gridLines;
      canvas.drawLine(Offset(leftPad, y), Offset(size.width, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: '${(maxY * (1 - i / gridLines)).round()}',
          style: TextStyle(fontSize: 9, color: Colors.grey.shade400),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - 5));
    }

    if (values.isEmpty) return;

    final n = values.length;
    final pts = List.generate(n, (i) {
      final x = n == 1 ? leftPad + chartW / 2 : leftPad + chartW * i / (n - 1);
      final y = chartH * (1 - (values[i] / maxY).clamp(0.0, 1.0));
      return Offset(x, y);
    });

    if (pts.length == 1) {
      canvas.drawCircle(pts.first, 6, Paint()..color = color);
    } else {
      final linePath = _smoothPath(pts);
      final pathMetrics = linePath.computeMetrics().toList();
      if (pathMetrics.isEmpty) return;
      final animatedLine = pathMetrics.first.extractPath(
        0,
        pathMetrics.first.length * progress,
      );

      final fillPath = Path.from(animatedLine)
        ..lineTo(pts.last.dx, chartH)
        ..lineTo(leftPad, chartH)
        ..close();
      canvas.drawPath(
        fillPath,
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, Offset(0, chartH), [
            color.withValues(alpha: 0.28),
            color.withValues(alpha: 0.0),
          ])
          ..style = PaintingStyle.fill,
      );

      canvas.drawPath(
        animatedLine,
        Paint()
          ..color = color
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // X-axis labels — skip empty strings (used for month view non-Monday points)
    if (labels.length == n) {
      final labelStyle = TextStyle(fontSize: 10, color: Colors.grey.shade500);
      for (int i = 0; i < n; i++) {
        if (labels[i].isEmpty) continue;
        final tp = TextPainter(
          text: TextSpan(text: labels[i], style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(pts[i].dx - tp.width / 2, chartH + 6));
      }
    }

    final selected = selectedIndex;
    if (selected != null && selected >= 0 && selected < pts.length) {
      _drawSelection(canvas, size, chartH, pts[selected], selected);
    }
  }

  void _drawSelection(
    Canvas canvas,
    Size size,
    double chartH,
    Offset point,
    int index,
  ) {
    canvas.drawLine(
      Offset(point.dx, 0),
      Offset(point.dx, chartH),
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(point, 7, Paint()..color = Colors.white);
    canvas.drawCircle(point, 4.5, Paint()..color = color);

    final value = values[index];
    final valueText = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
    final label = labels.length == values.length && labels[index].isNotEmpty
        ? labels[index]
        : 'Day ${index + 1}';
    final painter = TextPainter(
      text: TextSpan(
        text: '$label: $valueText',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const horizontalPadding = 9.0;
    const tooltipHeight = 26.0;
    final tooltipWidth = painter.width + horizontalPadding * 2;
    final left = (point.dx - tooltipWidth / 2).clamp(
      leftPad,
      size.width - tooltipWidth,
    );
    final top = (point.dy - 34).clamp(2.0, chartH - tooltipHeight);
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, tooltipWidth, tooltipHeight),
      const Radius.circular(6),
    );
    canvas.drawRRect(rect, Paint()..color = const Color(0xEB1C1C1E));
    painter.paint(
      canvas,
      Offset(
        left + horizontalPadding,
        top + (tooltipHeight - painter.height) / 2,
      ),
    );
  }

  Path _smoothPath(List<Offset> pts) {
    if (pts.length == 1) {
      return Path()..moveTo(pts[0].dx, pts[0].dy);
    }
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 0; i < pts.length - 1; i++) {
      final cp1 = Offset((pts[i].dx + pts[i + 1].dx) / 2, pts[i].dy);
      final cp2 = Offset((pts[i].dx + pts[i + 1].dx) / 2, pts[i + 1].dy);
      path.cubicTo(
        cp1.dx,
        cp1.dy,
        cp2.dx,
        cp2.dy,
        pts[i + 1].dx,
        pts[i + 1].dy,
      );
    }
    return path;
  }

  @override
  bool shouldRepaint(_AreaChartPainter old) =>
      old.progress != progress ||
      old.selectedIndex != selectedIndex ||
      !listEquals(old.values, values) ||
      !listEquals(old.labels, labels);
}
