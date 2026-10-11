import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/circle_profile_service.dart';

void main() {
  String? badge(Map<String, dynamic> data) =>
      CircleProfileService.achievementBadgeFor(data);

  test('keeps a saved badge', () {
    expect(
      badge({
        'kind': 'achievement',
        'achievementId': 'pulse_check',
        'achievementBadgeAsset': 'assets/achievements/pulse_check_gold.png',
      }),
      'assets/achievements/pulse_check_gold.png',
    );
  });

  test('derives one-time and tiered badges for older posts', () {
    expect(
      badge({'kind': 'achievement', 'achievementId': 'your_circle'}),
      'assets/achievements/your_circle.png',
    );
    expect(
      badge({
        'kind': 'achievement',
        'achievementId': 'workout_momentum',
        'achievementTier': 'silver',
      }),
      'assets/achievements/workout_momentum_silver.png',
    );
  });

  test('leaves non-achievement posts alone', () {
    expect(badge({'kind': 'workout', 'achievementId': 'x'}), isNull);
    expect(badge({'kind': 'achievement'}), isNull);
  });
}
