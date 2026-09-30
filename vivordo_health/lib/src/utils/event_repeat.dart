import 'package:intl/intl.dart';

enum RepeatUnit { day, week, month, year }

const _freq = {
  RepeatUnit.day: 'DAILY',
  RepeatUnit.week: 'WEEKLY',
  RepeatUnit.month: 'MONTHLY',
  RepeatUnit.year: 'YEARLY',
};
const _dayCodes = {
  DateTime.monday: 'MO',
  DateTime.tuesday: 'TU',
  DateTime.wednesday: 'WE',
  DateTime.thursday: 'TH',
  DateTime.friday: 'FR',
  DateTime.saturday: 'SA',
  DateTime.sunday: 'SU',
};
const _dayNames = {
  DateTime.monday: 'Mon',
  DateTime.tuesday: 'Tue',
  DateTime.wednesday: 'Wed',
  DateTime.thursday: 'Thu',
  DateTime.friday: 'Fri',
  DateTime.saturday: 'Sat',
  DateTime.sunday: 'Sun',
};

/// A calendar event's repeat rule as the event form edits it.
///
/// ponytail: COUNT, BYMONTHDAY and nth-weekday rules from other apps are not
/// modelled; they are kept on the event unless the user changes its repeat.
class EventRepeat {
  const EventRepeat({
    this.unit,
    this.interval = 1,
    this.weekdays = const {},
    this.until,
  });

  /// Null when the event does not repeat.
  final RepeatUnit? unit;
  final int interval;

  /// [DateTime.monday]..[DateTime.sunday]; weekly only. Empty repeats on the
  /// start date's weekday.
  final Set<int> weekdays;

  /// Last day an occurrence may fall on, inclusive.
  final DateTime? until;

  bool get repeats => unit != null;

  EventRepeat copyWith({
    RepeatUnit? unit,
    int? interval,
    Set<int>? weekdays,
    DateTime? until,
    bool clearUntil = false,
  }) => EventRepeat(
    unit: unit ?? this.unit,
    interval: interval ?? this.interval,
    weekdays: weekdays ?? this.weekdays,
    until: clearUntil ? null : until ?? this.until,
  );

  /// A Google Calendar recurrence line, or 'none'. All-day events need a
  /// date-only UNTIL; timed events need the end of that day in UTC.
  String recurrence({bool allDay = false}) {
    final unit = this.unit;
    if (unit == null) return 'none';
    final days = unit == RepeatUnit.week
        ? (weekdays.toList()..sort()).map((d) => _dayCodes[d]).join(',')
        : '';
    final until = this.until;
    final untilValue = until == null
        ? null
        : allDay
        ? DateFormat('yyyyMMdd').format(until)
        : '${DateFormat("yyyyMMdd'T'HHmmss").format(DateTime(until.year, until.month, until.day, 23, 59, 59).toUtc())}Z';
    return [
      'RRULE:FREQ=${_freq[unit]}',
      if (interval > 1) 'INTERVAL=$interval',
      if (days.isNotEmpty) 'BYDAY=$days',
      if (untilValue != null) 'UNTIL=$untilValue',
    ].join(';');
  }

  /// Reads an event's RRULE lines; anything without an RRULE does not repeat.
  static EventRepeat parse(Iterable<String>? lines) {
    final rule = lines
        ?.map((line) => line.trim().toUpperCase())
        .firstWhere((line) => line.startsWith('RRULE:'), orElse: () => '');
    if (rule == null || rule.isEmpty) return const EventRepeat();
    final parts = {
      for (final part in rule.substring('RRULE:'.length).split(';'))
        if (part.contains('='))
          part.substring(0, part.indexOf('=')): part.substring(
            part.indexOf('=') + 1,
          ),
    };
    final unit = _freq.entries
        .where((e) => e.value == parts['FREQ'])
        .firstOrNull
        ?.key;
    if (unit == null) return const EventRepeat();
    final codes = {for (final e in _dayCodes.entries) e.value: e.key};
    return EventRepeat(
      unit: unit,
      interval: int.tryParse(parts['INTERVAL'] ?? '') ?? 1,
      weekdays: unit == RepeatUnit.week
          ? (parts['BYDAY'] ?? '')
                .split(',')
                .map((c) => codes[c])
                .nonNulls
                .toSet()
          : const {},
      until: _parseUntil(parts['UNTIL']),
    );
  }

  static DateTime? _parseUntil(String? value) {
    if (value == null || value.length < 8) return null;
    final date = DateTime.tryParse(value.substring(0, 8));
    if (date == null) return null;
    if (!value.endsWith('Z') || value.length < 15) return date;
    final utc = DateTime.tryParse(value);
    if (utc == null) return date;
    final local = utc.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  /// e.g. "Every week", "Every 2 weeks on Mon, Wed, until Dec 31, 2026".
  String describe() {
    final unit = this.unit;
    if (unit == null) return 'Does not repeat';
    final name = unit.name;
    final base = interval == 1 ? 'Every $name' : 'Every $interval ${name}s';
    final days = unit == RepeatUnit.week && weekdays.isNotEmpty
        ? ' on ${(weekdays.toList()..sort()).map((d) => _dayNames[d]).join(', ')}'
        : '';
    final until = this.until;
    final end = until == null
        ? ''
        : ', until ${DateFormat('MMM d, y').format(until)}';
    return '$base$days$end';
  }
}
