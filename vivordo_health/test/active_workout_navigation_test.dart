import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/active_workout_navigation.dart';

void main() {
  testWidgets('focus returns to the same nested workout state', (tester) async {
    final root = GlobalKey<NavigatorState>();
    final nested = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: root,
        home: Navigator(
          key: nested,
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Fitness')),
          ),
        ),
      ),
    );
    nested.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const _Workout()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sets: 0'));
    await tester.pump();
    nested.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Exercise picker')),
      ),
    );
    await tester.pumpAndSettle();
    root.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Overlay')),
      ),
    );
    await tester.pumpAndSettle();
    expect(ActiveWorkoutNavigation.focusExisting(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Sets: 1'), findsOneWidget);
    expect(find.text('Exercise picker'), findsNothing);
    expect(ActiveWorkoutNavigation.focusExisting(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Sets: 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(ActiveWorkoutNavigation.focusExisting(), isFalse);
  });
}

class _Workout extends StatefulWidget {
  const _Workout();
  @override
  State<_Workout> createState() => _WorkoutState();
}

class _WorkoutState extends State<_Workout> {
  int count = 0;
  Route<dynamic>? route;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    route = ModalRoute.of(context);
    ActiveWorkoutNavigation.register(context);
  }

  @override
  void dispose() {
    ActiveWorkoutNavigation.unregister(route);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: TextButton(
      onPressed: () => setState(() => count++),
      child: Text('Sets: $count'),
    ),
  );
}
