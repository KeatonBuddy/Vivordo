import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridges the active workout to ActivityKit on supported iPhones.
///
/// The elapsed timer is rendered from [startedAt] by iOS, so it remains
/// accurate while Flutter is suspended and does not require per-second calls.
class WorkoutLiveActivityService {
  const WorkoutLiveActivityService._();

  static const _channel = MethodChannel('com.vivordo.health/workout_activity');

  static bool get _isSupportedPlatform =>
      defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> configureLaunchHandler(
    Future<void> Function() onWorkoutLaunch,
  ) async {
    if (!_isSupportedPlatform) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'workoutActivityTapped') {
        await onWorkoutLaunch();
      }
    });

    try {
      final shouldOpen =
          await _channel.invokeMethod<bool>('consumeWorkoutLaunch') ?? false;
      if (shouldOpen) await onWorkoutLaunch();
    } on PlatformException catch (error) {
      debugPrint('Workout Live Activity launch could not be consumed: $error');
    } on MissingPluginException {
      // Expected on non-iOS test hosts and until a native rebuild completes.
    }
  }

  static void clearLaunchHandler() {
    if (!_isSupportedPlatform) return;
    _channel.setMethodCallHandler(null);
  }

  static Future<void> start({
    required DateTime startedAt,
    required String title,
    required int exerciseCount,
  }) async {
    if (!_isSupportedPlatform) return;
    try {
      await _channel.invokeMethod<void>('start', {
        'startedAt': startedAt.millisecondsSinceEpoch,
        'title': title,
        'exerciseCount': exerciseCount,
      });
    } on PlatformException catch (error) {
      debugPrint('Workout Live Activity could not start: $error');
    } on MissingPluginException {
      // Expected on non-iOS test hosts and during a stale hot-reload session.
    }
  }

  static Future<void> update({
    required String title,
    required int exerciseCount,
  }) async {
    if (!_isSupportedPlatform) return;
    try {
      await _channel.invokeMethod<void>('update', {
        'title': title,
        'exerciseCount': exerciseCount,
      });
    } on PlatformException catch (error) {
      debugPrint('Workout Live Activity could not update: $error');
    } on MissingPluginException {
      // Expected on non-iOS test hosts and during a stale hot-reload session.
    }
  }

  static Future<void> end() async {
    if (!_isSupportedPlatform) return;
    try {
      await _channel.invokeMethod<void>('end');
    } on PlatformException catch (error) {
      debugPrint('Workout Live Activity could not end: $error');
    } on MissingPluginException {
      // Expected on non-iOS test hosts and during a stale hot-reload session.
    }
  }
}
