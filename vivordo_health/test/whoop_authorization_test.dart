import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/whoop_authorization.dart';

void main() {
  test('recognizes an explicit WHOOP reconnect response', () {
    expect(
      whoopReconnectRequired('failed-precondition', {
        'whoopReconnectRequired': true,
      }),
      isTrue,
    );
  });

  test('does not disconnect for unrelated or temporary failures', () {
    expect(whoopReconnectRequired('failed-precondition', null), isFalse);
    expect(
      whoopReconnectRequired('resource-exhausted', {
        'whoopReconnectRequired': true,
      }),
      isFalse,
    );
    expect(
      whoopReconnectRequired('unavailable', {'whoopReconnectRequired': true}),
      isFalse,
    );
  });
}
