import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/utils/day_key.dart';
import '../src/utils/chart_text.dart';

/// Which score a [ScoreHistory] charts.
enum ScoreHistoryKind {
  /// `scores_daily.capacity.score` as a line against the usual band.
  capacity,

  /// `scores_daily.effort.total` as a bar per day against the usual line.
  effort,

  /// `planned_demand.points` (the day's plan) beside that day's Effort.
  plannedVsActual,
}

/// How much one page shows: a calendar week, month or quarter.
enum ScoreHistoryRange {
  week('7D'),
  month('30D'),
  quarter('90D');

  const ScoreHistoryRange(this.label);
  final String label;
}

/// One page: its first and last day (inclusive).
typedef HistoryPeriod = ({DateTime start, DateTime end});

/// The period [back] pages before the one holding [today]: weeks run Monday
/// to Sunday, quarters Jan–Mar, Apr–Jun and so on.
HistoryPeriod historyPeriod(ScoreHistoryRange range, DateTime today, int back) {
  final day = DateUtils.dateOnly(today);
  switch (range) {
    case ScoreHistoryRange.week:
      final monday = day.subtract(Duration(days: day.weekday - 1 + 7 * back));
      return (
        start: monday,
        end: DateTime(monday.year, monday.month, monday.day + 6),
      );
    case ScoreHistoryRange.month:
      final start = DateTime(day.year, day.month - back);
      return (start: start, end: DateTime(start.year, start.month + 1, 0));
    case ScoreHistoryRange.quarter:
      final first = (day.month - 1) ~/ 3 * 3 + 1;
      final start = DateTime(day.year, first - 3 * back);
      return (start: start, end: DateTime(start.year, start.month + 3, 0));
  }
}

/// How many pages reach back to [earliest]: 1 when it's in this period.
int historyPageCount(
  ScoreHistoryRange range,
  DateTime today,
  DateTime earliest,
) {
  var pages = 1;
  while (pages < 400 &&
      historyPeriod(
            range,
            today,
            pages,
          ).end.compareTo(DateUtils.dateOnly(earliest)) >=
          0) {
    pages++;
  }
  return pages;
}

/// "This week · Oct 12 – 18", "Oct 5 – 11", "October", "Jul – Sep".
String historyPeriodLabel(ScoreHistoryRange range, DateTime today, int back) {
  final p = historyPeriod(range, today, back);
  final year = p.end.year == today.year ? '' : ' ${p.end.year}';
  switch (range) {
    case ScoreHistoryRange.week:
      final span = p.start.month == p.end.month
          ? '${DateFormat('MMM d').format(p.start)} – ${p.end.day}'
          : '${DateFormat('MMM d').format(p.start)} – '
                '${DateFormat('MMM d').format(p.end)}';
      return back == 0 ? 'This week · $span' : '$span$year';
    case ScoreHistoryRange.month:
      return '${DateFormat('MMMM').format(p.start)}$year';
    case ScoreHistoryRange.quarter:
      return '${DateFormat('MMM').format(p.start)} – '
          '${DateFormat('MMM').format(p.end)}$year';
  }
}

/// Reads `users/{uid}/{collection}` documents from [start] to [end] day keys
/// (inclusive), keyed by day.
typedef HistoryLoader =
    Future<Map<String, Map<String, dynamic>>> Function(
      String collection,
      String start,
      String end,
    );

/// The first day key in `users/{uid}/{collection}`, or null when empty.
typedef HistoryEarliest = Future<String?> Function(String collection);

CollectionReference<Map<String, dynamic>>? _collection(String name) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection(name);
}

Future<Map<String, Map<String, dynamic>>> _firestoreLoad(
  String collection,
  String start,
  String end,
) async {
  final ref = _collection(collection);
  if (ref == null) return const {};
  final snapshot = await ref
      .where(FieldPath.documentId, isGreaterThanOrEqualTo: start)
      .where(FieldPath.documentId, isLessThanOrEqualTo: end)
      .get();
  return {for (final doc in snapshot.docs) doc.id: doc.data()};
}

Future<String?> _firestoreEarliest(String collection) async {
  final ref = _collection(collection);
  if (ref == null) return null;
  final snapshot = await ref.orderBy(FieldPath.documentId).limit(1).get();
  return snapshot.docs.firstOrNull?.id;
}

/// One day's values on the chart.
typedef _Day = ({DateTime day, double? value, double? planned, String detail});

/// A day took well over its plan. Days with nothing planned never count:
/// any effort at all would be "over" nothing.
bool _ranOver(double planned, double took) =>
    planned > 0 && took > planned * 1.25;

const _purple = Color(0xFF7F77DD);
const _line = Color(0xFFA99BFF);
const _orange = Color(0xFFF08A5D);
const _grey = Color(0xFF85859B);

/// A score's history inside its breakdown sheet: 7D / 30D / 90D pages of
/// calendar weeks, months or quarters, swiped (or ‹ ›) back to the first
/// saved day. Tapping a day explains it. Hidden until there's history.
class ScoreHistory extends StatefulWidget {
  const ScoreHistory({
    super.key,
    required this.kind,
    this.usual,
    this.today,
    this.load = _firestoreLoad,
    this.earliest = _firestoreEarliest,
  });

  final ScoreHistoryKind kind;

  /// Capacity's usual (the sheet's own); Effort's is worked out here from
  /// the 28 days before today.
  final double? usual;

  final DateTime? today;
  final HistoryLoader load;
  final HistoryEarliest earliest;

  @override
  State<ScoreHistory> createState() => _ScoreHistoryState();
}

class _ScoreHistoryState extends State<ScoreHistory> {
  var _range = ScoreHistoryRange.week;
  var _back = 0;
  int? _selected;
  late final DateTime _today = DateUtils.dateOnly(
    widget.today ?? DateTime.now(),
  );
  late final PageController _pages = PageController();
  late final Future<({DateTime? earliest, double? usual})> _setup = _load();
  final _cache = <String, Future<List<_Day>>>{};

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  String get _source => widget.kind == ScoreHistoryKind.plannedVsActual
      ? 'planned_demand'
      : 'scores_daily';

  Future<({DateTime? earliest, double? usual})> _load() async {
    final first = await widget.earliest(_source);
    var usual = widget.usual;
    if (widget.kind == ScoreHistoryKind.effort && usual == null) {
      final past = await widget.load(
        'scores_daily',
        localDayKey(_today.subtract(const Duration(days: 28))),
        localDayKey(_today.subtract(const Duration(days: 1))),
      );
      final totals = [
        for (final day in past.values)
          if ((day['effort'] as Map?)?['total'] case final num total)
            total.toDouble(),
      ]..sort();
      if (totals.length >= 7) usual = totals[totals.length ~/ 2];
    }
    return (
      earliest: first == null ? null : DateTime.tryParse(first),
      usual: usual,
    );
  }

  Future<List<_Day>> _page(int back) {
    final period = historyPeriod(_range, _today, back);
    final key = '${_range.name}:$back';
    return _cache[key] ??= () async {
      final start = localDayKey(period.start);
      final end = localDayKey(period.end);
      final scores = await widget.load('scores_daily', start, end);
      final planned = widget.kind == ScoreHistoryKind.plannedVsActual
          ? await widget.load('planned_demand', start, end)
          : const <String, Map<String, dynamic>>{};
      return [
        for (
          var day = period.start;
          !day.isAfter(period.end);
          day = DateTime(day.year, day.month, day.day + 1)
        )
          _dayOf(day, scores[localDayKey(day)], planned[localDayKey(day)]),
      ];
    }();
  }

  _Day _dayOf(
    DateTime day,
    Map<String, dynamic>? scores,
    Map<String, dynamic>? planned,
  ) {
    final future = day.isAfter(_today);
    final capacity = scores?['capacity'] as Map?;
    final effort = scores?['effort'] as Map?;
    final effortTotal = (effort?['total'] as num?)?.toDouble();
    switch (widget.kind) {
      case ScoreHistoryKind.capacity:
        final score = (capacity?['score'] as num?)?.toDouble();
        final parts = capacity?['parts'] as Map?;
        final sleep = (capacity?['sleepHours'] as num?)?.toDouble();
        final low = [
          for (final (key, name) in [
            ('sleep', 'sleep'),
            ('body', 'overnight body'),
            ('recovery', 'recovery'),
          ])
            if ((parts?[key] as num?) case final num v when v < 60) '$name low',
        ];
        return (
          day: day,
          value: future ? null : score,
          planned: null,
          detail: [
            if (sleep != null) 'Slept ${sleep.toStringAsFixed(1)} h',
            ...low,
            if (capacity?['provisional'] == true) 'estimated',
          ].join(' · '),
        );
      case ScoreHistoryKind.effort:
        final after = (effort?['afterHoursMinutes'] as num?)?.round() ?? 0;
        return (
          day: day,
          value: future ? null : effortTotal,
          planned: null,
          detail: effort == null
              ? ''
              : [
                  'Schedule: ${((effort['mental'] as num?) ?? 0).round()}',
                  'Activity: ${((effort['physical'] as num?) ?? 0).round()}',
                  if (after > 0) '$after min after hours',
                ].join(' · '),
        );
      case ScoreHistoryKind.plannedVsActual:
        final plan = (planned?['points'] as num?)?.toDouble();
        return (
          day: day,
          value: future || plan == null ? null : effortTotal,
          planned: future ? null : plan,
          detail: plan == null || effortTotal == null
              ? ''
              : 'Planned ${plan.round()} · took ${effortTotal.round()}',
        );
    }
  }

  void _go(int back, int pages) {
    final target = back.clamp(0, pages - 1);
    setState(() {
      _back = target;
      _selected = null;
    });
    _pages.animateToPage(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _setup,
    builder: (context, setup) {
      final earliest = setup.data?.earliest;
      // Nothing saved yet (new account, or planned Demand before its first
      // day): no chart to show.
      if (earliest == null) return const SizedBox.shrink();
      final pages = historyPageCount(_range, _today, earliest);
      final colors = context.vivordoColors;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The picker's 6 pt tap margins replace spacing here.
          const SizedBox(height: 8),
          _RangePicker(
            range: _range,
            onChanged: (range) => setState(() {
              _range = range;
              _back = 0;
              _selected = null;
              if (_pages.hasClients) _pages.jumpToPage(0);
            }),
          ),
          Row(
            children: [
              IconButton(
                tooltip: 'Earlier',
                onPressed: _back >= pages - 1
                    ? null
                    : () => _go(_back + 1, pages),
                icon: const Icon(CupertinoIcons.chevron_left),
                color: _purple,
              ),
              Expanded(
                child: Text(
                  historyPeriodLabel(_range, _today, _back),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Later',
                onPressed: _back == 0 ? null : () => _go(_back - 1, pages),
                icon: const Icon(CupertinoIcons.chevron_right),
                color: _purple,
              ),
            ],
          ),
          SizedBox(
            height: 150,
            // Reversed: swiping right goes back in time, like a calendar.
            child: PageView.builder(
              key: ValueKey(_range),
              controller: _pages,
              reverse: true,
              itemCount: pages,
              onPageChanged: (back) => setState(() {
                _back = back;
                _selected = null;
              }),
              itemBuilder: (context, back) => FutureBuilder(
                future: _page(back),
                builder: (context, days) => _Chart(
                  kind: widget.kind,
                  days: days.data ?? const [],
                  today: _today,
                  usual: setup.data?.usual,
                  selected: back == _back ? _selected : null,
                  onSelect: (i) => setState(() => _selected = i),
                ),
              ),
            ),
          ),
          FutureBuilder(
            future: _page(_back),
            builder: (context, days) => _Detail(
              kind: widget.kind,
              days: days.data ?? const [],
              selected: _selected,
              usual: setup.data?.usual,
            ),
          ),
        ],
      );
    },
  );
}

class _RangePicker extends StatelessWidget {
  const _RangePicker({required this.range, required this.onChanged});
  final ScoreHistoryRange range;
  final ValueChanged<ScoreHistoryRange> onChanged;

  /// Invisible tap margin above and below the track, so each segment is at
  /// least a 44 pt target while the track looks the same.
  static const _slop = 6.0;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        top: _slop,
        bottom: _slop,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.vivordoColors.input,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Row(
          children: [
            for (final value in ScoreHistoryRange.values)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: value == range,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    excludeFromSemantics: true,
                    onTap: () => onChanged(value),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: _slop + 3),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => onChanged(value),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          decoration: BoxDecoration(
                            color: value == range
                                ? const Color(0xFF6B5CE7)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            value.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: value == range ? Colors.white : _grey,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class _Chart extends StatelessWidget {
  const _Chart({
    required this.kind,
    required this.days,
    required this.today,
    required this.usual,
    required this.selected,
    required this.onSelect,
  });

  final ScoreHistoryKind kind;
  final List<_Day> days;
  final DateTime today;
  final double? usual;
  final int? selected;
  final ValueChanged<int> onSelect;

  /// What the chart shows, for VoiceOver: its low and high days. The
  /// average sits in the detail card underneath.
  String get _summary {
    final name = switch (kind) {
      ScoreHistoryKind.capacity => 'Capacity',
      ScoreHistoryKind.effort => 'Effort',
      ScoreHistoryKind.plannedVsActual => 'Effort against the plan',
    };
    final saved = [
      for (final d in days)
        if (d.value != null) d,
    ];
    if (saved.isEmpty) return '$name by day: no days saved here.';
    final low = saved.reduce((a, b) => b.value! < a.value! ? b : a);
    final high = saved.reduce((a, b) => b.value! > a.value! ? b : a);
    final date = DateFormat('EEE, MMM d');
    return '$name by day, ${saved.length} '
        '${saved.length == 1 ? 'day' : 'days'} saved: '
        'lowest ${low.value!.round()} on ${date.format(low.day)}, '
        'highest ${high.value!.round()} on ${date.format(high.day)}.';
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: _summary,
    child: ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, box) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (tap) {
            if (days.isEmpty) return;
            final i = (tap.localPosition.dx / box.maxWidth * days.length)
                .floor()
                .clamp(0, days.length - 1);
            if (days[i].value != null || days[i].planned != null) onSelect(i);
          },
          child: CustomPaint(
            size: Size(box.maxWidth, 150),
            painter: _ChartPainter(
              kind: kind,
              days: days,
              today: today,
              usual: usual,
              selected: selected,
              labelColor: context.vivordoColors.textSecondary,
              gridColor: context.vivordoColors.border,
              // Painted text doesn't inherit the theme's font.
              fontFamily: DefaultTextStyle.of(context).style.fontFamily,
            ),
          ),
        ),
      ),
    ),
  );
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.kind,
    required this.days,
    required this.today,
    required this.usual,
    required this.selected,
    required this.labelColor,
    required this.gridColor,
    this.fontFamily,
  });

  final ScoreHistoryKind kind;
  final List<_Day> days;
  final DateTime today;
  final double? usual;
  final int? selected;
  final Color labelColor, gridColor;
  final String? fontFamily;

  static const _bottom = 18.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    final h = size.height - _bottom;
    final slot = size.width / days.length;
    final values = [
      for (final d in days) ...[?d.value, ?d.planned],
      ?usual,
    ];
    final top = kind == ScoreHistoryKind.capacity
        ? 100.0
        : math.max(10.0, values.fold<double>(0, math.max) * 1.15);
    // Capacity mostly sits between 50 and 100: start the axis a step below
    // the lowest point so the line isn't squeezed into the top.
    final bottom = kind == ScoreHistoryKind.capacity && values.isNotEmpty
        ? (math.max(0.0, values.fold<double>(100, math.min) - 15) / 10)
                  .floor() *
              10.0
        : 0.0;
    double y(double v) => h - ((v - bottom) / (top - bottom)) * h;
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, h), Offset(size.width, h), grid);

    final usualValue = usual;
    if (usualValue != null && kind == ScoreHistoryKind.capacity) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(0, y(usualValue + 5), size.width, y(usualValue - 5)),
          const Radius.circular(3),
        ),
        Paint()..color = _purple.withValues(alpha: .16),
      );
    }

    switch (kind) {
      case ScoreHistoryKind.capacity:
        final path = Path();
        var started = false;
        for (final (i, d) in days.indexed) {
          final v = d.value;
          if (v == null) continue;
          final p = Offset(slot * (i + .5), y(v));
          started ? path.lineTo(p.dx, p.dy) : path.moveTo(p.dx, p.dy);
          started = true;
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = _line
            ..style = PaintingStyle.stroke
            ..strokeWidth = days.length > 40 ? 1.5 : 2.5
            ..strokeJoin = StrokeJoin.round,
        );
        for (final (i, d) in days.indexed) {
          final v = d.value;
          if (v == null) continue;
          final p = Offset(slot * (i + .5), y(v));
          final on = i == selected;
          if (on) canvas.drawCircle(p, 6, Paint()..color = Colors.white);
          canvas.drawCircle(
            p,
            on ? 4.5 : (days.length > 40 ? 1.8 : 3.2),
            Paint()..color = v < 50 ? _orange : _line,
          );
        }
      case ScoreHistoryKind.effort:
        final w = math.max(2.0, slot * .6);
        for (final (i, d) in days.indexed) {
          final v = d.value;
          if (v == null) continue;
          final rect = RRect.fromRectAndRadius(
            Rect.fromLTWH(slot * (i + .5) - w / 2, y(v), w, h - y(v)),
            const Radius.circular(2),
          );
          final isToday = DateUtils.isSameDay(d.day, today);
          final heavy = usualValue != null && v >= usualValue * 1.5;
          final color = heavy ? _orange : _purple;
          if (isToday) {
            canvas.drawRRect(
              rect,
              Paint()
                ..color = _line
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5,
            );
          } else {
            canvas.drawRRect(
              rect,
              Paint()..color = color.withValues(alpha: i == selected ? 1 : .75),
            );
          }
        }
        if (usualValue != null) {
          final dash = Paint()
            ..color = const Color(0xFF32C878)
            ..strokeWidth = 1.5;
          for (var x = 0.0; x < size.width; x += 7) {
            canvas.drawLine(
              Offset(x, y(usualValue)),
              Offset(math.min(x + 4, size.width), y(usualValue)),
              dash,
            );
          }
        }
      case ScoreHistoryKind.plannedVsActual:
        final w = math.max(1.5, slot * .34);
        for (final (i, d) in days.indexed) {
          final plan = d.planned;
          if (plan == null) continue;
          final x = slot * (i + .5);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x - w - .5, y(plan), w, h - y(plan)),
              const Radius.circular(2),
            ),
            Paint()..color = _grey.withValues(alpha: .8),
          );
          final took = d.value;
          if (took == null) continue;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x + .5, y(took), w, h - y(took)),
              const Radius.circular(2),
            ),
            Paint()
              ..color = (_ranOver(plan, took) ? _orange : _line).withValues(
                alpha: i == selected ? 1 : .85,
              ),
          );
        }
    }

    // Day letters for a week, a few dates for longer pages.
    final step = days.length <= 7 ? 1 : (days.length / 4).ceil();
    for (var i = 0; i < days.length; i += step) {
      final d = days[i].day;
      final label = days.length <= 7
          ? 'MTWTFSS'[d.weekday - 1]
          : DateFormat('MMM d').format(d);
      final text = TextPainter(
        textScaler: chartTextScaler,
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: 11,
            fontFamily: fontFamily,
            color: DateUtils.isSameDay(d, today) ? _line : labelColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = (slot * (i + .5) - text.width / 2).clamp(
        0.0,
        size.width - text.width,
      );
      text.paint(canvas, Offset(x, h + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.days != days ||
      old.selected != selected ||
      old.usual != usual ||
      old.labelColor != labelColor ||
      old.fontFamily != fontFamily;
}

class _Detail extends StatelessWidget {
  const _Detail({
    required this.kind,
    required this.days,
    required this.selected,
    required this.usual,
  });

  final ScoreHistoryKind kind;
  final List<_Day> days;
  final int? selected;
  final double? usual;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final pick = selected;
    String title;
    String body;
    if (pick != null && pick < days.length) {
      final d = days[pick];
      final date = DateFormat('EEE, MMM d').format(d.day);
      final v = d.value;
      title = switch (kind) {
        ScoreHistoryKind.capacity when v != null =>
          '$date · ${v.round()} '
              '${v >= 80
                  ? 'High'
                  : v >= 50
                  ? 'Moderate'
                  : 'Low'}',
        ScoreHistoryKind.effort when v != null => '$date · ${v.round()}',
        _ => date,
      };
      body = d.detail;
    } else {
      final counted = [
        for (final d in days)
          if (d.value != null) d,
      ];
      final planned = [
        for (final d in counted)
          if ((d.planned ?? 0) > 0) d,
      ];
      title = switch (kind) {
        ScoreHistoryKind.plannedVsActual =>
          planned.isEmpty
              ? counted.isEmpty
                    ? 'Planned vs actual'
                    : 'Nothing planned on these days'
              : 'Ran over the plan on '
                    '${planned.where((d) => _ranOver(d.planned!, d.value!)).length} '
                    'of ${planned.length} '
                    '${planned.length == 1 ? 'day' : 'days'}',
        _ when counted.isEmpty => 'No days saved here',
        _ =>
          'Average ${(counted.fold<double>(0, (s, d) => s + d.value!) / counted.length).round()}'
              '${usual == null ? '' : ' · usual ${usual!.round()}'}',
      };
      body = switch (kind) {
        ScoreHistoryKind.plannedVsActual =>
          'Grey: planned that day · purple: what it took'
              '${planned.length < counted.length ? ' · days with nothing planned aren\'t counted' : ''}',
        _ => 'Tap a day to see why.',
      };
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.cardMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          if (body.isNotEmpty)
            Text(
              body,
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
        ],
      ),
    );
  }
}
