import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/burnout_view.dart';
import 'package:vivordo_health/src/utils/training_load_view.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/burnout_card.dart';
import 'package:vivordo_health/widgets/training_load_card.dart';

void main() {
  final burnout = BurnoutView.fromMap({
    'level': 'warning',
    'areas': {
      'capacity': {'elevated': true, 'worseDays': 9, 'days': 14, 'score': 2},
      'effort': {'elevated': true, 'worseDays': 8, 'days': 14, 'score': 2},
    },
  }, '2026-11-12')!;
  final load = TrainingLoadView.fromMap({
    'version': TrainingLoadView.version,
    'state': 'strained',
    'ratio': 1.6,
  }, '2026-11-12')!;

  Widget host(Widget child) => MaterialApp(
    theme: VivordoTheme.light,
    home: Scaffold(body: child),
  );

  testWidgets('a burnout alert is one row that opens out on a tap', (
    tester,
  ) async {
    var expanded = 0;
    await tester.pumpWidget(
      host(
        BurnoutCard(view: burnout, compact: true, onExpand: () => expanded++),
      ),
    );
    expect(find.text('Burnout check'), findsOneWidget);
    expect(find.text(burnout.title), findsOneWidget);
    expect(find.text(burnout.body), findsNothing);
    await tester.tap(find.text('Burnout check'));
    expect(expanded, 1);

    // Opened out: the full card, with a way to fold it back.
    var folded = 0;
    await tester.pumpWidget(
      host(BurnoutCard(view: burnout, onCollapse: () => folded++)),
    );
    expect(find.text(burnout.body), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Show less'));
    expect(folded, 1);
  });

  testWidgets('a training-load alert starts as one row', (tester) async {
    await tester.pumpWidget(host(TrainingLoadAlert(view: load, compact: true)));
    expect(find.text('Training load'), findsOneWidget);
    expect(find.text('Strained'), findsOneWidget);
    expect(find.text('Details ›'), findsNothing);
  });
}
