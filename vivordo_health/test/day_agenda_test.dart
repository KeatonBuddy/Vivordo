import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/day_agenda.dart';

void main() {
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 9, 29, hour, minute);
  AgendaItem<String> item(String id, DateTime start, DateTime end) =>
      AgendaItem(id, start, end);
  String describe(AgendaEntry<String> e) => switch (e) {
    AgendaItem(:final item) => item,
    AgendaOpening(:final start, :final end) =>
      'open ${start.hour}:${start.minute}-${end?.hour ?? 'end'}',
    AgendaBreak(:final minutes) => 'break $minutes',
  };

  test('openings, breaks and back-to-back gaps between items', () {
    final agenda = buildDayAgenda(at(9, 10), [
      item('design', at(10), at(11)),
      item('1:1', at(11, 15), at(12)),
      item('sprint', at(14), at(15)),
      item('call', at(15, 5), at(15, 30)),
    ]);
    expect(agenda.map(describe), [
      'open 9:10-10',
      'design',
      'break 15',
      '1:1',
      'open 12:0-14',
      'sprint',
      'call',
      'open 15:30-end',
    ]);
  });

  test('overlaps do not create false openings', () {
    final agenda = buildDayAgenda(at(9), [
      item('long', at(9), at(12)),
      item('inside', at(10), at(11)),
      item('after', at(12), at(13)),
    ]);
    expect(agenda.map(describe), ['long', 'inside', 'after', 'open 13:0-end']);
  });

  test('past items are dropped and an ongoing item starts the list', () {
    final agenda = buildDayAgenda(at(10, 30), [
      item('past', at(8), at(9)),
      item('ongoing', at(10), at(11)),
    ]);
    expect(agenda.map(describe), ['ongoing', 'open 11:0-end']);
  });

  test('no trailing opening in the last half hour of the day', () {
    expect(buildDayAgenda(at(23, 40), <AgendaItem<String>>[]), isEmpty);
    expect(buildDayAgenda(at(20), <AgendaItem<String>>[]).map(describe), [
      'open 20:0-end',
    ]);
  });
}
