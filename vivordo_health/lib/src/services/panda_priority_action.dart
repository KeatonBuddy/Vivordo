/// Validated single-occurrence priority mutation proposed by Panda.
/// Missing fields mean preserve existing values, not clear them.
class PandaPriorityAction {
  PandaPriorityAction(Map<String, dynamic> data) {
    const allowed = {
      'operation',
      'title',
      'target_title',
      'target_date',
      'date',
      'scheduled_at',
      'reminder_at',
    };
    if (data.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('That priority change is not supported yet.');
    }
    operation = data['operation'] as String? ?? '';
    title = _text(data['title']);
    targetTitle = _text(data['target_title']);
    if (!{'create', 'update', 'delete'}.contains(operation) ||
        (operation == 'create' ? title == null : targetTitle == null)) {
      throw const FormatException(
        'Please specify the priority and change you want.',
      );
    }
    date = _date(data['date']);
    targetDate = _date(data['target_date']);
    scheduledAt = _time(data['scheduled_at']);
    reminderAt = _time(data['reminder_at']);
    final day = date ?? scheduledAt ?? reminderAt;
    for (final time in [scheduledAt, reminderAt]) {
      if (day != null && time != null && !_sameDay(day, time)) {
        throw const FormatException(
          'The priority and reminder must be on the same day.',
        );
      }
    }
    if (scheduledAt != null &&
        reminderAt != null &&
        reminderAt!.isAfter(scheduledAt!)) {
      throw const FormatException(
        'The reminder must be at or before the scheduled time.',
      );
    }
  }

  late final String operation;
  late final String? title, targetTitle;
  late final DateTime? date, targetDate, scheduledAt, reminderAt;

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String? _text(dynamic value) {
    if (value == null) return null;
    if (value is! String || value.trim().isEmpty || value.length > 300) {
      throw const FormatException('Please provide a valid priority title.');
    }
    return value.trim();
  }

  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw const FormatException('Please provide a valid date.');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
      throw const FormatException('Please provide a valid date.');
    }
    return parsed;
  }

  static DateTime? _time(dynamic value) {
    if (value == null) return null;
    if (value is! String ||
        !RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:00(\.000)?)?$',
        ).hasMatch(value)) {
      throw const FormatException(
        'Please specify a local date and time to the minute.',
      );
    }
    _date(value.substring(0, 10));
    if (int.parse(value.substring(11, 13)) > 23 ||
        int.parse(value.substring(14, 16)) > 59) {
      throw const FormatException('Invalid time.');
    }
    return DateTime.parse(value);
  }
}
