import 'dart:async';

class AchievementUnlock {
  const AchievementUnlock({
    required this.id,
    required this.name,
    required this.requirement,
    required this.badgeAsset,
    this.tier,
  });

  final String id;
  final String name;
  final String requirement;
  final String badgeAsset;
  final String? tier;
}

/// Sends confirmed achievement unlocks to the app-level celebration UI.
class AchievementUnlockService {
  AchievementUnlockService._();

  static final _controller = StreamController<AchievementUnlock>.broadcast();

  static Stream<AchievementUnlock> get unlocks => _controller.stream;

  static void announce(AchievementUnlock achievement) {
    if (!_controller.isClosed) _controller.add(achievement);
  }
}
