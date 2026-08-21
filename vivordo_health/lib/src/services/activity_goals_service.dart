import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

const Map<String, int> kDefaultStrengthGoals = {
  'Chest': 10,
  'Back': 10,
  'Legs': 12,
  'Shoulders': 8,
  'Arms': 10,
};

class ActivityGoals {
  const ActivityGoals({
    this.steps = 10000,
    this.activeCalories = 700,
    this.exerciseMinutes = 40,
    this.workoutsPerWeek = 4,
  });

  final int steps;
  final int activeCalories;
  final int exerciseMinutes;
  final int workoutsPerWeek;

  factory ActivityGoals.fromUserData(Map<String, dynamic>? data) {
    final preferences = data?['preferences'] as Map?;
    final goals = preferences?['activityGoals'] as Map?;
    int positiveInt(String key, int fallback) {
      final value = (goals?[key] as num?)?.round();
      return value != null && value > 0 ? value : fallback;
    }

    return ActivityGoals(
      steps: positiveInt('steps', 10000),
      activeCalories: positiveInt('activeCalories', 700),
      exerciseMinutes: positiveInt('exerciseMinutes', 40),
      workoutsPerWeek: positiveInt('workoutsPerWeek', 4),
    );
  }

  Map<String, int> toMap() => {
    'steps': steps,
    'activeCalories': activeCalories,
    'exerciseMinutes': exerciseMinutes,
    'workoutsPerWeek': workoutsPerWeek,
  };
}

class ActivityGoalsService {
  const ActivityGoalsService._();

  static String? _watchedUid;
  static Stream<ActivityGoals>? _goalsStream;

  static Stream<ActivityGoals> watch() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(const ActivityGoals());
    if (_watchedUid == user.uid && _goalsStream != null) return _goalsStream!;
    _watchedUid = user.uid;
    _goalsStream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .asyncMap((snapshot) async {
          final data = snapshot.data();
          final preferences = data?['preferences'] as Map?;
          if (preferences?['activityGoals'] is! Map) {
            const defaults = ActivityGoals();
            await save(defaults);
            return defaults;
          }
          return ActivityGoals.fromUserData(data);
        })
        .asBroadcastStream();
    return _goalsStream!;
  }

  static Future<ActivityGoals> load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const ActivityGoals();
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = snapshot.data();
    final preferences = data?['preferences'] as Map?;
    if (preferences?['activityGoals'] is! Map) {
      const defaults = ActivityGoals();
      await save(defaults);
      return defaults;
    }
    return ActivityGoals.fromUserData(data);
  }

  static Map<String, int> strengthGoalsFromUserData(
    Map<String, dynamic>? data,
  ) {
    final preferences = data?['preferences'] as Map?;
    final stored = preferences?['strengthGoals'] as Map?;
    return {
      for (final entry in kDefaultStrengthGoals.entries)
        entry.key: switch (stored?[entry.key]) {
          final num value when value > 0 => value.round(),
          _ => entry.value,
        },
    };
  }

  static Future<Map<String, int>> loadStrengthGoals() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Map.of(kDefaultStrengthGoals);
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = snapshot.data();
    final preferences = data?['preferences'] as Map?;
    if (preferences?['strengthGoals'] is! Map) {
      await saveStrengthGoals(kDefaultStrengthGoals);
      return Map.of(kDefaultStrengthGoals);
    }
    return strengthGoalsFromUserData(data);
  }

  static Future<void> save(ActivityGoals goals) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'preferences': {'activityGoals': goals.toMap()},
    }, SetOptions(merge: true));
  }

  static Future<void> saveStrengthGoals(Map<String, int> goals) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final sanitized = {
      for (final entry in kDefaultStrengthGoals.entries)
        entry.key: (goals[entry.key] ?? entry.value).clamp(1, 1000),
    };
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'preferences': {'strengthGoals': sanitized},
    }, SetOptions(merge: true));
  }
}
