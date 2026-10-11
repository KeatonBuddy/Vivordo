import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/journal_summary.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/journal_entry_sheet.dart';

void main() {
  Future<List<JournalDraft>> open(
    WidgetTester tester, {
    JournalItem? editing,
  }) async {
    final saved = <JournalDraft>[];
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.dark,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showJournalEntrySheet(
              context,
              date: DateTime(2026, 9, 30),
              editing: editing,
              prompt: 'How did Standup go?',
              onSave: (draft) async => saved.add(draft),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return saved;
  }

  testWidgets('no mood is preselected and saving asks for one', (tester) async {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    final saved = await open(tester);
    expect(find.text('How did Standup go?'), findsOneWidget);
    expect(find.text('How are you feeling?'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'A calm day.');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(saved, isEmpty);
    expect(haptics, contains('HapticFeedbackType.heavyImpact'));
    expect(find.text('Wednesday, Sep 30'), findsOneWidget);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Good'));
    await tester.tap(find.text('Share with Circle'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, hasLength(1));
    expect(saved.single.text, 'A calm day.');
    expect(saved.single.mood, 'Good');
    expect(saved.single.shared, isTrue);
    expect(find.text('Wednesday, Sep 30'), findsNothing);
  });

  testWidgets('editing starts from the entry and keeps its mood', (
    tester,
  ) async {
    final saved = await open(
      tester,
      editing: JournalItem(
        id: 'e1',
        text: 'Long day',
        date: DateTime(2026, 9, 30, 21),
        mood: 'Low',
        shared: true,
      ),
    );
    expect(find.text('Long day'), findsOneWidget);
    expect(find.text('Shared with your Circle'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved.single.mood, 'Low');
    expect(saved.single.shared, isTrue);
  });
}
