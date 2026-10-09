import 'body_reaction.dart';

/// Which meetings tend to run your heart rate high or keep it calm, from the
/// per-event reactions My Day saves (users/{uid}/event_reactions/{day}, no
/// titles). A wellness estimate: heart rate during an event against your
/// usual at that time of day, not a measure of stress.

/// One saved event reaction.
class MeetingReaction {
  const MeetingReaction({
    required this.day,
    required this.key,
    required this.series,
    required this.category,
    required this.guests,
    required this.minutes,
    required this.startHour,
    required this.median,
    required this.usual,
  });

  final DateTime day;

  /// reactionKey of the event, and of its repeating series (Google only).
  final String key;
  final String? series;
  final String category;
  final int guests;
  final int minutes;
  final int startHour;
  final double median;
  final double usual;

  double get liftBpm => median - usual;

  static MeetingReaction? fromMap(String dayKey, String key, Object? raw) {
    if (raw is! Map || raw['v'] != 1) return null;
    final median = (raw['median'] as num?)?.toDouble();
    final usual = (raw['usual'] as num?)?.toDouble();
    final day = DateTime.tryParse(dayKey);
    if (median == null || usual == null || usual <= 0 || day == null) {
      return null;
    }
    return MeetingReaction(
      day: day,
      key: key,
      series: raw['series'] as String?,
      category: raw['category'] as String? ?? 'unknown',
      guests: (raw['guests'] as num?)?.toInt() ?? 0,
      minutes: (raw['minutes'] as num?)?.toInt() ?? 0,
      startHour: (raw['startHour'] as num?)?.toInt() ?? 12,
      median: median,
      usual: usual,
    );
  }

  /// Every reaction in event_reactions documents (day key -> data).
  static List<MeetingReaction> fromDays(
    Map<String, Map<String, dynamic>> days,
  ) => [
    for (final day in days.entries)
      for (final e in day.value.entries)
        ?MeetingReaction.fromMap(day.key, e.key, e.value),
  ];
}

enum PatternDirection { high, calm }

/// A group of events with a consistent reaction.
class MeetingPattern {
  const MeetingPattern({
    required this.id,
    required this.label,
    required this.isSeries,
    required this.direction,
    required this.count,
    required this.agreeing,
    required this.liftBpm,
    required this.liftPercent,
    required this.events,
  });

  /// The series' reactionKey, or a kind id like 'size:large'.
  final String id;

  /// For a kind: "Meetings with 6+ people". For a series: a description
  /// from its events ("A repeating meeting · Thu 2 PM · 8 people"), to be
  /// replaced by the calendar title when the phone can match it.
  final String label;
  final bool isSeries;
  final PatternDirection direction;
  final int count;

  /// Events that went the pattern's way.
  final int agreeing;

  /// Median change against your usual.
  final double liftBpm;
  final double liftPercent;

  /// Oldest first, for the per-meeting chart.
  final List<MeetingReaction> events;

  bool get high => direction == PatternDirection.high;

  /// "22% over your usual" / "About your usual" / "6% under your usual".
  String get liftLabel {
    final p = liftPercent.round();
    if (p.abs() < 3) return 'About your usual';
    return '${p.abs()}% ${p > 0 ? 'over' : 'under'} your usual';
  }

  /// "6 of 6 times" for a series, "14 events" for a kind.
  String get countLabel =>
      isSeries ? '$agreeing of $count times' : '$count events';
}

class MeetingPatterns {
  const MeetingPatterns({
    required this.measured,
    required this.high,
    required this.calm,
    required this.bySeries,
  });

  static const empty = MeetingPatterns(
    measured: 0,
    high: [],
    calm: [],
    bySeries: {},
  );

  /// Events with a saved reaction in the window.
  final int measured;

  /// Up to 3 each, strongest first.
  final List<MeetingPattern> high;
  final List<MeetingPattern> calm;

  /// Every repeating series with a pattern, for My Day's and Home's tags.
  final Map<String, MeetingPattern> bySeries;

  bool get learning => high.isEmpty && calm.isEmpty;

  /// Toward about 60 measured events, for the learning bar.
  double get progress => (measured / learningTarget).clamp(0, 1);

  static const learningTarget = 60;
}

const _minSeries = 4;
const _minKind = 8;
const _highBpm = 5.0;
const _calmBpm = -3.0;
const _agreeShare = .7;
const _shown = 3;

/// Kinds an event belongs to, with labels. Exercise isn't saved at all
/// (looksLikeExercise), breaks and unrated events aren't a kind.
List<(String, String)> _kindsOf(MeetingReaction r) => [
  if (_categoryLabels[r.category] case final label?)
    ('cat:${r.category}', label),
  if (r.guests == 2) ('size:one', '1:1s'),
  if (r.guests >= 3 && r.guests <= 5) ('size:small', 'Meetings of 3–5 people'),
  if (r.guests >= 6) ('size:large', 'Meetings with 6+ people'),
  if (r.startHour < 10) ('time:early', 'Anything before 10 AM'),
  if (r.startHour >= 16) ('time:late', 'Anything after 4 PM'),
  if (r.minutes >= 90) ('long', 'Meetings of 90+ minutes'),
];

const _categoryLabels = {
  'routine': 'Routine events',
  'social': 'Social plans',
  'collaboration': 'Working sessions',
  'focused-work': 'Focus blocks',
  'high-consequence': 'High-stakes meetings',
};

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// A pattern for [events] when they're enough and consistent; else null.
/// High: median +5 bpm or more and 70% above your usual. Calm: median −3 or
/// less and 70% below.
MeetingPattern? _patternFor(
  String id,
  String label,
  bool isSeries,
  List<MeetingReaction> events,
) {
  if (events.length < (isSeries ? _minSeries : _minKind)) return null;
  final lift = _median([for (final e in events) e.liftBpm]);
  final percent = _median([for (final e in events) e.liftBpm / e.usual * 100]);
  final up = events.where((e) => e.liftBpm > 0).length;
  final down = events.where((e) => e.liftBpm < 0).length;
  final direction = lift >= _highBpm && up >= events.length * _agreeShare
      ? PatternDirection.high
      : lift <= _calmBpm && down >= events.length * _agreeShare
      ? PatternDirection.calm
      : null;
  if (direction == null) return null;
  return MeetingPattern(
    id: id,
    label: label,
    isSeries: isSeries,
    direction: direction,
    count: events.length,
    agreeing: direction == PatternDirection.high ? up : down,
    liftBpm: lift,
    liftPercent: percent,
    events: [...events]..sort((a, b) => a.day.compareTo(b.day)),
  );
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "A repeating meeting · Thu 2 PM · 8 people", from a series' latest
/// event.
String seriesDescription(List<MeetingReaction> events) {
  final last = events.reduce((a, b) => a.day.isAfter(b.day) ? a : b);
  final hour = last.startHour % 12 == 0 ? 12 : last.startHour % 12;
  final when =
      '${_weekdays[last.day.weekday - 1]} $hour ${last.startHour < 12 ? 'AM' : 'PM'}';
  return [
    'A repeating meeting',
    when,
    if (last.guests >= 2) '${last.guests} people',
  ].join(' · ');
}

/// Patterns from saved reactions: repeating series (4+ times) and kinds of
/// event (8+), consistent in direction. The top 3 each way, strongest
/// first; a kind is skipped when a shown series makes up most of it.
MeetingPatterns meetingPatternsFrom(List<MeetingReaction> reactions) {
  final series = <String, List<MeetingReaction>>{};
  final kinds = <String, (String, List<MeetingReaction>)>{};
  for (final r in reactions) {
    if (r.series case final s?) (series[s] ??= []).add(r);
    for (final (id, label) in _kindsOf(r)) {
      (kinds[id] ??= (label, [])).$2.add(r);
    }
  }
  final bySeries = <String, MeetingPattern>{
    for (final e in series.entries)
      e.key: ?_patternFor(e.key, seriesDescription(e.value), true, e.value),
  };
  final all = [
    ...bySeries.values,
    for (final e in kinds.entries)
      ?_patternFor(e.key, e.value.$1, false, e.value.$2),
  ];
  List<MeetingPattern> pick(PatternDirection direction) {
    final ranked = all.where((p) => p.direction == direction).toList()
      ..sort((a, b) => b.liftBpm.abs().compareTo(a.liftBpm.abs()));
    final shown = <MeetingPattern>[];
    for (final p in ranked) {
      if (shown.length == _shown) break;
      // A kind adds nothing when most of its events are already shown
      // ("Meetings with 6+ people" that are mostly Sprint planning, or
      // "Before 10 AM" that's the same focus blocks).
      if (!p.isSeries) {
        final keys = {for (final e in p.events) e.key};
        final shownKeys = {
          for (final s in shown)
            for (final e in s.events) e.key,
        };
        if (keys.where(shownKeys.contains).length * 2 > keys.length) continue;
      }
      shown.add(p);
    }
    return shown;
  }

  return MeetingPatterns(
    measured: reactions.length,
    high: pick(PatternDirection.high),
    calm: pick(PatternDirection.calm),
    bySeries: bySeries,
  );
}

/// The series key My Day saves for a Google event's repeating series.
String? seriesKeyFor(String? recurringEventId) =>
    recurringEventId == null ? null : reactionKey('google:$recurringEventId');
