import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/widgets/check_off.dart';

void main() {
  Widget host(Future<void> Function() onToggle, {bool completed = false}) =>
      MaterialApp(
        home: CheckOff(
          completed: completed,
          onToggle: onToggle,
          builder: (context, checked, toggle) => TextButton(
            onPressed: toggle,
            child: Text(checked ? 'done' : 'open'),
          ),
        ),
      );

  testWidgets('shows the tick, holds, closes, then saves', (tester) async {
    var saved = 0;
    await tester.pumpWidget(host(() async => saved++));
    await tester.tap(find.text('open'));
    await tester.pump();
    expect(find.text('done'), findsOneWidget);
    expect(saved, 0);
    await tester.pump(CheckOff.hold);
    expect(saved, 0); // closing
    await tester.pump();
    await tester.pump(CheckOff.close);
    expect(saved, 1);
  });

  testWidgets('a second tap during the hold takes it back', (tester) async {
    var saved = 0;
    await tester.pumpWidget(host(() async => saved++));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.tap(find.text('done'));
    await tester.pump();
    expect(find.text('open'), findsOneWidget);
    await tester.pump(CheckOff.hold + CheckOff.close);
    expect(saved, 0);
  });

  testWidgets('leaving mid-animation still saves', (tester) async {
    var saved = 0;
    await tester.pumpWidget(host(() async => saved++));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    expect(saved, 1);
    await tester.pump(CheckOff.hold + CheckOff.close);
    expect(saved, 1);
  });

  testWidgets('unchecking saves at once', (tester) async {
    var saved = 0;
    await tester.pumpWidget(host(() async => saved++, completed: true));
    await tester.tap(find.text('done'));
    expect(saved, 1);
  });
}
