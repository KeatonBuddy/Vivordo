import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The Add Exercise picker (_AddExerciseScreen in fitness_screen.dart) is
// private, and its State.initState reaches Firebase-backed services
// (ExerciseCatalogService, WorkoutService), so it cannot be pumped directly
// in a widget test without a fake-Firestore dependency this project does not
// have (see exercise_picker_results_test.dart for the same constraint on the
// picker's search/sort logic). This test instead reproduces the picker's
// sliver layout in isolation: a CustomScrollView holding a SliverToBoxAdapter
// for the pinned custom section and a SliverFillRemaining for the default
// list, matching the structure in _AddExerciseScreenState.build. It verifies
// that shape does not overflow when the custom section grows large, which is
// the failure mode a plain Column mixing an unbounded child with an Expanded
// sibling produced.
Widget _pickerLayout({required int customCount, required int defaultCount}) {
  Widget row(String label) => SizedBox(height: 56, child: Text(label));

  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 700,
        child: CustomScrollView(
          slivers: [
            if (customCount > 0) ...[
              const SliverToBoxAdapter(child: Text('YOUR EXERCISES')),
              SliverToBoxAdapter(
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: const BoxDecoration(),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: customCount,
                    itemBuilder: (context, index) => row('Custom $index'),
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 72),
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: Text('ALL EXERCISES')),
            SliverFillRemaining(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(),
                child: ListView.separated(
                  itemCount: defaultCount,
                  itemBuilder: (context, index) => row('Default $index'),
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 72),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a large custom section does not overflow the picker layout', (
    tester,
  ) async {
    await tester.pumpWidget(_pickerLayout(customCount: 50, defaultCount: 20));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
