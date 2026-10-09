import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/daily_priority_service.dart';
import 'package:vivordo_health/src/utils/panda_priority_context.dart';

void main() {
  test(
    'includes planning details, excludes completed work, preserves unknowns',
    () {
      final db = FakeFirebaseFirestore();
      DailyPriority item(
        String title, {
        bool done = false,
        Map<String, dynamic> planning = const {},
      }) => DailyPriority(
        id: title,
        title: title,
        completed: done,
        reference: db.collection('items').doc(title),
        isAllDay: false,
        source: 'manual',
        planning: planning,
      );
      final context = buildPandaPriorityContext([
        item(
          'Prepare presentation',
          planning: {'minutes': 90, 'effort': 'demanding'},
        ),
        item('Call Sam'),
        item('Finished task', done: true),
      ], DateTime(2026, 9, 24));
      expect(context, contains('Prepare presentation'));
      expect(context, contains('"estimatedMinutes":90'));
      expect(context, contains('"effort":"demanding"'));
      expect(context, contains('"scheduledAt":null'));
      expect(context, contains('"estimatedMinutes":null'));
      expect(context, isNot(contains('Finished task')));
      expect(context, contains('2 of 2'));
    },
  );
  test('empty snapshot is explicitly empty', () {
    expect(
      buildPandaPriorityContext([], DateTime(2026, 9, 24)),
      contains('0 of 0'),
    );
  });
}
