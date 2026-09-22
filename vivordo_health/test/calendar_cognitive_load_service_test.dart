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

  test('app development is focused work', () {
    final result = CalendarCognitiveLoadService.scoreLocally(
      event(title: 'Vivordo App Development', minutes: 120),
    );

    expect(result.category, 'focused-work');
    expect(result.score, 55);
  });

  test('focused professional work is moderate demand', () {
    for (final title in [
      'Production deployment',
      'Architecture review',
      'Financial modeling',
      'Grant writing',
    ]) {
      final result = CalendarCognitiveLoadService.scoreLocally(
        event(title: title),
      );

      expect(result.score, 55, reason: title);
    }
  });

  test('school preparation is focused work', () {
    for (final title in [
      'Study session',
      'Research paper',
      'Lab report',
      'Capstone project',
    ]) {
      final result = CalendarCognitiveLoadService.scoreLocally(
        event(title: title),
      );

      expect(result.score, 55, reason: title);
    }
  });

  test('ordinary meetings are moderate demand', () {
    final result = CalendarCognitiveLoadService.scoreLocally(
      event(title: 'Weekly team meeting', attendeeCount: 3),
    );

    expect(result.score, 40);
  });

  test('duration alone cannot make an unclear event high load', () {
    final result = CalendarCognitiveLoadService.scoreLocally(
      event(title: 'Reserved block', minutes: 480),
    );

    expect(result.level, isNot(CognitiveLoadLevel.high));
  });

  test('tight transitions do not alter intrinsic demand', () {
    final baseline = CalendarCognitiveLoadService.scoreLocally(
      event(title: 'Project sync'),
    );
    final tight = CalendarCognitiveLoadService.scoreLocally(
      event(title: 'Project sync', hasTightTransition: true),
    );

    expect(tight.score, baseline.score);
    expect(tight.level, CognitiveLoadLevel.moderate);
  });

  test('demand is independent of duration and responsibility metadata', () {
    final short = CalendarCognitiveLoadService.scoreLocally(
      event(title: 'Lunch', minutes: 15),
    );
    final long = CalendarCognitiveLoadService.scoreLocally(
      event(
        title: 'Lunch',
        minutes: 240,
        attendeeCount: 20,
        isOrganizer: true,
        hasTightTransition: true,
      ),
    );
    expect(short.score, long.score);
    expect(long.score, 20);
  });

  test('specific phrases and word boundaries prevent false matches', () {
    for (final entry in {
      'Pub golf': 20,
      'Lunch meeting': 20,
      'Prepare slides': 55,
      'Presentation preparation': 55,
      'Exam preparation': 55,
      'Client presentation': 75,
      'Example project': 0,
      'Recall photos': 0,
    }.entries) {
      expect(
        CalendarCognitiveLoadService.scoreLocally(
          event(title: entry.key),
        ).score,
        entry.value,
        reason: entry.key,
      );
    }
  });

  test('ambiguous events have no asserted demand or confidence', () {
    final result = CalendarCognitiveLoadService.scoreLocally(
      event(title: 'Project Alpha'),
    );
    expect(result.category, 'unknown');
    expect(result.confidence, 0);
    expect(result.isKnown, false);
  });

  test('everyday calendar titles use the expanded categories', () {
    final cases = <String, String>{
      'Grocery run after work': 'routine',
      'School pick-up': 'routine',
      'DAYCARE DROP-OFF': 'routine',
      'Haircut with Sam': 'routine',
      'Prescription refill': 'routine',
      'Hotel check-in': 'routine',
      'Coffee break': 'routine',
      'PTO': 'routine',
      'Brunch with Alex': 'social',
      'Friday game night': 'social',
      'Family reunion': 'social',
      'Book club': 'social',
      'Happy hour': 'social',
      'Mini-golf': 'social',
      'Daily stand-up': 'collaboration',
      'Project kickoff': 'collaboration',
      'Backlog refinement': 'collaboration',
      'Sprint retrospective': 'collaboration',
      'Mentoring with Alex': 'collaboration',
      'Team check-in': 'collaboration',
      'All-hands': 'collaboration',
    };
    for (final entry in cases.entries) {
      expect(
        CalendarCognitiveLoadService.scoreLocally(
          event(title: entry.key),
        ).category,
        entry.value,
        reason: entry.key,
      );
    }
  });

  test(
    'expanded vocabulary preserves specific demand and avoids substrings',
    () {
      for (final entry in {
        'Client presentation': 75,
        'Performance review': 75,
        'Architecture review': 55,
        'Lunch meeting': 20,
        'Hotel check in': 15,
        'Team check in': 40,
        'Business': 0,
        'Constraint': 0,
        'Apartments': 0,
      }.entries) {
        expect(
          CalendarCognitiveLoadService.scoreLocally(
            event(title: entry.key),
          ).score,
          entry.value,
          reason: entry.key,
        );
      }
    },
  );

  test('classification uses local rules by default without Firebase', () async {
    final result = await CalendarCognitiveLoadService.scoreEvents([
      event(title: 'Coding'),
    ]);
    expect(result.single.score, 55);
    expect(result.single.source, 'rules');
  });
}
