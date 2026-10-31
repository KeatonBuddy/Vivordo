import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/watch_reset.dart';

void main() {
  test('queued resets are this account only, oldest first, rates optional', () {
    final queued = pendingWatchResets('me', [
      {
        'id': 'pendingReset.2',
        'at': 2000,
        'seconds': 60,
        'hrStart': 82,
        'hrEnd': 71,
        'account': 'me',
      },
      {'id': 'pendingReset.1', 'at': 1000, 'seconds': 60, 'account': 'me'},
      {'id': 'pendingReset.3', 'at': 3000, 'seconds': 60, 'account': 'other'},
      {'id': 'pendingReset.4', 'seconds': 60, 'account': 'me'},
    ]);
    expect(queued.map((r) => r.id), ['pendingReset.1', 'pendingReset.2']);
    expect(queued.first.hrStart, isNull);
    expect(queued.last.hrStart, 82);
    expect(queued.last.hrEnd, 71);
  });
}
