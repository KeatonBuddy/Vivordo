import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:intl/intl.dart' show DateFormat;
import 'package:msal_auth/msal_auth.dart';
import 'package:http/http.dart' as http;
import 'package:vivordo_health/src/services/calendar_service.dart';
import 'package:vivordo_health/src/utils/event_repeat.dart';
import 'package:vivordo_health/src/utils/request_coalescer.dart';

/// Outlook (Microsoft 365 and Outlook.com) calendars through Microsoft Graph.
///
/// Events come back as [gcal.Event]s, ids prefixed `outlook:`, so everything
/// that reads Google events reads these too; [CalendarService] merges both
/// and sends changes to Outlook events here. Changing one first asks the
/// user to let Vivordo edit their calendar; until then it only reads.
class OutlookCalendarService {
  /// Off hides the Settings row and reads nothing.
  static const bool enabled = true;

  static const String clientId = '07c05b6e-07ad-4ed3-bfd2-35af418decdf';
  static const String authority = 'https://login.microsoftonline.com/common';

  /// Matches CalendarService: long enough to collapse simultaneous requests
  /// for the same range, short enough to stay close to the server.
  static const _eventCacheTtl = Duration(seconds: 30);

  static final RequestCoalescer<List<gcal.Event>> _eventRequests =
      RequestCoalescer<List<gcal.Event>>(ttl: _eventCacheTtl);

  /// Drops cached ranges after an edit, deletion or account change.
  static void invalidateEventCache() => _eventRequests.invalidateAll();

  static const List<String> scopes = [
    'https://graph.microsoft.com/User.Read',
    'https://graph.microsoft.com/Calendars.Read',
  ];

  /// Asked for the first time an Outlook event is changed.
  static const List<String> _writeScopes = [
    'https://graph.microsoft.com/User.Read',
    'https://graph.microsoft.com/Calendars.ReadWrite',
  ];

  static const String _graphHost = 'graph.microsoft.com';

  /// Graph fields Vivordo reads; the rest (bodies, every attendee's
  /// details) stays on Microsoft's side.
  static const String _eventFields =
      'id,subject,start,end,isAllDay,showAs,isCancelled,responseStatus,'
      'attendees,organizer,isOrganizer,seriesMasterId,isOnlineMeeting,'
      'onlineMeeting,location,bodyPreview,iCalUId,originalStart';

  /// Marks an event Vivordo made for a priority, like Google's private
  /// `vivordoPriority` property. Its value is the priority's path, or
  /// 'true'.
  static const String _priorityProperty =
      'String {6f3c2d9e-5b1a-4c7e-9d2f-8a4b6c1e3f70} Name vivordoPriority';
  static const String _expandPriority =
      "singleValueExtendedProperties(\$filter=id eq '$_priorityProperty')";

  /// The calendar each event was read from (`outlook:<calendar id>`), for
  /// the edit form's calendar row.
  static final Map<String, String> _eventCalendarIds = {};

  static String? calendarIdFor(gcal.Event event) => _eventCalendarIds[event.id];

  /// A series' Graph recurrence as read, so moving its start keeps every
  /// rule Vivordo's form doesn't model (like "second Tuesday").
  static final Map<String, Map<String, dynamic>> _seriesRecurrence = {};

  /// A Graph URL. Ids go in escaped: Outlook ids can hold `/`, `+` and `=`.
  static Uri _graphUri(String path, [Map<String, String>? query]) => Uri.parse(
    'https://$_graphHost/v1.0$path',
  ).replace(queryParameters: query);

  static String _graphId(String id) =>
      Uri.encodeComponent(id.startsWith('outlook:') ? id.substring(8) : id);

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _outlookSignedInKey = 'outlook_signed_in';
  // Written by the first version, which kept its own copy of the token.
  static const _legacyTokenKeys = [
    'outlook_access_token',
    'outlook_access_token_expiry',
  ];

  /// Whether an Outlook account is connected, for Settings and anything
  /// else that shows it. Goes false when Microsoft wants the user to sign in
  /// again.
  static final ValueNotifier<bool> connectionNotifier = ValueNotifier<bool>(
    false,
  );
  static bool? _signedIn;

  static SingleAccountPca? _pca;

  static Future<SingleAccountPca> _getPca() async =>
      _pca ??= await SingleAccountPca.create(
        clientId: clientId,
        appleConfig: AppleConfig(
          authority: authority,
          authorityType: AuthorityType.aad,
          broker: Broker.safariBrowser,
        ),
      );

  static Future<bool> isSignedIn() async {
    if (!enabled) return false;
    _signedIn ??= await _secureStorage.read(key: _outlookSignedInKey) == 'true';
    connectionNotifier.value = _signedIn!;
    return _signedIn!;
  }

  static Future<void> _setSignedIn(bool signedIn) async {
    _signedIn = signedIn;
    connectionNotifier.value = signedIn;
    if (signedIn) {
      await _secureStorage.write(key: _outlookSignedInKey, value: 'true');
    } else {
      await _secureStorage.delete(key: _outlookSignedInKey);
    }
    // Screens reload: the merged calendar gained or lost these events.
    CalendarService.invalidateEventCache();
  }

  /// Signs in interactively. True once connected; false when the user
  /// cancelled. Other failures throw, for the caller to report.
  static Future<bool> connect() async {
    if (!enabled) return false;
    try {
      final result = await (await _getPca()).acquireToken(
        scopes: scopes,
        prompt: Prompt.selectAccount,
        authority: authority,
      );
      if (result.accessToken.isEmpty) return false;
      await _setSignedIn(true);
      return true;
    } on MsalUserCancelException {
      return false;
    }
  }

  static Future<void> signOut() async {
    if (enabled) {
      try {
        await (await _getPca()).signOut();
      } catch (e) {
        debugPrint('Outlook sign out error: $e');
      }
    }
    for (final key in _legacyTokenKeys) {
      await _secureStorage.delete(key: key);
    }
    await _setSignedIn(false);
  }

  /// A Graph token from MSAL's cache, refreshed silently when it expired.
  /// Null when it can't be had; when Microsoft needs the user to sign in
  /// again, Outlook also shows as disconnected.
  static Future<String?> _token() async {
    try {
      final result = await (await _getPca()).acquireTokenSilent(
        scopes: scopes,
        authority: authority,
      );
      return result.accessToken.isEmpty ? null : result.accessToken;
    } on MsalUiRequiredException catch (e) {
      debugPrint('Outlook needs signing in again: $e');
      await _setSignedIn(false);
      return null;
    } catch (e) {
      debugPrint('Outlook token error: $e');
      return null;
    }
  }

  static Future<List<gcal.Event>> getWeekEvents(
    DateTime weekStart, {
    bool forceRefresh = false,
  }) => getEventsBetween(
    weekStart,
    weekStart.add(const Duration(days: 7)),
    forceRefresh: forceRefresh,
  );

  /// Events between [start] and [end] from every calendar the user owns;
  /// [] when Outlook isn't connected or can't be read. Identical range
  /// requests are coalesced and reused briefly, since several screens ask
  /// for the same window at once. Pass [forceRefresh] for a pull-to-refresh.
  static Future<List<gcal.Event>> getEventsBetween(
    DateTime start,
    DateTime end, {
    bool forceRefresh = false,
  }) async {
    if (!await isSignedIn()) return const <gcal.Event>[];
    return _eventRequests.run(
      '${start.toIso8601String()}|${end.toIso8601String()}',
      () async => await _fetchEvents(start, end) ?? const <gcal.Event>[],
      forceRefresh: forceRefresh,
    );
  }

  /// Silent, all-or-nothing fetch for scoring, like
  /// CalendarService.getScoringEvents: null when Outlook can't be read (not
  /// connected, no token, or any calendar or page that didn't load), an
  /// empty list when it read fine and had no events.
  static Future<List<gcal.Event>?> getScoringEvents(
    DateTime start,
    DateTime end,
  ) async {
    if (!await isSignedIn()) return null;
    return _fetchEvents(start, end, requireComplete: true);
  }

  static Future<List<gcal.Event>?> _fetchEvents(
    DateTime start,
    DateTime end, {
    bool requireComplete = false,
  }) async {
    final token = await _token();
    if (token == null) return null;
    try {
      final (:me, :ids) = ownCalendars(
        await _pages(
          token,
          _graphUri('/me/calendars', {
            r'$select': 'id,owner,isDefaultCalendar',
          }),
        ),
      );
      final perCalendar = await Future.wait(
        ids.map((id) async {
          try {
            final items = await _pages(
              token,
              _graphUri('/me/calendars/${_graphId(id)}/calendarView', {
                'startDateTime': start.toUtc().toIso8601String(),
                'endDateTime': end.toUtc().toIso8601String(),
                r'$select': _eventFields,
                r'$expand': _expandPriority,
                r'$top': '100',
              }),
            );
            for (final item in items) {
              _eventCalendarIds['outlook:${item['id']}'] = 'outlook:$id';
            }
            return items;
          } catch (e) {
            if (requireComplete) rethrow;
            debugPrint('Outlook calendar skipped: $e');
            return const <Map<String, dynamic>>[];
          }
        }),
      );
      // Sorted by CalendarService, which merges these with Google's.
      return [
        for (final json in perCalendar.expand((items) => items))
          ?toGoogleEvent(json, me: me),
      ];
    } catch (e) {
      debugPrint('Outlook events error: $e');
      return null;
    }
  }

  /// Graph serves each mailbox only a few requests at once (429
  /// "MailboxConcurrency" past that), and screens load together, so at most
  /// [_maxConcurrent] run at a time and a 429 waits its Retry-After and
  /// tries again.
  static const _maxConcurrent = 3;
  static int _running = 0;
  static final Queue<Completer<void>> _queued = Queue();

  @visibleForTesting
  static Future<http.Response> throttled(
    Future<http.Response> Function() call,
  ) async {
    if (_running < _maxConcurrent) {
      _running++;
    } else {
      final turn = Completer<void>();
      _queued.add(turn);
      await turn.future; // The finishing request hands over its slot.
    }
    try {
      for (var attempt = 1; ; attempt++) {
        final response = await call();
        if (response.statusCode != 429 || attempt == 3) return response;
        final wait = int.tryParse(response.headers['retry-after'] ?? '') ?? 1;
        await Future<void>.delayed(Duration(seconds: wait.clamp(1, 10)));
      }
    } finally {
      if (_queued.isNotEmpty) {
        _queued.removeFirst().complete();
      } else {
        _running--;
      }
    }
  }

  /// Every item of a Graph collection, following `@odata.nextLink` so a busy
  /// range isn't cut off at the first page. Throws on any failed page.
  static Future<List<Map<String, dynamic>>> _pages(
    String token,
    Uri first,
  ) async {
    final items = <Map<String, dynamic>>[];
    Uri? page = first;
    while (page != null) {
      final uri = page;
      final response = await throttled(
        () => http.get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
            // Times come back in UTC, written without a zone.
            'Prefer': 'outlook.timezone="UTC"',
          },
        ),
      );
      if (response.statusCode == 401) await _setSignedIn(false);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw http.ClientException(
          'Graph ${response.statusCode}: ${response.body}',
          page,
        );
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      items.addAll(
        (decoded['value'] as List? ?? const []).cast<Map<String, dynamic>>(),
      );
      final next = decoded['@odata.nextLink'];
      page = next is String ? Uri.parse(next) : null;
    }
    return items;
  }

  /// The user's address (their default calendar's owner) and the ids of the
  /// calendars they own. Colleagues' calendars shared with them are left
  /// out, or someone else's meetings would count as theirs.
  @visibleForTesting
  static ({String? me, List<String> ids}) ownCalendars(
    List<Map<String, dynamic>> calendars,
  ) {
    String? ownerOf(Map<String, dynamic> calendar) =>
        ((calendar['owner'] as Map?)?['address'] as String?)?.toLowerCase();
    final me = calendars
        .where((calendar) => calendar['isDefaultCalendar'] == true)
        .map(ownerOf)
        .firstOrNull;
    return (
      me: me,
      ids: [
        for (final calendar in calendars)
          if (calendar['isDefaultCalendar'] == true ||
              (me != null && ownerOf(calendar) == me))
            calendar['id'] as String,
      ],
    );
  }

  /// A Graph event as the Google event the rest of the app reads. Null when
  /// it has no times. [me] is the user's address, to find them among the
  /// invitees.
  @visibleForTesting
  static gcal.Event? toGoogleEvent(Map<String, dynamic> json, {String? me}) {
    final startText = (json['start'] as Map?)?['dateTime'] as String?;
    final endText = (json['end'] as Map?)?['dateTime'] as String?;
    final id = json['id'] as String?;
    if (startText == null || endText == null || id == null) return null;
    final allDay = json['isAllDay'] == true;
    // Asked for in UTC, which Graph writes without a zone. All-day events
    // are dates, whatever the zone.
    gcal.EventDateTime time(String text) {
      final utc = DateTime.parse(text.endsWith('Z') ? text : '${text}Z');
      return allDay
          ? (gcal.EventDateTime()
              ..date = DateTime(utc.year, utc.month, utc.day))
          : (gcal.EventDateTime()..dateTime = utc);
    }

    final response =
        (json['responseStatus'] as Map?)?['response'] as String? ?? 'none';
    final organizer = (json['organizer'] as Map?)?['emailAddress'] as Map?;
    final isOrganizer = json['isOrganizer'] == true;
    final invitees = [
      for (final attendee in json['attendees'] as List? ?? const [])
        if (((attendee as Map)['emailAddress'] as Map?)?['address']
            case final String address
            when address.toLowerCase() != me?.toLowerCase())
          gcal.EventAttendee()
            ..email = address
            ..optional = attendee['type'] == 'optional',
    ];
    final showAs = json['showAs'] as String?;
    final summary = (json['subject'] as String?)?.trim();
    final priority = [
      for (final property
          in json['singleValueExtendedProperties'] as List? ?? const [])
        if ((property as Map)['id'] == _priorityProperty ||
            '${property['id']}'.endsWith('Name vivordoPriority'))
          property['value'] as String?,
    ].nonNulls.firstOrNull;
    final originalStart = json['originalStart'] as String?;
    return gcal.Event()
      ..id = 'outlook:$id'
      ..iCalUID = json['iCalUId'] as String?
      ..summary = summary == null || summary.isEmpty ? null : summary
      ..description = json['bodyPreview'] as String?
      ..location = (json['location'] as Map?)?['displayName'] as String?
      ..start = time(startText)
      ..end = time(endText)
      ..status = json['isCancelled'] == true ? 'cancelled' : 'confirmed'
      ..transparency = showAs == 'free' || showAs == 'workingElsewhere'
          ? 'transparent'
          : 'opaque'
      ..recurringEventId = switch (json['seriesMasterId']) {
        final String series => 'outlook:$series',
        _ => null,
      }
      ..recurrence = recurrenceLines(json['recurrence'] as Map?, allDay: allDay)
      ..originalStartTime = originalStart == null
          ? null
          : (gcal.EventDateTime()..dateTime = DateTime.tryParse(originalStart))
      ..extendedProperties = priority == null
          ? null
          : (gcal.EventExtendedProperties()
              ..private = {
                'vivordoPriority': 'true',
                if (priority != 'true') 'vivordoPriorityReference': priority,
              })
      ..organizer = (gcal.EventOrganizer()
        ..self = isOrganizer
        ..email = organizer?['address'] as String?
        ..displayName = organizer?['name'] as String?)
      ..hangoutLink = (json['onlineMeeting'] as Map?)?['joinUrl'] as String?
      ..conferenceData = json['isOnlineMeeting'] == true
          ? gcal.ConferenceData()
          : null
      // Graph lists only the invitees, the user among them when someone else
      // organised it, with no `self`. Listed the way Google does instead:
      // the organizer, everyone else, then the user with their reply.
      ..attendees = invitees.isEmpty && isOrganizer && response != 'declined'
          ? null
          : [
              if (!isOrganizer && organizer?['address'] is String)
                gcal.EventAttendee()
                  ..email = organizer!['address'] as String
                  ..organizer = true
                  ..responseStatus = 'accepted',
              ...invitees,
              gcal.EventAttendee()
                ..self = true
                ..organizer = isOrganizer
                ..responseStatus = switch (response) {
                  'accepted' || 'organizer' => 'accepted',
                  'tentativelyAccepted' => 'tentative',
                  'declined' => 'declined',
                  _ => 'needsAction',
                },
            ];
  }

  /// A token that can change events. The first change asks the user, once,
  /// to let Vivordo edit their calendar; until then Outlook is only read.
  static Future<String> _writeToken() async {
    final pca = await _getPca();
    try {
      final result = await pca.acquireTokenSilent(
        scopes: _writeScopes,
        authority: authority,
      );
      if (result.accessToken.isNotEmpty) return result.accessToken;
    } on MsalUiRequiredException {
      // Not allowed yet: asked for below.
    } on MsalDeclinedScopeException {
      // Not allowed yet: asked for below.
    }
    try {
      final result = await pca.acquireToken(
        scopes: _writeScopes,
        authority: authority,
      );
      if (result.accessToken.isNotEmpty) return result.accessToken;
    } on MsalUserCancelException {
      // Falls through to the message below.
    }
    throw StateError(
      'Vivordo needs permission to change your Outlook calendar.',
    );
  }

  /// One Graph request; the decoded reply, if any. Anything but a GET
  /// needs the permission to change events.
  static Future<Map<String, dynamic>?> _send(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    final token = method == 'GET' ? await _token() : await _writeToken();
    if (token == null) throw StateError('Outlook couldn’t be reached.');
    final response = await throttled(() async {
      final request = http.Request(method, uri)
        ..headers.addAll({
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Prefer': 'outlook.timezone="UTC"',
          if (body != null) 'Content-Type': 'application/json',
        });
      if (body != null) request.body = jsonEncode(body);
      return http.Response.fromStream(await request.send());
    });
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint('Outlook $method failed: ${response.body}');
      throw StateError(
        'Outlook couldn’t save that change (${response.statusCode}).',
      );
    }
    return response.body.isEmpty
        ? null
        : jsonDecode(response.body) as Map<String, dynamic>;
  }

  static String _date(DateTime day) => DateFormat('yyyy-MM-dd').format(day);

  /// Start, end and all-day as Graph takes them: wall-clock times in the
  /// device's zone (so repeats follow daylight saving), or UTC without one.
  static Map<String, dynamic> _times(
    DateTime start,
    DateTime end, {
    required bool allDay,
    required String? zone,
  }) {
    String wall(DateTime time) =>
        DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(time);
    Map<String, String> at(DateTime time) => zone == null || allDay
        ? {
            'dateTime': wall(allDay ? time : time.toUtc()),
            'timeZone': allDay ? (zone ?? 'UTC') : 'UTC',
          }
        : {'dateTime': wall(time.toLocal()), 'timeZone': zone};
    if (allDay) {
      final first = DateTime(start.year, start.month, start.day);
      final last = DateTime(end.year, end.month, end.day);
      return {
        'isAllDay': true,
        'start': at(first),
        // All-day ends are the next midnight, as with Google.
        'end': at(
          last.isAfter(first) ? last : first.add(const Duration(days: 1)),
        ),
      };
    }
    return {'isAllDay': false, 'start': at(start), 'end': at(end)};
  }

  /// A Google-style recurrence ([CalendarService.recurrenceRules]) as a
  /// Graph `patternedRecurrence`; null when it doesn't repeat.
  @visibleForTesting
  static Map<String, dynamic>? graphRecurrence(
    String recurrence,
    DateTime start, {
    String? zone,
  }) {
    final repeat = EventRepeat.parse(
      CalendarService.recurrenceRules(recurrence),
    );
    final unit = repeat.unit;
    if (unit == null) return null;
    final until = repeat.until;
    return {
      'pattern': {
        'type': switch (unit) {
          RepeatUnit.day => 'daily',
          RepeatUnit.week => 'weekly',
          RepeatUnit.month => 'absoluteMonthly',
          RepeatUnit.year => 'absoluteYearly',
        },
        'interval': repeat.interval,
        if (unit == RepeatUnit.week) ...{
          'daysOfWeek': [
            for (final day
                in repeat.weekdays.isEmpty
                    ? [start.weekday]
                    : (repeat.weekdays.toList()..sort()))
              _weekdayNames[day - 1],
          ],
          'firstDayOfWeek': 'sunday',
        },
        if (unit == RepeatUnit.month || unit == RepeatUnit.year)
          'dayOfMonth': start.day,
        if (unit == RepeatUnit.year) 'month': start.month,
      },
      'range': {
        'type': until == null ? 'noEnd' : 'endDate',
        'startDate': _date(start),
        'endDate': ?(until == null ? null : _date(until)),
        'recurrenceTimeZone': ?zone,
      },
    };
  }

  static const _weekdayNames = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  /// A Graph recurrence as Google RRULE lines, for the edit form. Monthly
  /// and yearly rules by weekday ("second Tuesday") read as plain monthly
  /// or yearly; they're only rewritten if the user changes the repeat.
  @visibleForTesting
  static List<String>? recurrenceLines(
    Map? recurrence, {
    required bool allDay,
  }) {
    final pattern = recurrence?['pattern'] as Map?;
    final range = recurrence?['range'] as Map?;
    final unit = switch (pattern?['type']) {
      'daily' => RepeatUnit.day,
      'weekly' => RepeatUnit.week,
      'absoluteMonthly' || 'relativeMonthly' => RepeatUnit.month,
      'absoluteYearly' || 'relativeYearly' => RepeatUnit.year,
      _ => null,
    };
    if (unit == null) return null;
    final endDate = range?['type'] == 'endDate'
        ? DateTime.tryParse('${range?['endDate']}')
        : null;
    return [
      EventRepeat(
        unit: unit,
        interval: (pattern?['interval'] as num?)?.toInt() ?? 1,
        weekdays: unit == RepeatUnit.week
            ? {
                for (final day in pattern?['daysOfWeek'] as List? ?? const [])
                  if (_weekdayNames.indexOf('$day') case final i when i >= 0)
                    i + 1,
              }
            : const {},
        until: endDate,
      ).recurrence(allDay: allDay),
    ];
  }

  static Future<gcal.Event> createEvent({
    required String title,
    required DateTime start,
    required DateTime end,
    required String recurrence,
    required bool allDay,
    String? calendarId,
    bool isPriority = false,
    String? priorityReference,
  }) async {
    final zone = await CalendarService.deviceTimeZone();
    final graphCalendar = calendarId == null || calendarId == 'primary'
        ? null
        : _graphId(calendarId);
    final json = await _send(
      'POST',
      _graphUri(
        graphCalendar == null
            ? '/me/events'
            : '/me/calendars/$graphCalendar/events',
      ),
      body: {
        'subject': title,
        ..._times(start, end, allDay: allDay, zone: zone),
        'recurrence': ?graphRecurrence(recurrence, start, zone: zone),
        if (isPriority)
          'singleValueExtendedProperties': [
            {'id': _priorityProperty, 'value': priorityReference ?? 'true'},
          ],
      },
    );
    CalendarService.invalidateEventCache();
    final event = toGoogleEvent(json!)!;
    if (graphCalendar != null) _eventCalendarIds[event.id!] = calendarId!;
    return event;
  }

  /// Changes [event]: a single event, one occurrence, or (given the series
  /// from [seriesFor]) the whole series. A null [title] or [recurrence]
  /// leaves it as it was.
  static Future<gcal.Event> updateEvent(
    gcal.Event event, {
    String? title,
    required DateTime start,
    required DateTime end,
    required bool allDay,
    String? recurrence,
    String? calendarId,
  }) async {
    if (calendarId != null &&
        calendarId != _eventCalendarIds[event.id] &&
        calendarId != 'primary') {
      throw StateError('Outlook events can’t move to another calendar yet.');
    }
    final zone = await CalendarService.deviceTimeZone();
    final kept = _seriesRecurrence[event.id];
    final json = await _send(
      'PATCH',
      _graphUri('/me/events/${_graphId(event.id!)}'),
      body: {
        if (title?.trim().isNotEmpty == true) 'subject': title!.trim(),
        ..._times(start, end, allDay: allDay, zone: zone),
        if (recurrence != null)
          'recurrence': graphRecurrence(recurrence, start, zone: zone)
        // A series that moved keeps its rule, starting from its new date.
        else if (kept != null)
          'recurrence': {
            ...kept,
            'range': {...?kept['range'] as Map?, 'startDate': _date(start)},
          },
      },
    );
    CalendarService.invalidateEventCache();
    return (json == null ? null : toGoogleEvent(json)) ?? event;
  }

  static Future<void> deleteEvent(String id) async {
    await _send('DELETE', _graphUri('/me/events/${_graphId(id)}'));
    CalendarService.invalidateEventCache();
  }

  /// The series [event] is one occurrence of, with its repeat rule; null
  /// when it isn't an occurrence.
  static Future<gcal.Event?> seriesFor(gcal.Event event) async {
    final seriesId = event.recurringEventId;
    if (seriesId == null) return null;
    final json = await _send(
      'GET',
      _graphUri('/me/events/${_graphId(seriesId)}', {
        r'$select': '$_eventFields,recurrence',
        r'$expand': _expandPriority,
      }),
    );
    if (json == null) return null;
    if (json['recurrence'] case final Map<String, dynamic> recurrence) {
      _seriesRecurrence[seriesId] = recurrence;
    }
    final calendar = _eventCalendarIds[event.id];
    if (calendar != null) _eventCalendarIds[seriesId] = calendar;
    return toGoogleEvent(json);
  }

  /// Ends [occurrence]'s series just before it; from the first occurrence
  /// the whole series goes.
  static Future<void> endSeriesBefore(gcal.Event occurrence) async {
    final series = await seriesFor(occurrence);
    final recurrence = _seriesRecurrence[occurrence.recurringEventId];
    final seriesStart =
        series?.start?.dateTime?.toLocal() ?? series?.start?.date;
    final occurrenceStart =
        occurrence.originalStartTime?.dateTime?.toLocal() ??
        occurrence.start?.dateTime?.toLocal() ??
        occurrence.start?.date;
    if (series?.id == null ||
        recurrence == null ||
        seriesStart == null ||
        occurrenceStart == null) {
      throw StateError('The repeating series for this event was not found.');
    }
    if (!occurrenceStart.isAfter(seriesStart)) {
      return deleteEvent(series!.id!);
    }
    await _send(
      'PATCH',
      _graphUri('/me/events/${_graphId(series!.id!)}'),
      body: {
        'recurrence': {
          ...recurrence,
          'range': {
            ...?recurrence['range'] as Map?,
            'type': 'endDate',
            'endDate': _date(
              DateTime(
                occurrenceStart.year,
                occurrenceStart.month,
                occurrenceStart.day - 1,
              ),
            ),
          },
        },
      },
    );
    CalendarService.invalidateEventCache();
  }

  /// The Outlook calendars the user owns and can add to, ids prefixed
  /// `outlook:`; [] when Outlook isn't connected.
  static Future<List<WritableCalendar>> getWritableCalendars() async {
    if (!await isSignedIn()) return const [];
    final token = await _token();
    if (token == null) return const [];
    final calendars = await _pages(
      token,
      _graphUri('/me/calendars', {
        r'$select': 'id,name,owner,isDefaultCalendar,canEdit,hexColor',
      }),
    );
    final own = ownCalendars(calendars).ids.toSet();
    return [
      for (final calendar in calendars)
        if (own.contains(calendar['id']) && calendar['canEdit'] != false)
          WritableCalendar(
            id: 'outlook:${calendar['id']}',
            name: '${calendar['name'] ?? 'Calendar'} · Outlook',
            isPrimary: calendar['isDefaultCalendar'] == true,
            colorHex: switch (calendar['hexColor']) {
              final String hex when hex.isNotEmpty => hex,
              _ => '#F4A62A',
            },
          ),
    ];
  }
}
