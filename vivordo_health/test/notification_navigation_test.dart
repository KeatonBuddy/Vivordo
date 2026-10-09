import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/notification_navigation.dart';

void main() {
  test('Circle notifications retain the main app as a back destination', () {
    expect(notificationRouteStack('circle'), ['/home', '/circle']);
  });

  test('scan notifications retain the main app as a back destination', () {
    expect(notificationRouteStack('scan'), ['/home', '/scan']);
  });

  test('AI chat notifications retain the main app as a back destination', () {
    expect(notificationRouteStack('ai_chat'), ['/home', '/ai-chat']);
  });

  test('fitness notifications retain the main app as a back destination', () {
    expect(notificationRouteStack('fitness'), ['/home', '/fitness']);
  });

  test('unknown notification destinations safely open the main app', () {
    expect(notificationRouteStack('unknown'), ['/home']);
    expect(notificationRouteStack(null), ['/home']);
  });

  test('challenge and achievement pushes open Circle at Challenges', () {
    for (final type in [
      'challenge_invite',
      'challenge_started',
      'challenge_completed',
      'achievement_unlocked',
    ]) {
      expect(notificationRouteStack('circle', type: type), [
        '/home',
        '/circle/challenges',
      ], reason: type);
    }
    // Likes, comments and friend requests land on the feed, where requests
    // are listed first.
    expect(notificationRouteStack('circle', type: 'circle_friend_request'), [
      '/home',
      '/circle',
    ]);
  });
}
