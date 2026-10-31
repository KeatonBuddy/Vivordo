import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/watch_action.dart';

void main() {
  test('queued actions are this account only, oldest first, complete', () {
    final queued = pendingWatchActions('me', [
      {
        'id': 'pendingWatch.2',
        'kind': 'reset',
        'at': 2000,
        'seconds': 60,
        'hrStart': 82,
        'hrEnd': 71,
        'account': 'me',
      },
      {
        'id': 'pendingWatch.1',
        'kind': 'checkIn',
        'at': 1000,
        'score': 80,
        'account': 'me',
      },
      {
        'id': 'pendingWatch.3',
        'kind': 'taskDone',
        'at': 3000,
        'priorityId': 'p1',
        'day': '2026-10-31',
        'account': 'me',
      },
      {'id': 'pendingWatch.4', 'kind': 'taskDone', 'at': 4000, 'account': 'me'},
      {
        'id': 'pendingWatch.5',
        'kind': 'reset',
        'at': 5000,
        'seconds': 60,
        'account': 'other',
      },
      {'id': 'pendingWatch.6', 'kind': 'dance', 'at': 6000, 'account': 'me'},
    ]);
    expect(queued.map((a) => a.id), [
      'pendingWatch.1',
      'pendingWatch.2',
      'pendingWatch.3',
    ]);
    expect(queued[0].score, 80);
    expect(queued[1].hrStart, 82);
    expect(queued[1].hrEnd, 71);
    expect(queued[2].priorityId, 'p1');
    expect(queued[2].day, '2026-10-31');
  });
}
