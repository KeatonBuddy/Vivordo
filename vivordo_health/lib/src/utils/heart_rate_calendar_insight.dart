import 'package:intl/intl.dart';

class HeartRateCalendarEvent {
  const HeartRateCalendarEvent({
    required this.title,
    required this.start,
    required this.end,
  });

  final String title;
  final DateTime start;
  final DateTime end;

  bool contains(DateTime value) =>
      !value.isBefore(start) && !value.isAfter(end);
}

class HeartRateCalendarInsight {
  const HeartRateCalendarInsight({required this.title, required this.subtitle});

  final String title;
  final String subtitle;
}

HeartRateCalendarInsight buildHeartRateCalendarInsight({
  required int bpm,
  required DateTime? timestamp,
  Iterable<HeartRateCalendarEvent> events = const [],
}) {
  final localTime = timestamp?.toLocal();
  HeartRateCalendarEvent? matchingEvent;
  if (localTime != null) {
    for (final event in events) {
      if (event.contains(localTime)) {
        matchingEvent = event;
        break;
      }
    }
  }

  final eventTitle = matchingEvent?.title.trim();
  final duringEvent = eventTitle != null && eventTitle.isNotEmpty;
  final time = localTime == null ? null : DateFormat.jm().format(localTime);

  if (duringEvent) {
    final state = bpm >= 100
        ? 'elevated'
        : bpm >= 80
        ? 'slightly elevated'
        : bpm < 60
        ? 'relaxed'
        : 'in a normal range';
    return HeartRateCalendarInsight(
      title: 'Your heart rate was $state during “$eventTitle”',
      subtitle: time == null
          ? '$bpm bpm recorded during this event.'
          : '$bpm bpm recorded at $time.',
    );
  }

  final atTime = time == null ? '' : ' at $time';
  if (bpm >= 100) {
    return HeartRateCalendarInsight(
      title: 'Your heart rate elevated to $bpm bpm$atTime',
      subtitle: 'Try a brief breathing or recovery break.',
    );
  }
  if (bpm >= 80) {
    return HeartRateCalendarInsight(
      title: 'Your heart rate was slightly elevated$atTime',
      subtitle: '$bpm bpm recorded. Consider taking a short recovery break.',
    );
  }
  if (bpm < 60) {
    return HeartRateCalendarInsight(
      title: 'Your heart rate looked relaxed$atTime',
      subtitle: '$bpm bpm recorded.',
    );
  }
  return HeartRateCalendarInsight(
    title: 'Your heart rate was in a normal range$atTime',
    subtitle: '$bpm bpm recorded.',
  );
}
