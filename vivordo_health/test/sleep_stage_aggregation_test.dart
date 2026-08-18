import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/sleep_stage_aggregation.dart';

void main() {
  SleepInterval interval(
    VivordoSleepStage stage,
    DateTime start,
    DateTime end,
  ) => SleepInterval(stage: stage, start: start, end: end);

  test('assigns a staged night to the day the user wakes up', () {
    final summaries = summarizeSleepByWakeDay([
      interval(
        VivordoSleepStage.core,
        DateTime(2026, 8, 16, 23),
        DateTime(2026, 8, 17, 1),
      ),
      interval(
        VivordoSleepStage.deep,
        DateTime(2026, 8, 17, 1),
        DateTime(2026, 8, 17, 3),
      ),
      interval(
        VivordoSleepStage.rem,
        DateTime(2026, 8, 17, 3),
        DateTime(2026, 8, 17, 7),
      ),
    ]);

    expect(summaries, hasLength(1));
    expect(summaries.single.date, DateTime(2026, 8, 17));
    expect(summaries.single.totalAsleepMinutes, 480);
    expect(summaries.single.stageMinutes['core'], 120);
    expect(summaries.single.stageMinutes['deep'], 120);
    expect(summaries.single.stageMinutes['rem'], 240);
  });

  test('overlapping source intervals do not inflate total sleep', () {
    final summaries = summarizeSleepByWakeDay([
      interval(
        VivordoSleepStage.unspecified,
        DateTime(2026, 8, 16, 23),
        DateTime(2026, 8, 17, 7),
      ),
      interval(
        VivordoSleepStage.core,
        DateTime(2026, 8, 16, 23),
        DateTime(2026, 8, 17, 3),
      ),
      interval(
        VivordoSleepStage.core,
        DateTime(2026, 8, 17, 1),
        DateTime(2026, 8, 17, 5),
      ),
      interval(
        VivordoSleepStage.rem,
        DateTime(2026, 8, 17, 5),
        DateTime(2026, 8, 17, 7),
      ),
    ]);

    expect(summaries.single.totalAsleepMinutes, 480);
    expect(summaries.single.stageMinutes['core'], 360);
    expect(summaries.single.stageMinutes['rem'], 120);
  });

  test('awake time is shown as a stage but excluded from total sleep', () {
    final summaries = summarizeSleepByWakeDay([
      interval(
        VivordoSleepStage.core,
        DateTime(2026, 8, 17, 0),
        DateTime(2026, 8, 17, 2),
      ),
      interval(
        VivordoSleepStage.awake,
        DateTime(2026, 8, 17, 2),
        DateTime(2026, 8, 17, 2, 30),
      ),
      interval(
        VivordoSleepStage.deep,
        DateTime(2026, 8, 17, 2, 30),
        DateTime(2026, 8, 17, 4),
      ),
    ]);

    expect(summaries.single.totalAsleepMinutes, 210);
    expect(summaries.single.stageMinutes['awake'], 30);
  });
}
