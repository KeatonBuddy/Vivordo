import 'dart:math' as math;

import 'package:intl/intl.dart';

import 'day_effort.dart';

/// One line of a score's breakdown (lib/widgets/score_breakdown_sheet.dart).
class BreakdownRow {
  const BreakdownRow(
    this.title,
    this.detail, {
    this.points,
    this.chip,
    this.leftOut = false,
    this.item,
  });

  final String title, detail;

  /// Capacity: how much this part moved today against your usual (signed).
  /// Demand and Effort: the points it adds. Null when there's no number.
  final double? points;

  /// The event's type, short ("Focused", "High stakes").
  final String? chip;

  /// Not counted (Free, declined, all-day), shown for why.
  final bool leftOut;

  /// The event or priority behind the row, so it can open its type.
  final EffortItem? item;
}

/// Capacity's weights (functions/capacity.js WEIGHTS).
const _capacityWeights = {
  'sleep': 45,
  'body': 35,
  'recovery': 20,
  'checkIn': 15,
};

/// Fewer earlier days than this and a part has no usual to compare with.
const _minUsualDays = 3;

/// Today's Capacity, part by part: how much each part moved the score
/// against your usual day. A part's usual is its median in [earlier]
/// (earlier records of the same formula), and its effect is (today −
/// usual) × its weight ÷ the weights of the parts counted today. With
/// [usualScore], parts your usual day has but today doesn't (sleep not
/// synced yet, no check-in) get one more line for the rest of the gap, so
/// the lines add up to today's score minus your usual.
List<BreakdownRow> capacityBreakdown(
  Map today,
  List<Map> earlier, {
  int? usualScore,
  DateTime? day,
}) {
  final parts = today['parts'] is Map ? today['parts'] as Map : const {};
  double? part(Map record, String name) {
    final value = (record['parts'] is Map
        ? record['parts'] as Map
        : const {})[name];
    return value is num ? value.toDouble() : null;
  }

  final present = [
    for (final name in _capacityWeights.keys)
      if (parts[name] is num) name,
  ];
  final weight = present.fold<int>(0, (s, n) => s + _capacityWeights[n]!);
  if (weight == 0) return const [];
  double? effect(String name) {
    final usuals = [for (final record in earlier) ?part(record, name)];
    if (usuals.length < _minUsualDays) return null;
    final usual = _median(usuals);
    return (part(today, name)! - usual) * _capacityWeights[name]! / weight;
  }

  final rows = [
    for (final name in present)
      BreakdownRow(
        switch (name) {
          'sleep' => 'Sleep',
          'body' => 'Overnight body',
          'recovery' => 'Recent load',
          _ => 'Morning check-in',
        },
        switch (name) {
          'sleep' => _sleepDetail(today),
          'body' => _bodyDetail(today),
          'recovery' => _recoveryDetail(today, effect(name), day),
          _ => _checkInDetail(today, effect(name)),
        },
        points: effect(name),
      ),
  ];
  final absent = [
    for (final name in _capacityWeights.keys)
      if (!present.contains(name) &&
          earlier.where((r) => part(r, name) != null).length >= _minUsualDays)
        name,
  ];
  final score = (today['score'] as num?)?.toDouble();
  if (usualScore != null && score != null && absent.isNotEmpty) {
    // Whole points, as shown, so the lines on screen add up exactly.
    final explained = rows.fold<int>(0, (s, r) => s + (r.points?.round() ?? 0));
    rows.add(
      BreakdownRow(
        'Not in today',
        '${_names(absent)}: part of your usual day',
        points: score - usualScore - explained,
      ),
    );
  }
  return rows;
}

String _names(List<String> parts) {
  final names = [
    for (final p in parts)
      switch (p) {
        'sleep' => 'sleep',
        'body' => 'overnight body',
        'recovery' => 'recent load',
        _ => 'check-in',
      },
  ];
  final text = names.length == 1
      ? names.single
      : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  return text[0].toUpperCase() + text.substring(1);
}

String _sleepDetail(Map c) {
  final hours = (c['sleepHours'] as num?)?.toDouble();
  if (hours == null) return 'From last night';
  final asleep = _hoursMinutes(hours);
  final need = (c['sleepNeed'] as num?)?.toDouble();
  final offset = [
    (c['bedtimeOffsetMin'] as num?)?.abs() ?? 0,
    (c['wakeOffsetMin'] as num?)?.abs() ?? 0,
  ].reduce(math.max);
  final clock = offset > 60
      ? ' · ${offset.round()} min off your usual times'
      : '';
  if (need == null || c['sleepNeedSettled'] != true) return '$asleep$clock';
  final gap = ((hours - need) * 60).round();
  final versus = gap.abs() <= 15
      ? 'about your need'
      : '${_hoursMinutes(gap.abs() / 60)} ${gap < 0 ? 'under' : 'over'} your need';
  return '$asleep · $versus$clock';
}

String _bodyDetail(Map c) {
  if (c['bodyMeasured'] != true) {
    return 'No overnight heart data, so counted as normal';
  }
  final bits = <String>[];
  final hrv = (c['hrv'] as num?)?.toDouble();
  final hrvNormal = (c['hrvNormal'] as num?)?.toDouble();
  if (hrv != null && hrvNormal != null && hrvNormal > 0) {
    final change = hrv / hrvNormal - 1;
    bits.add(
      change.abs() < .05
          ? 'HRV about your normal'
          : 'HRV ${change > 0 ? 'above' : 'below'} your normal',
    );
  }
  final resting = (c['restingHr'] as num?)?.toDouble();
  final restingNormal = (c['restingHrNormal'] as num?)?.toDouble();
  if (resting != null && c['restingHrIgnored'] == true) {
    bits.add('resting heart rate left out (an unusual reading)');
  } else if (resting != null && restingNormal != null) {
    final diff = (resting - restingNormal).round();
    bits.add(
      diff == 0
          ? 'resting heart rate at your normal'
          : 'resting heart rate ${diff.abs()} ${diff > 0 ? 'above' : 'below'} your normal',
    );
  }
  if (bits.isEmpty) return 'HRV and resting heart rate';
  final text = bits.join(' · ');
  return text[0].toUpperCase() + text.substring(1);
}

/// [effect] is how much it moved today against your usual: a heavy
/// yesterday can still help when your recent days were heavier, and the
/// detail says so rather than sit oddly beside a positive number.
String _recoveryDetail(Map c, double? effect, DateTime? day) {
  final lighter = effect != null && effect.round() > 0;
  final big = c['bigDay'];
  if (big is Map && big['ratio'] is num) {
    final ratio = (big['ratio'] as num).toStringAsFixed(1);
    // A big day counts for 3 days: name it unless it was yesterday.
    final on = DateTime.tryParse('${big['day']}');
    final when = on == null || day == null
        ? ''
        : DateTime(day.year, day.month, day.day).difference(on).inDays <= 1
        ? ' yesterday'
        : ' on ${DateFormat('EEEE').format(on)}';
    return 'A big day$when: $ratio× your usual activity'
        '${lighter
            ? ', but lighter than your recent days'
            : big['halved'] == true
            ? ', halved as your body had recovered'
            : ''}';
  }
  final recovery =
      (c['parts'] is Map ? (c['parts'] as Map)['recovery'] : null) as num?;
  if (recovery == null || recovery >= 100) {
    return 'Yesterday was no heavier than usual';
  }
  return lighter
      ? 'Heavier than usual, but lighter than your recent days'
      : 'Yesterday was heavier than your usual';
}

/// Both answers and how they compare with your usual check-in, so "felt
/// good" never sits unexplained beside a negative number. The part is the
/// average of "How do you feel?" (checkInFeel) and "How did you sleep?",
/// so the sleep answer is worked back from it when the two differ.
String _checkInDetail(Map c, double? effect) {
  final feel = (c['checkInFeel'] as num?)?.toDouble();
  final part =
      ((c['parts'] is Map ? c['parts'] as Map : const {})['checkIn'] as num?)
          ?.toDouble();
  final sleep = feel == null
      ? part
      : part != null && (part - feel).abs() > .5
      ? 2 * part - feel
      : null;
  final answers = [
    if (feel != null)
      'felt ${feel >= 75
          ? 'good'
          : feel >= 50
          ? 'okay'
          : 'low'}',
    if (sleep != null)
      'slept ${switch (sleep) {
        < 12.5 => 'awfully',
        < 37.5 => 'poorly',
        < 62.5 => 'okay',
        < 87.5 => 'well',
        _ => 'great',
      }}',
  ];
  final said = answers.isEmpty
      ? 'From your morning check-in'
      : answers
            .join(', ')
            .replaceFirstMapped(RegExp('^.'), (m) => m[0]!.toUpperCase());
  final rounded = effect?.round();
  return rounded == null
      ? said
      : '$said · ${rounded > 0
            ? 'better than'
            : rounded < 0
            ? 'lower than'
            : 'about'} your usual check-in';
}

/// The event types, short, for a breakdown chip.
String _chip(String category) => switch (category) {
  'high-consequence' => 'High stakes',
  'focused-work' => 'Focused',
  'collaboration' => 'Meeting or class',
  'social' => 'Social',
  'routine' => 'Routine',
  'rest' => 'Break',
  'priority' => 'Priority',
  _ => 'Not sure',
};

String _when(EffortItem item) {
  final minutes = item.event.end.difference(item.event.start).inMinutes;
  return '${DateFormat.jm().format(item.event.start)} · '
      '${_hoursMinutes(minutes / 60)}';
}

/// Demand still ahead, item by item, as [buildDayEffort] prices it: each
/// item's points on its own, untimed priorities together, and what
/// back-to-backs, long runs and overlaps add (or take off: overlapping
/// events count once). The rows add up to [total].
({List<BreakdownRow> rows, double total}) demandBreakdown({
  required DateTime now,
  required DateTime from,
  required DateTime until,
  required DateTime wrapUp,
  required List<EffortItem> items,
  required List<Object?> untimedOpen,
}) {
  DayEffort day(List<EffortItem> only, List<Object?> untimed) => buildDayEffort(
    now: now,
    from: from,
    until: until,
    wrapUp: wrapUp,
    items: only,
    untimedOpen: untimed,
  );
  final total = day(items, untimedOpen).demand;
  final rows = <BreakdownRow>[];
  var counted = 0.0;
  for (final item in items) {
    if (item.done ||
        !item.event.end.isAfter(now) ||
        !item.event.contributesToSchedule ||
        !item.event.end.isAfter(from) ||
        !item.event.start.isBefore(until)) {
      continue;
    }
    final points = day([item], const []).demand;
    counted += points;
    rows.add(
      BreakdownRow(
        item.event.title.isEmpty ? 'Untitled' : item.event.title,
        _when(item),
        points: points,
        chip: _chip(item.score.category),
        item: item,
      ),
    );
  }
  final untimed = day(const [], untimedOpen).demand;
  if (untimedOpen.isNotEmpty) {
    counted += untimed;
    rows.add(
      BreakdownRow(
        '${untimedOpen.length} ${untimedOpen.length == 1 ? 'priority' : 'priorities'}',
        'No time set',
        points: untimed,
      ),
    );
  }
  final extra = total - counted;
  if (extra.abs() >= .5) {
    rows.add(
      BreakdownRow(
        extra > 0 ? 'Back-to-backs and long runs' : 'Overlapping events',
        extra > 0
            ? 'Little or no break between events, and long stretches'
            : 'Counted once while they overlap',
        points: extra,
      ),
    );
  }
  return (rows: rows, total: total);
}

/// Effort so far: what each item took (each on its own), ticked-off
/// untimed priorities, what back-to-backs added, and activity
/// ([physical], already worked out by [physicalSoFar]). The rows add up to
/// [total].
({List<BreakdownRow> mental, double physical, double total}) effortBreakdown({
  required DateTime now,
  required DateTime from,
  required DateTime until,
  required DateTime wrapUp,
  required List<EffortItem> items,
  required List<({DateTime doneAt, Object? effort})> untimedDone,
  required double physical,
}) {
  DayEffort day(
    List<EffortItem> only,
    List<({DateTime doneAt, Object? effort})> done,
  ) => buildDayEffort(
    now: now,
    from: from,
    until: until,
    wrapUp: wrapUp,
    items: only,
    untimedDone: done,
  );
  final mentalTotal = day(items, untimedDone).soFar;
  final rows = <BreakdownRow>[];
  var counted = 0.0;
  for (final item in items) {
    final points = day([item], const []).soFar;
    if (points <= 0) continue;
    counted += points;
    rows.add(
      BreakdownRow(
        item.event.title.isEmpty ? 'Untitled' : item.event.title,
        item.done && item.score.category == 'priority'
            ? 'Priority · ticked off'
            : _when(item),
        points: points,
        chip: _chip(item.score.category),
        item: item,
      ),
    );
  }
  if (untimedDone.isNotEmpty) {
    final points = day(const [], untimedDone).soFar;
    counted += points;
    rows.add(
      BreakdownRow(
        '${untimedDone.length} ${untimedDone.length == 1 ? 'priority' : 'priorities'} ticked off',
        'No time set',
        points: points,
      ),
    );
  }
  final extra = mentalTotal - counted;
  if (extra.abs() >= .5) {
    rows.add(
      BreakdownRow(
        extra > 0 ? 'Back-to-backs and long runs' : 'Overlapping events',
        extra > 0
            ? 'Little or no break between events, and long stretches'
            : 'Counted once while they overlap',
        points: extra,
      ),
    );
  }
  return (mental: rows, physical: physical, total: mentalTotal + physical);
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

String _hoursMinutes(double hours) {
  final minutes = (hours * 60).round();
  final h = minutes ~/ 60, m = minutes % 60;
  return h == 0
      ? '$m min'
      : m == 0
      ? '$h h'
      : '$h h $m';
}
