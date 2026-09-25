import 'dart:convert';
import 'package:flutter/material.dart';
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
      'Your workout',
      'You recorded ${workout.exerciseCount} exercises and ${workout.setCount} sets in this workout. Want advice on your performance or help planning your next session?',
      context: workoutAdviceContext(workout),
    ),
  );
}
