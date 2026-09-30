/// Pure helpers behind the Journal home: moods by day, streaks, prompts.
library;

const journalMoods = ['Great', 'Good', 'Okay', 'Low', 'Stressed'];

enum MoodTone { good, middling, hard, none }

MoodTone moodTone(String? mood) => switch (mood) {
  'Great' || 'Good' => MoodTone.good,
  'Okay' || 'Low' => MoodTone.middling,
  'Stressed' => MoodTone.hard,
  _ => MoodTone.none,
};

/// One saved entry, as the Journal screens use it.
class JournalItem {
  const JournalItem({
    required this.id,
    required this.text,
    required this.date,
    this.title,
    this.mood,
    this.shared = false,
  });

  final String id;
  final String text;
  final DateTime date;
  final String? title;
  final String? mood;
  final bool shared;

  String get displayTitle =>
      title?.trim().isNotEmpty == true ? title!.trim() : journalTitleFrom(text);
}

/// The first line, shortened to fit one row.
String journalTitleFrom(String text) {
  final line = text.trim().split('\n').first.trim();
  if (line.isEmpty) return 'Journal entry';
  return line.length <= 42 ? line : '${line.substring(0, 39).trimRight()}…';
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Days in a row with at least one entry, counting back from today, or from
/// yesterday when today has none yet (an unwritten evening keeps the streak).
int journalStreak(Iterable<JournalItem> items, DateTime now) {
  final days = {for (final i in items) _day(i.date)};
  var day = _day(now);
  if (!days.contains(day)) day = DateTime(day.year, day.month, day.day - 1);
  var streak = 0;
  while (days.contains(day)) {
    streak++;
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return streak;
}

/// Day of month to the mood of that day's latest entry, for [month].
Map<int, String?> moodsByDay(Iterable<JournalItem> items, DateTime month) {
  final latest = <int, JournalItem>{};
  for (final i in items) {
    if (i.date.year != month.year || i.date.month != month.month) continue;
    final seen = latest[i.date.day];
    if (seen == null || i.date.isAfter(seen.date)) latest[i.date.day] = i;
  }
  return {for (final e in latest.entries) e.key: e.value.mood};
}

/// Entries matching [query] (title or text, any case), newest first.
List<JournalItem> searchJournal(Iterable<JournalItem> items, String query) {
  final q = query.trim().toLowerCase();
  final found =
      items
          .where(
            (i) =>
                q.isEmpty ||
                i.text.toLowerCase().contains(q) ||
                (i.title ?? '').toLowerCase().contains(q),
          )
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
  return found;
}

const _generalPrompts = [
  'What took most of your energy today?',
  'What went better than you expected?',
  'What would you like to let go of before tomorrow?',
  'Who made today easier, and how?',
  'What is one thing you want to remember about today?',
  'What felt heavy today, and what helped?',
  'What are you looking forward to tomorrow?',
];

/// Prompts for writing about [now]'s day: first about today's events that
/// have already ended (latest first), then general ones, rotated by date so
/// each day opens on a different question.
List<String> journalPrompts(
  DateTime now,
  Iterable<({String title, DateTime end})> finishedToday,
) {
  final events = finishedToday.where((e) => !e.end.isAfter(now)).toList()
    ..sort((a, b) => b.end.compareTo(a.end));
  final seen = <String>{};
  final fromEvents = [
    for (final e in events)
      if (seen.add(e.title.trim().toLowerCase()) && e.title.trim().isNotEmpty)
        'How did ${e.title.trim()} go?',
  ];
  // Calendar days in UTC: local midnights can be 23 or 25 hours apart.
  final offset = DateTime.utc(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime.utc(now.year)).inDays;
  final general = [
    for (var i = 0; i < _generalPrompts.length; i++)
      _generalPrompts[(i + offset) % _generalPrompts.length],
  ];
  return [...fromEvents.take(3), ...general];
}
