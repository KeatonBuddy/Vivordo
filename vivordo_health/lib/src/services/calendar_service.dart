import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:vivordo_health/src/utils/event_repeat.dart';
import 'package:vivordo_health/src/utils/request_coalescer.dart';

class WritableCalendar {
  const WritableCalendar({
    required this.id,
    required this.name,
    required this.isPrimary,
    this.colorHex,
  });

  final String id;
  final String name;
  final bool isPrimary;
  final String? colorHex;
}

class CalendarService {
  /// Window in which an identical range request is reused. Short on purpose:
  /// long enough to collapse the burst when several screens and the home
  /// widget load together, short enough that a change made in Google Calendar
  /// itself shows up quickly.
  static const _eventCacheTtl = Duration(seconds: 30);

  static final RequestCoalescer<List<gcal.Event>> _eventRequests =
      RequestCoalescer<List<gcal.Event>>(ttl: _eventCacheTtl);

  /// Drops cached ranges after a local edit, deletion or account change.
  static void invalidateEventCache() {
    _eventRequests.invalidateAll();
    eventsChanged.value++;
  }

  /// Bumped whenever the events may have changed, from any screen or Vivordo
  /// AI, so open screens can reload their schedule.
  static final ValueNotifier<int> eventsChanged = ValueNotifier<int>(0);

  /// Silent, all-or-nothing fetch for scoring. Null means unavailable, while
  /// an empty list means a successful fetch with no events.
  static Future<List<gcal.Event>?> getScoringEvents(
    DateTime start,
    DateTime end,
  ) async {
    try {
      await initialize();
      final user = _currentUser;
      if (user == null) return null;
      const scopes = [gcal.CalendarApi.calendarScope];
      final authorization = await user.authorizationClient
          .authorizationForScopes(scopes);
      if (authorization == null) return null;
      final client = authorization.authClient(scopes: scopes);
      try {
        return await _fetchEventsFromCalendars(
          gcal.CalendarApi(client),
          start: start,
          end: end,
          requireComplete: true,
        );
      } finally {
        client.close();
      }
    } catch (_) {
      return null;
    }
  }

  static bool _initialized = false;
  static Future<void>? _initializationFuture;
  static GoogleSignInAccount? _currentUser;
  static final ValueNotifier<bool> connectionNotifier = ValueNotifier<bool>(
    false,
  );
  static final Map<String, String> _eventCalendarIds = <String, String>{};

  static String? _calendarIdFor(gcal.Event event) =>
      event.id == null ? null : _eventCalendarIds[event.id!];

  static String? calendarIdForEvent(gcal.Event event) => _calendarIdFor(event);

  /// Records the account returned directly by an interactive Google sign-in.
  /// This avoids waiting for the asynchronous authentication event before
  /// screens that depend on Google Calendar are built.
  static void registerSignedInAccount(GoogleSignInAccount account) {
    _currentUser = account;
  }

  /// Requests Calendar access for the currently authenticated Google account.
  /// Google identity sign-in and Calendar authorization are separate grants.
  static Future<bool> authorizeCalendarAccess() async {
    try {
      await initialize();
      var user = _currentUser;
      user ??= await GoogleSignIn.instance.attemptLightweightAuthentication();
      _currentUser = user;
      if (user == null) return false;

      const scopes = [gcal.CalendarApi.calendarScope];
      var authorization = await user.authorizationClient.authorizationForScopes(
        scopes,
      );
      authorization ??= await user.authorizationClient.authorizeScopes(scopes);
      connectionNotifier.value = true;
      return true;
    } catch (e) {
      debugPrint('Calendar authorization failed: $e');
      connectionNotifier.value = false;
      return false;
    }
  }

  static Future<gcal.CalendarApi> _authorizedCalendarApi() async {
    await initialize();
    var user = _currentUser;
    user ??= await GoogleSignIn.instance.attemptLightweightAuthentication();
    _currentUser = user;
    if (user == null) throw StateError('Google Calendar is not connected.');

    const scopes = [gcal.CalendarApi.calendarScope];
    var authorization = await user.authorizationClient.authorizationForScopes(
      scopes,
    );
    authorization ??= await user.authorizationClient.authorizeScopes(scopes);
    return gcal.CalendarApi(authorization.authClient(scopes: scopes));
  }

  /// Deletes [event]. For one occurrence of a repeating event, [scope] can
  /// widen that to the occurrences after it or to the whole series.
  static Future<void> deleteEvent(
    gcal.Event event, {
    EventScope scope = EventScope.thisEvent,
  }) async {
    if (scope == EventScope.thisAndFollowing &&
        event.recurringEventId != null) {
      return _endSeriesBefore(event);
    }
    final calendarId = _calendarIdFor(event);
    final eventId = scope == EventScope.allEvents
        ? event.recurringEventId ?? event.id
        : event.id;
    if (calendarId == null || eventId == null) {
      throw StateError(
        'This event cannot be removed because its calendar is unknown.',
      );
    }
    final calendarApi = await _authorizedCalendarApi();
    await calendarApi.events.delete(calendarId, eventId);
    _eventCalendarIds.remove(eventId);
    invalidateEventCache();
  }

  static Future<List<WritableCalendar>> getWritableCalendars() async {
    final calendarApi = await _authorizedCalendarApi();
    final calendars = <WritableCalendar>[];
    String? pageToken;
    do {
      final page = await calendarApi.calendarList.list(pageToken: pageToken);
      for (final entry in page.items ?? const <gcal.CalendarListEntry>[]) {
        final id = entry.id;
        final role = entry.accessRole;
        if (id == null || (role != 'owner' && role != 'writer')) continue;
        calendars.add(
          WritableCalendar(
            id: id,
            name: entry.summary?.trim().isNotEmpty == true
                ? entry.summary!.trim()
                : 'Untitled calendar',
            isPrimary: entry.primary == true,
            colorHex: entry.backgroundColor,
          ),
        );
      }
      pageToken = page.nextPageToken;
    } while (pageToken != null && pageToken.isNotEmpty);

    calendars.sort((a, b) {
      if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return calendars;
  }

  /// Google recurrence lines for [recurrence]: an `RRULE:` line from the
  /// event form, or the older 'daily' / 'weekly' / 'monthly' /
  /// 'weekly:MO,WE' names, optionally ending ';until=yyyyMMdd', that
  /// priorities and Panda use. Anything else does not repeat.
  static List<String> recurrenceRules(String recurrence) {
    if (recurrence.startsWith('RRULE:')) return [recurrence];
    final parts = recurrence.split(';until=');
    final base = parts.first;
    final until = parts.length > 1 ? ';UNTIL=${parts[1]}T235959Z' : '';
    final weeklyDays = base.startsWith('weekly:')
        ? base.substring('weekly:'.length)
        : '';
    return switch (base) {
      'daily' => ['RRULE:FREQ=DAILY$until'],
      'weekly' => ['RRULE:FREQ=WEEKLY$until'],
      'monthly' => ['RRULE:FREQ=MONTHLY$until'],
      _ when weeklyDays.isNotEmpty => [
        'RRULE:FREQ=WEEKLY;BYDAY=$weeklyDays$until',
      ],
      _ => <String>[],
    };
  }

  /// The device's IANA zone. Google rejects repeating timed events whose
  /// start has no zone, and uses it to expand repeats across DST.
  static Future<String?> _deviceTimeZone() async {
    try {
      return (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      return null;
    }
  }

  static Future<gcal.Event> createEvent({
    required String title,
    required DateTime start,
    required DateTime end,
    required String recurrence,
    bool isAllDay = false,
    String calendarId = 'primary',
    bool isPriority = false,
    String? priorityReference,
  }) async {
    if (!end.isAfter(start)) {
      throw ArgumentError('The end time must be after the start time.');
    }

    final zone = isAllDay ? null : await _deviceTimeZone();
    final event = gcal.Event()
      ..summary = title
      ..start = (gcal.EventDateTime()
        ..dateTime = isAllDay ? null : start.toUtc()
        ..date = isAllDay ? DateTime(start.year, start.month, start.day) : null
        ..timeZone = zone)
      ..end = (gcal.EventDateTime()
        ..dateTime = isAllDay ? null : end.toUtc()
        ..date = isAllDay ? DateTime(end.year, end.month, end.day) : null
        ..timeZone = zone)
      ..recurrence = recurrenceRules(recurrence)
      ..extendedProperties = isPriority
          ? (gcal.EventExtendedProperties()
              ..private = {
                'vivordoPriority': 'true',
                'vivordoPriorityReference': ?priorityReference,
              })
          : null;

    final calendarApi = await _authorizedCalendarApi();
    final result = await calendarApi.events.insert(event, calendarId);
    if (result.id != null) _eventCalendarIds[result.id!] = calendarId;
    invalidateEventCache();
    return result;
  }

  static Future<gcal.Event> updateEventTimeAndRecurrence(
    gcal.Event event, {
    required DateTime start,
    required DateTime end,
    required String recurrence,
  }) async {
    final calendarId = _calendarIdFor(event);
    final eventId = event.id;
    if (calendarId == null || eventId == null) {
      throw StateError(
        'This event cannot be edited because its calendar is unknown.',
      );
    }
    if (!end.isAfter(start)) {
      throw ArgumentError('The end time must be after the start time.');
    }

    final zone = event.start?.timeZone ?? await _deviceTimeZone();
    final updated = gcal.Event()
      ..start = (gcal.EventDateTime()
        ..dateTime = start.toUtc()
        ..timeZone = zone)
      ..end = (gcal.EventDateTime()
        ..dateTime = end.toUtc()
        ..timeZone = event.end?.timeZone ?? zone)
      ..recurrence = recurrenceRules(recurrence);

    final calendarApi = await _authorizedCalendarApi();
    final result = await calendarApi.events.patch(updated, calendarId, eventId);
    if (result.id != null) _eventCalendarIds[result.id!] = calendarId;
    invalidateEventCache();
    return result;
  }

  /// Ends [occurrence]'s series just before it, keeping earlier occurrences.
  /// From the first occurrence nothing would remain, so the series goes.
  static Future<void> _endSeriesBefore(gcal.Event occurrence) async {
    final series = await seriesFor(occurrence);
    final seriesStart = _startOf(series);
    final occurrenceStart = _occurrenceStart(occurrence);
    final calendarId = _calendarIdFor(occurrence);
    if (series?.id == null || seriesStart == null || occurrenceStart == null) {
      throw StateError('The repeating series for this event was not found.');
    }
    if (!occurrenceStart.isAfter(seriesStart)) {
      return deleteEvent(occurrence, scope: EventScope.allEvents);
    }
    final allDay = series!.start?.dateTime == null;
    final updated = gcal.Event()
      ..recurrence = [
        for (final line in series.recurrence ?? const <String>[])
          line.toUpperCase().startsWith('RRULE:')
              ? endRuleBefore(line, occurrenceStart, allDay: allDay)
              : line,
      ];
    if (!allDay && series.start?.timeZone == null) {
      // Google rejects a repeating timed event without a zone.
      final zone = await _deviceTimeZone();
      updated
        ..start = (gcal.EventDateTime()
          ..dateTime = series.start?.dateTime
          ..timeZone = zone)
        ..end = (gcal.EventDateTime()
          ..dateTime = series.end?.dateTime
          ..timeZone = zone);
    }
    final api = await _authorizedCalendarApi();
    await api.events.patch(updated, calendarId!, series.id!);
    invalidateEventCache();
  }

  static DateTime? _startOf(gcal.Event? event) =>
      event?.start?.dateTime?.toLocal() ?? event?.start?.date?.toLocal();

  /// Where [occurrence] sat in its series, even if it was moved since.
  static DateTime? _occurrenceStart(gcal.Event occurrence) =>
      occurrence.originalStartTime?.dateTime?.toLocal() ??
      occurrence.originalStartTime?.date?.toLocal() ??
      _startOf(occurrence);

  /// The repeating series [event] is one occurrence of, or null when it is
  /// not an occurrence. Occurrences do not carry the series' RRULE.
  static Future<gcal.Event?> seriesFor(gcal.Event event) async {
    final seriesId = event.recurringEventId;
    final calendarId = _calendarIdFor(event);
    if (seriesId == null || calendarId == null) return null;
    final api = await _authorizedCalendarApi();
    final series = await api.events.get(calendarId, seriesId);
    _eventCalendarIds[seriesId] = calendarId;
    return series;
  }

  /// Where the series starts and ends after one occurrence moves from
  /// [occurrenceStart] to [start]..[end]: every occurrence shifts by the same
  /// amount and takes the new length.
  static (DateTime, DateTime) shiftSeries({
    required DateTime seriesStart,
    required DateTime occurrenceStart,
    required DateTime start,
    required DateTime end,
  }) {
    final shifted = seriesStart.add(start.difference(occurrenceStart));
    return (shifted, shifted.add(end.difference(start)));
  }

  /// Updates the fields Panda is allowed to propose. Null fields are preserved.
  /// With [allEvents], an occurrence's changes go to its whole series.
  static Future<gcal.Event> updateEvent(
    gcal.Event event, {
    String? title,
    DateTime? start,
    DateTime? end,
    String? recurrence,
    String? calendarId,
    bool? isAllDay,
    bool allEvents = false,
  }) async {
    if (allEvents && event.recurringEventId != null) {
      final series = await seriesFor(event);
      final seriesStart = _startOf(series);
      final occurrenceStart = _occurrenceStart(event);
      if (series == null || seriesStart == null || occurrenceStart == null) {
        throw StateError('The repeating series for this event was not found.');
      }
      final times = start == null || end == null
          ? null
          : shiftSeries(
              seriesStart: seriesStart,
              occurrenceStart: occurrenceStart,
              start: start,
              end: end,
            );
      return updateEvent(
        series,
        title: title,
        start: times?.$1,
        end: times?.$2,
        recurrence: recurrence,
        calendarId: calendarId,
        isAllDay: isAllDay,
      );
    }
    final sourceCalendarId = _calendarIdFor(event);
    final eventId = event.id;
    if (sourceCalendarId == null || eventId == null) {
      throw StateError(
        'This event cannot be edited because its calendar is unknown.',
      );
    }
    final originalIsAllDay =
        event.start?.dateTime == null && event.start?.date != null;
    final nextIsAllDay = isAllDay ?? originalIsAllDay;
    final originalStart =
        event.start?.dateTime?.toLocal() ?? event.start?.date?.toLocal();
    final originalEnd =
        event.end?.dateTime?.toLocal() ?? event.end?.date?.toLocal();
    final nextStart = start ?? originalStart;
    final nextEnd = end ?? originalEnd;
    if (nextStart == null || nextEnd == null || !nextEnd.isAfter(nextStart)) {
      throw ArgumentError('The event must have a valid start and end time.');
    }
    final updated = gcal.Event()
      ..summary = title?.trim().isNotEmpty == true ? title!.trim() : null;
    if (nextIsAllDay) {
      updated
        ..start = (gcal.EventDateTime()
          ..date = DateTime(nextStart.year, nextStart.month, nextStart.day))
        ..end = (gcal.EventDateTime()
          ..date = DateTime(nextEnd.year, nextEnd.month, nextEnd.day));
    } else {
      final zone = event.start?.timeZone ?? await _deviceTimeZone();
      updated
        ..start = (gcal.EventDateTime()
          ..dateTime = nextStart.toUtc()
          ..timeZone = zone)
        ..end = (gcal.EventDateTime()
          ..dateTime = nextEnd.toUtc()
          ..timeZone = event.end?.timeZone ?? zone);
    }
    if (recurrence != null) updated.recurrence = recurrenceRules(recurrence);
    final api = await _authorizedCalendarApi();
    var result = await api.events.patch(updated, sourceCalendarId, eventId);
    final destinationCalendarId = calendarId;
    if (destinationCalendarId != null &&
        destinationCalendarId != sourceCalendarId) {
      result = await api.events.move(
        sourceCalendarId,
        eventId,
        destinationCalendarId,
      );
    }
    if (result.id != null) {
      _eventCalendarIds[result.id!] = destinationCalendarId ?? sourceCalendarId;
    }
    invalidateEventCache();
    return result;
  }

  static Future<void> initialize() async {
    if (_initialized) return;
    if (_initializationFuture != null) return _initializationFuture!;

    _initializationFuture = _initialize();
    try {
      await _initializationFuture;
    } finally {
      _initializationFuture = null;
    }
  }

  static Future<void> _initialize() async {
    // GoogleSignIn.instance is a singleton — this is the one place it gets
    // initialized for the whole app (AuthService.signInWithGoogle reuses it
    // via this same initialize() call rather than calling initialize() a
    // second time, which google_sign_in doesn't support).
    // serverClientId (the Android/web OAuth client, not the iOS one above)
    // is what makes GoogleSignInAccount.authentication.idToken come back
    // non-null — without it, Firebase's GoogleAuthProvider.credential(idToken:)
    // sign-in has nothing to authenticate with, especially on Android.
    await GoogleSignIn.instance.initialize(
      clientId:
          '226030806435-7a9a6m45j21jaefhduqf4ikqc1m81olu.apps.googleusercontent.com',
      serverClientId:
          '226030806435-51d18dlptiokmfejr5irqmjefq8han4g.apps.googleusercontent.com',
    );
    GoogleSignIn.instance.authenticationEvents
        .listen((event) {
          switch (event) {
            case GoogleSignInAuthenticationEventSignIn():
              final previous = _currentUser?.id;
              _currentUser = event.user;
              // Anything cached belonged to whoever was signed in before.
              if (previous != event.user.id) invalidateEventCache();
            case GoogleSignInAuthenticationEventSignOut():
              _currentUser = null;
              connectionNotifier.value = false;
              invalidateEventCache();
          }
        })
        .onError((e) => debugPrint('Auth error: $e'));

    try {
      _currentUser = await GoogleSignIn.instance
          .attemptLightweightAuthentication();
    } catch (e) {
      debugPrint('Silent Google sign-in failed: $e');
    }

    _initialized = true;
  }

  static Future<List<gcal.Event>> getWeekEvents(
    DateTime weekStart, {
    bool forceRefresh = false,
  }) => getEventsBetween(
    weekStart,
    weekStart.add(const Duration(days: 7)),
    forceRefresh: forceRefresh,
  );

  /// Returns the user's visible Google Calendar events between [start] and [end]
  /// (expanded recurrences, ordered by start time). Returns [] when the user
  /// hasn't connected Google Calendar or on any auth/network error.
  ///
  /// Several screens and the home widget ask for the same range at once, so
  /// identical requests are coalesced and the result is reused briefly. Pass
  /// [forceRefresh] for a pull-to-refresh, which always reaches the network.
  static Future<List<gcal.Event>> getEventsBetween(
    DateTime start,
    DateTime end, {
    bool forceRefresh = false,
  }) => _eventRequests.run(
    _eventCacheKey(start, end),
    () => _fetchEventsBetween(start, end),
    forceRefresh: forceRefresh,
  );

  /// Cache key for a range, scoped to the signed-in Google account so one
  /// account can never be served another's events. The auth listener also
  /// clears the cache outright; this is the second line of defence for the
  /// window before a sign-in event is observed.
  static String _eventCacheKey(DateTime start, DateTime end) =>
      '${_currentUser?.id ?? 'signed-out'}'
      '|${start.toIso8601String()}|${end.toIso8601String()}';

  static Future<List<gcal.Event>> _fetchEventsBetween(
    DateTime start,
    DateTime end,
  ) async {
    try {
      await initialize();

      var user = _currentUser;
      user ??= await GoogleSignIn.instance.attemptLightweightAuthentication();
      _currentUser = user;
      if (user == null) return [];

      const scopes = [gcal.CalendarApi.calendarScope];

      final authorization = await user.authorizationClient
          .authorizationForScopes(scopes);

      if (authorization == null) {
        connectionNotifier.value = false;
        return [];
      }

      final client = authorization.authClient(scopes: scopes);
      final calendarApi = gcal.CalendarApi(client);

      final events = await _fetchEventsFromCalendars(
        calendarApi,
        start: start,
        end: end,
      );

      connectionNotifier.value = true;
      return events;
    } catch (e) {
      debugPrint('CalendarService error: $e');
      return [];
    }
  }

  static Future<List<gcal.Event>> connectAndGetWeekEvents(
    DateTime weekStart,
  ) async {
    try {
      await initialize();

      if (_currentUser == null) {
        if (GoogleSignIn.instance.supportsAuthenticate()) {
          _currentUser = await GoogleSignIn.instance.authenticate();
        } else {
          return [];
        }
      }

      final user = _currentUser;
      if (user == null) return [];

      const scopes = [gcal.CalendarApi.calendarScope];

      var authorization = await user.authorizationClient.authorizationForScopes(
        scopes,
      );
      authorization ??= await user.authorizationClient.authorizeScopes(scopes);

      final client = authorization.authClient(scopes: scopes);
      final calendarApi = gcal.CalendarApi(client);
      final weekEnd = weekStart.add(const Duration(days: 7));

      final events = await _fetchEventsFromCalendars(
        calendarApi,
        start: weekStart,
        end: weekEnd,
      );

      connectionNotifier.value = true;
      return events;
    } catch (e) {
      debugPrint('CalendarService connect error: $e');
      return [];
    }
  }

  static Future<bool> isSignedIn() async {
    await initialize();
    _currentUser ??= await GoogleSignIn.instance
        .attemptLightweightAuthentication();
    return _currentUser != null;
  }

  static Future<bool> hasCalendarAccess() async {
    try {
      await initialize();

      var user = _currentUser;
      user ??= await GoogleSignIn.instance.attemptLightweightAuthentication();
      _currentUser = user;
      if (user == null) {
        connectionNotifier.value = false;
        return false;
      }

      const scopes = [gcal.CalendarApi.calendarScope];
      final authorization = await user.authorizationClient
          .authorizationForScopes(scopes);
      final hasAccess = authorization != null;
      connectionNotifier.value = hasAccess;
      return hasAccess;
    } catch (e) {
      debugPrint('CalendarService access check error: $e');
      connectionNotifier.value = false;
      return false;
    }
  }

  static Future<void> signOut() async {
    await initialize();
    await GoogleSignIn.instance.disconnect();
    _currentUser = null;
    connectionNotifier.value = false;
    invalidateEventCache();
  }

  static Future<List<gcal.Event>> _fetchEventsFromCalendars(
    gcal.CalendarApi calendarApi, {
    required DateTime start,
    required DateTime end,
    bool requireComplete = false,
  }) async {
    final entries = <gcal.CalendarListEntry>[];
    String? calendarPage;
    do {
      final page = await calendarApi.calendarList.list(pageToken: calendarPage);
      entries.addAll(page.items ?? const []);
      calendarPage = page.nextPageToken;
    } while (calendarPage != null && calendarPage.isNotEmpty);
    final calendars = entries
        .where((calendar) => calendar.id != null)
        .where((calendar) => calendar.hidden != true)
        // Google omits `selected` when a calendar is not selected. Requiring an
        // explicit true keeps Vivordo aligned with the calendars visible in the
        // user's Google Calendar sidebar instead of treating null as selected.
        .where((calendar) => calendar.selected == true)
        .toList();

    if (calendars.isEmpty) {
      return [];
    }

    final eventLists = await Future.wait(
      calendars.map((calendar) async {
        try {
          final items = <gcal.Event>[];
          String? eventPage;
          do {
            final events = await calendarApi.events.list(
              calendar.id!,
              timeMin: start.toUtc(),
              timeMax: end.toUtc(),
              singleEvents: true,
              orderBy: 'startTime',
              pageToken: eventPage,
            );
            items.addAll(events.items ?? const []);
            eventPage = events.nextPageToken;
          } while (eventPage != null && eventPage.isNotEmpty);
          for (final event in items) {
            if (event.id != null) _eventCalendarIds[event.id!] = calendar.id!;
          }
          return items;
        } catch (e) {
          if (requireComplete) rethrow;
          debugPrint(
            'CalendarService calendar fetch skipped ${calendar.summary ?? calendar.id}: $e',
          );
          return const <gcal.Event>[];
        }
      }),
    );

    final events = eventLists.expand((items) => items).toList();
    events.sort((a, b) {
      final aStart = a.start?.dateTime ?? a.start?.date;
      final bStart = b.start?.dateTime ?? b.start?.date;

      if (aStart == null && bStart == null) return 0;
      if (aStart == null) return 1;
      if (bStart == null) return -1;
      return aStart.compareTo(bStart);
    });

    return events;
  }
}

/// Which part of a repeating event a change applies to.
enum EventScope { thisEvent, thisAndFollowing, allEvents }
