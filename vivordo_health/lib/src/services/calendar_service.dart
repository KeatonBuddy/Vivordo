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
    await GoogleSignIn.instance.initialize(
      clientId: '226030806435-d4nqtstrlhtm1cltipnat2bpo5eqn0mj.apps.googleusercontent.com',
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

  /// Returns the user's primary-calendar events between [start] and [end]
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

      final events = await calendarApi.events.list(
        'primary',
        timeMin: start.toUtc(),
        timeMax: end.toUtc(),
        singleEvents: true,
        orderBy: 'startTime',
      );

      connectionNotifier.value = true;
      return events.items ?? [];
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

      final events = await calendarApi.events.list(
        'primary',
        timeMin: weekStart.toUtc(),
        timeMax: weekEnd.toUtc(),
        singleEvents: true,
        orderBy: 'startTime',
      );

      connectionNotifier.value = true;
      return events.items ?? [];
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
}
