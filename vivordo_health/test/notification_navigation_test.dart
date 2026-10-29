import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/notification_navigation.dart';

void main() {
  test('tab notifications open that tab of the running app', () {
    expect(notificationDestination('scan'), (tab: 2, push: null));
    expect(notificationDestination('ai_chat'), (tab: 5, push: null));
    expect(notificationDestination('fitness'), (tab: 3, push: null));
    expect(notificationDestination('calendar'), (tab: 1, push: null));
  });

  test('unknown notification destinations safely open Home', () {
    expect(notificationDestination('unknown'), (tab: 0, push: null));
    expect(notificationDestination(null), (tab: 0, push: null));
  });

  test('Circle opens over Home, so back has somewhere to go', () {
    expect(notificationDestination('circle'), (tab: 0, push: '/circle'));
  });

  test('challenge and achievement pushes open Circle at Challenges', () {
    for (final type in [
      'challenge_invite',
      'challenge_started',
      'challenge_completed',
      'achievement_unlocked',
    ]) {
      expect(notificationDestination('circle', type: type), (
        tab: 0,
        push: '/circle/challenges',
      ), reason: type);
    }
    // Likes, comments and friend requests land on the feed, where requests
    // are listed first.
    expect(notificationDestination('circle', type: 'circle_friend_request'), (
      tab: 0,
      push: '/circle',
    ));
  });
}
