part of 'detail_insights.dart';

/// Sleep detail's "Your patterns": what the last few weeks of nights show,
/// whichever of Day, Week or Month is selected. Each pattern compares the
/// person with their own nights and offers one thing to try. Never a total
/// of hours owed: how lost sleep adds up and pays back isn't precise enough
/// to count. Never a pattern from sleep stages, which wearables score
/// loosely, and never advice to spend longer in bed.

/// What a pattern's button does.
enum SleepPatternAction { preferences, tagSick }

/// Bars for a pattern, oldest first: hours (null for a missing night), one
/// label per bar ('' for none), the bars to colour, and a line to draw.
class SleepPatternChart {
  const SleepPatternChart(
    this.values, {
    required this.labels,
    this.highlight = const {},
    this.reference,
  });

  final List<double?> values;
  final List<String> labels;
  final Set<int> highlight;
  final double? reference;
}

class SleepPattern {
  const SleepPattern({
    required this.id,
    required this.tone,
    required this.title,
    required this.body,
    this.why,
    this.tryThis,
    this.action,
    this.actionLabel,
    this.chart,
    this.basis,
    this.progress,
  });

  final String id;
  final InsightTone tone;
  final String title;

  /// The card's line, and the sheet's "What Vivordo noticed".
  final String body;

  /// The sheet: why it matters and what to try. A pattern without [why]
  /// has no sheet.
  final String? why, tryThis;
  final SleepPatternAction? action;
  final String? actionLabel;
  final SleepPatternChart? chart;

  /// The sheet's footnote: what it's based on.
  final String? basis;

  /// Set only on the "not enough nights yet" card (0–1).
  final double? progress;
}

/// Nights of the last 14 before any pattern shows.
const sleepPatternMinNights = 10;

/// Night tags that are habits to change (sick and travel aren't).
const _leverTags = {
  'late_caffeine': (
    name: 'late caffeine',
    title: 'Late caffeine costs you sleep',
    tryThis: 'Try keeping caffeine before 2 PM for a week and see.',
  ),
  'alcohol': (
    name: 'alcohol',
    title: 'Alcohol costs you sleep',
    tryThis: 'Try an alcohol-free evening before nights that matter.',
  ),
  'late_meal': (
    name: 'a late meal',
    title: 'Late meals cost you sleep',
    tryThis: 'Try finishing dinner about 3 hours before bed.',
  ),
  'screens_in_bed': (
    name: 'screens in bed',
    title: 'Screens in bed cost you sleep',
    tryThis: 'Try leaving your phone outside the bedroom for a few nights.',
  ),
};

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Patterns, most important first: things worth a look, then what's behind
/// them, then good news. [nights] are keyed by the morning they end on (as
/// metrics_daily is), [need] is Capacity's sleep need (null while it's the
/// placeholder). [tags] are daily_tags by the evening they belong to,
/// [ratings] the "How did you sleep?" score (0–100) by morning, and
/// [firstEvents] the minutes after midnight of each day's first calendar
/// event. Fewer than [sleepPatternMinNights] of the last 14 nights: only a
/// card saying how many so far.
List<SleepPattern> sleepPatterns({
  required Map<DateTime, SleepNight> nights,
  required DateTime today,
  double? need,
  Map<DateTime, Set<String>> tags = const {},
  Map<DateTime, double> ratings = const {},
  Map<DateTime, int> firstEvents = const {},
}) {
  final day = insightDay(today);
  DateTime back(int i) => DateTime(day.year, day.month, day.day - i);
  // The evening a night starts on, for weekdays and tags.
  DateTime evening(DateTime morning) =>
      DateTime(morning.year, morning.month, morning.day - 1);
  bool freeNight(DateTime morning) =>
      evening(morning).weekday >= DateTime.friday &&
      evening(morning).weekday <= DateTime.saturday;
  // Phone-only nights are time in bed, which runs longer than sleep.
  double asleep(SleepNight n) => n.inBed ? n.hours - .5 : n.hours;

  final last14 = [for (var i = 0; i < 14; i++) nights[back(i)]];
  final tracked = last14.whereType<SleepNight>().toList();
  if (tracked.length < sleepPatternMinNights) {
    return [
      SleepPattern(
        id: 'building',
        tone: InsightTone.neutral,
        title: 'Patterns are on the way',
        body:
            'Vivordo needs $sleepPatternMinNights nights in the last 2 weeks '
            'to spot patterns. ${tracked.length} so far.',
        progress: tracked.length / sleepPatternMinNights,
      ),
    ];
  }

  final worth = <SleepPattern>[], behind = <SleepPattern>[];
  final good = <SleepPattern>[];
  final bedtimes = [
    for (final n in tracked)
      if (n.bedtime case final b?) _minutesFromNoon(b).toDouble(),
  ];
  final wakes = [
    for (final n in tracked)
      if (n.wakeTime case final w?) _minutesOfDay(w).toDouble(),
  ];
  final usualWake = wakes.length >= sleepPatternMinNights
      ? median(wakes)
      : null;
  final wakeTime = usualWake == null ? 'usual' : _clockOfDay(usualWake);

  // ── Running short ──
  if (need != null) {
    bool short(SleepNight n) => n.hours < need - .75;
    final shortCount = tracked.where(short).length;
    var streak = 0;
    for (final n in tracked) {
      if (!short(n)) break;
      streak++;
    }
    if (streak >= 3 || shortCount >= 8) {
      final of = 'on $shortCount of the last ${tracked.length} nights';
      final oldestFirst = last14.reversed.toList();
      worth.add(
        SleepPattern(
          id: 'running_short',
          tone: InsightTone.concern,
          title: 'Running short lately',
          body: shortCount >= 8
              ? 'Under your sleep need $of'
                    '${streak >= 3 ? ', the last $streak in a row' : ''}.'
              : 'The last $streak nights were under your sleep need.',
          why:
              'A run of short nights builds up. Focus and mood can dip '
              'before you feel tired. A lie-in helps a little, but it '
              "doesn't undo the run.",
          tryThis:
              'Start winding down 30 minutes earlier for the next few '
              'nights, and keep your $wakeTime wake time.',
          action: SleepPatternAction.preferences,
          actionLabel: 'Set up wind-down reminder',
          chart: SleepPatternChart(
            [for (final n in oldestFirst) n?.hours],
            labels: [
              for (var i = 0; i < 14; i++)
                i == 0
                    ? '2 weeks ago'
                    : i == 13
                    ? 'Last night'
                    : '',
            ],
            highlight: {
              for (final (i, n) in oldestFirst.indexed)
                if (n != null && short(n)) i,
            },
            reference: need,
          ),
          basis:
              'Vivordo shows the pattern, not a total of hours owed: how '
              "lost sleep adds up and pays back isn't precise enough to "
              'count. Based on ${tracked.length} nights.',
        ),
      );
    }
  }

  // ── Long sleep: usually long, or suddenly longer ──
  final month = [
    for (var i = 0; i < 30; i++)
      if (nights[back(i)] case final n?) asleep(n),
  ];
  final usualHours = month.length >= 20 ? median(month)! : null;
  if (usualHours != null && usualHours >= 10) {
    worth.add(
      SleepPattern(
        id: 'long_usual',
        tone: InsightTone.neutral,
        title: 'Long nights are your usual',
        body:
            'Your usual is about ${hoursMinutes(usualHours)} a night this '
            "month. If you still wake up tired, it's worth mentioning to a "
            'doctor.',
        why:
            'Most adults need 7 to 9 hours. Regularly needing 10 or more can '
            'mean something is getting in the way of good-quality sleep.',
        basis: 'Based on ${month.length} nights.',
      ),
    );
  } else if (longSleepAverage([
        for (final n in last14) n == null ? null : asleep(n),
      ], need)
      case final average?) {
    worth.add(
      SleepPattern(
        id: 'long_sudden',
        tone: InsightTone.concern,
        title: 'Sleeping longer than usual',
        body:
            'About ${_duration(((average - need!) * 60).round())} more than '
            'your need a night this week. You may be run down or fighting '
            'something off.',
        why:
            "Sleeping a lot more than you need, when you weren't short "
            "before, is often your body asking for rest, like when you're "
            'coming down with something.',
        tryThis:
            "Go easy today. If you're unwell, tag it so your energy forecast "
            'eases off.',
        action: SleepPatternAction.tagSick,
        actionLabel: 'Tag sick',
        basis: 'Based on ${tracked.length} nights.',
      ),
    );
  }

  // ── Weekend shift (social jet lag): Friday and Saturday nights ──
  final midpoints = <(bool, double)>[];
  for (var i = 0; i < 28; i++) {
    final n = nights[back(i)];
    if (n?.bedtime == null || n?.wakeTime == null) continue;
    final bed = _minutesFromNoon(n!.bedtime!);
    final wake = _minutesFromNoon(n.wakeTime!);
    if (wake <= bed) continue;
    midpoints.add((freeNight(back(i)), (bed + wake) / 2));
  }
  final free = [
    for (final (f, m) in midpoints)
      if (f) m,
  ];
  final work = [
    for (final (f, m) in midpoints)
      if (!f) m,
  ];
  var weekendShift = false;
  if (free.length >= 3 && work.length >= 6) {
    final shift = (median(free)! - median(work)!).round();
    if (shift >= 60) {
      weekendShift = true;
      worth.add(
        SleepPattern(
          id: 'weekend_shift',
          tone: shift >= 120 ? InsightTone.concern : InsightTone.neutral,
          title: 'Weekend shift',
          body:
              'Your sleep runs about ${_duration(shift)} later on Friday and '
              'Saturday nights, so getting back into the week can feel like '
              'jet lag.',
          why:
              'Sleeping later at the weekend is like flying a time zone or '
              "two west and back every week. It's called social jet lag, "
              'and 2 hours or more is linked to feeling worse.',
          tryThis:
              'Keep weekend wake times within an hour of your weekdays. A '
              'later bedtime matters less than a long lie-in.',
          action: SleepPatternAction.preferences,
          actionLabel: 'Set weekend times',
          basis:
              'Based on ${free.length} weekend and ${work.length} weekday '
              'nights.',
        ),
      );
    }
  }

  // ── Irregular times (a weekend shift alone doesn't count) ──
  List<double> spreadOf(double? Function(SleepNight) minutes) => [
    for (var i = 0; i < 14; i++)
      if (nights[back(i)] case final n?)
        if (!weekendShift || !freeNight(back(i))) ?minutes(n),
  ];
  final bedSpread = _spread(
    spreadOf(
      (n) => n.bedtime == null ? null : _minutesFromNoon(n.bedtime!) * 1.0,
    ),
  );
  final wakeSpread = _spread(
    spreadOf(
      (n) => n.wakeTime == null ? null : _minutesOfDay(n.wakeTime!) * 1.0,
    ),
  );
  if (math.max(bedSpread ?? 0, wakeSpread ?? 0) >= 60) {
    final isBed = (bedSpread ?? 0) >= (wakeSpread ?? 0);
    final spread = (isBed ? bedSpread : wakeSpread)!.round();
    worth.add(
      SleepPattern(
        id: 'irregular',
        tone: spread >= 90 ? InsightTone.concern : InsightTone.neutral,
        title: 'Irregular sleep times',
        body:
            'Your ${isBed ? 'bedtime' : 'wake time'} moved by about '
            '${_duration(spread)} from night to night over the last 2 '
            '${weekendShift ? 'weeks, weekends aside' : 'weeks'}. A steady '
            'wake time is the easiest place to start.',
        why:
            'Your body clock runs best on a routine. Big swings in when you '
            'sleep are linked to worse sleep and health, even when the '
            'hours add up.',
        tryThis:
            'Pick a wake time you can keep every day, within about 30 '
            'minutes.',
        action: SleepPatternAction.preferences,
        actionLabel: 'Set your usual times',
        basis: 'Based on ${tracked.length} nights.',
      ),
    );
  }

  // ── Bedtime creeping later than a month ago ──
  final earlierBeds = [
    for (var i = 28; i < 56; i++)
      if (nights[back(i)]?.bedtime case final b?) _minutesFromNoon(b) * 1.0,
  ];
  if (bedtimes.length >= sleepPatternMinNights && earlierBeds.length >= 10) {
    final now = median(bedtimes)!, then = median(earlierBeds)!;
    final drift = (now - then).round();
    if (drift >= 60) {
      final earlierWakes = [
        for (var i = 28; i < 56; i++)
          if (nights[back(i)]?.wakeTime case final w?) _minutesOfDay(w) * 1.0,
      ];
      final sameWake =
          usualWake != null &&
          earlierWakes.length >= 10 &&
          (usualWake - median(earlierWakes)!).abs() < 30;
      worth.add(
        SleepPattern(
          id: 'bedtime_drift',
          tone: InsightTone.concern,
          title: 'Bedtime creeping later',
          body:
              'Around ${_clock(now)} now, about ${_duration(drift)} later '
              'than a month ago${sameWake ? ', with the same wake time' : ''}.',
          why: sameWake
              ? "When bedtime drifts later but your alarm doesn't, the time "
                    'comes out of your sleep.'
              : 'A later bedtime is fine if your wake time moves with it. '
                    "When it doesn't, the time comes out of your sleep.",
          tryThis:
              'Start winding down 15 minutes earlier at a time, until '
              "you're back near ${_clock(then)}.",
          action: SleepPatternAction.preferences,
          actionLabel: 'Set up wind-down reminder',
          basis: 'Based on ${bedtimes.length + earlierBeds.length} nights.',
        ),
      );
    }
  }

  // ── A weekday that's always short ──
  final sixWeeks = [
    for (var i = 0; i < 42; i++)
      if (nights[back(i)] case final n?) (morning: back(i), night: n),
  ];
  ({int weekday, double diff, double usual, List<double> hours})? weekday;
  for (var wd = DateTime.monday; wd <= DateTime.sunday; wd++) {
    final mine = [
      for (final e in sixWeeks)
        if (evening(e.morning).weekday == wd) e.night.hours,
    ];
    final others = [
      for (final e in sixWeeks)
        if (evening(e.morning).weekday != wd) e.night.hours,
    ];
    if (mine.length < 4 || others.length < 12) continue;
    final usual = median(others)!;
    final diff = usual - median(mine)!;
    final shortLately = mine.take(4).where((h) => h <= usual - .75).length;
    // Still true without its worst night, so one bad week doesn't make it.
    final rest = [...mine]..remove(mine.reduce(math.min));
    if (diff >= .75 &&
        shortLately >= 3 &&
        median(rest)! <= usual - .75 &&
        diff > (weekday?.diff ?? 0)) {
      weekday = (weekday: wd, diff: diff, usual: usual, hours: mine);
    }
  }
  if (weekday != null) {
    final wd = weekday.weekday;
    final name = _weekdays[wd - 1];
    final nextDay = _weekdays[wd % 7];
    bool mine(DateTime morning) => evening(morning).weekday == wd;
    // The likely cause: the next morning's calendar, an early wake, or a
    // late bedtime.
    String? cause;
    var fromCalendar = false;
    final starts = [
      for (final e in sixWeeks)
        if (firstEvents[e.morning] case final s? when mine(e.morning)) s * 1.0,
    ];
    final otherStarts = [
      for (final MapEntry(:key, :value) in firstEvents.entries)
        if (!mine(key)) value * 1.0,
    ];
    if (starts.length >= 3 && otherStarts.length >= 6) {
      final early = median(starts)!;
      if (early <= median(otherStarts)! - 45) {
        cause =
            '${nextDay}s usually start with something before '
            '${_clockOfDay((early ~/ 60 + 1) * 60.0)}.';
        fromCalendar = true;
      }
    }
    double? usualOf(bool want, double? Function(SleepNight) minutes) => median([
      for (final e in sixWeeks)
        if (mine(e.morning) == want) ?minutes(e.night),
    ]);
    double? wakeOf(SleepNight n) =>
        n.wakeTime == null ? null : _minutesOfDay(n.wakeTime!) * 1.0;
    double? bedOf(SleepNight n) =>
        n.bedtime == null ? null : _minutesFromNoon(n.bedtime!) * 1.0;
    final wakeEarlier = switch ((
      usualOf(false, wakeOf),
      usualOf(true, wakeOf),
    )) {
      (final o?, final m?) => (o - m).round(),
      _ => 0,
    };
    final bedLater = switch ((usualOf(true, bedOf), usualOf(false, bedOf))) {
      (final m?, final o?) => (m - o).round(),
      _ => 0,
    };
    if (cause == null && wakeEarlier >= 45) {
      cause =
          'You wake about ${_duration(wakeEarlier)} earlier on ${nextDay}s'
          '${bedLater.abs() < 30 ? ', but go to bed at your usual time' : ''}.';
    } else if (cause == null && bedLater >= 45) {
      cause = 'You go to bed about ${_duration(bedLater)} later on ${name}s.';
    }
    final usualBed = usualOf(false, bedOf);
    final early = fromCalendar || wakeEarlier >= 45;
    behind.add(
      SleepPattern(
        id: 'weekday_short',
        tone: InsightTone.neutral,
        title: '$name nights run short',
        body:
            'About ${_duration((weekday.diff * 60).round())} less than your '
            'other nights.${cause == null ? '' : ' $cause'}',
        why:
            'The same short night every week is easy to miss, but it '
            'repeats, and the next day pays for it each time.',
        tryThis: early && usualBed != null
            ? 'On ${name}s, aim for bed around '
                  '${_clock(usualBed - weekday.diff * 60)} so the early start '
                  "doesn't cost you sleep."
            : 'On ${name}s, start winding down a little earlier than usual.',
        chart: SleepPatternChart(
          [
            for (var d = DateTime.monday; d <= DateTime.sunday; d++)
              median([
                for (final e in sixWeeks)
                  if (evening(e.morning).weekday == d) e.night.hours,
              ]),
          ],
          labels: [for (final d in _weekdays) d.substring(0, 3)],
          highlight: {wd - 1},
        ),
        basis:
            'Based on ${weekday.hours.length} ${name}s and '
            '${sixWeeks.length - weekday.hours.length} other nights'
            '${fromCalendar ? ', and the times of your calendar events' : ''}.',
      ),
    );
  }

  // ── A night tag that costs sleep ──
  ({String tag, int lower, int tagged, double diff})? lever;
  for (final tag in _leverTags.keys) {
    final withTag = <double>[], without = <double>[];
    for (var i = 0; i < 60; i++) {
      final n = nights[back(i)];
      final saved = tags[evening(back(i))];
      if (n == null || saved == null) continue;
      (saved.contains(tag) ? withTag : without).add(n.hours);
    }
    if (withTag.length < 3 || without.length < 5) continue;
    final usual = median(without)!;
    final diff = usual - median(withTag)!;
    final lower = withTag.where((h) => h <= usual - .5).length;
    if (diff >= .5 &&
        lower >= 3 &&
        lower * 3 >= withTag.length * 2 &&
        diff > (lever?.diff ?? 0)) {
      lever = (tag: tag, lower: lower, tagged: withTag.length, diff: diff);
    }
  }
  if (lever != null) {
    final about = _leverTags[lever.tag]!;
    behind.add(
      SleepPattern(
        id: 'tag_${lever.tag}',
        tone: InsightTone.neutral,
        title: about.title,
        body:
            'On ${lever.lower} of the ${lever.tagged} nights you tagged '
            '${about.name}, you slept about '
            '${_duration((lever.diff * 60).round())} less than usual.',
        why:
            "This comes from your own tagged nights, so it's something you "
            'can change.',
        tryThis: about.tryThis,
        basis: 'Based on the nights you tagged in the last 2 months.',
      ),
    );
  }

  // ── What the mornings you rated say ──
  final rated = [
    for (var i = 0; i < 60; i++)
      if ((nights[back(i)], ratings[back(i)]) case (final n?, final r?))
        (hours: n.hours, rested: r >= 75),
  ];
  ({double hours, int above, int restedAbove, int below, int restedBelow})?
  mornings;
  if (rated.length >= 10) {
    // At least 30 points apart; on a tie, the lowest number of hours.
    var bestGap = .299;
    for (final t in const [6.5, 7.0, 7.5, 8.0, 8.5]) {
      final above = rated.where((r) => r.hours >= t).toList();
      final below = rated.where((r) => r.hours < t).toList();
      if (above.length < 4 || below.length < 4) continue;
      final a = above.where((r) => r.rested).length;
      final b = below.where((r) => r.rested).length;
      final gap = a / above.length - b / below.length;
      if (a / above.length >= .6 && gap > bestGap) {
        bestGap = gap;
        mornings = (
          hours: t,
          above: above.length,
          restedAbove: a,
          below: below.length,
          restedBelow: b,
        );
      }
    }
  }
  if (mornings != null) {
    behind.add(
      SleepPattern(
        id: 'mornings',
        tone: InsightTone.neutral,
        title: 'What helps your mornings',
        body:
            'You rated your sleep Good or Great on ${mornings.restedAbove} of '
            '${mornings.above} mornings after ${hoursMinutes(mornings.hours)} '
            'or more, and ${mornings.restedBelow} of ${mornings.below} after '
            'less.',
        why:
            'How rested you feel matters as much as the numbers. This is '
            'what your own mornings say.',
        tryThis:
            'Use it as a guide for nights that matter, not a target to '
            'worry about.',
        basis: 'Based on ${rated.length} mornings you rated.',
      ),
    );
  }

  // ── Good news ──
  int within30(List<double> minutes) {
    final usual = median(minutes)!;
    return minutes.where((m) => (m - usual).abs() <= 30).length;
  }

  final steadyWake =
      wakes.length >= sleepPatternMinNights &&
      within30(wakes) >= wakes.length * .8;
  final steadyBed =
      bedtimes.length >= sleepPatternMinNights &&
      within30(bedtimes) >= bedtimes.length * .8;
  final met = need == null
      ? 0
      : tracked.where((n) => n.hours >= need - .25).length;
  if (steadyWake && steadyBed && met >= tracked.length - 2) {
    good.add(
      SleepPattern(
        id: 'well_rested',
        tone: InsightTone.good,
        title: 'Well rested and steady',
        body:
            'Met your need on $met of ${tracked.length} nights, with bed and '
            'wake times within about 30 minutes. Keep it going.',
        why:
            'Enough sleep at steady times is the combination that does the '
            'most for energy, mood and long-term health.',
        basis: 'Based on ${tracked.length} nights.',
      ),
    );
  } else if (steadyWake) {
    good.add(
      SleepPattern(
        id: 'steady_wake',
        tone: InsightTone.good,
        title: 'Steady wake time',
        body:
            'Up within 30 minutes of $wakeTime on ${within30(wakes)} of '
            '${wakes.length} mornings. Keep that anchor.',
        why:
            'A steady wake time sets your body clock for the day, and does '
            'the most for a regular rhythm.',
        basis: 'Based on ${wakes.length} mornings.',
      ),
    );
  }

  int rank(SleepPattern p) => p.tone == InsightTone.concern ? 0 : 1;
  worth.sort((a, b) => rank(a) - rank(b));
  return [...worth, ...behind, ...good];
}

/// The standard deviation, with at least [sleepPatternMinNights] values.
double? _spread(List<double> values) {
  if (values.length < sleepPatternMinNights) return null;
  final mean = _mean(values);
  return math.sqrt(
    values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
        values.length,
  );
}

/// "12:40 AM" from minutes after noon, to the nearest 5 minutes.
String _clock(double minutesFromNoon) => _clockOfDay(minutesFromNoon + 720);

/// "7:05 AM" from minutes after midnight, to the nearest 5 minutes.
String _clockOfDay(double minutes) {
  final m = ((minutes / 5).round() * 5) % 1440;
  final hour = m ~/ 60 % 12 == 0 ? 12 : m ~/ 60 % 12;
  return '$hour:${(m % 60).toString().padLeft(2, '0')} '
      '${m < 720 ? 'AM' : 'PM'}';
}
