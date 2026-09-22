import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/heart_rate_history.dart';
import 'package:vivordo_health/src/utils/hourly_heart_insight.dart';

void main() {
  final now = DateTime(2026, 9, 17, 18);
  HeartRateHistoryReading reading(DateTime time, double bpm) =>
      HeartRateHistoryReading(bpm: bpm, timestamp: time);
  final baseline = [
    for (var day = 1; day <= 7; day++)
      for (var m = 1; m <= 60; m++)
        reading(now.subtract(Duration(days: day, minutes: m)), 70),
  ];
  List<HeartRateHistoryReading> hour({bool spike = false}) => [
    for (var m = 1; m <= 60; m++)
      reading(
        now.subtract(Duration(minutes: m)),
        spike && (m == 15 || m == 16) ? 110 : 70,
      ),
  ];
  HourlyHeartInsight run(
    List<HeartRateHistoryReading> data, {
    List<HeartActivityWindow> workouts = const [],
    List<HeartActivityWindow> sleep = const [],
  }) => summarizeHeartHour(
    now: now,
    readings: data,
    workouts: workouts,
    sleep: sleep,
  );
  test('no readings and stale history do not describe current hour', () {
    expect(run(baseline).title, 'No recent heart-rate data');
  });
  test('sparse and duplicate readings are insufficient', () {
    expect(run(List.filled(60, reading(now, 70))).title, 'Limited readings');
  });
  test('requires seven historical days', () {
    expect(run(hour()).subtitle, contains('still learning'));
  });
  test('steady personal comparison', () {
    expect(run([...baseline, ...hour()]).title, 'Steady over the past hour');
  });
  test('repeated high readings identify a rise', () {
    expect(
      run([...baseline, ...hour(spike: true)]).subtitle,
      contains('rise was recorded'),
    );
  });
  test('one isolated high reading does not identify a spike', () {
    final data = hour();
    data[15] = reading(data[15].timestamp, 140);
    expect(
      run([...baseline, ...data]).subtitle,
      isNot(contains('rise was recorded')),
    );
  });
  test('workout-overlapping rise uses timing language', () {
    final result = run(
      [...baseline, ...hour(spike: true)],
      workouts: [
        HeartActivityWindow(
          now.subtract(const Duration(minutes: 20)),
          now.subtract(const Duration(minutes: 10)),
        ),
      ],
    );
    expect(result.subtitle, contains('coincided with your recorded workout'));
    expect(result.subtitle, isNot(contains('rise was recorded')));
  });
  test('sleep history cannot establish an awake baseline', () {
    expect(
      run(
        [...baseline, ...hour()],
        sleep: [
          HeartActivityWindow(
            now.subtract(const Duration(days: 28)),
            now.subtract(const Duration(days: 1)),
          ),
        ],
      ).subtitle,
      contains('still learning'),
    );
  });
}
