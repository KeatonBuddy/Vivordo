import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/calendar_service.dart';
import 'package:vivordo_health/src/services/outlook_calendar_service.dart';

void main() {
  // As Graph sends them with `Prefer: outlook.timezone="UTC"`: no zone, seven
  // fractional digits.
  Map<String, dynamic> graphEvent({
    String start = '2026-10-13T15:00:00.0000000',
    String end = '2026-10-13T16:00:00.0000000',
    bool allDay = false,
    String showAs = 'busy',
    String response = 'accepted',
    bool isOrganizer = false,
    List<String> attendees = const ['me@contoso.com', 'sam@contoso.com'],
    String? series,
  }) => {
    'id': 'AAMk1',
    'subject': ' Planning ',
    'start': {'dateTime': start, 'timeZone': 'UTC'},
    'end': {'dateTime': end, 'timeZone': 'UTC'},
    'isAllDay': allDay,
    'showAs': showAs,
    'isCancelled': false,
    'responseStatus': {'response': response},
    'isOrganizer': isOrganizer,
    'organizer': {
      'emailAddress': {
        'name': 'Alex',
        'address': isOrganizer ? 'me@contoso.com' : 'alex@contoso.com',
      },
    },
    'attendees': [
      for (final address in attendees)
        {
          'type': 'required',
          'emailAddress': {'address': address},
        },
    ],
    'seriesMasterId': series,
    'isOnlineMeeting': true,
    'onlineMeeting': {'joinUrl': 'https://teams.example/join'},
  };

  test('times are UTC, not read as local', () {
    final event = OutlookCalendarService.toGoogleEvent(graphEvent())!;
    expect(event.start!.dateTime, DateTime.utc(2026, 10, 13, 15));
    expect(event.start!.dateTime!.isUtc, isTrue);
    expect(event.end!.dateTime, DateTime.utc(2026, 10, 13, 16));
    expect(event.summary, 'Planning');
    expect(event.id, 'outlook:AAMk1');
  });

  test('all-day events are dates, the end exclusive like Google', () {
    final event = OutlookCalendarService.toGoogleEvent(
      graphEvent(
        allDay: true,
        start: '2026-10-13T00:00:00.0000000',
        end: '2026-10-14T00:00:00.0000000',
      ),
    )!;
    expect(event.start!.dateTime, isNull);
    expect(event.start!.date, DateTime(2026, 10, 13));
    expect(event.end!.date, DateTime(2026, 10, 14));
  });

  test("an invite lists the organizer, the others, then the user", () {
    final event = OutlookCalendarService.toGoogleEvent(
      graphEvent(),
      me: 'Me@Contoso.com',
    )!;
    expect(
      [for (final a in event.attendees!) a.email ?? 'self'],
      ['alex@contoso.com', 'sam@contoso.com', 'self'],
    );
    expect(event.attendees!.last.responseStatus, 'accepted');
    expect(event.organizer!.self, isFalse);
  });

  test('a solo event of their own has no attendees, like Google', () {
    final event = OutlookCalendarService.toGoogleEvent(
      graphEvent(isOrganizer: true, response: 'organizer', attendees: []),
      me: 'me@contoso.com',
    )!;
    expect(event.attendees, isNull);
    expect(event.organizer!.self, isTrue);
  });

  test('free, declined, series and online meetings carry over', () {
    final event = OutlookCalendarService.toGoogleEvent(
      graphEvent(showAs: 'free', response: 'declined', series: 'AAMkS'),
      me: 'me@contoso.com',
    )!;
    expect(event.transparency, 'transparent');
    expect(
      event.attendees!.singleWhere((a) => a.self == true).responseStatus,
      'declined',
    );
    expect(event.recurringEventId, 'outlook:AAMkS');
    expect(event.hangoutLink, 'https://teams.example/join');
    expect(event.conferenceData, isNotNull);
  });

  test('only the calendars the user owns are read', () {
    final own = OutlookCalendarService.ownCalendars([
      {
        'id': 'main',
        'isDefaultCalendar': true,
        'owner': {'address': 'Me@contoso.com'},
      },
      {
        'id': 'birthdays',
        'isDefaultCalendar': false,
        'owner': {'address': 'me@contoso.com'},
      },
      {
        'id': 'colleague',
        'isDefaultCalendar': false,
        'owner': {'address': 'sam@contoso.com'},
      },
    ]);
    expect(own.ids, ['main', 'birthdays']);
    expect(own.me, 'me@contoso.com');
  });

  test('Outlook events key and edit as Outlook', () async {
    final event = OutlookCalendarService.toGoogleEvent(graphEvent())!;
    expect(CalendarService.isOutlook(event), isTrue);
    expect(CalendarService.eventKey(event), 'outlook:AAMk1');
    await expectLater(
      CalendarService.deleteEvent(event),
      throwsA(isA<StateError>()),
    );
  });
}
