import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/widgets/report_post_sheet.dart';

void main() {
  Future<void> openSheet(
    WidgetTester tester,
    Future<void> Function(String, String) submit,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => ReportPostSheet(onSubmit: submit),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('requires a reason and submits the selected reason', (
    tester,
  ) async {
    String? reason;
    await openSheet(tester, (value, details) async {
      reason = value;
    });
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('Spam or scams'));
    await tester.pump();
    await tester.ensureVisible(find.text('Submit report'));
    await tester.tap(find.text('Submit report'));
    await tester.pumpAndSettle();
    expect(reason, 'spam');
    expect(find.text('Report post'), findsNothing);
  });

  testWidgets('Other requires details and trims them', (tester) async {
    String? sent;
    await openSheet(tester, (reason, details) async {
      sent = details;
    });
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Submit report'));
    await tester.tap(find.text('Submit report'));
    await tester.pump();
    expect(sent, isNull);
    expect(
      find.text('Please describe why you are reporting this post.'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), '  An issue  ');
    await tester.ensureVisible(find.text('Submit report'));
    await tester.tap(find.text('Submit report'));
    await tester.pumpAndSettle();
    expect(sent, 'An issue');
  });

  testWidgets('failure keeps the sheet open for retry', (tester) async {
    await openSheet(tester, (_, _) async {
      throw Exception('offline');
    });
    await tester.tap(find.text('Privacy concern'));
    await tester.pump();
    await tester.ensureVisible(find.text('Submit report'));
    await tester.tap(find.text('Submit report'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not send your report. Please try again.'),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });
}
