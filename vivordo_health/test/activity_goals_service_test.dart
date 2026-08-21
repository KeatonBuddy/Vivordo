import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/activity_goals_service.dart';

void main() {
  group('strengthGoalsFromUserData', () {
    test('returns defaults when no strength goals are stored', () {
      expect(
        ActivityGoalsService.strengthGoalsFromUserData(null),
        kDefaultStrengthGoals,
      );
    });

    test('restores saved goals and falls back for invalid values', () {
      final goals = ActivityGoalsService.strengthGoalsFromUserData({
        'preferences': {
          'strengthGoals': {'Chest': 16, 'Back': 14.4, 'Legs': 0},
        },
      });

      expect(goals['Chest'], 16);
      expect(goals['Back'], 14);
      expect(goals['Legs'], kDefaultStrengthGoals['Legs']);
      expect(goals['Shoulders'], kDefaultStrengthGoals['Shoulders']);
      expect(goals['Arms'], kDefaultStrengthGoals['Arms']);
    });
  });
}
