import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:msal_auth/msal_auth.dart';
import 'package:http/http.dart' as http;
import 'package:vivordo_health/src/services/calendar_service.dart';
import 'package:vivordo_health/src/utils/request_coalescer.dart';

/// Outlook (Microsoft 365 and Outlook.com) calendars through Microsoft Graph.
///
/// Events come back as [gcal.Event]s, ids prefixed `outlook:`, so everything
/// that reads Google events reads these too; [CalendarService] merges both.
/// Read-only for now: [CalendarService]'s edits refuse Outlook events.
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

  static const String _graphHost = 'graph.microsoft.com';

  /// Graph fields Vivordo reads; the rest (bodies, every attendee's
  /// details) stays on Microsoft's side.
  static const String _eventFields =
      'id,subject,start,end,isAllDay,showAs,isCancelled,responseStatus,'
      'attendees,organizer,isOrganizer,seriesMasterId,isOnlineMeeting,'
      'onlineMeeting,location,bodyPreview,iCalUId';

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
          Uri.https(_graphHost, '/v1.0/me/calendars', {
            r'$select': 'id,owner,isDefaultCalendar',
          }),
        ),
      );
      final perCalendar = await Future.wait(
        ids.map((id) async {
          try {
            return await _pages(
              token,
              Uri.https(_graphHost, '/v1.0/me/calendars/$id/calendarView', {
                'startDateTime': start.toUtc().toIso8601String(),
                'endDateTime': end.toUtc().toIso8601String(),
                r'$select': _eventFields,
                r'$top': '100',
              }),
            );
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

  /// Every item of a Graph collection, following `@odata.nextLink` so a busy
  /// range isn't cut off at the first page. Throws on any failed page.
  static Future<List<Map<String, dynamic>>> _pages(
    String token,
    Uri first,
  ) async {
    final items = <Map<String, dynamic>>[];
    Uri? page = first;
    while (page != null) {
      final response = await http.get(
        page,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          // Times come back in UTC, written without a zone.
          'Prefer': 'outlook.timezone="UTC"',
        },
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
}
