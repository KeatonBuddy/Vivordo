import 'dart:math' as math;

import 'package:intl/intl.dart';

import 'day_key.dart';
import 'meeting_patterns.dart';

/// The Sunday weekly review (docs/scores.md §9): last Sunday to Saturday
/// from the small daily documents Vivordo already saves, and the week ahead
/// from the calendar. Pure, so every rule is tested. A wellness summary,
/// not a diagnosis.

/// What the review is built from.
class WeeklyReviewInput {
  const WeeklyReviewInput({
    required this.weekStart,
    required this.scores,
    this.reactions = const [],
    this.nightTags = const {},
    this.dayFixes = const {},
    this.workouts = 0,
    this.openPriorities = const [],
    this.nextWeek = const [],
    this.lastWeekNote,
  });

  /// The Sunday the reviewed week starts on.
  final DateTime weekStart;

  /// scores_daily by day key: the week and the 28 days before it.
  final Map<String, Map<String, dynamic>> scores;
  final List<MeetingReaction> reactions;

  /// daily_tags by night key (the evening's date).
  final Map<String, List<String>> nightTags;

  /// day_fixes by day key.
  final Map<String, Map<String, dynamic>> dayFixes;
  final int workouts;

  /// Today's open priorities that were due before today.
  final List<({String title, DateTime since})> openPriorities;

  /// Next week's weekdays and their expected Demand.
  final List<({DateTime day, double demand})> nextWeek;

  /// Last week's "anything else going on" answer, if any.
  final String? lastWeekNote;
}

/// One line under "What drained you" or "What helped".
class ReviewLine {
  const ReviewLine(this.kind, this.title, this.detail, {this.seriesKey});

  /// For the icon: sick, travel, heavyDay, bigDay, meeting, lateNight,
  /// afterHours, training, priority, sleep, fixes, calm.
  final String kind;

  /// For a meeting, empty: its name comes from the calendar ([seriesKey]),
  /// so no event title is stored.
  final String title;
  final String detail;
  final String? seriesKey;

  Map<String, Object?> toMap() => {
    'kind': kind,
    'title': title,
    'detail': detail,
    if (seriesKey != null) 'series': seriesKey,
  };

  static ReviewLine fromMap(Map m) => ReviewLine(
    m['kind'] as String? ?? '',
    m['title'] as String? ?? '',
    m['detail'] as String? ?? '',
    seriesKey: m['series'] as String?,
  );
}

class ReviewDay {
  const ReviewDay(this.day, this.effort, this.capacity, this.heavy, this.sick);

  final String day;
  final double? effort;
  final double? capacity;
  final bool heavy;
  final bool sick;

  Map<String, Object?> toMap() => {
    'day': day,
    'effort': effort,
    'capacity': capacity,
    'heavy': heavy,
    'sick': sick,
  };

  static ReviewDay fromMap(Map m) => ReviewDay(
    m['day'] as String? ?? '',
    (m['effort'] as num?)?.toDouble(),
    (m['capacity'] as num?)?.toDouble(),
    m['heavy'] == true,
    m['sick'] == true,
  );
}

class WeeklyReview {
  const WeeklyReview({
    required this.weekStart,
    required this.headline,
    required this.why,
    required this.chips,
    required this.days,
    required this.usualCapacity,
    required this.rows,
    required this.drained,
    required this.helped,
    required this.offDayNote,
    required this.burnout,
    required this.nextWeek,
    required this.nextHeadline,
    required this.suggestion,
    this.lastWeekNote,
    this.context = const [],
    this.note,
  });

  static const version = 1;

  final String weekStart;
  final String headline;
  final String why;

  /// Two or three short facts for Journal's row and My Day's card.
  final List<String> chips;
  final List<ReviewDay> days;
  final double? usualCapacity;
  final List<({String label, String value})> rows;
  final List<ReviewLine> drained;
  final List<ReviewLine> helped;

  /// Why a day's meetings weren't counted against them.
  final String? offDayNote;

  /// watch or warning, when the burnout check was there this week.
  final String? burnout;
  final List<({String day, String label})> nextWeek;
  final String? nextHeadline;
  final String? suggestion;
  final String? lastWeekNote;

  /// "Anything else going on": the chosen options and the free-text note.
  final List<String> context;
  final String? note;

  /// "Oct 4 – 10".
  String get range {
    final start = DateTime.parse(weekStart);
    final end = start.add(const Duration(days: 6));
    return start.month == end.month
        ? '${DateFormat('MMM d').format(start)} – ${end.day}'
        : '${DateFormat('MMM d').format(start)} – '
              '${DateFormat('MMM d').format(end)}';
  }

  /// The Sunday it's read on, where Journal lists it: the day after its
  /// week ends.
  DateTime get readOn {
    final start = DateTime.parse(weekStart);
    return DateTime(start.year, start.month, start.day + 7);
  }

  /// Journal search: the headline, why, facts and lines (meetings by
  /// [name], as shown).
  bool matches(String query, String Function(ReviewLine) name) {
    final q = query.trim().toLowerCase();
    return q.isEmpty ||
        [
          headline,
          why,
          ...chips,
          for (final l in [...drained, ...helped]) '${name(l)} ${l.detail}',
          ...context,
          ?note,
        ].any((t) => t.toLowerCase().contains(q));
  }

  WeeklyReview withContext(List<String> context, String? note) => WeeklyReview(
    weekStart: weekStart,
    headline: headline,
    why: why,
    chips: chips,
    days: days,
    usualCapacity: usualCapacity,
    rows: rows,
    drained: drained,
    helped: helped,
    offDayNote: offDayNote,
    burnout: burnout,
    nextWeek: nextWeek,
    nextHeadline: nextHeadline,
    suggestion: suggestion,
    lastWeekNote: lastWeekNote,
    context: context,
    note: note,
  );

  Map<String, Object?> toMap() => {
    'v': version,
    'weekStart': weekStart,
    'headline': headline,
    'why': why,
    'chips': chips,
    'days': [for (final d in days) d.toMap()],
    'usualCapacity': usualCapacity,
    'rows': [
      for (final r in rows) {'label': r.label, 'value': r.value},
    ],
    'drained': [for (final l in drained) l.toMap()],
    'helped': [for (final l in helped) l.toMap()],
    'offDayNote': offDayNote,
    'burnout': burnout,
    'nextWeek': [
      for (final d in nextWeek) {'day': d.day, 'label': d.label},
    ],
    'nextHeadline': nextHeadline,
    'suggestion': suggestion,
    'lastWeekNote': lastWeekNote,
    'context': context,
    'note': note,
  };

  static WeeklyReview? fromMap(Object? raw) {
    if (raw is! Map || raw['v'] != version || raw['weekStart'] is! String) {
      return null;
    }
    List<Map> maps(Object? v) => [
      for (final m in v is List ? v : const [])
        if (m is Map) m,
    ];
    return WeeklyReview(
      weekStart: raw['weekStart'] as String,
      headline: raw['headline'] as String? ?? '',
      why: raw['why'] as String? ?? '',
      chips: [...(raw['chips'] as List? ?? const []).whereType<String>()],
      days: [for (final m in maps(raw['days'])) ReviewDay.fromMap(m)],
      usualCapacity: (raw['usualCapacity'] as num?)?.toDouble(),
      rows: [
        for (final m in maps(raw['rows']))
          (
            label: m['label'] as String? ?? '',
            value: m['value'] as String? ?? '',
          ),
      ],
      drained: [for (final m in maps(raw['drained'])) ReviewLine.fromMap(m)],
      helped: [for (final m in maps(raw['helped'])) ReviewLine.fromMap(m)],
      offDayNote: raw['offDayNote'] as String?,
      burnout: raw['burnout'] as String?,
      nextWeek: [
        for (final m in maps(raw['nextWeek']))
          (day: m['day'] as String? ?? '', label: m['label'] as String? ?? ''),
      ],
      nextHeadline: raw['nextHeadline'] as String?,
      suggestion: raw['suggestion'] as String?,
      lastWeekNote: raw['lastWeekNote'] as String?,
      context: [...(raw['context'] as List? ?? const []).whereType<String>()],
      note: raw['note'] as String?,
    );
  }

  /// What Vivordo AI is told for "Plan next week".
  String chatContext(String Function(ReviewLine) name) => [
    'Weekly review for $range: $headline. $why',
    for (final r in rows) '${r.label}: ${r.value}.',
    if (drained.isNotEmpty)
      'What drained them: ${drained.map((l) => '${name(l)} (${l.detail})').join('; ')}.',
    if (helped.isNotEmpty)
      'What helped: ${helped.map((l) => '${name(l)} (${l.detail})').join('; ')}.',
    if (nextWeek.isNotEmpty)
      'Next week: ${nextWeek.map((d) => '${d.day} ${d.label}').join(', ')}.',
    if (suggestion != null) 'Suggested: $suggestion',
    if (context.isNotEmpty || (note?.isNotEmpty ?? false))
      'They said this week also had: ${[...context, ?note].join(', ')}.',
  ].join(' ');
}

/// A review needs Capacity on this many of the 7 days.
const minReviewDays = 4;

/// Heavy day: Effort more than this above that day's Capacity (as My Day's
/// brief, docs/scores.md §2).
const _heavyMargin = 15.0;

/// A low day: Capacity this far under the usual.
const _lowBy = 8.0;
const _partWeights = {'sleep': 45.0, 'body': 35.0, 'recovery': 20.0};

double? _num(Object? v) => v is num ? v.toDouble() : null;

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

String _hours(double hours) {
  final minutes = (hours * 60).round();
  return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
}

String _minutes(num minutes) {
  final m = minutes.round();
  if (m < 60) return '${m}m';
  return m % 60 == 0 ? '${m ~/ 60}h' : '${m ~/ 60}h ${m % 60}m';
}

String _weekday(DateTime d) => DateFormat('EEEE').format(d);

/// Days in order as words: "Monday", "Sunday and Saturday", or with three
/// or more, abbreviated with only consecutive runs of 3+ as a range:
/// "Sun–Tue and Sat". A range never spans a day that isn't in [on].
String weekdayList(List<DateTime> on) {
  final name = on.length <= 2 ? _weekday : DateFormat('EEE').format;
  bool next(DateTime a, DateTime b) =>
      DateTime(a.year, a.month, a.day + 1) == DateTime(b.year, b.month, b.day);
  final parts = <String>[];
  for (var i = 0; i < on.length;) {
    var j = i;
    while (j + 1 < on.length && next(on[j], on[j + 1])) {
      j++;
    }
    if (j - i >= 2) {
      parts.add('${name(on[i])}–${name(on[j])}');
    } else {
      parts.addAll([for (var k = i; k <= j; k++) name(on[k])]);
    }
    i = j + 1;
  }
  return parts.length == 1
      ? parts.single
      : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
}

/// The review for [input], or null with Capacity on fewer than 4 days.
WeeklyReview? buildWeeklyReview(WeeklyReviewInput input) {
  final start = DateTime(
    input.weekStart.year,
    input.weekStart.month,
    input.weekStart.day,
  );
  final dates = [
    for (var i = 0; i < 7; i++)
      DateTime(start.year, start.month, start.day + i),
  ];
  Map<String, dynamic>? capacityOf(DateTime d) =>
      input.scores[localDayKey(d)]?['capacity'] as Map<String, dynamic>?;
  Map<String, dynamic>? effortOf(DateTime d) =>
      input.scores[localDayKey(d)]?['effort'] as Map<String, dynamic>?;

  final capacityDays = dates.where(
    (d) => _num(capacityOf(d)?['score']) != null,
  );
  if (capacityDays.length < minReviewDays) return null;

  // Usual Capacity: the 28 days before, same formula version as this week.
  final version = capacityOf(capacityDays.last)?['version'];
  final before = [
    for (var i = 1; i <= 28; i++)
      if (input.scores[localDayKey(
            start.subtract(Duration(days: i)),
          )]?['capacity']
          case final Map c
          when c['version'] == version && _num(c['score']) != null)
        c,
  ];
  final weekCapacity = [
    for (final d in capacityDays) _num(capacityOf(d)!['score'])!,
  ];
  final usual = before.length >= 7
      ? _median([for (final c in before) _num(c['score'])!])
      : _median(weekCapacity);
  double? usualPart(String part) {
    final values = [for (final c in before) ?_num((c['parts'] as Map?)?[part])];
    return values.length >= 7 ? _median(values) : null;
  }

  final sickNights = {
    for (final d in dates)
      if (input.nightTags[localDayKey(d.subtract(const Duration(days: 1)))]
              ?.contains('sick') ??
          false)
        localDayKey(d),
  };
  final travelNights = dates
      .where(
        (d) =>
            input.nightTags[localDayKey(d.subtract(const Duration(days: 1)))]
                ?.contains('travel') ??
            false,
      )
      .length;

  final days = [
    for (final d in dates)
      () {
        final effort = _num(effortOf(d)?['total']);
        final capacity = _num(capacityOf(d)?['score']);
        return ReviewDay(
          localDayKey(d),
          effort,
          capacity,
          effort != null &&
              capacity != null &&
              effort > capacity + _heavyMargin,
          sickNights.contains(localDayKey(d)),
        );
      }(),
  ];
  final heavy = days.where((d) => d.heavy).toList();
  final capAvg = weekCapacity.reduce((a, b) => a + b) / weekCapacity.length;

  // Off days: the body was clearly off all day, so events that day aren't
  // judged against themselves.
  final offDays = dates.where((d) => bodyOffDay(capacityOf(d))).toList();

  // Low days and what caused them: the part whose drop against its usual,
  // weighted as in Capacity, was largest.
  final bodyLowDays = <DateTime>[];
  for (final d in dates) {
    final c = capacityOf(d);
    final score = _num(c?['score']);
    if (c == null || score == null || score > usual - _lowBy) continue;
    final parts = c['parts'] as Map?;
    String? top;
    var topDrop = 0.0;
    for (final MapEntry(key: part, value: weight) in _partWeights.entries) {
      final value = _num(parts?[part]);
      final base = usualPart(part);
      if (value == null || base == null) continue;
      final drop = (base - value) * weight;
      if (drop > topDrop) {
        topDrop = drop;
        top = part;
      }
    }
    if (top == 'body') bodyLowDays.add(d);
  }

  String bodyReason(List<DateTime> on) {
    final rises = [
      for (final d in on)
        if (_num(capacityOf(d)?['restingHr']) case final r?)
          if (_num(capacityOf(d)?['restingHrNormal']) case final n?) r - n,
    ];
    if (rises.isNotEmpty && _median(rises) >= 3) {
      return 'your resting heart rate was up about ${_median(rises).round()} bpm';
    }
    return 'your HRV was lower than usual';
  }

  String dayList(List<DateTime> on) => weekdayList(on);

  // --- What drained you, strongest first.
  final drained = <ReviewLine>[];
  if (sickNights.isNotEmpty) {
    drained.add(
      ReviewLine(
        'sick',
        'Being unwell',
        bodyLowDays.isNotEmpty
            ? '${_cap(bodyReason(bodyLowDays))} ${dayList(bodyLowDays)}, which '
                  'pulled Capacity down more than your sleep did.'
            : 'You tagged sick on ${sickNights.length} '
                  '${sickNights.length == 1 ? 'night' : 'nights'}.',
      ),
    );
  } else if (bodyLowDays.length >= 2) {
    drained.add(
      ReviewLine(
        'body',
        'Your body was under strain',
        '${_cap(bodyReason(bodyLowDays))} ${dayList(bodyLowDays)}, which '
            'pulled Capacity down more than your sleep did.',
      ),
    );
  }
  if (travelNights >= 1) {
    drained.add(
      ReviewLine(
        'travel',
        'Travel',
        'You tagged travel on $travelNights '
            '${travelNights == 1 ? 'night' : 'nights'}.',
      ),
    );
  }
  if (heavy.isNotEmpty) {
    final worst = heavy.reduce(
      (a, b) => (a.effort! - a.capacity!) >= (b.effort! - b.capacity!) ? a : b,
    );
    final date = DateTime.parse(worst.day);
    final b2b = _num(effortOf(date)?['backToBack'])?.round() ?? 0;
    drained.add(
      ReviewLine(
        'heavyDay',
        b2b >= 3 ? '${_weekday(date)}: $b2b back-to-backs' : _weekday(date),
        'Your heaviest day: Effort well above your Capacity.',
      ),
    );
  }
  final bigDays = {
    for (final d in dates)
      if ((capacityOf(d)?['bigDay'] as Map?)?['day'] case final String day)
        if (dates.any((x) => localDayKey(x) == day)) day,
  };
  if (bigDays.isNotEmpty) {
    final first = DateTime.parse(bigDays.first);
    drained.add(
      ReviewLine(
        'bigDay',
        bigDays.length == 1
            ? 'A big day on ${_weekday(first)}'
            : '${bigDays.length} big days',
        'Much more activity than your usual, which lowered the next mornings.',
      ),
    );
  }
  // Meetings that raised the heart rate, not counting off days.
  final offKeys = {for (final d in offDays) localDayKey(d)};
  final raised = <String, int>{};
  for (final r in input.reactions) {
    if (r.series == null || offKeys.contains(localDayKey(r.day))) continue;
    if (r.liftBpm >= 7) raised[r.series!] = (raised[r.series!] ?? 0) + 1;
  }
  if (raised.isNotEmpty) {
    final top = raised.entries.reduce((a, b) => a.value >= b.value ? a : b);
    drained.add(
      ReviewLine(
        'meeting',
        '',
        top.value == 1
            ? 'Your heart rate ran higher than usual during it.'
            : 'Your heart rate ran higher than usual, ${top.value} times '
                  'this week.',
        seriesKey: top.key,
      ),
    );
  }
  final lateLow = [
    for (final d in dates)
      if ((_num(capacityOf(d)?['bedtimeOffsetMin']) ?? 0) >= 45 &&
          (_num(capacityOf(d)?['score']) ?? usual) <= usual - 5)
        d,
  ];
  if (lateLow.length >= 2) {
    drained.add(
      ReviewLine(
        'lateNight',
        'Late nights',
        'After ${lateLow.length} late nights, those mornings started lower.',
      ),
    );
  }
  final afterHours = dates.fold<double>(
    0,
    (sum, d) => sum + (_num(effortOf(d)?['afterHoursMinutes']) ?? 0),
  );
  // The usual week: the median of earlier weeks with Effort on 5+ days, so
  // weeks before Effort existed don't count as zero after-hours. Needs 2.
  final priorWeeks = [
    for (var w = 1; w <= 4; w++)
      if ([
            for (var i = 0; i < 7; i++)
              _num(
                (input.scores[localDayKey(
                      start.subtract(Duration(days: 7 * w - i)),
                    )]?['effort']
                    as Map?)?['afterHoursMinutes'],
              ),
          ].whereType<double>().toList()
          case final week when week.length >= 5)
        week.fold<double>(0, (a, b) => a + b),
  ];
  final usualAfter = priorWeeks.length < 2 ? null : _median(priorWeeks);
  if (usualAfter != null &&
      afterHours >= usualAfter * 1.5 &&
      afterHours - usualAfter >= 60) {
    drained.add(
      ReviewLine(
        'afterHours',
        'After-hours work',
        '${_minutes(afterHours)} after hours, ${_minutes(afterHours - usualAfter)} '
            'more than usual.',
      ),
    );
  }
  final training = [
    for (final d in dates.reversed)
      if ((input.scores[localDayKey(d)]?['trainingLoad'] as Map?)?['state']
          case final String s)
        s,
  ].firstOrNull;
  if (training == 'high' || training == 'strained') {
    drained.add(
      ReviewLine(
        'training',
        'A big training week',
        training == 'strained'
            ? 'A lot more than your usual week, and your body agreed.'
            : 'A lot more than your usual week.',
      ),
    );
  }
  final today = start.add(const Duration(days: 7));
  final slipping = [
    for (final p in input.openPriorities)
      if (today.difference(p.since).inDays >= 3) p,
  ]..sort((a, b) => a.since.compareTo(b.since));
  if (slipping.isNotEmpty) {
    final p = slipping.first;
    final since = today.difference(p.since).inDays < 7
        ? _weekday(p.since)
        : DateFormat('MMM d').format(p.since);
    drained.add(
      ReviewLine(
        'priority',
        '"${p.title}" has been open since $since',
        'Worth giving it a time slot next week.',
      ),
    );
  }

  // --- What helped.
  final helped = <ReviewLine>[];
  final onTarget = <double>[], short = <double>[];
  var nightsOnTarget = 0, sleepNights = 0;
  final sleepHours = <double>[];
  for (final d in dates) {
    final c = capacityOf(d);
    final hours = _num(c?['sleepHours']);
    final need = _num(c?['sleepNeed']);
    final score = _num(c?['score']);
    if (hours == null) continue;
    sleepHours.add(hours);
    sleepNights++;
    if (need == null) continue;
    final ok = hours >= need - .25;
    if (ok) nightsOnTarget++;
    if (score != null) (ok ? onTarget : short).add(score);
  }
  if (onTarget.length >= 2 && short.length >= 2) {
    final gain =
        (onTarget.reduce((a, b) => a + b) / onTarget.length -
                short.reduce((a, b) => a + b) / short.length)
            .round();
    if (gain >= 5) {
      helped.add(
        ReviewLine(
          'sleep',
          'Sleeping your need',
          'On the ${onTarget.length} nights you did, the next morning started '
              'about $gain points higher.',
        ),
      );
    }
  }
  var fixesUsed = 0;
  for (final d in dates) {
    final kinds = input.dayFixes[localDayKey(d)]?['kinds'];
    if (kinds is! Map) continue;
    for (final k in kinds.values) {
      if (k is! Map) continue;
      fixesUsed += math.max(
        0,
        (_num(k['used']) ?? 0).round() - (_num(k['undone']) ?? 0).round(),
      );
    }
  }
  if (fixesUsed >= 2) {
    helped.add(
      ReviewLine(
        'fixes',
        'Lightening your days',
        'You used $fixesUsed of the changes Vivordo suggested.',
      ),
    );
  }
  final calm = [
    for (final r in input.reactions)
      if (r.liftBpm <= -3 && !offKeys.contains(localDayKey(r.day))) r,
  ];
  if (calm.length >= 2) {
    final focus = calm.where((r) => r.category == 'focused-work').length;
    helped.add(
      ReviewLine(
        'calm',
        focus * 2 >= calm.length ? 'Focus blocks' : 'Calmer meetings',
        focus * 2 >= calm.length
            ? 'They kept your heart rate lower than your meetings did.'
            : '${calm.length} events kept your heart rate under your usual.',
      ),
    );
  }
  if (training == 'steady' && input.workouts >= 2) {
    helped.add(
      ReviewLine(
        'training',
        'A steady training week',
        '${input.workouts} workouts, about your usual load.',
      ),
    );
  }

  // --- Headline.
  final firstHalf = weekCapacity.take(3).toList();
  final lastHalf = weekCapacity.skip(weekCapacity.length - 3).toList();
  double avg(List<double> v) => v.reduce((a, b) => a + b) / v.length;
  final woreOn = avg(lastHalf) <= avg(firstHalf) - 5 || capAvg <= usual - 5;
  final burnout = [
    for (final d in dates.reversed)
      if ((input.scores[localDayKey(d)]?['burnout'] as Map?)?['level']
          case final String level when level == 'watch' || level == 'warning')
        level,
  ].firstOrNull;
  final lowDays = days
      .where((d) => d.capacity != null && d.capacity! <= usual - _lowBy)
      .length;
  final String headline, why;
  if (sickNights.isNotEmpty && lowDays >= 2) {
    headline = 'A tough week while you were unwell';
    why =
        'You tagged sick on ${sickNights.length} '
        '${sickNights.length == 1 ? 'night' : 'nights'}'
        '${heavy.isEmpty ? '' : ', with ${heavy.length} heavy ${heavy.length == 1 ? 'day' : 'days'} around it'}'
        ', and Capacity was lower for most of the week.';
  } else if (training == 'high' || training == 'strained' || burnout != null) {
    headline = 'A week that asked a lot';
    why = burnout != null
        ? 'The burnout check is ${burnout == 'warning' ? 'warning you' : 'worth watching'}, '
              'and Capacity averaged ${_vsUsual(capAvg, usual)}.'
        : 'You trained a lot more than usual, and Capacity averaged '
              '${_vsUsual(capAvg, usual)}.';
  } else if (heavy.length >= 3) {
    headline = woreOn
        ? 'A heavy week that wore on you'
        : 'A heavy week you handled well';
    why = woreOn
        ? 'Effort was above your Capacity on ${heavy.length} days, and your '
              'mornings started lower as the week went on.'
        : 'Effort was above your Capacity on ${heavy.length} days, but your '
              'mornings bounced back each time.';
  } else if (nightsOnTarget >= 5) {
    headline = 'A good week for sleep';
    why = 'You slept your need on $nightsOnTarget of 7 nights.';
  } else if (heavy.isEmpty && (capAvg - usual).abs() < 5) {
    headline = 'A lighter, steadier week';
    why = 'No days above your Capacity, and Capacity stayed near your usual.';
  } else {
    headline = 'A mixed week';
    why =
        '${heavy.isEmpty ? 'No heavy days' : '${heavy.length} heavy ${heavy.length == 1 ? 'day' : 'days'}'}'
        ', and Capacity averaged ${_vsUsual(capAvg, usual)}.';
  }

  // --- The week at a glance.
  final done = dates.fold<int>(
    0,
    (sum, d) => sum + (_num(effortOf(d)?['prioritiesDone'])?.round() ?? 0),
  );
  final lastEffort = dates.reversed
      .map(effortOf)
      .firstWhere((e) => e != null, orElse: () => null);
  final left = _num(lastEffort?['unfinishedPriorities'])?.round() ?? 0;
  final moods = [
    for (final d in dates)
      if (_num(capacityOf(d)?['checkInFeel']) case final f?) _moodLabel(f),
  ];
  final rows = <({String label, String value})>[
    if (sleepHours.isNotEmpty)
      (
        label: 'Sleep',
        value:
            '${_hours(sleepHours.reduce((a, b) => a + b) / sleepHours.length)} a night'
            '${sleepNights > 0 && onTarget.length + short.length > 0 ? ' · $nightsOnTarget of $sleepNights on target' : ''}',
      ),
    (label: 'Capacity', value: _cap(_vsUsual(capAvg, usual))),
    if (done + left > 0)
      (label: 'Priorities', value: '$done of ${done + left} done'),
    if (input.workouts > 0 || training != null)
      (
        label: 'Workouts',
        value:
            '${input.workouts}'
            '${training == null ? '' : ' · training load ${_trainingWord(training)}'}',
      ),
    if (moods.isNotEmpty) (label: 'Mood', value: 'Mostly ${_mode(moods)}'),
  ];
  final chips = [
    if (heavy.isNotEmpty)
      '${heavy.length} heavy ${heavy.length == 1 ? 'day' : 'days'}'
    else
      'no heavy days',
    if (done + left > 0) '$done of ${done + left} done',
    if (nightsOnTarget >= 5) 'sleep on target',
    if (sickNights.isNotEmpty) 'unwell',
  ].take(3).toList();

  // --- Next week.
  String label(double demand) => demand <= usual - _heavyMargin
      ? 'Light'
      : demand > usual + _heavyMargin
      ? 'More than your usual'
      : 'About usual';
  final next = [
    for (final d in input.nextWeek)
      (day: _weekday(d.day), label: label(d.demand)),
  ];
  final nextHeavy = next.where((d) => d.label == 'More than your usual').length;
  final nextHeadline = next.isEmpty
      ? null
      : nextHeavy > heavy.length
      ? 'Busier than this one'
      : nextHeavy < heavy.length
      ? 'Lighter than this one'
      : 'About as busy as this one';
  final lightest = input.nextWeek.isEmpty
      ? null
      : input.nextWeek.reduce((a, b) => a.demand <= b.demand ? a : b);
  final heaviest = input.nextWeek.isEmpty
      ? null
      : input.nextWeek.reduce((a, b) => a.demand >= b.demand ? a : b);
  String? suggestion;
  final twoInARow = [
    for (var i = 1; i < next.length; i++)
      if (next[i].label == 'More than your usual' &&
          next[i - 1].label == 'More than your usual')
        i - 1,
  ];
  if (slipping.isNotEmpty && lightest != null) {
    suggestion =
        'Give "${slipping.first.title}" a slot on ${_weekday(lightest.day)}, '
        'your lightest day.';
  } else if (twoInARow.isNotEmpty && lightest != null) {
    suggestion =
        'Move one priority from ${next[twoInARow.first].day} to '
        '${_weekday(lightest.day)}.';
  } else if (lateLow.length >= 2 && heaviest != null && nextHeavy > 0) {
    suggestion =
        'Protect the evening before ${_weekday(heaviest.day)}: late nights '
        'cost you most this week.';
  } else if (heaviest != null && nextHeavy > 0) {
    suggestion = 'Keep the evening before ${_weekday(heaviest.day)} light.';
  }

  return WeeklyReview(
    weekStart: localDayKey(start),
    headline: headline,
    why: why,
    chips: chips,
    days: days,
    usualCapacity: usual,
    rows: rows,
    drained: drained.take(3).toList(),
    helped: helped.take(3).toList(),
    offDayNote:
        offDays.isEmpty ||
            !input.reactions.any((r) => offKeys.contains(localDayKey(r.day)))
        ? null
        : 'Your heart rate was up all day ${dayList(offDays)}, so meetings '
              'then aren\'t counted against them.',
    burnout: burnout,
    nextWeek: next,
    nextHeadline: nextHeadline,
    suggestion: suggestion,
    lastWeekNote: input.lastWeekNote,
  );
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _vsUsual(double value, double usual) {
  final diff = (value - usual).round();
  if (diff.abs() < 3) return 'about your usual';
  return '${diff.abs()} ${diff < 0 ? 'lower' : 'higher'} than usual';
}

String _trainingWord(String state) => switch (state) {
  'high' => 'high',
  'strained' => 'strained',
  'building' => 'building',
  'lighter' => 'lighter',
  _ => 'steady',
};

String _moodLabel(double feel) => feel >= 80
    ? 'Great'
    : feel >= 60
    ? 'Good'
    : feel >= 40
    ? 'Okay'
    : feel >= 20
    ? 'Down'
    : 'Awful';

String _mode(List<String> values) {
  final counts = <String, int>{};
  for (final v in values) {
    counts[v] = (counts[v] ?? 0) + 1;
  }
  return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}

/// The Sunday a review for [today] covers: the Sunday before today's.
DateTime reviewWeekStart(DateTime today) {
  final day = DateTime(today.year, today.month, today.day);
  final thisSunday = day.subtract(Duration(days: day.weekday % 7));
  return thisSunday.subtract(const Duration(days: 7));
}
