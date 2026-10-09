import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:vivordo_health/src/services/daily_priority_service.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/habit_chips.dart';

// ignore: subtype_of_sealed_class, must_be_immutable
class _Ref extends Mock implements DocumentReference<Map<String, dynamic>> {
  _Ref(this.path);
  @override
  final String path;
}

void main() {
  DailyPriority habit(String title, {int target = 1, int count = 0}) =>
      DailyPriority(
        id: title,
        title: title,
        completed: count >= target,
        reference: _Ref('habits/$title'),
        isAllDay: false,
        source: 'recurring_manual',
        templateId: title,
        habit: true,
        target: target,
        count: count,
      );

  testWidgets('taps add, long presses take away, and streaks show', (
    tester,
  ) async {
    final calls = <String>[];
    final today = DateTime(2026, 10, 7);
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.dark,
        home: Scaffold(
          body: HabitChips(
            today: today,
            habits: [
              habit('Water', target: 8, count: 3),
              habit('Meds', count: 1),
              habit('Walk'),
            ],
            templates: {
              'Meds': const PriorityTemplate(
                id: 'Meds',
                title: 'Meds',
                recurrence: 'daily',
                doneDays: {'2026-10-07', '2026-10-06', '2026-10-05'},
              ),
            },
            onChanged: (h, count) => calls.add('${h.title} $count'),
          ),
        ),
      ),
    );

    expect(find.text('3/8'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // Meds streak
    await tester.tap(find.text('Water'));
    await tester.tap(find.text('Walk'));
    await tester.tap(find.text('Meds'));
    await tester.longPress(find.text('Water'));
    await tester.pump();
    expect(calls, ['Water 4', 'Walk 1', 'Meds 0', 'Water 2']);
  });
}
