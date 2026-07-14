import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:flutter/foundation.dart';

class CalendarService {
  static bool _initialized = false;
  static Future<void>? _initializationFuture;
  static GoogleSignInAccount? _currentUser;
  static final ValueNotifier<bool> connectionNotifier = ValueNotifier<bool>(false);

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
      clientId: '226030806435-d4nqtstrlhtm1cltipnat2bpo5eqn0mj.apps.googleusercontent.com',
      serverClientId: '226030806435-51d18dlptiokmfejr5irqmjefq8han4g.apps.googleusercontent.com',
    );
    GoogleSignIn.instance.authenticationEvents.listen((event) {
      switch (event) {
        case GoogleSignInAuthenticationEventSignIn():
          _currentUser = event.user;
        case GoogleSignInAuthenticationEventSignOut():
          _currentUser = null;
          connectionNotifier.value = false;
      }
    }).onError((e) => debugPrint('Auth error: $e'));

    try {
      _currentUser = await GoogleSignIn.instance.attemptLightweightAuthentication();
    } catch (e) {
      debugPrint('Silent Google sign-in failed: $e');
    }

    _initialized = true;
  }

  static Future<List<gcal.Event>> getWeekEvents(DateTime weekStart) =>
      getEventsBetween(weekStart, weekStart.add(const Duration(days: 7)));

  /// Returns the user's visible Google Calendar events between [start] and [end]
  /// (expanded recurrences, ordered by start time). Returns [] when the user
  /// hasn't connected Google Calendar or on any auth/network error.
  static Future<List<gcal.Event>> getEventsBetween(
      DateTime start, DateTime end) async {
    try {
      await initialize();

      var user = _currentUser;
      user ??= await GoogleSignIn.instance.attemptLightweightAuthentication();
      _currentUser = user;
      if (user == null) return [];

      const scopes = [gcal.CalendarApi.calendarReadonlyScope];

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

  static Future<List<gcal.Event>> connectAndGetWeekEvents(DateTime weekStart) async {
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

      const scopes = [gcal.CalendarApi.calendarReadonlyScope];

      var authorization = await user.authorizationClient
          .authorizationForScopes(scopes);
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

      const scopes = [gcal.CalendarApi.calendarReadonlyScope];
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
  }

  static Future<List<gcal.Event>> _fetchEventsFromCalendars(
    gcal.CalendarApi calendarApi, {
    required DateTime start,
    required DateTime end,
  }) async {
    final calendarList = await calendarApi.calendarList.list();
    final calendars = (calendarList.items ?? const <gcal.CalendarListEntry>[])
        .where((calendar) => calendar.id != null)
        .where((calendar) => calendar.hidden != true)
        .where((calendar) => calendar.selected != false)
        .toList();

    if (calendars.isEmpty) {
      return [];
    }

    final eventLists = await Future.wait(
      calendars.map((calendar) async {
        try {
          final events = await calendarApi.events.list(
            calendar.id!,
            timeMin: start.toUtc(),
            timeMax: end.toUtc(),
            singleEvents: true,
            orderBy: 'startTime',
          );
          return events.items ?? const <gcal.Event>[];
        } catch (e) {
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
