import 'package:googleapis/calendar/v3.dart' as gcal;
import 'calendar_service.dart';
import 'calendar_cognitive_load_service.dart';
import 'hourly_calendar_load.dart';

class CalendarBaasContext {
  /// Fetch alongside health inputs; never delay scoring by more than 5 seconds.
  /// No interactive sign-in, AI classification, event text or IDs in payload.
  static Future<List<Map<String, Object?>>> load(DateTime asOf) async {
    final utc = asOf.toUtc();
    final from = DateTime.utc(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
    ).subtract(const Duration(days: 3));
    List<gcal.Event>? events;
    try {
      events = await CalendarService.getScoringEvents(
        from.subtract(const Duration(hours: 3)),
        utc,
      ).timeout(const Duration(seconds: 5));
    } catch (_) {
      events = null;
    }
    return build(events: events, from: from, asOf: utc);
  }

  static List<Map<String, Object?>> build({
    required List<gcal.Event>? events,
    required DateTime from,
    required DateTime asOf,
  }) {
    final inputs = <CalendarCognitiveEvent>[];
    for (var i = 0; i < (events?.length ?? 0); i++) {
      final event = events![i];
      final start = event.start?.dateTime;
      final end = event.end?.dateTime;
      if (start == null || end == null) continue;
      inputs.add(
        CalendarCognitiveEvent(
          id: '${event.id ?? i}:${start.toUtc().toIso8601String()}',
          title: event.summary ?? '',
          description: event.description ?? '',
          start: start.toUtc(),
          end: end.toUtc(),
          showsAsFree: event.transparency == 'transparent',
          isCancelled: event.status == 'cancelled',
          isDeclined:
              event.attendees?.any(
                (a) => a.self == true && a.responseStatus == 'declined',
              ) ??
              false,
        ),
      );
    }
    return HourlyCalendarLoadCalculator.calculate(
      events: inputs,
      scores: inputs.map(CalendarCognitiveLoadService.scoreLocally).toList(),
      from: from.toUtc(),
      until: asOf.toUtc(),
      asOf: asOf.toUtc(),
      calendarAvailable: events != null,
    ).map((h) => h.toJson()).toList();
  }
}
