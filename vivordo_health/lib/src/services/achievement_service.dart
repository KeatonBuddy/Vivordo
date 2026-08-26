import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'activity_goals_service.dart';
import 'achievement_unlock_service.dart';
import 'calendar_service.dart';
import 'circle_profile_service.dart';
import 'outlook_calendar_service.dart';

class AchievementProgress {
  const AchievementProgress({
    required this.id,
    required this.name,
    required this.requirement,
    required this.goalBadgeAsset,
    required this.earned,
    required this.progress,
    this.target = 1,
    this.earnedBadgeAsset,
    this.tier,
    this.goalTier,
    this.progressUnit,
    this.earnedAt,
  });

  final String id;
  final String name;
  final String requirement;
  final String goalBadgeAsset;
  final String? earnedBadgeAsset;
  final bool earned;
  final int progress;
  final int target;
  final String? tier;
  final String? goalTier;
  final String? progressUnit;
  final DateTime? earnedAt;

  bool get unlocked => earned || tier != null;

  AchievementProgress copyWith({bool? earned, DateTime? earnedAt}) =>
      AchievementProgress(
        id: id,
        name: name,
        requirement: requirement,
        goalBadgeAsset: goalBadgeAsset,
        earnedBadgeAsset: earnedBadgeAsset,
        earned: earned ?? this.earned,
        progress: progress,
        target: target,
        tier: tier,
        goalTier: goalTier,
        progressUnit: progressUnit,
        earnedAt: earnedAt ?? this.earnedAt,
      );
}

@visibleForTesting
int countCompletedActivityRingDays({
  required Iterable<Map<String, dynamic>> metricDays,
  required ActivityGoals goals,
}) {
  num? metricSum(Map<String, dynamic> day, String key) {
    final metric = day[key];
    return metric is Map ? metric['sum'] as num? : null;
  }

  return metricDays.where((day) {
    final steps = metricSum(day, 'steps');
    final activeCalories = metricSum(day, 'active_calories');
    final exerciseMinutes = metricSum(day, 'exercise_time');
    return steps != null &&
        activeCalories != null &&
        exerciseMinutes != null &&
        steps >= goals.steps &&
        activeCalories >= goals.activeCalories &&
        exerciseMinutes >= goals.exerciseMinutes;
  }).length;
}

/// Watches achievement inputs for the lifetime of the signed-in app.
class AchievementMonitor {
  AchievementMonitor._(this._userId);

  final String _userId;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _debounce;
  String? _workoutSignature;
  String? _metricSignature;
  String? _activityGoalsSignature;
  String? _journalSignature;
  String? _profileSignature;
  String? _friendSignature;

  static AchievementMonitor? start() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final monitor = AchievementMonitor._(user.uid);
    monitor._listen();
    return monitor;
  }

  void _listen() {
    final userRef = FirebaseFirestore.instance.collection('users').doc(_userId);
    _subscriptions.add(
      userRef
          .collection('workouts')
          .snapshots()
          .listen(
            (snapshot) => _updateSignature(
              snapshot.docs
                  .map((doc) {
                    final data = doc.data();
                    final exercises = (data['exercises'] as List? ?? const [])
                        .whereType<Map>()
                        .map((exercise) => exercise['category'])
                        .join(',');
                    return '${doc.id}:${data['activityCategory']}:$exercises';
                  })
                  .join('|'),
              (value) => _workoutSignature = value,
              () => _workoutSignature,
            ),
            onError: _logMonitorError,
          ),
    );
    _subscriptions.add(
      userRef
          .collection('metrics_daily')
          .snapshots()
          .listen(
            (snapshot) => _updateSignature(
              snapshot.docs
                  .map((doc) {
                    final data = doc.data();
                    final scan = data['heart_rate_scan'];
                    var count = 0;
                    if (scan is Map) {
                      final entries = scan['entries'];
                      count = entries is List && entries.isNotEmpty
                          ? entries.length
                          : (scan['source'] == 'camera_ppg' ||
                                scan['avg'] is num)
                          ? 1
                          : 0;
                    }
                    num? sumFor(String key) {
                      final metric = data[key];
                      return metric is Map ? metric['sum'] as num? : null;
                    }

                    return '${doc.id}:$count:${sumFor('steps')}:${sumFor('active_calories')}:${sumFor('exercise_time')}';
                  })
                  .join('|'),
              (value) => _metricSignature = value,
              () => _metricSignature,
            ),
            onError: _logMonitorError,
          ),
    );
    _subscriptions.add(
      userRef.snapshots().listen((snapshot) {
        final goals = ActivityGoals.fromUserData(snapshot.data());
        _updateSignature(
          '${goals.steps}:${goals.activeCalories}:${goals.exerciseMinutes}',
          (value) => _activityGoalsSignature = value,
          () => _activityGoalsSignature,
        );
      }, onError: _logMonitorError),
    );
    _subscriptions.add(
      userRef
          .collection('journal_entries')
          .snapshots()
          .listen(
            (snapshot) => _updateSignature(
              snapshot.docs.map((doc) => doc.id).join('|'),
              (value) => _journalSignature = value,
              () => _journalSignature,
            ),
            onError: _logMonitorError,
          ),
    );
    _subscriptions.add(
      CircleProfileService.watchCurrentProfile().listen(
        (profile) => _updateSignature(
          profile?.username.trim() ?? '',
          (value) => _profileSignature = value,
          () => _profileSignature,
        ),
        onError: _logMonitorError,
      ),
    );
    _subscriptions.add(
      CircleProfileService.watchFriends().listen(
        (friends) => _updateSignature(
          (friends.map((friend) => friend.uid).toList()..sort()).join('|'),
          (value) => _friendSignature = value,
          () => _friendSignature,
        ),
        onError: _logMonitorError,
      ),
    );
    scheduleNow();
  }

  void _updateSignature(
    String value,
    void Function(String) setValue,
    String? Function() getValue,
  ) {
    if (getValue() == value) return;
    setValue(value);
    _schedule();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), scheduleNow);
  }

  void scheduleNow() {
    _debounce?.cancel();
    _debounce = null;
    unawaited(
      AchievementService.reconcileAll().catchError((Object error) {
        debugPrint('AchievementMonitor: reconciliation failed: $error');
        return <AchievementProgress>[];
      }),
    );
  }

  void _logMonitorError(Object error) {
    debugPrint('AchievementMonitor: source listener failed: $error');
  }

  Future<void> dispose() async {
    _debounce?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }
}

/// Reconciles achievements whose progress is derived from user-owned data.
class AchievementService {
  AchievementService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static Future<List<AchievementProgress>>? _activeReconciliation;

  static Future<List<AchievementProgress>> reconcileAll({
    CircleProfile? profile,
  }) {
    final active = _activeReconciliation;
    if (active != null) return active;
    final future = _runReconciliation(profile);
    _activeReconciliation = future;
    return future;
  }

  static Future<List<AchievementProgress>> _runReconciliation(
    CircleProfile? profile,
  ) async {
    try {
      return await _reconcileAll(profile: profile);
    } finally {
      _activeReconciliation = null;
    }
  }

  static Future<List<AchievementProgress>> _reconcileAll({
    CircleProfile? profile,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const [];

    CircleProfile? resolvedProfile = profile;
    if (resolvedProfile == null) {
      try {
        resolvedProfile = await CircleProfileService.watchCurrentProfile().first
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        resolvedProfile = null;
      }
    }

    final userRef = _firestore.collection('users').doc(user.uid);
    final results = await Future.wait<Object>([
      userRef.collection('workouts').get(),
      userRef.collection('metrics_daily').get(),
      userRef.collection('journal_entries').count().get(),
      userRef.collection('achievements').get(),
      CircleProfileService.watchFriends().first,
      _hasGoogleCalendar(),
      _hasOutlookCalendar(),
      userRef.get(),
    ]);

    final workouts = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final metricDays = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final journalEntryCount =
        (results[2] as AggregateQuerySnapshot).count?.toInt() ?? 0;
    final savedAchievements = results[3] as QuerySnapshot<Map<String, dynamic>>;
    final friends = results[4] as List<CircleProfile>;
    final calendarConnected = (results[5] as bool) || (results[6] as bool);
    final userSnapshot = results[7] as DocumentSnapshot<Map<String, dynamic>>;
    final activityGoals = ActivityGoals.fromUserData(userSnapshot.data());
    final savedById = {
      for (final document in savedAchievements.docs) document.id: document,
    };

    final heartRateScanCount = metricDays.docs.fold<int>(0, (total, document) {
      final scan = document.data()['heart_rate_scan'];
      if (scan is! Map) return total;
      final entries = scan['entries'];
      if (entries is List && entries.isNotEmpty) return total + entries.length;
      if (scan['source'] == 'camera_ppg' || scan['avg'] is num) {
        return total + 1;
      }
      return total;
    });
    final cardioOrSportsActivityCount = workouts.docs.where((document) {
      final data = document.data();
      final activityCategory = data['activityCategory'] as String?;
      if (activityCategory == 'Cardio' || activityCategory == 'Sports') {
        return true;
      }
      final exercises = (data['exercises'] as List? ?? const [])
          .whereType<Map>()
          .toList(growable: false);
      if (exercises.isEmpty) return false;
      return exercises.every((exercise) {
        final category = exercise['category'] as String?;
        return category == 'Cardio' || category == 'Sports';
      });
    }).length;
    final strengthWorkoutCount =
        workouts.docs.length - cardioOrSportsActivityCount;
    final completedActivityRingDays = countCompletedActivityRingDays(
      metricDays: metricDays.docs.map((document) => document.data()),
      goals: activityGoals,
    );

    final momentum = _tierProgress(
      id: 'workout_momentum',
      savedTier: savedById['workout_momentum']?.data()['tier'] as String?,
      value: strengthWorkoutCount,
      bronze: 5,
      silver: 10,
      gold: 100,
    );
    final endurance = _tierProgress(
      id: 'endurance',
      savedTier: savedById['endurance']?.data()['tier'] as String?,
      value: cardioOrSportsActivityCount,
      bronze: 5,
      silver: 10,
      gold: 100,
    );
    final pulse = _tierProgress(
      id: 'pulse_check',
      savedTier: savedById['pulse_check']?.data()['tier'] as String?,
      value: heartRateScanCount,
      bronze: 10,
      silver: 100,
      gold: 1000,
    );
    final story = _tierProgress(
      id: 'story_keeper',
      savedTier: savedById['story_keeper']?.data()['tier'] as String?,
      value: journalEntryCount,
      bronze: 5,
      silver: 20,
      gold: 100,
    );
    final fullCircle = _tierProgress(
      id: 'full_circle',
      savedTier: savedById['full_circle']?.data()['tier'] as String?,
      value: completedActivityRingDays,
      bronze: 7,
      silver: 30,
      gold: 100,
    );

    final checks = <AchievementProgress>[
      _singleAchievement(
        id: 'in_motion',
        name: 'In Motion',
        requirement: 'Complete your first activity',
        unlocked: workouts.docs.isNotEmpty,
      ),
      _singleAchievement(
        id: 'first_pulse',
        name: 'First Pulse',
        requirement: 'Complete your first heart-rate scan',
        unlocked: heartRateScanCount > 0,
      ),
      _singleAchievement(
        id: 'dear_diary',
        name: 'Dear Diary',
        requirement: 'Write your first journal entry',
        unlocked: journalEntryCount > 0,
      ),
      _singleAchievement(
        id: 'your_circle',
        name: 'Your Circle',
        requirement: 'Create your Circle profile',
        unlocked: resolvedProfile?.username.trim().isNotEmpty ?? false,
      ),
      _singleAchievement(
        id: 'better_together',
        name: 'Better Together',
        requirement: 'Add your first friend',
        unlocked: friends.isNotEmpty,
      ),
      _singleAchievement(
        id: 'day_planner',
        name: 'Day Planner',
        requirement: 'Connect your calendar',
        unlocked: calendarConnected,
      ),
      _tierAchievement(
        progress: momentum,
        name: 'Workout Momentum',
        requirement: 'Complete ${momentum.target} strength workouts',
        progressUnit: 'workouts',
      ),
      _tierAchievement(
        progress: endurance,
        name: 'Endurance',
        requirement: 'Complete ${endurance.target} cardio or sports activities',
        progressUnit: 'activities',
      ),
      _tierAchievement(
        progress: pulse,
        name: 'Pulse Check',
        requirement: 'Complete ${pulse.target} heart-rate scans',
        progressUnit: 'scans',
      ),
      _tierAchievement(
        progress: story,
        name: 'Story Keeper',
        requirement: 'Write ${story.target} journal entries',
        progressUnit: 'entries',
      ),
      _tierAchievement(
        progress: fullCircle,
        name: 'Full Circle',
        requirement: 'Fill all activity rings on ${fullCircle.target} days',
        progressUnit: 'days',
      ),
    ];

    final batch = _firestore.batch();
    final now = DateTime.now();
    final newlyUnlocked = <AchievementUnlock>[];
    final resolved = checks
        .map((achievement) {
          final savedData = savedById[achievement.id]?.data();
          final wasEarned = savedData?['completed'] == true;
          final isEarned = achievement.earned || wasEarned;
          final savedTier = savedData?['tier'] as String?;
          final tierAdvanced =
              _tierRank(achievement.tier) > _tierRank(savedTier);
          final wasUnlocked = wasEarned || savedTier != null;
          final newUnlock =
              achievement.unlocked && (!wasUnlocked || tierAdvanced);
          final earnedAt = newUnlock
              ? now
              : (savedData?['earnedAt'] as Timestamp?)?.toDate();
          batch.set(
            userRef.collection('achievements').doc(achievement.id),
            {
              'achievementId': achievement.id,
              'name': achievement.name,
              'requirement': achievement.requirement,
              'badgeAsset': achievement.earnedBadgeAsset,
              'progress': achievement.progress,
              'target': achievement.target,
              if (achievement.progressUnit != null)
                'progressUnit': achievement.progressUnit,
              'completed': isEarned,
              if (achievement.tier != null) 'tier': achievement.tier,
              if (achievement.goalTier != null)
                'nextTier': achievement.goalTier,
              if (newUnlock) 'earnedAt': FieldValue.serverTimestamp(),
              if (tierAdvanced)
                'earnedTiers': FieldValue.arrayUnion([achievement.tier]),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          if (newUnlock) {
            final unlockedRequirement = _requirementForTier(achievement);
            final activityId = achievement.tier == null
                ? 'achievement_${achievement.id}'
                : 'achievement_${achievement.id}_${achievement.tier}';
            batch.set(
              userRef.collection('circle_activity').doc(activityId),
              {
                'kind': 'achievement',
                'name': achievement.name,
                'summary': unlockedRequirement,
                'achievementId': achievement.id,
                'achievementBadgeAsset': achievement.earnedBadgeAsset,
                'achievementTier': ?achievement.tier,
                'minutes': 0,
                'day': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
            newlyUnlocked.add(
              AchievementUnlock(
                id: activityId,
                name: achievement.name,
                requirement: unlockedRequirement,
                badgeAsset:
                    achievement.earnedBadgeAsset ?? achievement.goalBadgeAsset,
                tier: achievement.tier,
              ),
            );
          }
          return achievement.copyWith(earned: isEarned, earnedAt: earnedAt);
        })
        .toList(growable: false);

    await batch.commit();
    for (final achievement in newlyUnlocked) {
      AchievementUnlockService.announce(achievement);
    }
    return resolved;
  }

  static Future<void> reconcileStoryKeeper() async {
    await reconcileAll();
  }

  static AchievementProgress _singleAchievement({
    required String id,
    required String name,
    required String requirement,
    required bool unlocked,
  }) => AchievementProgress(
    id: id,
    name: name,
    requirement: requirement,
    goalBadgeAsset: 'assets/achievements/$id.png',
    earned: unlocked,
    progress: unlocked ? 1 : 0,
  );

  static AchievementProgress _tierAchievement({
    required _TierProgress progress,
    required String name,
    required String requirement,
    required String progressUnit,
  }) => AchievementProgress(
    id: progress.id,
    name: name,
    requirement: requirement,
    goalBadgeAsset:
        'assets/achievements/${progress.id}_${progress.goalBadgeTier}.png',
    earnedBadgeAsset:
        'assets/achievements/${progress.id}_${progress.earnedBadgeTier}.png',
    earned: progress.tier == 'gold',
    progress: progress.value,
    target: progress.target,
    tier: progress.tier,
    goalTier: progress.goalTier,
    progressUnit: progressUnit,
  );

  static _TierProgress _tierProgress({
    required String id,
    required String? savedTier,
    required int value,
    required int bronze,
    required int silver,
    required int gold,
  }) {
    final calculatedTier = value >= gold
        ? 'gold'
        : value >= silver
        ? 'silver'
        : value >= bronze
        ? 'bronze'
        : null;
    final tier = _tierRank(savedTier) >= _tierRank(calculatedTier)
        ? savedTier
        : calculatedTier;
    final target = switch (tier) {
      'gold' => gold,
      'silver' => gold,
      'bronze' => silver,
      _ => bronze,
    };
    final goalTier = switch (tier) {
      'gold' => null,
      'silver' => 'gold',
      'bronze' => 'silver',
      _ => 'bronze',
    };
    return _TierProgress(
      id: id,
      value: value,
      target: target,
      tier: tier,
      goalTier: goalTier,
      goalBadgeTier: goalTier ?? tier ?? 'bronze',
      earnedBadgeTier: tier ?? 'bronze',
    );
  }

  static String _requirementForTier(AchievementProgress achievement) {
    final tier = achievement.tier;
    if (tier == null) return achievement.requirement;
    final target = switch ((achievement.id, tier)) {
      ('workout_momentum', 'bronze') => 5,
      ('workout_momentum', 'silver') => 10,
      ('workout_momentum', 'gold') => 100,
      ('endurance', 'bronze') => 5,
      ('endurance', 'silver') => 10,
      ('endurance', 'gold') => 100,
      ('pulse_check', 'bronze') => 10,
      ('pulse_check', 'silver') => 100,
      ('pulse_check', 'gold') => 1000,
      ('story_keeper', 'bronze') => 5,
      ('story_keeper', 'silver') => 20,
      ('story_keeper', 'gold') => 100,
      ('full_circle', 'bronze') => 7,
      ('full_circle', 'silver') => 30,
      ('full_circle', 'gold') => 100,
      _ => achievement.target,
    };
    return switch (achievement.id) {
      'workout_momentum' => 'Complete $target strength workouts',
      'endurance' => 'Complete $target cardio or sports activities',
      'pulse_check' => 'Complete $target heart-rate scans',
      'story_keeper' => 'Write $target journal entries',
      'full_circle' => 'Fill all activity rings on $target days',
      _ => achievement.requirement,
    };
  }

  static Future<bool> _hasGoogleCalendar() async {
    try {
      return await CalendarService.hasCalendarAccess();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _hasOutlookCalendar() async {
    try {
      return await OutlookCalendarService.isSignedIn();
    } catch (_) {
      return false;
    }
  }

  static int _tierRank(String? tier) => switch (tier) {
    'bronze' => 1,
    'silver' => 2,
    'gold' => 3,
    _ => 0,
  };
}

class _TierProgress {
  const _TierProgress({
    required this.id,
    required this.value,
    required this.target,
    required this.tier,
    required this.goalTier,
    required this.goalBadgeTier,
    required this.earnedBadgeTier,
  });

  final String id;
  final int value;
  final int target;
  final String? tier;
  final String? goalTier;
  final String goalBadgeTier;
  final String earnedBadgeTier;
}
