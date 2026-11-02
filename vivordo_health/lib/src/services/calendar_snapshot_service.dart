import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:path_provider/path_provider.dart';

/// Today's calendar as last fetched, kept on the phone so My Day can show
/// the schedule at launch while the live one loads.
///
/// Display only: day records, Vivordo AI, priorities and anything saved or
/// sent use the live fetch, never this. It belongs to one Vivordo account,
/// only answers for the range it was saved for, and is deleted when a
/// calendar is disconnected or the user signs out.
class CalendarSnapshotService {
  static const _fileName = 'calendar_snapshot.json';

  @visibleForTesting
  static Future<Directory> Function() directory =
      getApplicationSupportDirectory;

  static Future<Map<String, dynamic>?>? _snapshot;

  /// Drops the copy in memory, as a fresh launch would.
  @visibleForTesting
  static void forgetLoaded() => _snapshot = null;

  static Future<File> _file() async =>
      File('${(await directory()).path}/$_fileName');

  /// Starts reading the saved snapshot, so it's ready by the time a screen
  /// asks for it.
  static Future<void> preload() => _read();

  static Future<Map<String, dynamic>?> _read() => _snapshot ??= () async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Calendar snapshot unreadable: $e');
      return null;
    }
  }();

  /// The saved events between [start] and [end] and when they were saved,
  /// or null when there is no snapshot for [uid] covering that whole range.
  static Future<({List<gcal.Event> events, DateTime savedAt})?> eventsBetween(
    String uid,
    DateTime start,
    DateTime end,
  ) async {
    final saved = await _read();
    if (saved == null || saved['uid'] != uid) return null;
    final savedStart = DateTime.tryParse(saved['start'] as String? ?? '');
    final savedEnd = DateTime.tryParse(saved['end'] as String? ?? '');
    final savedAt = DateTime.tryParse(saved['savedAt'] as String? ?? '');
    if (savedStart == null ||
        savedEnd == null ||
        savedAt == null ||
        savedStart.isAfter(start) ||
        savedEnd.isBefore(end)) {
      return null;
    }
    try {
      return (
        events: [
          for (final json in saved['events'] as List)
            gcal.Event.fromJson(json as Map<String, dynamic>),
        ],
        savedAt: savedAt,
      );
    } catch (e) {
      debugPrint('Calendar snapshot unreadable: $e');
      return null;
    }
  }

  /// Saves a successful live fetch of [start]–[end]; a failed one must not
  /// replace the last good copy.
  static Future<void> save(
    String uid,
    DateTime start,
    DateTime end,
    List<gcal.Event> events,
  ) async {
    final snapshot = {
      'uid': uid,
      'savedAt': DateTime.now().toIso8601String(),
      'start': start.toIso8601String(),
      'end': end.toIso8601String(),
      'events': jsonDecode(jsonEncode(events)),
    };
    _snapshot = Future.value(snapshot);
    try {
      await (await _file()).writeAsString(jsonEncode(snapshot), flush: true);
    } catch (e) {
      debugPrint('Calendar snapshot not saved: $e');
    }
  }

  static Future<void> clear() async {
    _snapshot = Future.value(null);
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('Calendar snapshot not deleted: $e');
    }
  }
}
