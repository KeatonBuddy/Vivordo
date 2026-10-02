/// Days of history the first burnout check needs: 14 of normal, then the
/// 2-week gap and 2 recent weeks (functions/burnout.js).
const burnoutLearningDays = 42;

/// One area (Capacity, Effort or Mood) in the last 2 weeks vs its normal.
class BurnoutArea {
  const BurnoutArea(this.name, this.word, this.state, [this.worse = '']);

  final String name;

  /// "lower" or "heavier".
  final String worse;

  /// "Lower · 11 of 14 days", "Slightly heavier", "About usual"…
  final String word;

  /// "worse", "slightly" or "usual"; "none" without enough data yet.
  final String state;
}

/// What My Day shows for the nightly burnout check
/// (`scores_daily/{day}.burnout`, functions/burnout.js).
class BurnoutView {
  const BurnoutView({
    required this.level,
    required this.title,
    required this.body,
    required this.areas,
    required this.drivers,
    required this.suggestions,
    this.learningProgress,
  });

  /// "learning", "steady", "watch" or "warning".
  final String level;
  final String title, body;
  final List<BurnoutArea> areas;

  /// What's behind it, e.g. "Sleep 6h 10m a night (usual 7h 05m)".
  final List<String> drivers;
  final List<String> suggestions;

  /// 0–1 towards the first check while learning.
  final double? learningProgress;

  static BurnoutView? fromMap(Map<String, dynamic>? data, String evaluatedDay) {
    final level = data?['level'];
    if (data == null || level is! String) return null;
    final areas = (data['areas'] as Map?) ?? const {};
    BurnoutArea area(String name, String worse, String label) {
      final a = areas[name];
      if (a is! Map) return BurnoutArea(label, 'Not enough data yet', 'none');
      if (a['elevated'] == true) {
        return BurnoutArea(
          label,
          '$worse · ${a['worseDays']} of ${a['days']} days',
          'worse',
          '${worse.toLowerCase()} than usual on ${a['worseDays']} of the last '
              '${a['days']} days',
        );
      }
      if ((a['score'] as num? ?? 0) > 0) {
        return BurnoutArea(
          label,
          'Slightly ${worse.toLowerCase()}',
          'slightly',
        );
      }
      return BurnoutArea(label, 'About usual', 'usual');
    }

    final list = [
      area('capacity', 'Lower', 'Capacity'),
      area('effort', 'Heavier', 'Effort'),
      area('mood', 'Lower', 'Mood'),
    ];
    final strained = {
      for (final a in list)
        if (a.state == 'worse') a.name,
    };
    final drivers = [
      for (final d in (data['drivers'] as List? ?? const []).whereType<Map>())
        ?_driverText(d),
    ];
    final driverNames = {
      for (final d in (data['drivers'] as List? ?? const []).whereType<Map>())
        d['name'],
    };

    String title;
    String body;
    double? progress;
    switch (level) {
      case 'learning':
        final days = (data['learningDays'] as num? ?? 0).toInt();
        progress = (days / burnoutLearningDays).clamp(0, 1).toDouble();
        title = 'Learning your normal';
        body =
            'Vivordo needs about 6 weeks of Capacity, Effort and Mood to '
            'spot a slide. ${days.clamp(0, burnoutLearningDays)} of '
            '$burnoutLearningDays days so far.';
      case 'watch':
        title = switch (strained.firstOrNull) {
          'Effort' => 'Your days have been heavier than usual',
          'Mood' => 'Your mood has been lower than usual',
          _ => 'Your energy has been lower than usual',
        };
        final first = list.firstWhere(
          (a) => a.state == 'worse',
          orElse: () => list.first,
        );
        final steady = list
            .where((a) => a.state == 'usual')
            .map((a) => a.name)
            .toList();
        body =
            '${first.name} has been ${first.worse}'
            '${steady.isEmpty ? '' : ', while ${_join(steady)} held steady'}.';
      case 'warning':
        // How long the strain has run: the nights two areas have been off
        // (a warning starts after 7), or since the warning began if longer.
        final since = DateTime.tryParse(data['since'] as String? ?? '');
        final until = DateTime.tryParse(evaluatedDay);
        final strainedDays =
            ((data['state'] as Map?)?['strainedDays'] as num? ?? 0).toInt();
        final days = [
          strainedDays,
          if (since != null && until != null)
            until.difference(since).inDays + 1,
        ].reduce((a, b) => a > b ? a : b);
        title = days < 2
            ? 'Signs of a slide'
            : 'Signs of a slide for $days days';
        body =
            '${_join(strained.toList())} ${strained.length == 1 ? 'has' : 'have'} '
            'been off your normal'
            '${strainedDays >= 7 ? ', and it\'s held for over a week' : ' by a lot'}.';
      default:
        title = 'You\'re in your normal range';
        body = 'Your last 2 weeks look like your usual. Checked last night.';
    }

    return BurnoutView(
      level: level,
      title: title,
      body: body,
      areas: list,
      drivers: drivers,
      suggestions: level == 'warning' || level == 'watch'
          ? _suggestions(driverNames, strained)
          : const [],
      learningProgress: progress,
    );
  }
}

String _join(List<String> words) => words.length < 2
    ? words.join()
    : '${words.sublist(0, words.length - 1).join(', ')} and ${words.last}';

String _hoursMinutes(num minutes) {
  final m = minutes.round();
  return m >= 60
      ? '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m'
      : '${m}m';
}

String? _driverText(Map d) {
  final recent = d['recent'] as num?;
  final usual = d['usual'] as num?;
  if (recent == null || usual == null) return null;
  return switch (d['name']) {
    'sleepHours' =>
      'Sleep ${_hoursMinutes(recent * 60)} a night (usual ${_hoursMinutes(usual * 60)})',
    'restingHeartRate' =>
      'Resting heart rate ${recent.round()} bpm (usual ${usual.round()})',
    'hrv' => 'HRV ${recent.round()} ms (usual ${usual.round()})',
    'backToBack' =>
      '${recent.toStringAsFixed(1)} back-to-backs a day (usual ${usual.toStringAsFixed(1)})',
    'afterHoursMinutes' =>
      '${_hoursMinutes(recent)} after hours a day (usual ${_hoursMinutes(usual)})',
    _ => null,
  };
}

List<String> _suggestions(Set<Object?> drivers, Set<String> strained) {
  final picks = [
    if (drivers.contains('afterHoursMinutes'))
      'Protect one evening this week from after-hours work',
    if (drivers.contains('backToBack'))
      'Add 15-minute gaps between tomorrow\'s events',
    if (drivers.contains('sleepHours'))
      'Aim for your usual bedtime two nights in a row',
    if (drivers.contains('restingHeartRate') || drivers.contains('hrv'))
      'Keep tomorrow\'s workout easy',
    if (strained.contains('Mood'))
      'Make time for one thing you enjoy this week',
    if (strained.contains('Effort'))
      'Move one priority that can wait to next week',
    'Take a short walk between your busiest blocks',
  ];
  return picks.take(3).toList();
}
