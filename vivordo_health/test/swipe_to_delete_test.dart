import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/swipe_to_delete.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget row) => tester.pumpWidget(
    MaterialApp(
      theme: VivordoTheme.light,
      home: Scaffold(body: Center(child: row)),
    ),
  );

  testWidgets('Hide acts straight away; Delete asks first', (tester) async {
    var hidden = 0;
    await pump(
      tester,
      SwipeToDelete(
        actionLabel: 'Hide',
        actionIcon: CupertinoIcons.eye_slash,
        confirmTitle: null,
        onDelete: () async => hidden++,
        child: const SizedBox(height: 56, child: Text('Plan my day')),
      ),
    );
    await tester.drag(find.text('Plan my day'), const Offset(-120, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();
    expect(hidden, 1);

    var deleted = 0;
    await pump(
      tester,
      SwipeToDelete(
        confirmTitle: 'Delete priority?',
        onDelete: () async => deleted++,
        child: const SizedBox(height: 56, child: Text('Read chapter 4')),
      ),
    );
    await tester.drag(find.text('Read chapter 4'), const Offset(-120, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete priority?'), findsOneWidget);
    expect(deleted, 0);
  });
}
