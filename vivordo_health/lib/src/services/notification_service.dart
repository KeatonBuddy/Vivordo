import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:vivordo_health/main.dart' show navigatorKey;

/// Function to handle background messages
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Handling background message: ${message.messageId}');
}

/// Notification Service - Singleton pattern for managing FCM notifications
/// Handles iOS push notifications using Firebase Cloud Messaging
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  static const int _dailyScanReminderMorningId = 1001;
  static const int _dailyScanReminderEveningId = 1002;
  static const int _calendarCheckInReminderId = 1101;

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  /// Initialize the notification service
  /// Should be called once in main() after Firebase.initializeApp()
  Future<void> initialize() async {
    if (_isInitialized) return;

    if (kIsWeb) {
      print(
        'NotificationService: Web platform detected, skipping initialization',
      );
      _isInitialized = true;
      return;
    }

    try {
      tz.initializeTimeZones();
      final deviceTimeZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(deviceTimeZone.identifier));
      print(
        'NotificationService: Local timezone set to ${deviceTimeZone.identifier}',
      );

      // Request IOS permissions
      if (Platform.isIOS) {
        NotificationSettings settings = await _firebaseMessaging
            .requestPermission(
              alert: true,
              badge: true,
              sound: true,
              provisional: false,
            );

        print(
          'NotificationService: Permission status: ${settings.authorizationStatus}',
        );

        if (settings.authorizationStatus == AuthorizationStatus.authorized) {
          print('NotificationService: User granted permission');
        } else if (settings.authorizationStatus ==
            AuthorizationStatus.provisional) {
          print('NotificationService: User granted provisional permission');
        } else {
          print(
            'NotificationService: User declined or has not accepted permission',
          );
        }
      }

      // Initialize Local Notifications Plugin
      const DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
            requestSoundPermission: true,
            requestBadgePermission: true,
            requestAlertPermission: true,
          );

      const InitializationSettings initializationSettings =
          InitializationSettings(iOS: initializationSettingsIOS);

      await _localNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Remove the temporary notification used while testing scheduling.
      await _localNotificationsPlugin.cancel(1003);

      final launchDetails = await _localNotificationsPlugin
          .getNotificationAppLaunchDetails();
      final launchResponse = launchDetails?.notificationResponse;
      if (launchDetails?.didNotificationLaunchApp == true &&
          launchResponse != null) {
        _onNotificationTapped(launchResponse);
      }

      // Listen for token refresh
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        print('NotificationService: FCM Token refreshed: $newToken');
      });

      // Get and log FCM token after APNs token is available on iOS.
      try {
        if (Platform.isIOS) {
          String? apnsToken;

          for (int attempt = 1; attempt <= 10; attempt++) {
            apnsToken = await _firebaseMessaging.getAPNSToken();

            if (apnsToken != null) {
              print('NotificationService: APNs Token received: $apnsToken');
              break;
            }

            print(
              'NotificationService: APNs token not available yet, retrying ($attempt/10)',
            );
            await Future.delayed(const Duration(seconds: 1));
          }

          if (apnsToken == null) {
            print(
              'NotificationService: Warning - APNs token still unavailable; skipping FCM token for now',
            );
          } else {
            final token = await _firebaseMessaging.getToken();
            print('NotificationService: FCM Token: $token');
          }
        } else {
          final token = await _firebaseMessaging.getToken();
          print('NotificationService: FCM Token: $token');
        }
      } catch (e) {
        print('NotificationService: Warning - Could not get FCM token: $e');
      }

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle background messages
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      // Handle notification tap when app is in background but not terminated
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // Check if app was opened from a terminated state by tapping notification
      RemoteMessage? initialMessage = await _firebaseMessaging
          .getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationTap(initialMessage);
      }

      _isInitialized = true;
      print('NotificationService: Initialization complete');
    } catch (e) {
      print('NotificationService: Error during initialization: $e');
    }
  }

  /// Handle foreground messages by showing local notification
  void _handleForegroundMessage(RemoteMessage message) {
    print(
      'NotificationService: Foreground message received: ${message.messageId}',
    );

    if (message.notification != null) {
      showLocalNotification(
        title: message.notification?.title ?? 'New Notification',
        body: message.notification?.body ?? '',
        payload: message.data.toString(),
      );
    }
  }

  /// Handle notification tap
  void _handleNotificationTap(RemoteMessage message) {
    print('NotificationService: Notification tapped, data: ${message.data}');
    _navigateToNotificationScreen(message.data['screen'] as String?);
  }

  /// Handle local notification tap
  void _onNotificationTapped(NotificationResponse response) {
    print(
      'NotificationService: Local notification tapped, payload: ${response.payload}',
    );

    String? screen;
    final payload = response.payload;
    if (payload != null) {
      try {
        final data = jsonDecode(payload) as Map<String, dynamic>;
        screen = data['screen'] as String?;
      } catch (e) {
        print('NotificationService: Invalid notification payload: $e');
      }
    }

    _navigateToNotificationScreen(screen);
  }

  void _navigateToNotificationScreen(String? screen) {
    final route = screen == 'ai_chat' ? '/ai-chat' : '/home';
    final navigator = navigatorKey.currentState;
    if (navigator != null) {
      navigator.pushNamedAndRemoveUntil(route, (route) => false);
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        route,
        (route) => false,
      );
    });
  }

  /// Show a local notification for testing purposes
  Future<void> showTestNotification() async {
    await showLocalNotification(
      title: 'Test Notification',
      body: 'This is a test notification from Vivordo Health',
      payload: '{"screen": "home"}',
    );
  }

  /// Show a notification when a new goal is created
  Future<void> showGoalCreatedNotification(String goalTitle) async {
    await showLocalNotification(
      title: 'Goal Created! 🎯',
      body: 'Successfully added: "$goalTitle". Let\'s get to work!',
      payload: '{"screen": "goals"}',
    );
  }

  /// Show a local notification
  /// Used to display notifications when app is in foreground
  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (kIsWeb) {
      print('NotificationService: Cannot show local notification on web');
      return;
    }

    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          presentBanner: true,
          presentList: true,
        );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      iOS: iOSPlatformChannelSpecifics,
    );

    await _localNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      platformChannelSpecifics,
      payload: payload,
    );

    print('NotificationService: Local notification shown - $title');
  }

  /// Schedule a daily scan reminder notification.
  Future<void> scheduleDailyScanReminder({
    int hour = 9,
    int minute = 0,
    int notificationId = _dailyScanReminderMorningId,
  }) async {
    if (kIsWeb) {
      print('NotificationService: Cannot schedule daily scan reminder on web');
      return;
    }

    final now = tz.TZDateTime.now(tz.local);
    var scheduledTime = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduledTime.isBefore(now)) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }

    const DarwinNotificationDetails iOSDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      presentBanner: true,
      presentList: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      iOS: iOSDetails,
    );

    await _localNotificationsPlugin.zonedSchedule(
      notificationId,
      'Time for your daily scan',
      'Take a quick Vivordo scan to keep your stress insights updated.',
      scheduledTime,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: '{"screen": "home", "type": "daily_scan_reminder"}',
    );

    print(
      'NotificationService: Daily scan reminder $notificationId scheduled for '
      '$scheduledTime',
    );
  }

  /// Cancel the daily scan reminder notification.
  Future<void> cancelDailyScanReminder() async {
    if (kIsWeb) return;

    await _localNotificationsPlugin.cancel(_dailyScanReminderMorningId);
    await _localNotificationsPlugin.cancel(_dailyScanReminderEveningId);
    print('NotificationService: Daily scan reminder canceled');
  }

  /// Schedule a check-in when today's final calendar event ends.
  Future<void> scheduleCalendarCheckIn(DateTime eventEnd) async {
    if (kIsWeb) return;

    await _localNotificationsPlugin.cancel(_calendarCheckInReminderId);

    final scheduledTime = tz.TZDateTime.from(eventEnd, tz.local);
    if (!scheduledTime.isAfter(tz.TZDateTime.now(tz.local))) {
      print('NotificationService: Final calendar event has already ended');
      return;
    }

    const notificationDetails = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        presentBanner: true,
        presentList: true,
      ),
    );

    await _localNotificationsPlugin.zonedSchedule(
      _calendarCheckInReminderId,
      'Time for your daily check-in',
      'Your calendar is clear. Check in with Vivordo about your day.',
      scheduledTime,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: '{"screen": "ai_chat", "type": "calendar_check_in"}',
    );

    print(
      'NotificationService: Calendar check-in scheduled for $scheduledTime',
    );
  }

  Future<void> cancelCalendarCheckIn() async {
    if (kIsWeb) return;
    await _localNotificationsPlugin.cancel(_calendarCheckInReminderId);
  }

  /// Get the current FCM token
  Future<String?> getToken() async {
    if (kIsWeb) return null;
    return await _firebaseMessaging.getToken();
  }

  /// Subscribe to a topic
  Future<void> subscribeToTopic(String topic) async {
    if (kIsWeb) return;
    await _firebaseMessaging.subscribeToTopic(topic);
    print('NotificationService: Subscribed to topic: $topic');
  }

  /// Unsubscribe from a topic
  Future<void> unsubscribeFromTopic(String topic) async {
    if (kIsWeb) return;
    await _firebaseMessaging.unsubscribeFromTopic(topic);
    print('NotificationService: Unsubscribed from topic: $topic');
  }
}
