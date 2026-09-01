import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class CalendarPriorityCandidate {
  const CalendarPriorityCandidate({
    required this.sourceEventKey,
    required this.title,
    required this.start,
    required this.end,
    required this.isAllDay,
    required this.isRecurring,
    required this.attendeeCount,
  });

  final String sourceEventKey;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool isAllDay;
  final bool isRecurring;
  final int attendeeCount;
}

class DailyPriority {
  const DailyPriority({
    required this.id,
    required this.title,
    required this.completed,
    required this.reference,
    required this.isAllDay,
    required this.source,
    this.sourceStart,
    this.sourceEnd,
  });

  final String id;
  final String title;
  final bool completed;
  final bool isAllDay;
  final String source;
  final DateTime? sourceStart;
  final DateTime? sourceEnd;
  final DocumentReference<Map<String, dynamic>> reference;

  factory DailyPriority.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    return DailyPriority(
      id: document.id,
      title: (data['title'] as String? ?? 'Untitled priority').trim(),
      completed: data['completed'] == true,
      isAllDay: data['isAllDay'] == true,
      source: data['source'] as String? ?? 'manual',
      sourceStart: (data['sourceStart'] as Timestamp?)?.toDate(),
      sourceEnd: (data['sourceEnd'] as Timestamp?)?.toDate(),
      reference: document.reference,
    );
  }
}

class DailyPriorityService {
  DailyPriorityService._();

  static const _actionKeywords = <String>{
    'appointment',
    'assessment',
    'audition',
    'book appointment',
    'complete',
    'complete application',
    'confirm',
    'deadline',
    'deliver',
    'dentist',
    'doctor',
    'due',
    'exam',
    'finalize',
    'finish',
    'follow up',
    'interview',
    'pay bill',
    'payment',
    'physio',
    'pick up',
    'practice',
    'prepare',
    'prepare for',
    'presentation',
    'register',
    'rehearsal',
    'renew',
    'reply',
    'respond',
    'review',
    'send application',
    'study',
    'submit',
    'submit application',
    'training',
    'vaccination',
    'workout',
  };
  static const _ignoredPhrases = <String>{
    'birthday',
    'break',
    'brunch',
    'commute',
    'concert',
    'dinner',
    'drinks',
    'free',
    'game',
    'golf',
    'holiday',
    'hold',
    'lunch',
    'movie',
    'optional',
    'out of office',
    'ooo',
    'party',
    'social',
    'vacation',
  };
  static const _ignoredPrefixes = <String>{'watch'};
  static final _nonAlphanumeric = RegExp(r'[^a-z0-9]+');

  static String _dayKey(DateTime day) => DateFormat('yyyy-MM-dd').format(day);
  static DateTime _dateOnly(DateTime day) =>
      DateTime(day.year, day.month, day.day);

  static CollectionReference<Map<String, dynamic>>? _collection(DateTime day) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('daily_priorities')
        .doc(_dayKey(day))
        .collection('items');
  }

  static DocumentReference<Map<String, dynamic>>? _userDocument() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  static Stream<List<DailyPriority>> watch(DateTime day) {
    final collection = _collection(day);
    if (collection == null) return Stream.value(const []);
    return collection.snapshots().map((snapshot) {
      final priorities = snapshot.docs
          .where((document) => document.data()['dismissed'] != true)
          .map(DailyPriority.fromDocument)
          .toList();
      priorities.sort((a, b) {
        final aStart = a.sourceStart?.millisecondsSinceEpoch ?? 1 << 62;
        final bStart = b.sourceStart?.millisecondsSinceEpoch ?? 1 << 62;
        return aStart.compareTo(bStart);
      });
      return priorities;
    });
  }

  static Future<void> seedFromCalendar(
    DateTime day,
    Iterable<CalendarPriorityCandidate> candidates,
  ) async {
    final collection = _collection(day);
    if (collection == null) return;
    final existing = await collection.get();
    final existingById = {
      for (final document in existing.docs) document.id: document,
    };
    var batch = FirebaseFirestore.instance.batch();
    var writes = 0;
    Future<void> flushIfFull() async {
      if (writes < 450) return;
      await batch.commit();
      batch = FirebaseFirestore.instance.batch();
      writes = 0;
    }

    for (final candidate in candidates) {
      final id = _calendarDocumentId(candidate.sourceEventKey);
      final existingDocument = existingById[id];
      if (!_shouldSuggest(candidate)) {
        final data = existingDocument?.data();
        if (data?['source'] == 'calendar' &&
            data?['dismissed'] != true &&
            data?['completed'] != true) {
          batch.update(existingDocument!.reference, {
            'dismissed': true,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          writes++;
          await flushIfFull();
        }
        continue;
      }
      if (existingDocument != null) continue;
      batch.set(collection.doc(id), {
        'title': candidate.title.trim(),
        'completed': false,
        'dismissed': false,
        'source': 'calendar',
        'sourceEventKey': candidate.sourceEventKey,
        'sourceStart': Timestamp.fromDate(candidate.start),
        'sourceEnd': Timestamp.fromDate(candidate.end),
        'isAllDay': candidate.isAllDay,
        'score': _score(candidate),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      writes++;
      await flushIfFull();
    }
    if (writes > 0) await batch.commit();
  }

  static Future<void> createManual({
    required String title,
    required DateTime date,
    DateTime? scheduledAt,
    String recurrence = 'none',
    Set<int> selectedWeekdays = const {},
    DateTime? recurrenceEnd,
  }) async {
    final userDocument = _userDocument();
    final value = title.trim();
    if (userDocument == null || value.isEmpty) return;
    if (recurrence == 'none') {
      await _addManualItem(date: date, title: value, scheduledAt: scheduledAt);
      return;
    }

    final template = userDocument.collection('priority_templates').doc();
    await template.set({
      'title': value,
      'startDate': Timestamp.fromDate(_dateOnly(date)),
      'scheduledHour': scheduledAt?.hour,
      'scheduledMinute': scheduledAt?.minute,
      'recurrence': recurrence,
      'selectedWeekdays': selectedWeekdays.toList()..sort(),
      'recurrenceEnd': recurrenceEnd == null
          ? null
          : Timestamp.fromDate(_dateOnly(recurrenceEnd)),
      'enabled': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await materializeRecurring(date);
  }

  static Future<void> materializeRecurring(DateTime day) async {
    final userDocument = _userDocument();
    final collection = _collection(day);
    if (userDocument == null || collection == null) return;
    final templates = await userDocument.collection('priority_templates').get();
    final existing = await collection.get();
    final existingIds = existing.docs.map((document) => document.id).toSet();
    final date = _dateOnly(day);
    final batch = FirebaseFirestore.instance.batch();
    var writes = 0;
    for (final template in templates.docs) {
      final data = template.data();
      if (data['enabled'] != true) continue;
      final startDate = (data['startDate'] as Timestamp?)?.toDate();
      final endDate = (data['recurrenceEnd'] as Timestamp?)?.toDate();
      if (startDate == null || date.isBefore(_dateOnly(startDate))) {
        continue;
      }
      if (endDate != null && date.isAfter(_dateOnly(endDate))) continue;
      final recurrence = data['recurrence'] as String? ?? 'none';
      final weekdays = (data['selectedWeekdays'] as List?)
          ?.whereType<num>()
          .map((value) => value.toInt())
          .toSet();
      final applies =
          recurrence == 'daily' ||
          (recurrence == 'weekly' && weekdays?.contains(date.weekday) == true);
      if (!applies) continue;
      final hour = (data['scheduledHour'] as num?)?.toInt();
      final minute = (data['scheduledMinute'] as num?)?.toInt();
      final scheduledAt = hour == null || minute == null
          ? null
          : DateTime(date.year, date.month, date.day, hour, minute);
      final priorityId = 'template_${template.id}';
      if (existingIds.contains(priorityId)) continue;
      batch.set(collection.doc(priorityId), {
        'title': data['title'],
        'completed': false,
        'dismissed': false,
        'source': 'recurring_manual',
        'templateId': template.id,
        'sourceStart': scheduledAt == null
            ? null
            : Timestamp.fromDate(scheduledAt),
        'isAllDay': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      writes++;
    }
    if (writes > 0) await batch.commit();
  }

  static Future<void> _addManualItem({
    required DateTime date,
    required String title,
    DateTime? scheduledAt,
  }) async {
    final collection = _collection(date);
    if (collection == null) return;
    await collection.add({
      'title': title,
      'completed': false,
      'dismissed': false,
      'source': 'manual',
      'sourceStart': scheduledAt == null
          ? null
          : Timestamp.fromDate(scheduledAt),
      'isAllDay': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> setCompleted(DailyPriority priority, bool completed) =>
      priority.reference.update({
        'completed': completed,
        'completedAt': completed ? FieldValue.serverTimestamp() : null,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  static Future<void> delete(DailyPriority priority) {
    if (priority.source == 'manual') return priority.reference.delete();
    return priority.reference.update({
      'dismissed': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static bool _shouldSuggest(
    CalendarPriorityCandidate candidate, {
    DateTime? now,
  }) {
    final title = _normalizeForMatching(candidate.title);
    if (title.length < 3 || !candidate.end.isAfter(now ?? DateTime.now())) {
      return false;
    }
    if (_isIgnoredTitle(title)) return false;
    return _actionKeywords.any((keyword) => _containsTerm(title, keyword));
  }

  static int _score(CalendarPriorityCandidate candidate) {
    final title = _normalizeForMatching(candidate.title);
    if (_isIgnoredTitle(title)) return 0;
    return _actionKeywords.any((keyword) => _containsTerm(title, keyword))
        ? 3
        : 0;
  }

  @visibleForTesting
  static bool shouldSuggestForTesting(
    CalendarPriorityCandidate candidate, {
    required DateTime now,
  }) => _shouldSuggest(candidate, now: now);

  @visibleForTesting
  static int scoreForTesting(CalendarPriorityCandidate candidate) =>
      _score(candidate);

  static bool _isIgnoredTitle(String title) {
    final normalized = _normalizeForMatching(title);
    return _ignoredPhrases.any((phrase) => _containsTerm(normalized, phrase)) ||
        _ignoredPrefixes.any(
          (prefix) => normalized == prefix || normalized.startsWith('$prefix '),
        );
  }

  static String _normalizeForMatching(String value) => value
      .toLowerCase()
      .replaceAll(_nonAlphanumeric, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _containsTerm(String normalizedTitle, String term) {
    final normalizedTerm = _normalizeForMatching(term);
    return ' $normalizedTitle '.contains(' $normalizedTerm ');
  }

  static String _calendarDocumentId(String sourceEventKey) {
    final encoded = base64Url.encode(utf8.encode(sourceEventKey));
    return 'calendar_${encoded.replaceAll('=', '')}';
  }
}
