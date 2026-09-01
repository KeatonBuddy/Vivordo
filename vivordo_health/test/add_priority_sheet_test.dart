import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/add_priority_sheet.dart';

void main() {
  testWidgets('disabled Add Priority text remains visible in light mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAddPrioritySheet(context),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add Priority'),
    );
    final disabledColor = button.style?.foregroundColor?.resolve({
      WidgetState.disabled,
    });

    expect(disabledColor, Colors.white.withValues(alpha: .78));
  });
}
