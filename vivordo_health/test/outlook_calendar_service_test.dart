import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:msal_auth/msal_auth.dart';
import 'package:vivordo_health/src/services/calendar_service.dart';
import 'package:vivordo_health/src/services/outlook_calendar_service.dart';
import 'package:vivordo_health/src/utils/event_repeat.dart';

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

  test('Outlook events key as Outlook', () {
    final event = OutlookCalendarService.toGoogleEvent(graphEvent())!;
    expect(CalendarService.isOutlook(event), isTrue);
    expect(CalendarService.eventKey(event), 'outlook:AAMk1');
  });

  test('repeats become Graph patterns', () {
    final start = DateTime(2026, 10, 13, 9);
    expect(OutlookCalendarService.graphRecurrence('none', start), isNull);
    expect(
      OutlookCalendarService.graphRecurrence(
        'RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;UNTIL=20261231T235959Z',
        start,
        zone: 'America/Edmonton',
      ),
      {
        'pattern': {
          'type': 'weekly',
          'interval': 2,
          'daysOfWeek': ['monday', 'wednesday'],
          'firstDayOfWeek': 'sunday',
        },
        'range': {
          'type': 'endDate',
          'startDate': '2026-10-13',
          'endDate': '2026-12-31',
          'recurrenceTimeZone': 'America/Edmonton',
        },
      },
    );
    // The names priorities use; weekly without days repeats on the start's.
    expect(
      OutlookCalendarService.graphRecurrence('weekly', start)!['pattern'],
      {
        'type': 'weekly',
        'interval': 1,
        'daysOfWeek': ['tuesday'],
        'firstDayOfWeek': 'sunday',
      },
    );
    expect(
      OutlookCalendarService.graphRecurrence('monthly', start)!['pattern'],
      {'type': 'absoluteMonthly', 'interval': 1, 'dayOfMonth': 13},
    );
  });

  test('Graph patterns read back as the form edits them', () {
    final lines = OutlookCalendarService.recurrenceLines({
      'pattern': {
        'type': 'weekly',
        'interval': 2,
        'daysOfWeek': ['monday', 'wednesday'],
      },
      'range': {
        'type': 'endDate',
        'startDate': '2026-10-13',
        'endDate': '2026-12-31',
      },
    }, allDay: true);
    final repeat = EventRepeat.parse(lines);
    expect(repeat.unit, RepeatUnit.week);
    expect(repeat.interval, 2);
    expect(repeat.weekdays, {DateTime.monday, DateTime.wednesday});
    expect(repeat.until, DateTime(2026, 12, 31));
    expect(
      OutlookCalendarService.recurrenceLines({
        'pattern': {'type': 'daily', 'interval': 1},
        'range': {'type': 'noEnd', 'startDate': '2026-10-13'},
      }, allDay: false),
      ['RRULE:FREQ=DAILY'],
    );
    expect(OutlookCalendarService.recurrenceLines(null, allDay: false), isNull);
  });

  test('priority links and occurrence starts carry over', () {
    final event = OutlookCalendarService.toGoogleEvent({
      ...graphEvent(series: 'AAMkS'),
      'originalStart': '2026-10-13T15:00:00Z',
      'singleValueExtendedProperties': [
        {
          'id':
              'String {6f3c2d9e-5b1a-4c7e-9d2f-8a4b6c1e3f70} Name '
              'vivordoPriority',
          'value': 'users/u/daily_priorities/p1',
        },
      ],
    })!;
    expect(event.extendedProperties!.private, {
      'vivordoPriority': 'true',
      'vivordoPriorityReference': 'users/u/daily_priorities/p1',
    });
    expect(event.originalStartTime!.dateTime, DateTime.utc(2026, 10, 13, 15));
  });

  test('Graph gets at most 3 requests at once, and 429s are retried', () async {
    var running = 0, most = 0;
    final release = Completer<void>();
    final calls = [
      for (var i = 0; i < 6; i++)
        OutlookCalendarService.throttled(() async {
          most = (++running) > most ? running : most;
          await release.future;
          running--;
          return http.Response('', 200);
        }),
    ];
    await Future<void>.delayed(Duration.zero);
    expect(running, 3);
    release.complete();
    await Future.wait(calls);
    expect(most, 3);

    var attempts = 0;
    final response = await OutlookCalendarService.throttled(
      () async => ++attempts == 1
          ? http.Response('', 429, headers: {'retry-after': '1'})
          : http.Response('ok', 200),
    );
    expect((attempts, response.body), (2, 'ok'));
  });

  test('admin-approval refusals are told apart from other sign-in errors', () {
    bool needs(MsalException e) => OutlookCalendarService.needsAdminApproval(e);
    expect(
      needs(
        const MsalClientException(
          errorCode: 'server_error',
          message: 'AADSTS90094: The grant requires admin permission.',
          correlationId: null,
        ),
      ),
      isTrue,
    );
    expect(
      needs(
        const MsalUiRequiredException(
          oauthError: 'access_denied',
          oauthErrorDescription:
              'AADSTS90095: An administrator must approve this app.',
          oauthSubErrorCode: null,
          message: 'Interaction required',
          correlationId: null,
        ),
      ),
      isTrue,
    );
    expect(
      needs(
        const MsalClientException(
          errorCode: 'network',
          message: 'The Internet connection appears to be offline.',
          correlationId: null,
        ),
      ),
      isFalse,
    );
  });
}
