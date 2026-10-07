import 'package:cloud_firestore/cloud_firestore.dart';

import 'home_stress_card_logic.dart';

/// What the stress detail screen shows, from `metrics_daily/{day}.stress`
/// (written by StressScoreService) plus the day's mood, sleep and steps.

enum StressSignalKind {
  feel,
  sleep,
  hrv,
  heartRate,
  breathing,
  sitting,
  timeOfDay,
  activity,
  mindfulness,
  calendar,
  bloodOxygen,
  other,
}

class StressReading {
  const StressReading(this.score, this.at);

  final double score;
  final DateTime at;
}

/// One signal of the latest reading. [contribution] is in points: positive
/// raises stress, negative lowers it.
class StressSignal {
  const StressSignal({
    required this.label,
    required this.kind,
    required this.measured,
    required this.contribution,
  });

  final String label;
  final StressSignalKind kind;
  final bool measured;
  final double contribution;

  static StressSignal? fromName(
    String name,
    double contribution,
    bool measured,
  ) {
    final kind = _kind(name);
    if (kind == null) return null;
    return StressSignal(
      label: _labels[kind]!,
      kind: kind,
      measured: measured,
      contribution: contribution,
    );
  }
}

class StressDay {
  const StressDay({
    required this.date,
    this.current,
    this.average,
    this.minimum,
    this.maximum,
    this.anchor,
    this.confidence,
    this.coverage,
    this.computedAt,
    this.readings = const [],
    this.signals = const [],
    this.legacyDrivers = const [],
    this.moodLabel,
    this.moodAt,
    this.sleepHours,
    this.steps,
  });

  final DateTime date;
  final double? current, average, minimum, maximum;

  /// The person's own starting point for the day: their usual.
  final double? anchor;
  final String? confidence;
  final double? coverage;
  final DateTime? computedAt;
  final List<StressReading> readings;

  /// Every signal of the latest reading (newer records only).
  final List<StressSignal> signals;

  /// The top drivers older records carry instead of [signals].
  final List<StressSignal> legacyDrivers;
  final String? moodLabel;
  final DateTime? moodAt;
  final double? sleepHours;
  final int? steps;

  double? get score => current ?? average;
  double get usual => anchor ?? 50;
  bool get lowConfidence => confidence == 'low';
  int get measuredSignals => signals.where((s) => s.measured).length;

  /// What moved the latest reading, biggest first.
  List<StressSignal> get drivers {
    final source = signals.isNotEmpty ? signals : legacyDrivers;
    return [
      for (final s in source)
        if (s.measured && s.contribution.abs() >= 0.5) s,
    ]..sort((a, b) => b.contribution.abs().compareTo(a.contribution.abs()));
  }

  static StressDay fromDoc(DateTime date, Map<String, dynamic> data) {
    final stress = data['stress'] as Map?;
    final readings = <StressReading>[
      for (final raw in (stress?['entries'] as List?) ?? const [])
        if (raw is Map && raw['score'] is num)
          StressReading(
            (raw['score'] as num).toDouble(),
            _date(raw['timestamp']) ?? date,
          ),
    ]..sort((a, b) => a.at.compareTo(b.at));
    final mood = data['mood'] as Map?;
    return StressDay(
      date: date,
      current: _num(stress?['current']),
      average: _num(stress?['avg']),
      minimum: _num(stress?['min']),
      maximum: _num(stress?['max']),
      anchor: _num(stress?['anchor']),
      confidence: stress?['confidence']?.toString(),
      coverage: _num(stress?['coverage_pct']),
      computedAt: _date(stress?['computedAt']),
      readings: readings,
      signals: [
        for (final raw in (stress?['signals'] as List?) ?? const [])
          if (raw is Map && raw['name'] is String)
            ?StressSignal.fromName(
              raw['name'] as String,
              _num(raw['contribution']) ?? 0,
              raw['signal'] != null,
            ),
      ],
      legacyDrivers: [
        for (final raw in (stress?['top_drivers'] as List?) ?? const [])
          if (raw is Map && raw['name'] is String)
            ?StressSignal.fromName(
              raw['name'] as String,
              _num(raw['contribution']) ?? 0,
              true,
            ),
      ],
      moodLabel: mood?['label']?.toString(),
      moodAt: _date(mood?['checkInAt']),
      sleepHours: _num((data['sleep'] as Map?)?['avg']),
      steps: _num((data['steps'] as Map?)?['sum'])?.round(),
    );
  }
}

/// "4 above usual", "About usual" or "3 below usual".
String stressUsualHeadline(double score, double usual) {
  final difference = (score - usual).round();
  if (difference.abs() <= 1) return 'About usual';
  return '${difference.abs()} ${difference > 0 ? 'above' : 'below'} usual';
}

/// "Low", "Moderate", "Elevated" or "High" (Home's bands).
String stressBand(double score) => homeStressLevel(score)!;

/// The middle half of the person's daily averages over the 28 days before
/// [today]: their usual range. Null with fewer than 7 days.
(double, double)? stressUsualRange(List<StressDay> days, DateTime today) {
  final start = DateTime(today.year, today.month, today.day - 28);
  final end = DateTime(today.year, today.month, today.day);
  final values = [
    for (final d in days)
      if (!d.date.isBefore(start) && d.date.isBefore(end)) ?d.average,
  ]..sort();
  if (values.length < 7) return null;
  return (_quantile(values, .25), _quantile(values, .75));
}

/// The score [day] had at the same time of day as [now]: the last reading
/// at or before it. Null when there is none.
double? stressAtTimeOfDay(StressDay? day, DateTime now) {
  if (day == null) return null;
  final minutes = now.hour * 60 + now.minute;
  StressReading? last;
  for (final r in day.readings) {
    if (r.at.hour * 60 + r.at.minute <= minutes) last = r;
  }
  return last?.score;
}

StressReading? stressPeak(List<StressReading> readings) => readings.isEmpty
    ? null
    : readings.reduce((a, b) => b.score > a.score ? b : a);

/// One plain line for a driver, e.g. "6h 40m last night, less restful than
/// usual".
String stressDriverDetail(
  StressSignal s,
  StressDay day,
  String Function(DateTime) time,
) {
  final up = s.contribution > 0;
  switch (s.kind) {
    case StressSignalKind.sleep:
      final hours = day.sleepHours;
      final quality = up
          ? 'less restful than usual'
          : 'more restful than usual';
      return hours == null
          ? 'Last night was $quality'
          : '${_hm(hours)} last night, $quality';
    case StressSignalKind.feel:
      if (day.moodLabel case final label?) {
        return day.moodAt == null
            ? 'You checked in: $label'
            : 'You checked in: $label at ${time(day.moodAt!)}';
      }
      return up ? 'Your check-in raised it' : 'Your check-in lowered it';
    case StressSignalKind.hrv:
      return up
          ? 'Lower than usual for this time'
          : 'Higher than usual for this time';
    case StressSignalKind.heartRate:
    case StressSignalKind.breathing:
      return up
          ? 'Higher than usual for this time'
          : 'Lower than usual for this time';
    case StressSignalKind.sitting:
      return up ? 'A long stretch without moving' : 'You\'ve been moving';
    case StressSignalKind.timeOfDay:
      return up ? 'Early morning or late night' : 'Usual daytime hours';
    case StressSignalKind.activity:
      if (day.steps case final steps? when steps > 0) {
        return '${_thousands(steps)} steps today';
      }
      return up ? 'Not much movement lately' : 'Active recently';
    case StressSignalKind.mindfulness:
      return 'Mindful minutes recently';
    case StressSignalKind.calendar:
      return up ? 'A busy calendar' : 'A light calendar';
    case StressSignalKind.bloodOxygen:
      return up ? 'Lower than usual overnight' : 'Normal overnight';
    case StressSignalKind.other:
      return up ? 'Raising it' : 'Lowering it';
  }
}

enum StressNextAction { windDown, none }

class StressNextStep {
  const StressNextStep(
    this.title,
    this.body, [
    this.action = StressNextAction.none,
  ]);

  final String title, body;
  final StressNextAction action;
}

/// A suggestion tied to whatever is pushing stress up most.
StressNextStep stressNextStep(List<StressSignal> drivers) {
  final top = drivers.where((d) => d.contribution > 0).firstOrNull;
  return switch (top?.kind) {
    null => const StressNextStep(
      'Nothing is pushing it up right now',
      'Keep your routine steady to keep it that way.',
    ),
    StressSignalKind.sleep => const StressNextStep(
      'Sleep is today\'s biggest push',
      'An earlier night usually brings this back toward your usual.',
      StressNextAction.windDown,
    ),
    StressSignalKind.hrv ||
    StressSignalKind.heartRate ||
    StressSignalKind.breathing => const StressNextStep(
      'Your body is running hotter than usual',
      'A few minutes of slow breathing can help it settle.',
    ),
    StressSignalKind.sitting ||
    StressSignalKind.activity => const StressNextStep(
      'Moving would help most',
      'A short walk usually brings this down.',
    ),
    StressSignalKind.calendar => const StressNextStep(
      'Your calendar is today\'s biggest push',
      'A short break between events can help.',
    ),
    StressSignalKind.feel => const StressNextStep(
      'How you feel is today\'s biggest push',
      'Talking it through with Vivordo AI can help.',
    ),
    _ => const StressNextStep(
      'This is a usual pattern for now',
      'It tends to ease as the day settles.',
    ),
  };
}

class StressTrendStats {
  const StressTrendStats({
    required this.average,
    required this.calmest,
    required this.hardest,
    this.change,
  });

  final double average;
  final StressDay calmest, hardest;

  /// Against the period before; null without enough data.
  final double? change;
}

/// Stats for [period] (days with an average), compared with [previous].
StressTrendStats? stressTrendStats(
  List<StressDay> period,
  List<StressDay> previous,
) {
  final scored = [
    for (final d in period)
      if (d.average != null) d,
  ];
  if (scored.isEmpty) return null;
  double mean(List<StressDay> days) =>
      days.map((d) => d.average!).reduce((a, b) => a + b) / days.length;
  final before = [
    for (final d in previous)
      if (d.average != null) d,
  ];
  final average = mean(scored);
  return StressTrendStats(
    average: average,
    calmest: scored.reduce((a, b) => b.average! < a.average! ? b : a),
    hardest: scored.reduce((a, b) => b.average! > a.average! ? b : a),
    change: scored.length >= 3 && before.length >= 3
        ? average - mean(before)
        : null,
  );
}

const _labels = {
  StressSignalKind.feel: 'How you feel',
  StressSignalKind.sleep: 'Last night\'s sleep',
  StressSignalKind.hrv: 'HRV',
  StressSignalKind.heartRate: 'Heart rate',
  StressSignalKind.breathing: 'Breathing rate',
  StressSignalKind.sitting: 'Time sitting',
  StressSignalKind.timeOfDay: 'Time of day',
  StressSignalKind.activity: 'Activity',
  StressSignalKind.mindfulness: 'Mindfulness',
  StressSignalKind.calendar: 'Calendar',
  StressSignalKind.bloodOxygen: 'Blood oxygen',
  StressSignalKind.other: 'Other',
};

/// The BaaS component names (baas_scorer.py), hourly and daily.
StressSignalKind? _kind(String name) {
  final n = name.toLowerCase();
  if (n.contains('unavailable share')) return null;
  if (n.contains('perceived') || n.contains('mood')) {
    return StressSignalKind.feel;
  }
  if (n.contains('sleep')) return StressSignalKind.sleep;
  if (n.contains('hrv')) return StressSignalKind.hrv;
  if (n.startsWith('hr') || n.contains('nocturnal hr') || n.contains('heart')) {
    return StressSignalKind.heartRate;
  }
  if (n.contains('respiratory') || n.contains('rr')) {
    return StressSignalKind.breathing;
  }
  if (n.contains('sedentary')) return StressSignalKind.sitting;
  if (n.contains('circadian')) return StressSignalKind.timeOfDay;
  if (n.contains('activity') || n.contains('step')) {
    return StressSignalKind.activity;
  }
  if (n.contains('mindful')) return StressSignalKind.mindfulness;
  if (n.contains('calendar')) return StressSignalKind.calendar;
  if (n.contains('spo2') || n.contains('oxygen')) {
    return StressSignalKind.bloodOxygen;
  }
  return StressSignalKind.other;
}

double? _num(Object? v) => v is num ? v.toDouble() : null;

DateTime? _date(Object? raw) => switch (raw) {
  Timestamp t => t.toDate(),
  DateTime d => d,
  String s => DateTime.tryParse(s),
  _ => null,
};

double _quantile(List<double> sorted, double q) {
  final position = (sorted.length - 1) * q;
  final low = position.floor(), high = position.ceil();
  return sorted[low] + (sorted[high] - sorted[low]) * (position - low);
}

String _hm(double hours) {
  final minutes = (hours * 60).round();
  return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
}

String _thousands(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
