import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/mood_widget_values.dart';

void main() {
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 10, 10, hour, minute);

  test('queued taps are this account only, oldest first', () {
    final queued = pendingMoodCheckIns('me', [
      {
        'id': 'b',
        'score': 95,
        'label': 'Great',
        'at': at(14, 16).millisecondsSinceEpoch,
        'account': 'me',
      },
      {
        'id': 'a',
        'score': 75,
        'label': 'Good',
        'at': at(14, 14).millisecondsSinceEpoch,
        'account': 'me',
      },
      {
        'id': 'c',
        'score': 10,
        'label': 'Awful',
        'at': at(9).millisecondsSinceEpoch,
        'account': 'someone else',
      },
      {'id': 'd', 'score': 'bad', 'label': 'Good', 'at': 0, 'account': 'me'},
      'not a map',
    ]);
    expect(queued.map((c) => c.id), ['a', 'b']);
    expect(queued.first.score, 75);
    expect(queued.first.at, at(14, 14));
  });

  test('counts every check-in today and finds the latest', () {
    final values = moodWidgetValues({
      'avg': 75,
      'entries': [
        {'score': 50, 'timestamp': Timestamp.fromDate(at(9))},
        {'score': 95, 'timestamp': Timestamp.fromDate(at(14, 16))},
        {'score': 75, 'timestamp': Timestamp.fromDate(at(14, 14))},
      ],
    });
    expect(values['moodTodayCount'], 3);
    expect(values['moodLastScore'], 95);
    expect(values['moodLastAt'], at(14, 16).millisecondsSinceEpoch);
  });

  test('an older day without entries still counts its one check-in', () {
    final values = moodWidgetValues({
      'avg': 30.4,
      'checkInAt': Timestamp.fromDate(at(8)),
    });
    expect(values['moodTodayCount'], 1);
    expect(values['moodLastScore'], 30);
  });

  test('no check-ins yet', () {
    expect(moodWidgetValues(null), {
      'moodTodayCount': 0,
      'moodLastScore': -1,
      'moodLastAt': 0,
    });
  });
}
