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
}
