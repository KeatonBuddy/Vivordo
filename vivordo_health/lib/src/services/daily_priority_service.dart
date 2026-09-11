import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:vivordo_health/src/utils/day_key.dart';
import 'notification_service.dart';
import '../utils/priority_reminder.dart';

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
    this.reminderMinutes = 60,
    this.reminderTimeMinutes,
    this.date,
    this.templateId,
  });

  final String id;
  final String title;
  final bool completed;
  final bool isAllDay;
  final String source;
  final DateTime? sourceStart;
  final DateTime? sourceEnd;
  final int reminderMinutes;
  final int? reminderTimeMinutes;
  final DateTime? date;
  final String? templateId;
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
      reminderMinutes: (data['reminderMinutes'] as num?)?.toInt() ?? 60,
      reminderTimeMinutes: (data['reminderTimeMinutes'] as num?)?.toInt(),
      reference: document.reference,
      date: DateTime.tryParse(document.reference.parent.parent?.id ?? ''),
      templateId: data['templateId'] as String?,
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

  static DateTime _dateOnly(DateTime day) =>
      DateTime(day.year, day.month, day.day);

  static CollectionReference<Map<String, dynamic>>? _collection(DateTime day) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('daily_priorities')
        .doc(localDayKey(day))
        .collection('items');
  }

  static DocumentReference<Map<String, dynamic>>? _userDocument() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  static Stream<List<DailyPriority>> watch(
    DateTime day, {
    bool includeUpcoming = false,
  }) {
    final collection = _collection(day);
    final user = _userDocument();
    if (collection == null || user == null) return Stream.value(const []);
    final dayKey = localDayKey(day);
    final subscriptions =
        <String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};
    final items = <String, List<DailyPriority>>{};
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
    userSubscription;
    late StreamController<List<DailyPriority>> controller;

    void emit() {
      final priorities = items.values.expand((value) => value).toList();
      priorities.sort((a, b) {
        final aStart = a.sourceStart?.millisecondsSinceEpoch ?? 1 << 62;
        final bStart = b.sourceStart?.millisecondsSinceEpoch ?? 1 << 62;
        final comparison = aStart.compareTo(bStart);
        return comparison != 0
            ? comparison
            : a.reference.path.compareTo(b.reference.path);
      });
      if (!controller.isClosed) controller.add(priorities);
    }

    void subscribe(String key) {
      if (subscriptions.containsKey(key)) return;
      final source = user
          .collection('daily_priorities')
          .doc(key)
          .collection('items');
      // Keep today's completions visible (including pending offline writes).
      // Original references allow unchecking without duplicating the task.
      final Query<Map<String, dynamic>> query = key.compareTo(dayKey) >= 0
          ? source
          : source.where(
              Filter.or(
                Filter('completed', isEqualTo: false),
                Filter('completedDay', isEqualTo: dayKey),
              ),
            );
      subscriptions[key] = query.snapshots().listen((snapshot) {
        items[key] = snapshot.docs
            .where(
              (document) => visibleOnDay(
                document.data(),
                key,
                includeUpcoming && key.compareTo(dayKey) > 0 ? key : dayKey,
              ),
            )
            .map(DailyPriority.fromDocument)
            .toList();
        emit();
      }, onError: controller.addError);
    }

    controller = StreamController<List<DailyPriority>>(
      onListen: () {
        subscribe(dayKey);
        if (includeUpcoming) {
          for (var offset = 1; offset < 14; offset++) {
            subscribe(
              localDayKey(DateTime(day.year, day.month, day.day + offset)),
            );
          }
        }
        userSubscription = user.snapshots().listen((snapshot) {
          final days =
              snapshot.data()?['priorityReminderDays'] as List? ?? const [];
          for (final key in days.whereType<String>().toSet()) {
            if (DateTime.tryParse(key) != null &&
                (includeUpcoming || key.compareTo(dayKey) < 0)) {
              subscribe(key);
            }
          }
        }, onError: controller.addError);
      },
      onCancel: () async {
        await userSubscription?.cancel();
        await Future.wait(
          subscriptions.values.map((subscription) => subscription.cancel()),
        );
      },
    );
    return controller.stream;
  }

  static Stream<Map<String, String>> watchRecurrenceLabels() {
    final user = _userDocument();
    if (user == null) return Stream.value(const {});
    return user.collection('priority_templates').snapshots().map((snapshot) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return {
        for (final document in snapshot.docs)
          document.id: document.data()['recurrence'] == 'daily'
              ? 'Every day'
              : 'Every ${((document.data()['selectedWeekdays'] as List?) ?? const []).whereType<num>().where((d) => d >= 1 && d <= 7).map((d) => days[d.toInt() - 1]).join(', ')}',
      };
    });
  }

  @visibleForTesting
  static bool visibleOnDay(
    Map<String, dynamic> data,
    String storedDay,
    String viewingDay,
  ) {
    if (data['dismissed'] == true || storedDay.compareTo(viewingDay) > 0) {
      return false;
    }
    if (storedDay == viewingDay) return true;
    // Recurring occurrences and imported calendar events remain date-bound.
    return data['source'] == 'manual' &&
        data['sourceStart'] == null &&
        (data['completed'] != true || data['completedDay'] == viewingDay);
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
    await _userDocument()?.update({
      'priorityReminderDays': FieldValue.arrayUnion([localDayKey(day)]),
    });
    for (final document in (await collection.get()).docs) {
      await _syncReminder(document.reference);
    }
  }

  static Future<void> createManual({
    required String title,
    required DateTime date,
    DateTime? scheduledAt,
    String recurrence = 'none',
    Set<int> selectedWeekdays = const {},
    DateTime? recurrenceEnd,
    int reminderMinutes = 60,
    int? reminderTimeMinutes,
  }) async {
    final userDocument = _userDocument();
    final value = title.trim();
    if (userDocument == null || value.isEmpty) return;
    await userDocument.update({
      'priorityReminderDays': FieldValue.arrayUnion([localDayKey(date)]),
    });
    if (recurrence == 'none') {
      await _addManualItem(
        date: date,
        title: value,
        scheduledAt: scheduledAt,
        reminderMinutes: reminderMinutes,
        reminderTimeMinutes: reminderTimeMinutes,
      );
      return;
    }

    final template = userDocument.collection('priority_templates').doc();
    await template.set({
      'title': value,
      'reminderMinutes': reminderMinutes,
      'reminderTimeMinutes': reminderTimeMinutes,
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
    await refreshReminders(force: true);
  }

  static Future<void> materializeRecurring(
    DateTime day, {
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? cachedTemplates,
  }) async {
    final userDocument = _userDocument();
    final collection = _collection(day);
    if (userDocument == null || collection == null) return;
    final templates =
        cachedTemplates ??
        (await userDocument.collection('priority_templates').get()).docs;
    final existing = await collection.get();
    final existingIds = existing.docs.map((document) => document.id).toSet();
    final date = _dateOnly(day);
    final batch = FirebaseFirestore.instance.batch();
    var writes = 0;
    for (final template in templates) {
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
        'reminderMinutes': data['reminderMinutes'] ?? 60,
        'reminderTimeMinutes': data['reminderTimeMinutes'],
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
    int reminderMinutes = 60,
    int? reminderTimeMinutes,
  }) async {
    final collection = _collection(date);
    if (collection == null) return;
    final reference = await collection.add({
      'title': title,
      'completed': false,
      'dismissed': false,
      'source': 'manual',
      'reminderMinutes': reminderMinutes,
      'reminderTimeMinutes': reminderTimeMinutes,
      'sourceStart': scheduledAt == null
          ? null
          : Timestamp.fromDate(scheduledAt),
      'isAllDay': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _syncReminder(reference);
  }

  static Future<void> setCompleted(
    DailyPriority priority,
    bool completed,
  ) async {
    await priority.reference.update({
      'completed': completed,
      'completedAt': completed ? FieldValue.serverTimestamp() : null,
      'completedDay': completed ? localDayKey(DateTime.now()) : null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _syncReminder(priority.reference);
  }

  static Future<void> delete(DailyPriority priority) async {
    if (priority.source == 'manual') {
      await priority.reference.delete();
    } else {
      await priority.reference.update({
        'dismissed': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await _syncReminder(priority.reference);
  }

  static Future<void> editReminder(
    DailyPriority priority,
    String title,
    int minutes,
    int? reminderTimeMinutes,
  ) async {
    await priority.reference.update({
      'title': title.trim(),
      'reminderMinutes': minutes,
      'reminderTimeMinutes': reminderTimeMinutes,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _syncReminder(priority.reference);
  }

  static Future<void> editPriority(
    DailyPriority priority, {
    required String title,
    required DateTime date,
    required DateTime? scheduledAt,
    required bool completed,
    required int reminderMinutes,
    required int? reminderTimeMinutes,
    String recurrence = 'none',
    Set<int> selectedWeekdays = const {},
    DateTime? recurrenceEnd,
  }) async {
    final user = _userDocument();
    final collection = _collection(date);
    if (user == null || collection == null) return;
    final template = priority.source == 'manual' && recurrence != 'none'
        ? user.collection('priority_templates').doc()
        : null;
    final destination = collection.doc(
      template == null ? priority.id : 'template_${template.id}',
    );
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final original = await transaction.get(priority.reference);
      final data = original.data();
      if (data == null || data['dismissed'] == true) {
        throw StateError('Priority no longer exists');
      }
      if (destination.path != priority.reference.path) {
        final existing = await transaction.get(destination);
        if (existing.exists) {
          throw StateError('A priority already exists on that date');
        }
      }
      transaction.set(destination, {
        ...data,
        'title': title.trim(),
        'sourceStart': scheduledAt == null
            ? null
            : Timestamp.fromDate(scheduledAt),
        'sourceEnd': null,
        'isAllDay': false,
        'completed': completed,
        'completedAt': completed
            ? (data['completedAt'] ?? FieldValue.serverTimestamp())
            : null,
        'completedDay': completed
            ? (data['completed'] == true
                  ? (data['completedDay'] ?? localDayKey(DateTime.now()))
                  : localDayKey(DateTime.now()))
            : null,
        'reminderMinutes': reminderMinutes,
        'reminderTimeMinutes': reminderTimeMinutes,
        'updatedAt': FieldValue.serverTimestamp(),
        if (template != null) 'source': 'recurring_manual',
        if (template != null) 'templateId': template.id,
      });
      if (destination.path != priority.reference.path) {
        if (priority.source == 'manual') {
          transaction.delete(priority.reference);
        } else {
          transaction.update(priority.reference, {'dismissed': true});
        }
      }
      if (template != null) {
        transaction.set(template, {
          'title': title.trim(),
          'enabled': true,
          'startDate': Timestamp.fromDate(_dateOnly(date)),
          'scheduledHour': scheduledAt?.hour,
          'scheduledMinute': scheduledAt?.minute,
          'recurrence': recurrence,
          'selectedWeekdays': selectedWeekdays.toList()..sort(),
          'recurrenceEnd': recurrenceEnd == null
              ? null
              : Timestamp.fromDate(_dateOnly(recurrenceEnd)),
          'reminderMinutes': reminderMinutes,
          'reminderTimeMinutes': reminderTimeMinutes,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      transaction.update(user, {
        'priorityReminderDays': FieldValue.arrayUnion([localDayKey(date)]),
      });
    });
    if (destination.path != priority.reference.path) {
      await _syncReminder(priority.reference);
    }
    await _syncReminder(destination);
    if (template != null) await refreshReminders(force: true);
  }

  static Future<void> _syncReminder(
    DocumentReference<Map<String, dynamic>> reference,
  ) async {
    final data = (await reference.get()).data();
    final time = data == null || data['dismissed'] == true
        ? null
        : priorityReminderTime(
            start: (data['sourceStart'] as Timestamp?)?.toDate(),
            minutesBefore: (data['reminderMinutes'] as num?)?.toInt() ?? 60,
            completed: data['completed'] == true,
            allDay: data['isAllDay'] == true,
            now: DateTime.now(),
            priorityDate: DateTime.tryParse(reference.parent.parent!.id),
            reminderTimeMinutes: (data['reminderTimeMinutes'] as num?)?.toInt(),
          );
    await NotificationService().updatePriorityReminder(
      path: reference.path,
      title: data?['title'] as String? ?? 'Priority',
      time: time,
    );
  }

  static Future<void>? _refreshingReminders;
  static String? _lastReminderRefresh;

  static Future<void> refreshReminders({bool force = false}) {
    final key =
        '${FirebaseAuth.instance.currentUser?.uid}/${localDayKey(DateTime.now())}';
    if (!force && _lastReminderRefresh == key) return Future.value();
    return _refreshingReminders ??= _refreshReminders()
        .then((_) {
          _lastReminderRefresh = key;
        })
        .whenComplete(() => _refreshingReminders = null);
  }

  static Future<void> _refreshReminders() async {
    final user = _userDocument();
    if (user == null) return;
    final now = DateTime.now();
    final templates = (await user.collection('priority_templates').get()).docs;
    final savedDays =
        (await user.get()).data()?['priorityReminderDays'] as List? ?? const [];
    final days = <String>{
      ...savedDays.whereType<String>().where(
        (day) => day.compareTo(localDayKey(now)) >= 0,
      ),
      for (var offset = 0; offset < 14; offset++)
        localDayKey(DateTime(now.year, now.month, now.day + offset)),
    }.toList()..sort();
    // Materialize upcoming occurrences so reminders work while the app is closed.
    for (final dayKey in days) {
      if (FirebaseAuth.instance.currentUser?.uid != user.id) return;
      final day = DateTime.parse(dayKey);
      await materializeRecurring(day, cachedTemplates: templates);
      final collection = _collection(day);
      if (collection == null) return;
      for (final document in (await collection.get()).docs) {
        await _syncReminder(document.reference);
      }
    }
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
