import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/stress_source_precedence.dart';

void main() {
  test('preferred wearable metrics replace raw Apple samples by day', () {
    final samples = [
      _sample('heart_rate', '2026-08-19T09:00:00Z'),
      _sample('hrv', '2026-08-19T09:00:00Z'),
      _sample('respiratory_rate', '2026-08-19T09:00:00Z'),
      _sample('steps', '2026-08-19T09:00:00Z'),
      _sample('heart_rate', '2026-08-18T09:00:00Z'),
    ];
    final result = filterStressAppleSamplesBySource(samples, {
      '2026-08-19': {
        'heart_rate': {'source': 'whoop_ble'},
        'hrv': {'source': 'fitbit'},
        'respiratory_rate': {'source': 'apple_health'},
        'steps': {'source': 'fitbit'},
      },
    });

    expect(result.map((sample) => sample['metric_type']), [
      'respiratory_rate',
      'steps',
      'heart_rate',
    ]);
  });

  test('sleep precedence uses its wake day instead of interval start day', () {
    final result = filterStressAppleSamplesBySource(
      [
        {
          ..._sample('sleep', '2026-08-18T23:00:00Z'),
          '_metric_date': '2026-08-19',
        },
      ],
      {
        '2026-08-19': {
          'sleep': {'source': 'whoop'},
        },
      },
    );

    expect(result, isEmpty);
  });
}

Map<String, dynamic> _sample(String metric, String timestamp) => {
  'metric_type': metric,
  'timestamp': timestamp,
  'source': 'apple_health',
  'value': 1,
};
