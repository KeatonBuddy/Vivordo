import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/services/calendar_cognitive_load_service.dart';
import '../src/services/meeting_patterns_service.dart';
import '../src/utils/body_reaction.dart';
import '../src/utils/day_effort.dart';
import '../src/utils/day_key.dart';
import '../src/utils/heart_rate_history.dart';
import '../src/utils/meeting_patterns.dart';
import '../src/utils/screen_metric_projection.dart' show reactionHeartDays;
import 'day_timeline.dart' show formatSpan;
import 'event_type_section.dart';

const _summaryPurple = Color(0xFF6B5CE7);
const _heartRed = Color(0xFFE5484D);

/// A reading's colour against your usual (docs: body_reaction.dart).
const _bandColors = {
  HeartBand.usual: Color(0xFF1D9E75),
  HeartBand.above: Color(0xFFEF9F27),
  HeartBand.wellAbove: Color(0xFFE0703F),
};

const _bandLabels = {
  HeartBand.usual: 'Your usual',
  HeartBand.above: 'Above usual',
  HeartBand.wellAbove: 'Well above usual',
};

enum CalendarEventSummaryAction { edit, delete }

class CalendarEventSummaryData {
  const CalendarEventSummaryData({
    required this.title,
    required this.start,
    required this.end,
    required this.isAllDay,
    required this.isRecurring,
    required this.color,
    required this.calendarName,
    required this.canEdit,
    this.typeEvent,
    this.seriesKey,
    this.reaction,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final bool isAllDay;
  final bool isRecurring;
  final Color color;
  final String calendarName;
  final bool canEdit;

  /// A timed event's type, points and heart rate; null for all-day ones.
  final CalendarCognitiveEvent? typeEvent;

  /// The repeating series' key ([seriesKeyFor]), for its trend.
  final String? seriesKey;

  /// Heart rate already worked out (My Day); otherwise it's loaded once
  /// the event is over.
  final BodyReaction? reaction;

  String get durationLabel {
    if (isAllDay) return 'All day';
    return formatSpan(end.difference(start));
  }
}

/// Where the sheet gets its data; tests pass their own.
class EventSummarySources {
  const EventSummarySources({this.score, this.reaction, this.patterns});

  final Future<CognitiveLoadScore?> Function(CalendarCognitiveEvent event)?
  score;
  final Future<BodyReaction?> Function(DateTime start, DateTime end)? reaction;
  final Future<MeetingPatterns> Function()? patterns;
}

Future<CalendarEventSummaryAction?> showCalendarEventSummarySheet(
  BuildContext context, {
  required CalendarEventSummaryData event,
  @visibleForTesting EventSummarySources sources = const EventSummarySources(),
}) => showModalBottomSheet<CalendarEventSummaryAction>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (context) =>
      _CalendarEventSummarySheet(event: event, sources: sources),
);

/// Heart rate during [start]–[end] against your usual then, from that day's
/// readings and the [reactionHeartDays] before (as My Day works it out).
/// ponytail: reads up to 15 days of metrics on each open of a finished
/// event; cache per day if it shows up in a trace.
Future<BodyReaction?> loadEventReaction(DateTime start, DateTime end) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  final day = DateTime(start.year, start.month, start.day);
  final key = localDayKey(day);
  final docs = await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('metrics_daily')
      .where(
        FieldPath.documentId,
        isGreaterThanOrEqualTo: localDayKey(
          DateTime(day.year, day.month, day.day - reactionHeartDays),
        ),
      )
      .where(FieldPath.documentId, isLessThanOrEqualTo: key)
      .get();
  final today = <HeartRateHistoryReading>[];
  final history = <HeartRateHistoryReading>[];
  for (final doc in docs.docs) {
    final readings = mergedHeartRateHistory(
      doc.data(),
      fallbackDate: DateTime.tryParse(doc.id) ?? day,
      includeDailyFallback: false,
    );
    (doc.id == key ? today : history).addAll(readings);
  }
  return bodyReactionFor(
    start: start,
    end: end,
    today: today,
    history: history,
  );
}

class _CalendarEventSummarySheet extends StatefulWidget {
  const _CalendarEventSummarySheet({
    required this.event,
    required this.sources,
  });

  final CalendarEventSummaryData event;
  final EventSummarySources sources;

  @override
  State<_CalendarEventSummarySheet> createState() =>
      _CalendarEventSummarySheetState();
}

class _CalendarEventSummarySheetState
    extends State<_CalendarEventSummarySheet> {
  CognitiveLoadScore? _score;
  bool _changingType = false;
  BodyReaction? _reaction;
  bool _loadingReaction = false;
  MeetingPatterns _patterns = MeetingPatterns.empty;

  CalendarEventSummaryData get _event => widget.event;

  /// Counts toward your day and isn't exercise: a raised heart rate there
  /// is the point, so it isn't judged.
  bool get _hasHeartRate =>
      !_event.isAllDay &&
      _event.typeEvent?.contributesToSchedule != false &&
      !looksLikeExercise(_event.title);

  @override
  void initState() {
    super.initState();
    _reaction = _event.reaction;
    final typeEvent = _event.typeEvent;
    if (typeEvent != null) _loadScore(typeEvent);
    if (_reaction == null &&
        _hasHeartRate &&
        !DateTime.now().isBefore(_event.end)) {
      _loadReaction();
    }
    _loadPatterns();
  }

  Future<void> _loadScore(CalendarCognitiveEvent event) async {
    try {
      final score = widget.sources.score != null
          ? await widget.sources.score!(event)
          : (await CalendarCognitiveLoadService.scoreEvents([
              event,
            ], allowAi: true)).first;
      if (mounted) setState(() => _score = score);
    } catch (error) {
      debugPrint('Event type unavailable: $error');
    }
  }

  Future<void> _loadReaction() async {
    setState(() => _loadingReaction = true);
    BodyReaction? reaction;
    try {
      reaction = await (widget.sources.reaction ?? loadEventReaction)(
        _event.start,
        _event.end,
      );
    } catch (error) {
      debugPrint('Event heart rate unavailable: $error');
    }
    if (!mounted) return;
    setState(() {
      _reaction = reaction;
      _loadingReaction = false;
    });
  }

  Future<void> _loadPatterns() async {
    try {
      final patterns = widget.sources.patterns != null
          ? await widget.sources.patterns!()
          : (await MeetingPatternsService.load()).patterns;
      if (mounted) setState(() => _patterns = patterns);
    } catch (error) {
      debugPrint('Event trends unavailable: $error');
    }
  }

  Future<void> _changeType() async {
    final event = _event.typeEvent, score = _score;
    if (event == null || score == null || _changingType) return;
    setState(() => _changingType = true);
    final changed = await changeEventType(context, event, score);
    if (!mounted) return;
    setState(() {
      _score = changed ?? _score;
      _changingType = false;
    });
  }

  ({String label, Color color}) _status(DateTime now) {
    final colors = context.vivordoColors;
    if (!now.isBefore(_event.end)) {
      return (label: 'Done', color: colors.textSecondary);
    }
    if (!now.isBefore(_event.start)) {
      return (label: 'In progress', color: const Color(0xFFFF9F0A));
    }
    return (
      label: DateUtils.isSameDay(now, _event.start)
          ? 'In ${formatSpan(_event.start.difference(now))}'
          : 'Upcoming',
      color: _summaryPurple,
    );
  }

  String _dateLabel(DateTime now) {
    final day = DateUtils.dateOnly(_event.start);
    final today = DateUtils.dateOnly(now);
    final away = DateTime.utc(
      day.year,
      day.month,
      day.day,
    ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
    return switch (away) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      _ => DateFormat('EEE, MMM d').format(day),
    };
  }

  /// The event's own trend, then its kind's, when either is consistent.
  List<MeetingPattern> get _trends {
    final category = _score?.category;
    return [
      ?_patterns.bySeries[_event.seriesKey],
      if (category != null)
        for (final kind in [..._patterns.high, ..._patterns.calm])
          if (kind.id == 'cat:$category') kind,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final now = DateTime.now();
    final status = _status(now);
    final ended = !now.isBefore(_event.end);
    final started = !now.isBefore(_event.start);
    final time = _event.isAllDay
        ? 'All day'
        : '${DateFormat('h:mm').format(_event.start)}–'
              '${DateFormat('h:mm a').format(_event.end)}';
    final typeEvent = _event.typeEvent;
    final score = _score;
    final points = typeEvent == null || score == null
        ? null
        : eventPoints(typeEvent, score);
    final reaction = _reaction;
    final trends = _trends;

    return FractionallySizedBox(
      heightFactor: .9,
      child: Material(
        color: colors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _event.title,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: status.color.withValues(alpha: .16),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                status.label,
                                style: TextStyle(
                                  color: status.color,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 9,
                                  height: 9,
                                  decoration: BoxDecoration(
                                    color: _event.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _event.calendarName,
                                  style: TextStyle(
                                    color: colors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(CupertinoIcons.xmark),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SummarySurface(
                      padding: EdgeInsets.zero,
                      child: IntrinsicHeight(
                        child: Row(
                          children: [
                            _Fact('Date', _dateLabel(now)),
                            VerticalDivider(width: 1, color: colors.border),
                            _Fact('Time', time),
                            VerticalDivider(width: 1, color: colors.border),
                            _Fact('Length', _event.durationLabel),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _SummarySurface(
                      child: Column(
                        children: [
                          if (typeEvent != null)
                            _SummaryDetailRow(
                              icon: Icons.tune_rounded,
                              label: 'Type',
                              value: score == null
                                  ? ''
                                  : score.category == 'unknown'
                                  ? 'Not sure'
                                  : eventTypeLabels[score.category] ??
                                        'Not sure',
                              busy: score == null || _changingType,
                              onTap: score == null ? null : _changeType,
                            ),
                          _SummaryDetailRow(
                            icon: Icons.repeat_rounded,
                            label: 'Repeats',
                            value: _event.isRecurring
                                ? 'Repeating'
                                : "Doesn't repeat",
                            showDivider: points != null,
                          ),
                          if (points != null)
                            _SummaryDetailRow(
                              icon: Icons.bolt_rounded,
                              label: started ? 'Effort' : 'Demand',
                              value: _pointsLabel(points, ended),
                              showDivider: false,
                            ),
                        ],
                      ),
                    ),
                    if (score != null && typeEvent != null) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          eventTypeCaption(score, free: typeEvent.showsAsFree),
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                    if (_hasHeartRate) ...[
                      const SizedBox(height: 22),
                      if (!ended)
                        const _HeartRateNote(
                          "Shows after it's over, if wearable data is "
                          'available.',
                        )
                      else if (reaction != null)
                        _HeartRateCard(
                          reaction: reaction,
                          start: _event.start,
                          end: _event.end,
                        )
                      else if (_loadingReaction)
                        const _HeartRateNote(null),
                    ],
                    if (trends.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      const _SummarySectionLabel('Trends'),
                      const SizedBox(height: 10),
                      _SummarySurface(
                        child: Column(
                          children: [
                            for (final (i, trend) in trends.indexed)
                              _TrendRow(
                                pattern: trend,
                                showDivider: i < trends.length - 1,
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        onPressed: _event.canEdit
                            ? () => Navigator.pop(
                                context,
                                CalendarEventSummaryAction.edit,
                              )
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: _summaryPurple,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          _event.canEdit
                              ? 'Edit Event'
                              : '${_event.calendarName} event · Read only',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    if (_event.canEdit) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton.icon(
                          onPressed: () => Navigator.pop(
                            context,
                            CalendarEventSummaryAction.delete,
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFFF453A),
                            textStyle: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          icon: const Icon(CupertinoIcons.delete),
                          label: const Text('Delete'),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 10),
                      Text(
                        '${_event.calendarName} events are currently read-only in Vivordo.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// What the event adds on its own: "Added 5" once it's over, else
  /// "Adds about 5".
  static String _pointsLabel(double points, bool ended) {
    if (points <= 0) return "Doesn't add to your day";
    final n = points.round();
    final amount = n < 1 ? 'under 1' : '$n';
    return ended ? 'Added $amount' : 'Adds about $amount';
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label, value;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Before the event, or while its heart rate loads (no [text]).
class _HeartRateNote extends StatelessWidget {
  const _HeartRateNote(this.text);

  final String? text;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return _SummarySurface(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.favorite_rounded, color: _heartRed, size: 19),
          const SizedBox(width: 8),
          Text(
            'Heart rate',
            style: TextStyle(
              color: colors.textSecondary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: text == null
                ? const Align(
                    alignment: Alignment.centerRight,
                    child: CupertinoActivityIndicator(radius: 8),
                  )
                : Text(
                    text!,
                    textAlign: TextAlign.end,
                    style: TextStyle(color: colors.textSecondary, fontSize: 13),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Heart rate through the event, coloured against your usual at that time
/// of day, like the workout summary's card: drag to read any minute, and a
/// bar of the minutes within, above and well above your usual.
class _HeartRateCard extends StatefulWidget {
  const _HeartRateCard({
    required this.reaction,
    required this.start,
    required this.end,
  });

  final BodyReaction reaction;
  final DateTime start, end;

  @override
  State<_HeartRateCard> createState() => _HeartRateCardState();
}

class _HeartRateCardState extends State<_HeartRateCard> {
  HeartRateHistoryReading? scrubbed;

  void _scrub(double dx, double width) {
    final share = (dx / (width - _EventHeartPainter.axisWidth)).clamp(0.0, 1.0);
    final time = widget.start.add(widget.end.difference(widget.start) * share);
    Duration away(HeartRateHistoryReading r) =>
        r.timestamp.difference(time).abs();
    final nearest = widget.reaction.samples.reduce(
      (a, b) => away(a) <= away(b) ? a : b,
    );
    if (nearest != scrubbed) setState(() => scrubbed = nearest);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final reaction = widget.reaction;
    final bpms = [for (final s in reaction.samples) s.bpm];
    final average = (bpms.reduce((a, b) => a + b) / bpms.length).round();
    final max = bpms.reduce(math.max).round();
    final minutes = heartBandMinutes(reaction);
    final bands = [
      for (final band in HeartBand.values)
        if (minutes[band]! > 0) band,
    ];
    final summary = heartBandSummary(reaction);
    final reading = scrubbed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummarySurface(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 22,
                child: Row(
                  children: reading == null
                      ? [
                          const Icon(
                            Icons.favorite_rounded,
                            color: _heartRed,
                            size: 19,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Heart rate',
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '$average avg · $max max',
                              textAlign: TextAlign.end,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: colors.textSecondary),
                            ),
                          ),
                        ]
                      : [
                          Text(
                            DateFormat('h:mm a').format(reading.timestamp),
                            style: TextStyle(color: colors.textSecondary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${reading.bpm.round()} bpm · '
                              '${_bandLabels[heartBandOf(reaction, reading.bpm)]}',
                              style: TextStyle(
                                color:
                                    _bandColors[heartBandOf(
                                      reaction,
                                      reading.bpm,
                                    )],
                                fontWeight: FontWeight.w800,
                              ),
                              textAlign: TextAlign.end,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                label:
                    'Heart rate graph. Average $average, max $max beats per '
                    'minute. Your usual then: ${reaction.usualLow.round()} to '
                    '${reaction.usualHigh.round()}.',
                child: LayoutBuilder(
                  builder: (context, constraints) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (details) =>
                        _scrub(details.localPosition.dx, constraints.maxWidth),
                    onHorizontalDragUpdate: (details) =>
                        _scrub(details.localPosition.dx, constraints.maxWidth),
                    onHorizontalDragEnd: (_) => setState(() => scrubbed = null),
                    onHorizontalDragCancel: () =>
                        setState(() => scrubbed = null),
                    // The card's whole width, so it fills the space on any
                    // phone.
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, 160),
                      painter: _EventHeartPainter(
                        reaction: reaction,
                        start: widget.start,
                        end: widget.end,
                        band: _bandColors[HeartBand.usual]!.withValues(
                          alpha: .14,
                        ),
                        bandText: _bandColors[HeartBand.usual]!,
                        gridColor: colors.border,
                        textColor: colors.textSecondary,
                        scrubbed: reading,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: SizedBox(
                    height: 10,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < bands.length; i++) ...[
                          if (i > 0) const SizedBox(width: 2),
                          Expanded(
                            flex: minutes[bands[i]]!,
                            child: ColoredBox(color: _bandColors[bands[i]]!),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: summary.headline,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(text: ' (${summary.overall})'),
                  ],
                ),
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'A wellness estimate from your heart rate, not a diagnosis.',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// The workout summary's heart rate graph for an event: gridlines with bpm
/// labels on the right, times along the bottom, your usual as a band, and
/// the line coloured by [HeartBand].
class _EventHeartPainter extends CustomPainter {
  _EventHeartPainter({
    required this.reaction,
    required this.start,
    required this.end,
    required this.band,
    required this.bandText,
    required this.gridColor,
    required this.textColor,
    required this.scrubbed,
  });

  /// Room on the right for the bpm labels.
  static const axisWidth = 30.0;
  static const _footer = 18.0;
  static const _top = 6.0;

  final BodyReaction reaction;
  final DateTime start, end;
  final Color band, bandText, gridColor, textColor;
  final HeartRateHistoryReading? scrubbed;

  void _text(
    Canvas canvas,
    String text,
    Offset at, {
    TextAlign align = TextAlign.left,
    Color? color,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 10,
          color: color ?? textColor,
          fontFamily: 'DMSans',
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final dx = switch (align) {
      TextAlign.center => at.dx - painter.width / 2,
      TextAlign.right => at.dx - painter.width,
      _ => at.dx,
    };
    painter.paint(canvas, Offset(dx, at.dy - painter.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final samples = reaction.samples;
    if (samples.isEmpty) return;
    final width = size.width - axisWidth;
    final bottom = size.height - _footer;
    final bpms = samples.map((s) => s.bpm);
    var lo =
        ((math.min(reaction.usualLow, bpms.reduce(math.min)) - 5) / 10)
            .floorToDouble() *
        10;
    var hi =
        ((math.max(reaction.usualHigh, bpms.reduce(math.max)) + 5) / 10)
            .ceilToDouble() *
        10;
    if (hi - lo < 30) {
      lo -= 10;
      hi = lo + 40;
    }
    final span = math.max(1, end.difference(start).inSeconds);
    double x(DateTime t) =>
        width * (t.difference(start).inSeconds / span).clamp(0.0, 1.0);
    double y(double bpm) => bottom - (bpm - lo) / (hi - lo) * (bottom - _top);

    // Your usual at this time of day.
    canvas.drawRRect(
      RRect.fromLTRBR(
        0,
        y(reaction.usualHigh),
        width,
        y(reaction.usualLow),
        const Radius.circular(4),
      ),
      Paint()..color = band,
    );
    _text(
      canvas,
      'your usual',
      Offset(4, y(reaction.usualLow) - 8),
      color: bandText,
    );

    final gridStep = (hi - lo) <= 40 ? 10.0 : 20.0;
    final grid = Paint()..color = gridColor;
    for (var v = lo; v <= hi; v += gridStep) {
      canvas.drawLine(Offset(0, y(v)), Offset(width, y(v)), grid);
      _text(canvas, '${v.round()}', Offset(width + 6, y(v)));
    }

    // Times: start, end, and round quarter- or half-hours between.
    _text(canvas, DateFormat('h:mm').format(start), Offset(0, size.height - 7));
    _text(
      canvas,
      DateFormat('h:mm').format(end),
      Offset(width, size.height - 7),
      align: TextAlign.right,
    );
    final minutes = end.difference(start).inMinutes;
    final tickStep = minutes <= 45 ? 15 : (minutes <= 120 ? 30 : 60);
    var tick = DateTime(start.year, start.month, start.day, start.hour);
    while (!tick.isAfter(start)) {
      tick = tick.add(Duration(minutes: tickStep));
    }
    for (; tick.isBefore(end); tick = tick.add(Duration(minutes: tickStep))) {
      final tx = x(tick);
      if (tx < 40 || tx > width - 40) continue;
      _text(
        canvas,
        DateFormat('h:mm').format(tick),
        Offset(tx, size.height - 7),
        align: TextAlign.center,
      );
    }

    final line = Paint()
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i + 1 < samples.length; i++) {
      final a = samples[i], b = samples[i + 1];
      // A gap in the readings stays a gap.
      if (b.timestamp.difference(a.timestamp) > const Duration(minutes: 3)) {
        continue;
      }
      line.color = _bandColors[heartBandOf(reaction, a.bpm)]!;
      canvas.drawLine(
        Offset(x(a.timestamp), y(a.bpm)),
        Offset(x(b.timestamp), y(b.bpm)),
        line,
      );
    }
    if (samples.length == 1) {
      canvas.drawCircle(
        Offset(x(samples.first.timestamp), y(samples.first.bpm)),
        3,
        Paint()..color = _bandColors[heartBandOf(reaction, samples.first.bpm)]!,
      );
    }

    if (scrubbed case final reading?) {
      final at = Offset(x(reading.timestamp), y(reading.bpm));
      canvas.drawLine(
        Offset(at.dx, _top),
        Offset(at.dx, bottom),
        Paint()
          ..color = textColor.withValues(alpha: .5)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(
        at,
        5,
        Paint()..color = _bandColors[heartBandOf(reaction, reading.bpm)]!,
      );
      canvas.drawCircle(at, 2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_EventHeartPainter old) =>
      old.reaction != reaction ||
      old.scrubbed != scrubbed ||
      old.gridColor != gridColor;
}

/// A repeating meeting's or a kind of event's consistent heart rate trend.
class _TrendRow extends StatelessWidget {
  const _TrendRow({required this.pattern, required this.showDivider});

  final MeetingPattern pattern;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final p = pattern;
    final color = p.high
        ? _bandColors[HeartBand.wellAbove]!
        : _bandColors[HeartBand.usual]!;
    final title = p.isSeries
        ? 'This meeting usually ${p.high ? 'runs your heart rate up' : 'keeps you calm'}'
        : '${p.label} usually ${p.high ? 'run your heart rate up' : 'keep you calm'}';
    final recent = p.events.length > 10
        ? p.events.sublist(p.events.length - 10)
        : p.events;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                p.high ? Icons.trending_up_rounded : Icons.spa_outlined,
                color: color,
                size: 22,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${p.liftLabel} · ${p.countLabel}',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    if (p.isSeries) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        label: 'The last ${recent.length} times',
                        child: Wrap(
                          spacing: 4,
                          children: [
                            for (final e in recent)
                              Container(
                                width: 13,
                                height: 13,
                                decoration: BoxDecoration(
                                  color: e.liftBpm >= 2
                                      ? _bandColors[HeartBand.wellAbove]!
                                            .withValues(alpha: .75)
                                      : e.liftBpm <= -2
                                      ? _bandColors[HeartBand.usual]!
                                            .withValues(alpha: .75)
                                      : colors.border,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider) Divider(height: 1, color: colors.border),
      ],
    );
  }
}

class _SummarySectionLabel extends StatelessWidget {
  const _SummarySectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: _summaryPurple,
      fontSize: 13,
      fontWeight: FontWeight.w900,
    ),
  );
}

class _SummarySurface extends StatelessWidget {
  const _SummarySurface({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: context.vivordoColors.cardMuted,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: context.vivordoColors.border),
    ),
    child: child,
  );
}

class _SummaryDetailRow extends StatelessWidget {
  const _SummaryDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.showDivider = true,
    this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool showDivider;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Row(
        children: [
          Icon(icon, color: _summaryPurple, size: 23),
          const SizedBox(width: 14),
          Text(
            label,
            style: TextStyle(color: colors.textPrimary, fontSize: 15),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(color: colors.textSecondary, fontSize: 14),
            ),
          ),
          if (busy) ...[
            const SizedBox(width: 8),
            const CupertinoActivityIndicator(radius: 8),
          ] else if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(
              CupertinoIcons.chevron_right,
              color: colors.textSecondary,
              size: 18,
            ),
          ],
        ],
      ),
    );
    return Column(
      children: [
        onTap == null ? row : InkWell(onTap: busy ? null : onTap, child: row),
        if (showDivider) Divider(height: 1, color: colors.border),
      ],
    );
  }
}
