import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../src/services/metrics_service.dart';
import '../src/services/stress_score_service.dart';
import '../src/services/wind_down_reminder.dart';
import '../src/utils/day_key.dart';
import '../src/utils/smooth_chart_path.dart';
import '../src/utils/stress_view.dart';
import '../theme/vivordo_theme.dart';
import '../widgets/apple_ui.dart';
import '../widgets/contextual_insight_bar.dart';
import '../widgets/morning_check_in_card.dart' show feelCheckInLabels;

/// Stress, against the person's own usual: a dial anchored at their usual,
/// today's curve, what moved the latest reading, a next step, the trend and
/// which signals were measured (lib/src/utils/stress_view.dart).
class StressDetailScreen extends StatefulWidget {
  const StressDetailScreen({super.key});

  @override
  State<StressDetailScreen> createState() => _StressDetailScreenState();
}

const _purple = Color(0xFF6B55F5);

/// Band colours: graphics use the bright ones; text in light mode uses the
/// darker ones so it stays readable on white.
Color _bandColor(BuildContext context, double score, {bool text = false}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final i = score < 30
      ? 0
      : score < 60
      ? 1
      : score < 80
      ? 2
      : 3;
  const bright = [
    Color(0xFF69D6A4),
    Color(0xFFFFC53D),
    Color(0xFFFF9F43),
    Color(0xFFFF6B62),
  ];
  const deep = [
    Color(0xFF14855A),
    Color(0xFF9A6A00),
    Color(0xFFB35A00),
    Color(0xFFC93C35),
  ];
  return (text && !dark ? deep : bright)[i];
}

Color _up(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFFF9F43)
    : const Color(0xFFB35A00);

Color _down(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF69D6A4)
    : const Color(0xFF14855A);

class _StressDetailScreenState extends State<StressDetailScreen> {
  int _rangeIndex = 0;
  final _signalsKey = GlobalKey();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _days = _dayStream();
  late final Stream<DocumentSnapshot<Map<String, dynamic>>>? _calendar =
      _calendarStream();

  /// Whether the wind-down reminder is already on, so the next step offers
  /// it only when it isn't.
  bool _windDownOn = false;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FirebaseFirestore.instance.collection('users').doc(uid).get().then((u) {
      final on = (u.data()?['preferences'] as Map?)?['windDownReminder'];
      if (mounted && on == true) setState(() => _windDownOn = true);
    }, onError: (Object e) => debugPrint('StressDetailScreen: $e'));
  }

  int get _rangeDays => _rangeIndex == 0 ? 7 : 30;

  Stream<QuerySnapshot<Map<String, dynamic>>> _dayStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    final today = DateUtils.dateOnly(DateTime.now());
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('metrics_daily')
        .where(
          FieldPath.documentId,
          isGreaterThanOrEqualTo: localDayKey(
            today.subtract(const Duration(days: 60)),
          ),
        )
        .where(FieldPath.documentId, isLessThanOrEqualTo: localDayKey(today))
        .orderBy(FieldPath.documentId)
        .snapshots();
  }

  /// Today's event times (no titles), written by DayRecordService.
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _calendarStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('effort_inputs')
        .doc(localDayKey(DateTime.now()))
        .snapshots();
  }

  String _time(DateTime t) => DateFormat('h:mm a').format(t.toLocal());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.vivordoColors.page,
      appBar: AppBar(
        backgroundColor: context.vivordoColors.page,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _purple),
        ),
        title: const Text(
          'Stress',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'How stress is calculated',
            onPressed: _showHowItWorks,
            icon: const Icon(Icons.info_outline_rounded, color: _purple),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _days,
        builder: (context, snapshot) {
          if (!snapshot.hasData &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final days = [
            for (final doc in snapshot.data?.docs ?? const [])
              if (DateTime.tryParse(doc.id) case final date?)
                StressDay.fromDoc(date, doc.data()),
          ];
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _calendar,
            builder: (context, calendar) =>
                _content(days, _events(calendar.data?.data())),
          );
        },
      ),
    );
  }

  List<(DateTime, DateTime)> _events(Map<String, dynamic>? record) => [
    for (final e in (record?['events'] as List?) ?? const [])
      if (e is Map && e['start'] is Timestamp && e['end'] is Timestamp)
        ((e['start'] as Timestamp).toDate(), (e['end'] as Timestamp).toDate()),
  ];

  Widget _content(List<StressDay> days, List<(DateTime, DateTime)> events) {
    final now = DateTime.now();
    final todayDate = DateUtils.dateOnly(now);
    final byKey = {for (final d in days) localDayKey(d.date): d};
    final today = byKey[localDayKey(todayDate)] ?? StressDay(date: todayDate);
    final yesterday =
        byKey[localDayKey(todayDate.subtract(const Duration(days: 1)))];
    final usualRange = stressUsualRange(days, todayDate);
    final score = today.score;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _rightNow(today, stressAtTimeOfDay(yesterday, now)),
          const SizedBox(height: 14),
          _todaySoFar(today, usualRange, events),
          if (today.drivers.isNotEmpty) ...[
            const SizedBox(height: 14),
            _whatsMovingIt(today),
          ],
          const SizedBox(height: 14),
          _nextStep(today),
          const SizedBox(height: 14),
          _trend(days, todayDate),
          if (today.signals.isNotEmpty) ...[
            const SizedBox(height: 14),
            _signalsToday(today),
          ],
          const SizedBox(height: 14),
          _tunedToYou(days),
        ],
      ),
    ).withScreenInsight(
      ScreenInsight(
        'stress',
        "Today's stress estimate",
        score == null
            ? 'There is no stress estimate available for today yet. An empty reading does not mean low stress.'
            : 'Your latest displayed stress estimate is ${score.round()}/100, '
                  '${stressUsualHeadline(score, today.usual).toLowerCase()} for you. '
                  '${today.computedAt == null ? "Its update time is unavailable." : "Calculated ${DateFormat('MMM d, h:mm a').format(today.computedAt!.toLocal())}."} '
                  '${today.drivers.isEmpty ? "There are no recorded drivers to explain it yet." : "Recorded drivers include ${today.drivers.take(2).map((d) => d.label).join(' and ')}; these are contributions to the estimate, not proven causes."} '
                  'Want to explore a manageable next step?',
      ),
    );
  }

  // ── Right now ──────────────────────────────────────────────────────────────

  Widget _rightNow(StressDay today, double? yesterdayNow) {
    final colors = context.vivordoColors;
    final score = today.score;
    final grey = today.lowConfidence;
    final headline = score == null
        ? 'No reading yet today'
        : stressUsualHeadline(score, today.usual);
    final difference = score == null ? 0 : (score - today.usual).round();
    final measured = today.measuredSignals, total = today.signals.length;
    final confidence = today.confidence;

    return _card(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      borderColor: _purple.withValues(alpha: .4),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'RIGHT NOW',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: colors.textSecondary,
                ),
              ),
              const Spacer(),
              ValueListenableBuilder<bool>(
                valueListenable: StressScoreService.isComputing,
                builder: (context, computing, _) => Text(
                  computing
                      ? 'Updating…'
                      : today.computedAt == null
                      ? ''
                      : 'Updated ${_time(today.computedAt!)}',
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Semantics(
            label: score == null
                ? 'No stress reading yet today'
                : 'Stress ${score.round()} out of 100, '
                      '${stressBand(score)}, ${headline.toLowerCase()}'
                      '${grey ? ', low confidence' : ''}',
            child: ExcludeSemantics(
              child: SizedBox(
                width: 210,
                height: 186,
                child: CustomPaint(
                  painter: _DialPainter(
                    score: score,
                    usual: today.usual,
                    swing: score == null || grey
                        ? colors.textSecondary.withValues(alpha: .7)
                        : _bandColor(context, score),
                    knobFill: colors.card,
                    knob: grey ? colors.textSecondary : colors.textPrimary,
                    tick: colors.textPrimary,
                  ),
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.topCenter,
                        child: Text(
                          'USUAL',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 72,
                        child: Column(
                          children: [
                            Text(
                              score?.round().toString() ?? '--',
                              style: TextStyle(
                                fontSize: 64,
                                height: .9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -2.5,
                                color: grey
                                    ? colors.textSecondary
                                    : colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              score == null ? 'No data' : stressBand(score),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: score == null
                                    ? colors.textSecondary
                                    : _bandColor(context, score, text: true),
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
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (difference.abs() > 1)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    difference > 0
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 18,
                    color: difference > 0 ? _up(context) : _down(context),
                  ),
                ),
              Flexible(
                child: Text(
                  headline,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'How to read the ring',
                onPressed: _showRingInfo,
                icon: const Icon(
                  Icons.info_outline_rounded,
                  color: _purple,
                  size: 20,
                ),
              ),
            ],
          ),
          if (score == null)
            Text(
              'An empty reading doesn\'t mean low stress.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (confidence != null)
                _chip(
                  icon: grey
                      ? Icons.error_outline_rounded
                      : Icons.check_rounded,
                  iconColor: grey ? _up(context) : _down(context),
                  text: [
                    '${confidence[0].toUpperCase()}${confidence.substring(1)} confidence',
                    if (total > 0)
                      '$measured of $total signals'
                    else if (today.coverage != null)
                      '${today.coverage!.round()}% coverage',
                  ].join(' · '),
                  onTap: grey
                      ? () => _showLowConfidence(measured, total)
                      : total > 0
                      ? () => Scrollable.ensureVisible(
                          _signalsKey.currentContext!,
                          duration: const Duration(milliseconds: 350),
                        )
                      : today.coverage == null
                      ? null
                      : () => _showCoverageExplanation(today.coverage!),
                ),
              if (yesterdayNow != null)
                _chip(
                  text:
                      'Yesterday at ${_time(DateTime.now())}: ${yesterdayNow.round()}',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String text,
    IconData? icon,
    Color? iconColor,
    VoidCallback? onTap,
  }) {
    final colors = context.vivordoColors;
    return Material(
      color: colors.cardMuted,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: iconColor),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: onTap == null
                          ? colors.textSecondary
                          : colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Today so far ───────────────────────────────────────────────────────────

  Widget _todaySoFar(
    StressDay today,
    (double, double)? usualRange,
    List<(DateTime, DateTime)> events,
  ) {
    final colors = context.vivordoColors;
    final readings = today.readings;
    final peak = stressPeak(readings);
    final low = readings.isEmpty
        ? null
        : readings.map((r) => r.score).reduce(math.min);
    final duringEvent =
        peak != null &&
        events.any((e) => !peak.at.isBefore(e.$1) && peak.at.isBefore(e.$2));

    return _card(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              _title('Today so far'),
              const Spacer(),
              if (peak != null && low != null)
                Text(
                  'Low ${low.round()} · High ${peak.score.round()}',
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (readings.length < 2)
            Container(
              height: 120,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.border),
              ),
              child: Text(
                '${readings.length == 1 ? '1 reading' : 'No readings'} so far.\n'
                'Your timeline fills in as readings arrive through the day.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: colors.textSecondary,
                ),
              ),
            )
          else ...[
            SizedBox(
              height: 170,
              child: _DayChart(
                readings: readings,
                usualRange: usualRange,
                events: events,
                day: today.date,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                if (usualRange != null)
                  _legend(
                    colors.textPrimary.withValues(alpha: .16),
                    'Your usual range',
                  ),
                if (events.isNotEmpty)
                  _legend(_purple.withValues(alpha: .7), 'Calendar events'),
              ],
            ),
            if (peak != null && low != null) ...[
              const SizedBox(height: 8),
              Text(
                // A peak is only worth naming when the day actually rose.
                '${peak.score - low >= 3 ? 'Peak ${peak.score.round()} at ${_time(peak.at)}${duringEvent ? ', during an event' : ''}' : 'Steady around ${peak.score.round()} so far'}. '
                'Touch the curve to see any moment.',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _legend(Color color, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: context.vivordoColors.textSecondary,
        ),
      ),
    ],
  );

  // ── What's moving it ───────────────────────────────────────────────────────

  Widget _whatsMovingIt(StressDay today) {
    final colors = context.vivordoColors;
    final drivers = today.drivers.take(5).toList();
    final biggest = drivers.first.contribution.abs();
    return _card(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('What\'s moving it'),
          const SizedBox(height: 3),
          Text(
            'Points each signal added to or took off your latest reading',
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
          const SizedBox(height: 14),
          for (final d in drivers)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _driverRow(d, today, biggest),
            ),
          Divider(height: 1, color: colors.border),
          const SizedBox(height: 10),
          Text(
            'Bars to the right raise it, bars to the left lower it. '
            'Signals, not proven causes.',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _driverRow(StressSignal d, StressDay day, double biggest) {
    final up = d.contribution > 0;
    final color = up ? _up(context) : _down(context);
    final points = d.contribution.round();
    final value = points == 0
        ? (up ? '+<1' : '−<1')
        : '${up ? '+' : '−'}${points.abs()}';
    return Semantics(
      label:
          '${d.label}: ${up ? 'raised' : 'lowered'} it by ${points.abs()} points. '
          '${stressDriverDetail(d, day, _time)}',
      child: ExcludeSemantics(
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .14),
                shape: BoxShape.circle,
              ),
              child: Icon(_icon(d.kind), size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    stressDriverDetail(d, day, _time),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.vivordoColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 104,
              height: 22,
              child: CustomPaint(
                painter: _DriverBarPainter(
                  fraction: (d.contribution.abs() / biggest).clamp(.08, 1),
                  up: up,
                  color: color,
                  axis: context.vivordoColors.border,
                ),
                child: Align(
                  alignment: up ? Alignment.centerLeft : Alignment.centerRight,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _icon(StressSignalKind kind) => switch (kind) {
    StressSignalKind.feel => Icons.sentiment_satisfied_rounded,
    StressSignalKind.sleep => Icons.bedtime_rounded,
    StressSignalKind.hrv => Icons.monitor_heart_rounded,
    StressSignalKind.heartRate => Icons.favorite_rounded,
    StressSignalKind.breathing => Icons.air_rounded,
    StressSignalKind.sitting => Icons.event_seat_rounded,
    StressSignalKind.timeOfDay => Icons.schedule_rounded,
    StressSignalKind.activity => Icons.directions_walk_rounded,
    StressSignalKind.mindfulness => Icons.self_improvement_rounded,
    StressSignalKind.calendar => Icons.event_note_rounded,
    StressSignalKind.bloodOxygen => Icons.water_drop_rounded,
    StressSignalKind.other => Icons.insights_rounded,
  };

  // ── A next step ────────────────────────────────────────────────────────────

  Widget _nextStep(StressDay today) {
    final colors = context.vivordoColors;
    final step = stressNextStep(today.drivers);
    return _card(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _purple.withValues(alpha: .16),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 20,
                  color: _purple,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      step.body,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (step.action == StressNextAction.windDown) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _windDownOn ? null : _turnOnWindDown,
              style: FilledButton.styleFrom(
                backgroundColor: _purple,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: Icon(
                _windDownOn
                    ? Icons.check_rounded
                    : Icons.notifications_active_outlined,
                size: 18,
              ),
              label: Text(
                _windDownOn
                    ? 'Wind-down reminder is on'
                    : 'Remind me to wind down tonight',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Divider(height: 1, color: colors.border),
          const SizedBox(height: 14),
          const Text(
            'How do you feel right now?',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final (i, label) in feelCheckInLabels.indexed) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _checkIn(label),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: EdgeInsets.zero,
                      backgroundColor: colors.cardMuted,
                      foregroundColor: colors.textPrimary,
                      side: BorderSide(color: colors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'How you feel is the biggest signal, and each check-in teaches '
            'Vivordo what drives your stress.',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  Future<void> _checkIn(String label) async {
    try {
      await MetricsService.saveMoodCheckIn(label);
      if (!mounted) return;
      showToast(
        context,
        'Checked in: $label. Updating your score.',
        kind: ToastKind.success,
      );
    } catch (e) {
      debugPrint('StressDetailScreen: check-in failed: $e');
      if (mounted) {
        showToast(
          context,
          'Couldn\'t save your check-in. Try again.',
          kind: ToastKind.error,
        );
      }
    }
  }

  Future<void> _turnOnWindDown() async {
    try {
      await WindDownReminders.setEnabled(true);
      if (!mounted) return;
      setState(() => _windDownOn = true);
      showToast(
        context,
        'Wind-down reminder on. You\'ll get a nudge before your usual bedtime.',
        kind: ToastKind.success,
      );
    } catch (e) {
      debugPrint('StressDetailScreen: wind-down reminder failed: $e');
      if (mounted) {
        showToast(
          context,
          'Couldn\'t turn on the reminder. Try again.',
          kind: ToastKind.error,
        );
      }
    }
  }

  // ── Trend ──────────────────────────────────────────────────────────────────

  Widget _trend(List<StressDay> days, DateTime today) {
    final colors = context.vivordoColors;
    final byKey = {for (final d in days) localDayKey(d.date): d};
    List<StressDay> range(int from, int count) => [
      for (var i = count - 1; i >= 0; i--)
        byKey[localDayKey(
              DateTime(today.year, today.month, today.day - from - i),
            )] ??
            StressDay(
              date: DateTime(today.year, today.month, today.day - from - i),
            ),
    ];
    final period = range(0, _rangeDays);
    final previous = range(_rangeDays, _rangeDays);
    final stats = stressTrendStats(period, previous);
    final unit = _rangeIndex == 0 ? 'last week' : 'last month';

    return _card(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _title('Trend'),
              const Spacer(),
              SizedBox(
                width: 150,
                child: AppSegmented<int>(
                  segments: const {0: 'Week', 1: 'Month'},
                  value: _rangeIndex,
                  onChanged: (i) => setState(() => _rangeIndex = i),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Each bar is a day\'s range, the dot its average. Tap a day for details.',
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 170,
            child: _RangeChart(
              days: period,
              labels: [
                for (final (i, d) in period.indexed)
                  _rangeIndex == 0
                      ? (i == period.length - 1
                            ? 'Today'
                            : DateFormat('E').format(d.date))
                      : (i % 5 == 4 || i == period.length - 1
                            ? DateFormat('M/d').format(d.date)
                            : ''),
              ],
              onDay: (d) => _showDay(d),
            ),
          ),
          if (stats != null) ...[
            const SizedBox(height: 10),
            Divider(height: 1, color: colors.border),
            const SizedBox(height: 12),
            Row(
              children: [
                _stat(stats.average.round().toString(), 'Average'),
                _stat(stats.calmest.average!.round().toString(), 'Calmest day'),
                _stat(stats.hardest.average!.round().toString(), 'Hardest day'),
                _stat(
                  stats.change == null
                      ? '--'
                      : stats.change!.round() == 0
                      ? '0'
                      : '${stats.change! > 0 ? '+' : '−'}${stats.change!.round().abs()}',
                  'vs $unit',
                  color: stats.change == null || stats.change!.round() == 0
                      ? null
                      : stats.change! > 0
                      ? _up(context)
                      : _down(context),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String value, String label, {Color? color}) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: context.vivordoColors.textSecondary,
          ),
        ),
      ],
    ),
  );

  void _showDay(StressDay day) {
    final average = day.average;
    if (average == null) return;
    showAppleSheet<void>(
      context,
      builder: (sheetContext) {
        final colors = sheetContext.vivordoColors;
        final drivers = day.drivers.take(4).toList();
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: colors.border,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  DateFormat('EEEE, MMMM d').format(day.date),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      average.round().toString(),
                      style: const TextStyle(
                        fontSize: 44,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.5,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      stressBand(average),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _bandColor(sheetContext, average, text: true),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Day average'
                  '${day.minimum != null && day.maximum != null ? ' · ranged ${day.minimum!.round()} to ${day.maximum!.round()}' : ''}',
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                ),
                if (day.readings.length >= 2) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 130,
                    child: _DayChart(
                      readings: day.readings,
                      usualRange: null,
                      events: const [],
                      day: day.date,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'What moved it',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                if (drivers.isEmpty)
                  Text(
                    'No drivers were recorded for this day.',
                    style: TextStyle(fontSize: 13, color: colors.textSecondary),
                  ),
                for (final d in drivers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            d.label,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          '${d.contribution > 0 ? '+' : '−'}${d.contribution.round().abs()}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: d.contribution > 0
                                ? _up(sheetContext)
                                : _down(sheetContext),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Signals today ──────────────────────────────────────────────────────────

  Widget _signalsToday(StressDay today) {
    final colors = context.vivordoColors;
    final signals = today.signals;
    final missing = {
      for (final s in signals)
        if (!s.measured) s.kind,
    };
    final hints = [
      if (missing.contains(StressSignalKind.feel))
        'Check in above to add how you feel.',
      if (missing.contains(StressSignalKind.sleep))
        'Last night\'s sleep hasn\'t synced yet.',
      if (missing.contains(StressSignalKind.hrv) ||
          missing.contains(StressSignalKind.heartRate))
        'Wearing your watch adds heart signals.',
    ];
    return _card(
      key: _signalsKey,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _title('Signals today'),
              const Spacer(),
              Text(
                '${today.measuredSignals} of ${signals.length}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: today.lowConfidence ? _up(context) : _down(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              runSpacing: 8,
              children: [
                for (final s in signals)
                  SizedBox(
                    width: constraints.maxWidth / 2,
                    child: Row(
                      children: [
                        Icon(
                          s.measured
                              ? Icons.check_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 16,
                          color: s.measured
                              ? _down(context)
                              : colors.textSecondary,
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            s.label,
                            style: TextStyle(
                              fontSize: 13,
                              color: s.measured
                                  ? colors.textPrimary
                                  : colors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (hints.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final hint in hints)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  hint,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ── Tuned to you ───────────────────────────────────────────────────────────

  Widget _tunedToYou(List<StressDay> days) {
    final colors = context.vivordoColors;
    final history = days.where((d) => d.average != null).length;
    final checkIns = days.where((d) => d.moodLabel != null).length;
    return _card(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Tuned to you'),
          const SizedBox(height: 8),
          Text(
            'Built from $history day${history == 1 ? '' : 's'} of your recent '
            'history and $checkIns check-in${checkIns == 1 ? '' : 's'}. Each '
            'check-in nudges which signals count most for you.',
            style: const TextStyle(fontSize: 14, height: 1.45),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.sync_rounded, size: 16, color: colors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Updates about every 10 minutes, and after new health data '
                  'or a check-in.',
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: _showHowItWorks,
            style: TextButton.styleFrom(
              foregroundColor: _purple,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 44),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'How stress is calculated',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared pieces ──────────────────────────────────────────────────────────

  Widget _title(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w800,
      color: context.vivordoColors.textPrimary,
    ),
  );

  Widget _card({
    Key? key,
    required Widget child,
    required EdgeInsets padding,
    Color? borderColor,
  }) => Container(
    key: key,
    padding: padding,
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: borderColor ?? context.vivordoColors.border),
    ),
    child: child,
  );

  void _showRingInfo() => showInfoSheet(
    context,
    icon: CupertinoIcons.gauge,
    title: 'Reading the ring',
    items: const [
      AppleInfoItem(
        'The top is your usual',
        'The tick at the top marks a typical day for you, worked out from your own recent days.',
      ),
      AppleInfoItem(
        'The arc is how far you are from it',
        'It swings right when you\'re more stressed than usual and left when you\'re calmer. The faint colours behind it are the bands: Low, Moderate, Elevated and High.',
      ),
      AppleInfoItem(
        'Grey means low confidence',
        'With only a few signals the score stays close to your usual, so the ring turns grey until more data arrives.',
      ),
    ],
  );

  void _showLowConfidence(int measured, int total) => showInfoSheet(
    context,
    icon: CupertinoIcons.exclamationmark_circle,
    title: 'Low confidence',
    summary: total > 0
        ? 'Only $measured of $total signals so far today'
        : 'Few signals so far today',
    items: const [
      AppleInfoItem(
        'A rough guide for now',
        'With few signals, the score stays close to your usual instead of guessing, so treat it as a rough guide.',
      ),
      AppleInfoItem(
        'What helps',
        'A check-in on how you feel is the biggest single signal. Wearing your watch adds heart, HRV and breathing readings, and confidence rises as they sync through the day.',
      ),
    ],
  );

  void _showCoverageExplanation(double coverage) => showInfoSheet(
    context,
    icon: CupertinoIcons.chart_pie,
    title: 'What coverage means',
    summary: '${coverage.round()}% of relevant signals available',
    items: const [
      AppleInfoItem(
        'What it counts',
        'How much of the relevant signal set (mood, sleep, heart and recovery readings, activity, and breathing data) was available when Vivordo calculated today’s score.',
      ),
      AppleInfoItem(
        'Completeness, not accuracy',
        'A lower percentage usually means some signals haven’t been recorded or synced yet. Your score can still be calculated from what’s available, and coverage may improve as more data arrives through the day.',
      ),
    ],
  );

  void _showHowItWorks() => showInfoSheet(
    context,
    icon: CupertinoIcons.waveform_path_ecg,
    title: 'How your stress score works',
    items: const [
      AppleInfoItem(
        'Your own baseline',
        'Vivordo combines available signals such as mood, sleep, heart and recovery readings, activity, and breathing data. It compares them with your own recent baseline, not another person’s.',
      ),
      AppleInfoItem(
        'Reading the score',
        'Lower scores mean a calmer state. Confidence shows how many signals were available. The score is a wellness insight, not a medical diagnosis.',
      ),
    ],
  );
}

// ── Painters ─────────────────────────────────────────────────────────────────

/// A 270° ring with the person's usual at the top. The faint track shows the
/// four bands; the bright arc runs from the usual to the score.
class _DialPainter extends CustomPainter {
  const _DialPainter({
    required this.score,
    required this.usual,
    required this.swing,
    required this.knobFill,
    required this.knob,
    required this.tick,
  });

  final double? score;
  final double usual;
  final Color swing, knobFill, knob, tick;

  static const _bands = [
    (0.0, 30.0, Color(0xFF69D6A4)),
    (30.0, 60.0, Color(0xFFFFC53D)),
    (60.0, 80.0, Color(0xFFFF9F43)),
    (80.0, 100.0, Color(0xFFFF6B62)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 15.0;
    final center = Offset(size.width / 2, 112);
    const radius = 84.0;
    final rect = Rect.fromCircle(center: center, radius: radius);
    double angle(double v) => (135 + 2.7 * v.clamp(0, 100)) * math.pi / 180;
    void arc(double from, double to, Color color, StrokeCap cap) {
      if (to - from < .2) return;
      canvas.drawArc(
        rect,
        angle(from),
        angle(to) - angle(from),
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = cap,
      );
    }

    for (final (i, (from, to, color)) in _bands.indexed) {
      final faint = color.withValues(alpha: .22);
      arc(
        from + (i == 0 ? 1 : .6),
        to - (i == 3 ? 1 : .6),
        faint,
        StrokeCap.butt,
      );
      if (i == 0) arc(0, 1, faint, StrokeCap.round);
      if (i == 3) arc(99, 100, faint, StrokeCap.round);
    }

    final value = score;
    if (value != null) {
      arc(
        math.min(usual, value),
        math.max(usual, value),
        swing,
        StrokeCap.round,
      );
    }

    Offset at(double v, double r) => center + Offset.fromDirection(angle(v), r);
    canvas.drawLine(
      at(usual, radius - 12),
      at(usual, radius + 12),
      Paint()
        ..color = tick
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    if (value != null) {
      final k = at(value, radius);
      canvas.drawCircle(k, 8, Paint()..color = knobFill);
      canvas.drawCircle(
        k,
        8,
        Paint()
          ..color = knob
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.score != score ||
      old.usual != usual ||
      old.swing != swing ||
      old.knob != knob ||
      old.tick != tick ||
      old.knobFill != knobFill;
}

class _DriverBarPainter extends CustomPainter {
  const _DriverBarPainter({
    required this.fraction,
    required this.up,
    required this.color,
    required this.axis,
  });

  final double fraction;
  final bool up;
  final Color color, axis;

  @override
  void paint(Canvas canvas, Size size) {
    // Leave room for the number on the bar's far side.
    const label = 34.0;
    final mid = up ? label : size.width - label;
    canvas.drawLine(
      Offset(mid, 0),
      Offset(mid, size.height),
      Paint()
        ..color = axis
        ..strokeWidth = 1,
    );
    final length = (size.width - label) * fraction;
    final rect = up
        ? Rect.fromLTWH(mid + 1, 5, length - 1, size.height - 10)
        : Rect.fromLTWH(mid - length, 5, length - 1, size.height - 10);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        rect,
        topRight: up ? const Radius.circular(6) : Radius.zero,
        bottomRight: up ? const Radius.circular(6) : Radius.zero,
        topLeft: up ? Radius.zero : const Radius.circular(6),
        bottomLeft: up ? Radius.zero : const Radius.circular(6),
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_DriverBarPainter old) =>
      old.fraction != fraction || old.up != up || old.color != color;
}

/// Today's curve: readings over the day, the usual range as a band and the
/// calendar's event times underneath. Touch to read any moment.
class _DayChart extends StatefulWidget {
  const _DayChart({
    required this.readings,
    required this.usualRange,
    required this.events,
    required this.day,
  });

  final List<StressReading> readings;
  final (double, double)? usualRange;
  final List<(DateTime, DateTime)> events;
  final DateTime day;

  @override
  State<_DayChart> createState() => _DayChartState();
}

class _DayChartState extends State<_DayChart> {
  int? _selected;

  (double, double) get _hours {
    final first = widget.readings.first.at;
    final last = widget.readings.last.at;
    final start = math.min(6.0, first.hour.toDouble());
    final end = math.max(22.0, last.hour + 1.0);
    return (start, math.min(24, end));
  }

  void _select(double x, double width) {
    final (start, end) = _hours;
    final chart = width - _ChartFrame.right;
    final hour = start + (end - start) * (x / chart).clamp(0, 1);
    var best = 0;
    for (var i = 1; i < widget.readings.length; i++) {
      if ((_hourOf(widget.readings[i].at) - hour).abs() <
          (_hourOf(widget.readings[best].at) - hour).abs()) {
        best = i;
      }
    }
    if (best != _selected) setState(() => _selected = best);
  }

  double _hourOf(DateTime t) {
    final local = t.toLocal();
    final dayStart = DateTime(
      widget.day.year,
      widget.day.month,
      widget.day.day,
    );
    return local.difference(dayStart).inMinutes / 60;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final (start, end) = _hours;
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (e) => _select(e.localPosition.dx, constraints.maxWidth),
        onHorizontalDragUpdate: (e) =>
            _select(e.localPosition.dx, constraints.maxWidth),
        onHorizontalDragEnd: (_) => setState(() => _selected = null),
        child: CustomPaint(
          size: Size.infinite,
          painter: _DayChartPainter(
            points: [for (final r in widget.readings) (_hourOf(r.at), r.score)],
            start: start,
            end: end,
            usualRange: widget.usualRange,
            events: [
              for (final e in widget.events) (_hourOf(e.$1), _hourOf(e.$2)),
            ],
            selected: _selected,
            selectedLabel: _selected == null
                ? null
                : '${widget.readings[_selected!].score.round()} · '
                      '${DateFormat('h:mm a').format(widget.readings[_selected!].at.toLocal())}',
            line: _purple,
            text: colors.textSecondary,
            grid: colors.border,
            band: colors.textPrimary.withValues(alpha: .12),
            tooltip: colors.cardMuted,
            tooltipText: colors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _ChartFrame {
  static const right = 28.0; // y-axis labels
  static const bottom = 34.0; // events strip and hour labels
}

class _DayChartPainter extends CustomPainter {
  const _DayChartPainter({
    required this.points,
    required this.start,
    required this.end,
    required this.usualRange,
    required this.events,
    required this.selected,
    required this.selectedLabel,
    required this.line,
    required this.text,
    required this.grid,
    required this.band,
    required this.tooltip,
    required this.tooltipText,
  });

  final List<(double, double)> points;
  final double start, end;
  final (double, double)? usualRange;
  final List<(double, double)> events;
  final int? selected;
  final String? selectedLabel;
  final Color line, text, grid, band, tooltip, tooltipText;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width - _ChartFrame.right;
    final height = size.height - _ChartFrame.bottom;
    final values = points.map((p) => p.$2);
    final lo = math.max(0.0, math.min(20.0, values.reduce(math.min) - 5));
    final hi = math.min(100.0, math.max(80.0, values.reduce(math.max) + 5));
    double x(double hour) =>
        width * ((hour - start) / (end - start)).clamp(0, 1);
    double y(double v) => height * (1 - (v - lo) / (hi - lo));

    if (usualRange case (final a, final b)) {
      canvas.drawRect(
        Rect.fromLTRB(0, y(b), width, y(a)),
        Paint()..color = band,
      );
    }
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final v in [hi, (hi + lo) / 2, lo]) {
      canvas.drawLine(Offset(0, y(v)), Offset(width, y(v)), gridPaint);
      _text(
        canvas,
        v.round().toString(),
        Offset(width + 6, y(v) - 7),
        text,
        10,
      );
    }

    final offsets = [for (final p in points) Offset(x(p.$1), y(p.$2))];
    final path = smoothChartPath(offsets);
    final fill = Path.from(path)
      ..lineTo(offsets.last.dx, height)
      ..lineTo(offsets.first.dx, height)
      ..close();
    canvas.drawPath(fill, Paint()..color = line.withValues(alpha: .16));
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(offsets.last, 5, Paint()..color = line);

    // Calendar events strip.
    final strip = height + 8;
    canvas.drawLine(Offset(0, strip + 4), Offset(width, strip + 4), gridPaint);
    for (final (a, b) in events) {
      if (b <= start || a >= end) continue;
      final left = x(a), right = math.max(x(b), left + 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(left, strip, right, strip + 8),
          const Radius.circular(3),
        ),
        Paint()..color = line.withValues(alpha: .7),
      );
    }
    for (var h = (start / 4).ceil() * 4.0; h <= end; h += 4) {
      final label = h == 0 || h == 24
          ? '12a'
          : h == 12
          ? '12p'
          : h < 12
          ? '${h.round()}a'
          : '${(h - 12).round()}p';
      _text(canvas, label, Offset(x(h) - 8, strip + 12), text, 10);
    }

    final i = selected;
    if (i != null && i < offsets.length && selectedLabel != null) {
      final p = offsets[i];
      canvas.drawLine(
        Offset(p.dx, 0),
        Offset(p.dx, height),
        Paint()
          ..color = text.withValues(alpha: .5)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(p, 5, Paint()..color = tooltipText);
      final painter = TextPainter(
        text: TextSpan(
          text: selectedLabel,
          style: TextStyle(
            color: tooltipText,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final w = painter.width + 16, h = painter.height + 10;
      final left = (p.dx - w / 2).clamp(0.0, width - w);
      final top = (p.dy - h - 12).clamp(0.0, height - h);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, w, h),
          const Radius.circular(8),
        ),
        Paint()..color = tooltip,
      );
      painter.paint(canvas, Offset(left + 8, top + 5));
    }
  }

  @override
  bool shouldRepaint(_DayChartPainter old) =>
      old.points != points ||
      old.selected != selected ||
      old.usualRange != usualRange ||
      old.events != events ||
      old.line != line ||
      old.text != text;
}

/// Each day as a range bar (lowest to highest) with its average as a dot.
class _RangeChart extends StatelessWidget {
  const _RangeChart({
    required this.days,
    required this.labels,
    required this.onDay,
  });

  final List<StressDay> days;
  final List<String> labels;
  final ValueChanged<StressDay> onDay;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (e) {
          final slot = (constraints.maxWidth - _ChartFrame.right) / days.length;
          final i = (e.localPosition.dx / slot).floor();
          if (i >= 0 && i < days.length) onDay(days[i]);
        },
        child: CustomPaint(
          size: Size.infinite,
          painter: _RangeChartPainter(
            days: days,
            labels: labels,
            bar: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF4A4560)
                : const Color(0xFFD5D0F0),
            today: _purple.withValues(alpha: .6),
            dot: colors.textPrimary,
            text: colors.textSecondary,
            grid: colors.border,
          ),
        ),
      ),
    );
  }
}

class _RangeChartPainter extends CustomPainter {
  const _RangeChartPainter({
    required this.days,
    required this.labels,
    required this.bar,
    required this.today,
    required this.dot,
    required this.text,
    required this.grid,
  });

  final List<StressDay> days;
  final List<String> labels;
  final Color bar, today, dot, text, grid;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width - _ChartFrame.right;
    final height = size.height - 20;
    final values = [
      for (final d in days) ...[?d.minimum, ?d.maximum, ?d.average],
    ];
    final lo = values.isEmpty
        ? 20.0
        : math.max(0.0, math.min(20.0, values.reduce(math.min) - 5));
    final hi = values.isEmpty
        ? 80.0
        : math.min(100.0, math.max(80.0, values.reduce(math.max) + 5));
    double y(double v) => height * (1 - (v - lo) / (hi - lo));
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final v in [hi, (hi + lo) / 2, lo]) {
      canvas.drawLine(Offset(0, y(v)), Offset(width, y(v)), gridPaint);
      _text(
        canvas,
        v.round().toString(),
        Offset(width + 6, y(v) - 7),
        text,
        10,
      );
    }
    final slot = width / days.length;
    final barWidth = math.min(12.0, slot * .6);
    for (final (i, d) in days.indexed) {
      final cx = slot * (i + .5);
      final isToday = i == days.length - 1;
      // A day that barely moved shows just its dot.
      if (d.minimum != null &&
          d.maximum != null &&
          d.maximum! - d.minimum! >= 2) {
        final top = y(d.maximum!), bottom = y(d.minimum!);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              cx - barWidth / 2,
              top,
              cx + barWidth / 2,
              math.max(bottom, top + barWidth),
            ),
            Radius.circular(barWidth / 2),
          ),
          Paint()..color = isToday ? today : bar,
        );
      }
      if (d.average != null) {
        canvas.drawCircle(
          Offset(cx, y(d.average!)),
          math.min(4.5, barWidth / 2),
          Paint()..color = dot,
        );
      }
      if (labels[i].isNotEmpty) {
        final painter = TextPainter(
          text: TextSpan(
            text: labels[i],
            style: TextStyle(
              color: text,
              fontSize: 10,
              fontWeight: isToday ? FontWeight.w800 : FontWeight.w400,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(
          canvas,
          Offset(
            (cx - painter.width / 2).clamp(0.0, width - painter.width),
            height + 6,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_RangeChartPainter old) =>
      old.days != days || old.labels != labels || old.dot != dot;
}

void _text(Canvas canvas, String value, Offset at, Color color, double size) {
  (TextPainter(
    text: TextSpan(
      text: value,
      style: TextStyle(color: color, fontSize: size),
    ),
    textDirection: TextDirection.ltr,
  )..layout()).paint(canvas, at);
}
