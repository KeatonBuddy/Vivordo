import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:vivordo_health/src/services/calendar_snapshot_service.dart';

gcal.Event _event(String id, DateTime start) => gcal.Event(
  id: id,
  summary: 'Standup',
  start: gcal.EventDateTime(dateTime: start.toUtc()),
  end: gcal.EventDateTime(
    dateTime: start.add(const Duration(minutes: 30)).toUtc(),
  ),
);

void main() {
  final day = DateTime(2026, 10, 29);
  final twoDays = day.add(const Duration(days: 2));
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('snapshot');
    CalendarSnapshotService.directory = () async => dir;
    await CalendarSnapshotService.clear();
  });

  tearDown(() => dir.delete(recursive: true));

  test('gives back saved events for the same account and range', () async {
    await CalendarSnapshotService.save('a', day, twoDays, [
      _event('outlook:1', day.add(const Duration(hours: 9))),
    ]);
    // Read back from disk, as on the next launch.
    CalendarSnapshotService.forgetLoaded();
    final events = await CalendarSnapshotService.eventsBetween(
      'a',
      day,
      twoDays,
    );
    expect(events!.events.single.id, 'outlook:1');
    expect(
      events.events.single.start!.dateTime!.toLocal(),
      day.add(const Duration(hours: 9)),
    );
  });

  test('another account gets nothing', () async {
    await CalendarSnapshotService.save('a', day, twoDays, [
      _event('1', day.add(const Duration(hours: 9))),
    ]);
    expect(
      await CalendarSnapshotService.eventsBetween('b', day, twoDays),
      null,
    );
  });

  test('a range it does not cover gets nothing, e.g. the next day', () async {
    await CalendarSnapshotService.save('a', day, twoDays, [
      _event('1', day.add(const Duration(hours: 9))),
    ]);
    final nextDay = day.add(const Duration(days: 1));
    expect(
      await CalendarSnapshotService.eventsBetween(
        'a',
        nextDay,
        nextDay.add(const Duration(days: 2)),
      ),
      null,
    );
  });

  test('clear deletes it from memory and disk', () async {
    await CalendarSnapshotService.save('a', day, twoDays, [
      _event('1', day.add(const Duration(hours: 9))),
    ]);
    await CalendarSnapshotService.clear();
    expect(
      await CalendarSnapshotService.eventsBetween('a', day, twoDays),
      null,
    );
    expect(dir.listSync(), isEmpty);
  });

  test('an empty day is saved too', () async {
    await CalendarSnapshotService.save('a', day, twoDays, [
      _event('1', day.add(const Duration(hours: 9))),
    ]);
    await CalendarSnapshotService.save('a', day, twoDays, []);
    CalendarSnapshotService.forgetLoaded();
    final saved = await CalendarSnapshotService.eventsBetween(
      'a',
      day,
      twoDays,
    );
    expect(saved!.events, isEmpty);
  });
}
