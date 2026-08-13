import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'achievement_unlock_service.dart';

/// Reconciles achievements whose progress is derived from user-owned data.
class AchievementService {
  AchievementService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Recounts journal entries so Story Keeper progress also moves when an
  /// entry is deleted. Earned tiers remain earned, while the live progress
  /// count always reflects the source collection.
  static Future<void> reconcileStoryKeeper() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userRef = _firestore.collection('users').doc(user.uid);
    final achievementRef = userRef
        .collection('achievements')
        .doc('story_keeper');
    final results = await Future.wait<Object>([
      userRef.collection('journal_entries').count().get(),
      achievementRef.get(),
    ]);
    final entryCount =
        (results[0] as AggregateQuerySnapshot).count?.toInt() ?? 0;
    final saved = results[1] as DocumentSnapshot<Map<String, dynamic>>;
    final savedData = saved.data();
    final savedTier = savedData?['tier'] as String?;
    final calculatedTier = entryCount >= 100
        ? 'gold'
        : entryCount >= 20
        ? 'silver'
        : entryCount >= 5
        ? 'bronze'
        : null;
    final tier = _higherTier(savedTier, calculatedTier);
    final tierAdvanced = _tierRank(tier) > _tierRank(savedTier);
    final target = switch (tier) {
      'gold' => 100,
      'silver' => 100,
      'bronze' => 20,
      _ => 5,
    };
    final nextTier = switch (tier) {
      'gold' => null,
      'silver' => 'gold',
      'bronze' => 'silver',
      _ => 'bronze',
    };
    final badgeTier = tier ?? 'bronze';
    final unlockedTarget = switch (tier) {
      'gold' => 100,
      'silver' => 20,
      _ => 5,
    };
    final batch = _firestore.batch();
    batch.set(achievementRef, {
      'achievementId': 'story_keeper',
      'name': 'Story Keeper',
      'requirement': 'Write $target journal entries',
      'badgeAsset': tier == null
          ? null
          : 'assets/achievements/story_keeper_$tier.png',
      'progress': entryCount,
      'target': target,
      'progressUnit': 'entries',
      'completed': tier == 'gold',
      'tier': ?tier,
      'nextTier': nextTier,
      if (tierAdvanced) ...{
        'earnedAt': FieldValue.serverTimestamp(),
        'earnedTiers': FieldValue.arrayUnion([tier]),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (tierAdvanced && tier != null) {
      batch.set(
        userRef
            .collection('circle_activity')
            .doc('achievement_story_keeper_$tier'),
        {
          'kind': 'achievement',
          'name': 'Story Keeper',
          'summary': 'Write $unlockedTarget journal entries',
          'achievementId': 'story_keeper',
          'achievementBadgeAsset':
              'assets/achievements/story_keeper_$badgeTier.png',
          'achievementTier': tier,
          'minutes': 0,
          'day': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
    if (tierAdvanced && tier != null) {
      AchievementUnlockService.announce(
        AchievementUnlock(
          id: 'achievement_story_keeper_$tier',
          name: 'Story Keeper',
          requirement: 'Write $unlockedTarget journal entries',
          badgeAsset: 'assets/achievements/story_keeper_$badgeTier.png',
          tier: tier,
        ),
      );
    }
  }

  static String? _higherTier(String? first, String? second) =>
      _tierRank(first) >= _tierRank(second) ? first : second;

  static int _tierRank(String? tier) => switch (tier) {
    'bronze' => 1,
    'silver' => 2,
    'gold' => 3,
    _ => 0,
  };
}
