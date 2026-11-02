import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/merge_write.dart';

void main() {
  final bed = Timestamp.fromDate(DateTime(2026, 11, 1, 23, 10));
  Map<String, dynamic> sleepWrite({double hours = 7.5}) => {
    'sleep': {
      'avg': hours,
      'entries': [
        {'start': bed, 'minutes': 450.0},
      ],
      'stages': {'deep': 60, 'rem': 90},
      'measure': FieldValue.delete(),
      'syncedAt': FieldValue.serverTimestamp(),
    },
    'date': '2026-11-02',
    'updatedAt': FieldValue.serverTimestamp(),
  };
  // As Firestore hands the day back: timestamps filled in, whole numbers as
  // ints, and fields that other writers added.
  final saved = <String, dynamic>{
    'sleep': {
      'avg': 7.5,
      'entries': [
        {'start': bed, 'minutes': 450.0},
      ],
      'stages': {'deep': 60, 'rem': 90},
      'syncedAt': Timestamp.fromDate(DateTime(2026, 11, 2, 7)),
      'source': 'apple_health',
    },
    'steps': {'sum': 6152},
    'date': '2026-11-02',
    'updatedAt': Timestamp.fromDate(DateTime(2026, 11, 2, 7)),
  };

  test('the same values again is no change, whatever the timestamps', () {
    expect(mergeWouldChange(saved, sleepWrite()), isFalse);
  });

  test('a changed value, list or new field is a change', () {
    expect(mergeWouldChange(saved, sleepWrite(hours: 7.4)), isTrue);
    final moreEntries = sleepWrite();
    (moreEntries['sleep'] as Map)['entries'] = [
      {'start': bed, 'minutes': 450.0},
      {'start': bed, 'minutes': 5.0},
    ];
    expect(mergeWouldChange(saved, moreEntries), isTrue);
    expect(
      mergeWouldChange(saved, {
        'steps': {'sum': 6152.0, 'byHour': List.filled(24, 0)},
      }),
      isTrue,
    );
  });

  test('a list entry must match exactly; a nested map only its fields', () {
    final extraKey = sleepWrite();
    (extraKey['sleep'] as Map)['entries'] = [
      {'start': bed, 'minutes': 450.0, 'end': bed},
    ];
    expect(mergeWouldChange(saved, extraKey), isTrue);
    expect(
      mergeWouldChange(saved, {
        'steps': {'sum': 6152.0},
      }),
      isFalse,
      reason: '6152.0 is stored as 6152 and merging leaves its other fields',
    );
  });

  test('deleting is a change only while the field is there', () {
    expect(mergeWouldChange(saved, {'steps': FieldValue.delete()}), isTrue);
    expect(mergeWouldChange(saved, {'hrv': FieldValue.delete()}), isFalse);
    expect(
      mergeWouldChange(null, {'hrv': FieldValue.delete()}),
      isFalse,
      reason: 'a delete on a missing day used to create an empty document',
    );
  });

  test('anything onto a missing day is a change', () {
    expect(mergeWouldChange(null, sleepWrite()), isTrue);
  });
}
