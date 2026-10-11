import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/stress_view.dart';

void main() {
  final today = DateTime(2026, 10, 7);
  String time(DateTime t) => '${t.hour}:${t.minute.toString().padLeft(2, '0')}';

  test('a record with signals keeps measured and missing ones', () {
    final day = StressDay.fromDoc(today, {
      'stress': {
        'current': 54.2,
        'anchor': 50,
        'confidence': 'high',
        'signals': [
          {'name': 'Perceived stress', 'signal': -0.2, 'contribution': -6},
          {'name': 'Last-night sleep', 'signal': 0.35, 'contribution': 7},
          {'name': 'HRV', 'signal': 0.3, 'contribution': 3.6},
          {'name': 'Respiratory rate', 'signal': null, 'contribution': 0},
          {'name': 'Recent activity', 'signal': -0.1, 'contribution': -0.3},
          {
            'name': 'Calendar unavailable share',
            'signal': 1,
            'contribution': 2,
          },
        ],
        'top_drivers': [
          {'name': 'Last-night sleep', 'contribution': 7},
        ],
      },
      'sleep': {'avg': 5.67},
    });
    expect(day.signals.map((s) => s.label), [
      'How you feel',
      'Last night\'s sleep',
      'HRV',
      'Breathing rate',
      'Activity',
    ]);
    expect(day.measuredSignals, 4);
    // Biggest first; tiny and missing ones left out.
    expect(day.drivers.map((s) => s.kind), [
      StressSignalKind.sleep,
      StressSignalKind.feel,
      StressSignalKind.hrv,
    ]);
    expect(
      stressDriverDetail(day.drivers.first, day, time),
      '5h 40m last night, less restful than usual',
    );
    expect(stressUsualHeadline(day.score!, day.usual), '4 above usual');
    expect(stressNextStep(day.drivers).action, StressNextAction.windDown);
  });

  test('older records fall back to their top drivers', () {
    final day = StressDay.fromDoc(today, {
      'stress': {
        'avg': 49,
        'top_drivers': [
          {'name': 'Last-night sleep', 'contribution': -6},
        ],
      },
    });
    expect(day.signals, isEmpty);
    expect(day.drivers.single.kind, StressSignalKind.sleep);
    expect(day.usual, 50);
    expect(stressUsualHeadline(49, 50), 'About usual');
    expect(stressNextStep(day.drivers).title, contains('Nothing'));
  });

  test('the usual range is the middle half of the last 28 days', () {
    final days = [
      for (var i = 1; i <= 8; i++)
        StressDay(
          date: today.subtract(Duration(days: i)),
          average: 40.0 + i,
        ),
      StressDay(date: today, average: 90),
    ];
    final range = stressUsualRange(days, today)!;
    expect(range.$1, closeTo(42.75, .01));
    expect(range.$2, closeTo(46.25, .01));
    expect(stressUsualRange(days.take(5).toList(), today), isNull);
  });

  test('yesterday at the same time uses the last reading before it', () {
    final yesterday = StressDay(
      date: today.subtract(const Duration(days: 1)),
      readings: [
        StressReading(48, DateTime(2026, 10, 6, 9)),
        StressReading(52, DateTime(2026, 10, 6, 14, 30)),
        StressReading(60, DateTime(2026, 10, 6, 18)),
      ],
    );
    expect(stressAtTimeOfDay(yesterday, DateTime(2026, 10, 7, 15)), 52);
    expect(stressAtTimeOfDay(yesterday, DateTime(2026, 10, 7, 8)), isNull);
  });

  test('trend stats compare with the period before', () {
    StressDay d(int back, double avg) => StressDay(
      date: today.subtract(Duration(days: back)),
      average: avg,
    );
    final stats = stressTrendStats(
      [d(2, 50), d(1, 44), d(0, 62)],
      [d(9, 58), d(8, 56), d(7, 57)],
    )!;
    expect(stats.average, closeTo(52, .01));
    expect(stats.calmest.average, 44);
    expect(stats.hardest.average, 62);
    expect(stats.change, closeTo(-5, .01));
    expect(stressTrendStats([d(0, 50)], const [])!.change, isNull);
    expect(stressTrendStats(const [], const []), isNull);
  });
}
