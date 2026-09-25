import 'dart:developer';
import 'package:flutter/foundation.dart';

/// Profile-only timings. Never attach account IDs, readings or payloads.
class PerformanceTrace {
  static const enabled =
      !kReleaseMode &&
      bool.fromEnvironment('VIVORDO_PERFORMANCE_TRACE', defaultValue: true);

  static T measure<T>(String name, T Function() action) =>
      enabled ? Timeline.timeSync('Vivordo.$name', action) : action();

  static Future<T> async<T>(String name, Future<T> Function() action) async {
    if (!enabled) return action();
    final task = TimelineTask()..start('Vivordo.$name');
    try {
      return await action();
    } finally {
      task.finish();
    }
  }
}
