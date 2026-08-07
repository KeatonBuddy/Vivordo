import 'package:flutter/material.dart';

class WorkoutActivityVisual {
  const WorkoutActivityVisual(this.icon, this.color);

  final IconData icon;
  final Color color;
}

WorkoutActivityVisual workoutActivityVisual(String name, {String? category}) {
  final normalized = name.trim().toLowerCase();
  final icon = switch (normalized) {
    'run' => Icons.directions_run_rounded,
    'walk' => Icons.directions_walk_rounded,
    'hike' => Icons.hiking_rounded,
    'stairmaster' => Icons.stairs_rounded,
    'soccer' => Icons.sports_soccer_rounded,
    'basketball' => Icons.sports_basketball_rounded,
    'football' => Icons.sports_football_rounded,
    'pickleball' ||
    'tennis' ||
    'squash' ||
    'badminton' => Icons.sports_tennis_rounded,
    'hockey' => Icons.sports_hockey_rounded,
    'volleyball' => Icons.sports_volleyball_rounded,
    'baseball' => Icons.sports_baseball_rounded,
    'golf' => Icons.golf_course_rounded,
    'dance' => Icons.music_note_rounded,
    'rugby' => Icons.sports_rugby_rounded,
    'swimming' => Icons.pool_rounded,
    'boxing' => Icons.sports_mma_rounded,
    'cycling' => Icons.directions_bike_rounded,
    'skiing' => Icons.downhill_skiing_rounded,
    'lacrosse' => Icons.sports_rounded,
    _ =>
      category == 'Cardio'
          ? Icons.directions_run_rounded
          : category == 'Sports'
          ? Icons.sports_rounded
          : Icons.fitness_center_rounded,
  };
  final color = switch (category) {
    'Cardio' => const Color(0xFF10B77A),
    'Sports' => const Color(0xFF2563EB),
    _ => const Color(0xFF6B5CE7),
  };
  return WorkoutActivityVisual(icon, color);
}
