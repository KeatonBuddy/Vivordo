import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/journal_summary.dart';

void main() {
  JournalItem entry(DateTime date, {String? mood, String text = 'Note'}) =>
      JournalItem(id: '$date', text: text, date: date, mood: mood);
  final now = DateTime(2026, 9, 30, 21);

  test('streak counts back from today, or from yesterday before writing', () {
    final items = [
      entry(DateTime(2026, 9, 29, 22)),
      entry(DateTime(2026, 9, 28, 9)),
      entry(DateTime(2026, 9, 28, 20)),
      entry(DateTime(2026, 9, 26, 10)),
    ];
    expect(journalStreak(items, now), 2);
    expect(journalStreak([...items, entry(DateTime(2026, 9, 30, 8))], now), 3);
    expect(journalStreak([entry(DateTime(2026, 9, 27))], now), 0);
    expect(journalStreak(const [], now), 0);
  });

  test('each day takes the mood of its latest entry in that month', () {
    final moods = moodsByDay([
      entry(DateTime(2026, 9, 28, 9), mood: 'Great'),
      entry(DateTime(2026, 9, 28, 22), mood: 'Stressed'),
      entry(DateTime(2026, 9, 3), mood: 'Okay'),
      entry(DateTime(2026, 8, 28), mood: 'Low'),
    ], DateTime(2026, 9));
    expect(moods, {28: 'Stressed', 3: 'Okay'});
  });

  test('moods group into good, middling and hard', () {
    expect(moodTone('Good'), MoodTone.good);
    expect(moodTone('Low'), MoodTone.middling);
    expect(moodTone('Stressed'), MoodTone.hard);
    expect(moodTone(null), MoodTone.none);
  });

  test('search matches title or text, newest first', () {
    final items = [
      JournalItem(id: 'a', text: 'Quiet day', date: DateTime(2026, 9, 1)),
      JournalItem(
        id: 'b',
        text: 'Long talk with Sam',
        date: DateTime(2026, 9, 5),
      ),
      JournalItem(
        id: 'c',
        text: 'Gym',
        title: 'sam came along',
        date: DateTime(2026, 9, 9),
      ),
    ];
    expect(searchJournal(items, 'SAM').map((i) => i.id), ['c', 'b']);
    expect(searchJournal(items, '  ').map((i) => i.id), ['c', 'b', 'a']);
  });

  test('titles come from the first line, shortened', () {
    expect(journalTitleFrom('Great run\nThen breakfast'), 'Great run');
    expect(journalTitleFrom('   '), 'Journal entry');
    expect(journalTitleFrom('x' * 60), '${'x' * 39}…');
  });

  test('prompts start with finished events, latest first, then general', () {
    final prompts = journalPrompts(now, [
      (title: 'Standup', end: DateTime(2026, 9, 30, 9, 15)),
      (title: 'Sprint planning', end: DateTime(2026, 9, 30, 16)),
      (title: 'Dinner', end: DateTime(2026, 9, 30, 22)),
      (title: 'standup ', end: DateTime(2026, 9, 30, 11)),
    ]);
    expect(prompts.take(2), [
      'How did Sprint planning go?',
      'How did standup go?',
    ]);
    expect(prompts.where((p) => p.contains('Dinner')), isEmpty);
    expect(prompts.length, 2 + 7);
    // A different day opens on a different general prompt.
    expect(
      journalPrompts(now, const []).first,
      isNot(journalPrompts(DateTime(2026, 10, 1), const []).first),
    );
  });
}
