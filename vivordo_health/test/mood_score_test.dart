import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/metrics_service.dart';

void main() {
  test('maps the full 0–100 mood scale to familiar labels', () {
    expect(MetricsService.moodLabelForScore(0), 'Awful');
    expect(MetricsService.moodLabelForScore(20), 'Down');
    expect(MetricsService.moodLabelForScore(40), 'Okay');
    expect(MetricsService.moodLabelForScore(60), 'Good');
    expect(MetricsService.moodLabelForScore(80), 'Great');
    expect(MetricsService.moodLabelForScore(100), 'Great');
  });

  test('keeps older label-only mood records compatible', () {
    expect(MetricsService.moodScoreForLabel('Awful'), 10);
    expect(MetricsService.moodScoreForLabel('Down'), 30);
    expect(MetricsService.moodScoreForLabel('Okay'), 50);
    expect(MetricsService.moodScoreForLabel('Good'), 75);
    expect(MetricsService.moodScoreForLabel('Great'), 95);
  });

  test('clamps out-of-range values before deriving the label', () {
    expect(MetricsService.moodLabelForScore(-10), 'Awful');
    expect(MetricsService.moodLabelForScore(110), 'Great');
  });
}
