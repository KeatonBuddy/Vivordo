import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/calendar_cognitive_load_service.dart';

void main() {
  CalendarCognitiveEvent event({
    required String title,
    int minutes = 60,
    int attendeeCount = 0,
    bool isOrganizer = false,
    bool hasTightTransition = false,
  }) {
    final start = DateTime(2026, 8, 13, 12);
    return CalendarCognitiveEvent(
      id: title,
      title: title,
      start: start,
      end: start.add(Duration(minutes: minutes)),
      attendeeCount: attendeeCount,
      isOrganizer: isOrganizer,
      hasTightTransition: hasTightTransition,
    );
  }

  test('long logistical blocks remain low cognitive load', () {
    final result = CalendarCognitiveLoadService.scoreLocally(
      event(title: 'Vehicle drop-off', minutes: 240),
    );

    expect(result.level, CognitiveLoadLevel.low);
    expect(result.score, lessThan(30));
  });

  test('presentations with responsibility score high', () {
    final result = CalendarCognitiveLoadService.scoreLocally(
      event(
        title: 'Quarterly results presentation',
        attendeeCount: 8,
        isOrganizer: true,
      ),
    );

    expect(result.level, CognitiveLoadLevel.high);
    expect(result.score, greaterThanOrEqualTo(60));
  });

  test('app development is treated as high cognitive load', () {
    final result = CalendarCognitiveLoadService.scoreLocally(
      event(title: 'Vivordo App Development', minutes: 120),
    );

    expect(result.level, CognitiveLoadLevel.high);
    expect(result.score, greaterThanOrEqualTo(60));
  });

  test('focused professional work is treated as high cognitive load', () {
    for (final title in [
      'Production deployment',
      'Architecture review',
      'Financial modeling',
      'Grant writing',
    ]) {
      final result = CalendarCognitiveLoadService.scoreLocally(
        event(title: title),
      );

      expect(result.level, CognitiveLoadLevel.high, reason: title);
    }
  });

  test('demanding school work is treated as high cognitive load', () {
    for (final title in [
      'Study session',
      'Research paper',
      'Lab report',
      'Capstone project',
    ]) {
      final result = CalendarCognitiveLoadService.scoreLocally(
        event(title: title),
      );

      expect(result.level, CognitiveLoadLevel.high, reason: title);
    }
  });

  test('meetings are treated as high cognitive load', () {
    final result = CalendarCognitiveLoadService.scoreLocally(
      event(title: 'Weekly team meeting', attendeeCount: 3),
    );

    expect(result.level, CognitiveLoadLevel.high);
  });

  test('duration alone cannot make an unclear event high load', () {
    final result = CalendarCognitiveLoadService.scoreLocally(
      event(title: 'Reserved block', minutes: 480),
    );

    expect(result.level, isNot(CognitiveLoadLevel.high));
  });

  test('tight transitions add context without forcing high load', () {
    final baseline = CalendarCognitiveLoadService.scoreLocally(
      event(title: 'Project sync'),
    );
    final tight = CalendarCognitiveLoadService.scoreLocally(
      event(title: 'Project sync', hasTightTransition: true),
    );

    expect(tight.score, baseline.score + 8);
    expect(tight.level, CognitiveLoadLevel.moderate);
  });
}
