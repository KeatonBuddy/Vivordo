import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:vivordo_health/screens/all_priorities_screen.dart';
import 'package:vivordo_health/src/services/daily_priority_service.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/swipe_to_delete.dart';

// ignore: subtype_of_sealed_class, must_be_immutable
class _Ref extends Mock implements DocumentReference<Map<String, dynamic>> {
  _Ref(this.path);
  @override
  final String path;
}

void main() {
  final today = DateUtils.dateOnly(DateTime.now());
  DailyPriority priority(
    String id,
    int offset, {
    String? template,
    bool completed = false,
  }) => DailyPriority(
    id: id,
    title: id,
    completed: completed,
    reference: _Ref('priorities/$id'),
    isAllDay: false,
    source: template == null ? 'manual' : 'recurring_manual',
    date: today.add(Duration(days: offset)),
    templateId: template,
  );
  test(
    'recurring schedules appear once using their earliest available occurrence',
    () {
      final result = distinctPriorities([
        priority('tomorrow-repeat', 1, template: 'a'),
        priority('today-repeat', 0, template: 'a'),
        priority('one-off', 0),
      ]);
      expect(result.map((p) => p.id), containsAll(['today-repeat', 'one-off']));
      expect(result.length, 2);
    },
  );
  for (final light in [true, false]) {
    testWidgets(
      'plan groups, overdue, completed and actions in ${light ? 'light' : 'dark'} mode',
      (tester) async {
        tester.view.physicalSize = const Size(430, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var added = false;
        String? edited, deleted;
        await tester.pumpWidget(
          MaterialApp(
            theme: light ? VivordoTheme.light : VivordoTheme.dark,
            home: AllPrioritiesScreen(
              priorities: Stream.value([
                priority('Finish design', 0),
                priority('Completed task', 0, completed: true),
                priority('Submit update', 1),
                priority('Old errand', -2),
                priority('Morning planning', 0, template: 'routine'),
                priority('Next planning', 1, template: 'routine'),
              ]),
              onAdd: (_) async {
                added = true;
              },
              onEdit: (_, p) async {
                edited = p.id;
              },
              onDelete: (p) async {
                deleted = p.id;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        // Overdue counts toward today's work.
        expect(find.text('3 left today'), findsOneWidget);
        expect(find.text('OVERDUE'), findsOneWidget);
        expect(find.textContaining('From '), findsOneWidget);
        expect(find.text('TODAY · 1 OF 3'), findsOneWidget);
        expect(find.text('TOMORROW'), findsOneWidget);
        // Repeating ones appear once, on their first day.
        expect(find.text('Morning planning'), findsOneWidget);
        expect(find.text('Next planning'), findsNothing);
        // Completed ones stay collapsed until asked for.
        expect(find.text('Completed task'), findsNothing);
        await tester.tap(find.text('1 completed'));
        await tester.pumpAndSettle();
        expect(find.text('Completed task'), findsOneWidget);

        await tester.tap(find.text('Finish design'));
        expect(edited, 'Finish design');
        await tester.tap(find.byTooltip('Add priority'));
        expect(added, isTrue);

        await tester.drag(find.text('Submit update'), const Offset(-200, 0));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.ancestor(
              of: find.text('Submit update'),
              matching: find.byType(SwipeToDelete),
            ),
            matching: find.text('Delete'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Delete priority?'), findsOneWidget);
        await tester.tap(find.text('Delete').last);
        await tester.pumpAndSettle();
        expect(deleted, 'Submit update');

        await tester.tap(find.text('Repeating · 1'));
        await tester.pumpAndSettle();
        expect(find.text('Morning planning'), findsOneWidget);
        expect(find.text('Today'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
