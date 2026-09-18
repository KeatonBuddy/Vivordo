import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../src/utils/day_key.dart';
import '../src/utils/heart_rate_history.dart';
import '../src/utils/hourly_heart_insight.dart';
import '../theme/vivordo_theme.dart';

class HourlyHeartInsightCard extends StatefulWidget {
  const HourlyHeartInsightCard({super.key, required this.isActive});
  final bool isActive;
  @override
  State<HourlyHeartInsightCard> createState() => HourlyHeartInsightCardState();
}

class HourlyHeartInsightCardState extends State<HourlyHeartInsightCard>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _busy = false;
  bool _foreground = true;
  DateTime? _updated;
  String? _historyDay;
  String? _uid;
  List<HeartRateHistoryReading> _history = [];
  List<HeartActivityWindow> _sleep = [];
  List<HeartActivityWindow> _workouts = [];
  HourlyHeartInsight _insight = const HourlyHeartInsight(
    'Your past hour',
    'Loading heart-rate insights…',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _schedule();
    });
  }

  @override
  void didUpdateWidget(covariant HourlyHeartInsightCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (!widget.isActive || !_foreground) return;
    unawaited(refresh());
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => refresh());
  }

  Future<void> refresh({bool force = false}) async {
    if (!widget.isActive ||
        !_foreground ||
        (mounted && ModalRoute.of(context)?.isCurrent == false))
      return;
    final now = DateTime.now();
    if (_busy ||
        (!force &&
            _updated != null &&
            now.difference(_updated!) < const Duration(minutes: 5)))
      return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _busy = true;
    try {
      final user = FirebaseFirestore.instance.collection('users').doc(uid);
      final today = DateTime(now.year, now.month, now.day);
      final day = localDayKey(today);
      List<HeartActivityWindow> sleepWindows(
        Iterable<Map<String, dynamic>> docs,
      ) => [
        for (final data in docs)
          if (data['sleep'] is Map &&
              data['sleep']['bedtime'] is Timestamp &&
              data['sleep']['wakeTime'] is Timestamp)
            HeartActivityWindow(
              (data['sleep']['bedtime'] as Timestamp).toDate(),
              (data['sleep']['wakeTime'] as Timestamp).toDate(),
            ),
      ];
      List<HeartRateHistoryReading> samples(
        QuerySnapshot<Map<String, dynamic>> docs,
      ) => [
        for (final doc in docs.docs)
          ...mergedHeartRateHistory(
            doc.data(),
            fallbackDate: DateTime.parse(doc.id),
            includeDailyFallback: false,
          ),
      ];
      List<HeartActivityWindow> workoutWindows(
        QuerySnapshot<Map<String, dynamic>> docs,
      ) => [
        for (final doc in docs.docs)
          if (doc.data()['startedAt'] is Timestamp &&
              doc.data()['completedAt'] is Timestamp)
            HeartActivityWindow(
              (doc.data()['startedAt'] as Timestamp).toDate(),
              (doc.data()['completedAt'] as Timestamp).toDate(),
            ),
      ];
      if (force || _uid != uid || _historyDay != day) {
        final history = await user
            .collection('metrics_daily')
            .orderBy(FieldPath.documentId)
            .startAt([localDayKey(today.subtract(const Duration(days: 28)))])
            .endBefore([day])
            .get();
        final workouts = await user
            .collection('workouts')
            .where(
              'completedAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(
                today.subtract(const Duration(days: 28)),
              ),
            )
            .get();
        _history = samples(history);
        _sleep = sleepWindows(history.docs.map((d) => d.data()));
        _workouts = workoutWindows(workouts);
        _historyDay = day;
        _uid = uid;
      }
      // Include yesterday for a rolling window crossing local midnight.
      final recent = await user
          .collection('metrics_daily')
          .orderBy(FieldPath.documentId)
          .startAt([localDayKey(today.subtract(const Duration(days: 1)))])
          .endAt([day])
          .get();
      final workouts = await user
          .collection('workouts')
          .where(
            'completedAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(today),
          )
          .get();
      final result = summarizeHeartHour(
        now: now,
        readings: [..._history, ...samples(recent)],
        workouts: [..._workouts, ...workoutWindows(workouts)],
        sleep: [..._sleep, ...sleepWindows(recent.docs.map((d) => d.data()))],
      );
      _updated = now;
      if (mounted &&
          (result.title != _insight.title ||
              result.subtitle != _insight.subtitle))
        setState(() => _insight = result);
    } catch (error) {
      debugPrint('[HourlyHeartInsight] Refresh failed: $error');
      if (mounted)
        setState(
          () => _insight = const HourlyHeartInsight(
            'Insight unavailable',
            'Couldn’t refresh your heart-rate summary. Please try again.',
          ),
        );
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.vivordoColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.favorite_rounded,
            color: Color(0xFFFF3B30),
            size: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _insight.title,
                  style: TextStyle(
                    color: context.vivordoColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _insight.subtitle,
                  style: TextStyle(
                    color: context.vivordoColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
