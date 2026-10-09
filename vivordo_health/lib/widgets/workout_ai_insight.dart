import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../src/services/workout_service.dart';
import 'contextual_insight_bar.dart';

String workoutAdviceContext(SavedWorkout workout) => jsonEncode({
  'workoutId': workout.id,
  'name': workout.displayName,
  'completedAt': workout.completedAt.toIso8601String(),
  'durationSeconds': workout.durationSeconds,
  'exerciseCount': workout.exerciseCount,
  'setCount': workout.setCount,
  'exercises': workout.exercises.map((e) => e.toMap()).toList(),
  'limitations':
      'Only recorded sets and saved previous-attempt comparisons are available. No perceived effort, pain, or form data.',
});

String workoutInsightTitle(SavedWorkout workout) =>
    '${workout.displayName} · ${DateFormat('MMM d').format(workout.completedAt.toLocal())}';

/// Publishes local context only. Claude runs after opening Panda, not here.
class WorkoutAiInsight extends StatelessWidget {
  const WorkoutAiInsight({
    super.key,
    required this.workout,
    required this.child,
  });
  final SavedWorkout workout;
  final Widget child;
  @override
  Widget build(BuildContext context) => child.withScreenInsight(
    ScreenInsight(
      'workout_summary',
      // Names the workout so each chat about one stays tied to it ("Asked
      // from Workout · Sep 30"), even after asking about another.
      workoutInsightTitle(workout),
      'You recorded ${workout.exerciseCount} exercises and ${workout.setCount} sets in this workout. Want advice on your performance or help planning your next session?',
      context: workoutAdviceContext(workout),
    ),
  );
}
