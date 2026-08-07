import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class CircleProfile {
  const CircleProfile({
    required this.uid,
    required this.username,
    required this.friendCode,
    required this.bio,
    this.photoUrl,
    this.createdAt,
    this.featuredAchievementIds = const [],
  });

  final String uid;
  final String username;
  final String friendCode;
  final String bio;
  final String? photoUrl;
  final DateTime? createdAt;
  final List<String> featuredAchievementIds;

  factory CircleProfile.fromMap(String uid, Map<String, dynamic> data) =>
      CircleProfile(
        uid: uid,
        username: data['username'] as String? ?? '',
        friendCode: data['friendCode'] as String? ?? '',
        bio: data['bio'] as String? ?? '',
        photoUrl: data['photoUrl'] as String?,
        createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
        featuredAchievementIds:
            (data['featuredAchievementIds'] as List? ?? const [])
                .whereType<String>()
                .toList(growable: false),
      );
}

class CircleUsernameTakenException implements Exception {
  const CircleUsernameTakenException();
}

class CircleFriendRequest {
  const CircleFriendRequest({required this.profile, required this.createdAt});

  final CircleProfile profile;
  final DateTime? createdAt;
}

class CircleActivity {
  const CircleActivity({
    required this.id,
    required this.profile,
    required this.name,
    required this.minutes,
    required this.day,
    this.kind = 'activity',
    this.summary,
    this.mood,
    this.km,
    this.sets,
    this.activityCategory,
    this.achievementBadgeAsset,
    this.achievementTier,
  });

  final String id;
  final CircleProfile profile;
  final String name;
  final int minutes;
  final DateTime day;
  final String kind;
  final String? summary;
  final String? mood;
  final double? km;
  final int? sets;
  final String? activityCategory;
  final String? achievementBadgeAsset;
  final String? achievementTier;
}

class CircleDailyFitness {
  const CircleDailyFitness({
    required this.steps,
    required this.stepsGoal,
    required this.activeCalories,
    required this.activeCaloriesGoal,
    required this.exerciseMinutes,
    required this.exerciseMinutesGoal,
  });

  final int steps;
  final int stepsGoal;
  final int activeCalories;
  final int activeCaloriesGoal;
  final int exerciseMinutes;
  final int exerciseMinutesGoal;
}

class CircleActivityComment {
  const CircleActivityComment({
    required this.id,
    required this.authorUid,
    required this.authorName,
    required this.text,
    required this.createdAt,
    this.authorPhotoUrl,
  });

  final String id;
  final String authorUid;
  final String authorName;
  final String? authorPhotoUrl;
  final String text;
  final DateTime? createdAt;
}

class CircleActivityLike {
  const CircleActivityLike({
    required this.userUid,
    required this.username,
    this.photoUrl,
  });

  final String userUid;
  final String username;
  final String? photoUrl;
}

class CircleDailyEngagement {
  const CircleDailyEngagement({required this.likes, required this.comments});

  final int likes;
  final int comments;
}

class _CircleFriendCodeCollision implements Exception {
  const _CircleFriendCodeCollision();
}

class CircleProfileService {
  const CircleProfileService._();

  static final _random = Random.secure();
  static const _friendCodeCharacters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  static DocumentReference<Map<String, dynamic>> _profileReference(
    String uid,
  ) => FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('circle')
      .doc('profile');

  static Stream<CircleProfile?> watchCurrentProfile() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(null);
    return _profileReference(user.uid).snapshots().map((snapshot) {
      final data = snapshot.data();
      return data == null ? null : CircleProfile.fromMap(user.uid, data);
    });
  }

  /// Warms the Firestore cache for the data used by the Circle landing page.
  ///
  /// Startup calls this while the splash screen is visible so opening Circle
  /// can render from cached snapshots instead of waiting on its first network
  /// round trip.
  static Future<void> preload() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final profile = await watchCurrentProfile().first.timeout(
        const Duration(seconds: 4),
      );
      if (profile == null) return;

      final results = await Future.wait<Object?>([
        watchFriends().first,
        watchIncomingRequests().first,
        watchMyRecentActivities(profile).first,
        watchWorkoutStreak(profile.uid).first,
        watchTodayFitness(profile.uid).first,
        watchTodayEngagement().first,
      ]).timeout(const Duration(seconds: 5));

      final friends = results.first as List<CircleProfile>;
      await Future.wait<void>([
        for (final friend in friends) ...[
          _preloadFirst(watchWorkoutStreak(friend.uid)),
          _preloadFirst(watchTodayFitness(friend.uid)),
          FirebaseFirestore.instance
              .collection('users')
              .doc(friend.uid)
              .collection('circle_activity')
              .orderBy('day', descending: true)
              .limit(1)
              .get()
              .then<void>((_) {}),
        ],
      ]).timeout(const Duration(seconds: 5));
    } catch (error) {
      // Circle remains fully stream-driven, so a failed warm-up must never
      // prevent startup. The screen will retry normally when it is opened.
      debugPrint('CircleProfileService.preload: $error');
    }
  }

  static Future<void> _preloadFirst<T>(Stream<T> stream) async {
    await stream.first;
  }

  static String normalizeUsername(String username) =>
      username.trim().toLowerCase();

  static Future<bool> isUsernameAvailable(String username) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final normalized = normalizeUsername(username);
    if (normalized.isEmpty) return false;
    final snapshot = await FirebaseFirestore.instance
        .collection('circle_usernames')
        .doc(normalized)
        .get();
    return !snapshot.exists || snapshot.data()?['uid'] == user.uid;
  }

  static Future<CircleProfile> createProfile({
    required String username,
    required String bio,
    Uint8List? photoBytes,
    String? photoName,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Sign in before creating a Circle profile.');
    }
    final cleanUsername = username.trim();
    final normalizedUsername = normalizeUsername(cleanUsername);
    String? photoUrl;
    if (photoBytes != null) {
      final isPng = photoName?.toLowerCase().endsWith('.png') == true;
      final extension = isPng ? 'png' : 'jpg';
      final reference = FirebaseStorage.instance.ref().child(
        'circle_profiles/${user.uid}/profile.$extension',
      );
      await reference.putData(
        photoBytes,
        SettableMetadata(contentType: isPng ? 'image/png' : 'image/jpeg'),
      );
      photoUrl = await reference.getDownloadURL();
    }

    final db = FirebaseFirestore.instance;
    final profileReference = _profileReference(user.uid);
    final usernameReference = db
        .collection('circle_usernames')
        .doc(normalizedUsername);
    for (var attempt = 0; attempt < 12; attempt++) {
      final friendCode = _generateFriendCode();
      final codeReference = db
          .collection('circle_friend_codes')
          .doc(friendCode);
      try {
        await db.runTransaction((transaction) async {
          final existingUsername = await transaction.get(usernameReference);
          if (existingUsername.exists &&
              existingUsername.data()?['uid'] != user.uid) {
            throw const CircleUsernameTakenException();
          }
          final existingCode = await transaction.get(codeReference);
          if (existingCode.exists) throw const _CircleFriendCodeCollision();
          final now = FieldValue.serverTimestamp();
          transaction.set(usernameReference, {
            'uid': user.uid,
            'createdAt': now,
          });
          transaction.set(codeReference, {'uid': user.uid, 'createdAt': now});
          transaction.set(profileReference, {
            'uid': user.uid,
            'username': cleanUsername,
            'usernameNormalized': normalizedUsername,
            'bio': bio.trim(),
            'friendCode': friendCode,
            'photoUrl': photoUrl,
            'createdAt': now,
            'updatedAt': now,
          });
        });
        return CircleProfile(
          uid: user.uid,
          username: cleanUsername,
          friendCode: friendCode,
          bio: bio.trim(),
          photoUrl: photoUrl,
        );
      } on _CircleFriendCodeCollision {
        continue;
      }
    }
    throw StateError('Could not generate a unique friend code. Try again.');
  }

  static Future<CircleProfile> updateProfile({
    required CircleProfile currentProfile,
    required String username,
    required String bio,
    Uint8List? photoBytes,
    String? photoName,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != currentProfile.uid) {
      throw StateError('Sign in before updating your Circle profile.');
    }

    final cleanUsername = username.trim();
    final normalizedUsername = normalizeUsername(cleanUsername);
    var photoUrl = currentProfile.photoUrl;
    if (photoBytes != null) {
      final isPng = photoName?.toLowerCase().endsWith('.png') == true;
      final extension = isPng ? 'png' : 'jpg';
      final reference = FirebaseStorage.instance.ref().child(
        'circle_profiles/${user.uid}/profile.$extension',
      );
      await reference.putData(
        photoBytes,
        SettableMetadata(contentType: isPng ? 'image/png' : 'image/jpeg'),
      );
      photoUrl = await reference.getDownloadURL();
    }

    final db = FirebaseFirestore.instance;
    final profileReference = _profileReference(user.uid);
    final newUsernameReference = db
        .collection('circle_usernames')
        .doc(normalizedUsername);
    await db.runTransaction((transaction) async {
      final profileSnapshot = await transaction.get(profileReference);
      if (!profileSnapshot.exists) {
        throw StateError('Your Circle profile could not be found.');
      }
      final currentNormalized =
          profileSnapshot.data()?['usernameNormalized'] as String? ??
          normalizeUsername(currentProfile.username);
      final usernameSnapshot = await transaction.get(newUsernameReference);
      if (usernameSnapshot.exists &&
          usernameSnapshot.data()?['uid'] != user.uid) {
        throw const CircleUsernameTakenException();
      }

      final now = FieldValue.serverTimestamp();
      transaction.set(newUsernameReference, {
        'uid': user.uid,
        'createdAt': usernameSnapshot.data()?['createdAt'] ?? now,
        'updatedAt': now,
      }, SetOptions(merge: true));
      transaction.update(profileReference, {
        'username': cleanUsername,
        'usernameNormalized': normalizedUsername,
        'bio': bio.trim(),
        'photoUrl': photoUrl,
        'updatedAt': now,
      });
      if (currentNormalized != normalizedUsername) {
        transaction.delete(
          db.collection('circle_usernames').doc(currentNormalized),
        );
      }
    });

    return CircleProfile(
      uid: user.uid,
      username: cleanUsername,
      friendCode: currentProfile.friendCode,
      bio: bio.trim(),
      photoUrl: photoUrl,
      createdAt: currentProfile.createdAt,
      featuredAchievementIds: currentProfile.featuredAchievementIds,
    );
  }

  static Future<void> updateFeaturedAchievements(
    List<String> achievementIds,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Sign in before updating featured achievements.');
    }
    final uniqueIds = achievementIds.toSet().toList(growable: false);
    if (uniqueIds.length > 3) {
      throw ArgumentError.value(
        achievementIds,
        'achievementIds',
        'A profile can feature at most three achievements.',
      );
    }
    await _profileReference(user.uid).update({
      'featuredAchievementIds': uniqueIds,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<CircleProfile?> findByFriendCode(String friendCode) async {
    final code = friendCode.trim().toUpperCase();
    if (code.length != 10) return null;
    final codeSnapshot = await FirebaseFirestore.instance
        .collection('circle_friend_codes')
        .doc(code)
        .get();
    final uid = codeSnapshot.data()?['uid'] as String?;
    if (uid == null) return null;
    final profileSnapshot = await _profileReference(uid).get();
    final profileData = profileSnapshot.data();
    return profileData == null ? null : CircleProfile.fromMap(uid, profileData);
  }

  static Future<CircleProfile?> findByUsername(String username) async {
    final normalized = normalizeUsername(username);
    if (normalized.isEmpty) return null;
    final usernameSnapshot = await FirebaseFirestore.instance
        .collection('circle_usernames')
        .doc(normalized)
        .get();
    final uid = usernameSnapshot.data()?['uid'] as String?;
    return uid == null ? null : _loadProfile(uid);
  }

  static Future<CircleProfile?> findFriend(String query) {
    final cleaned = query.trim();
    final looksLikeCode = RegExp(r'^[A-Za-z0-9]{10}$').hasMatch(cleaned);
    return looksLikeCode ? findByFriendCode(cleaned) : findByUsername(cleaned);
  }

  static Stream<List<CircleFriendRequest>> watchIncomingRequests() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(const []);
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('circle')
        .doc('relationships')
        .collection('friend_requests')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
          final requests = await Future.wait(
            snapshot.docs.map((document) async {
              final fromUid = document.data()['fromUid'] as String?;
              if (fromUid == null) return null;
              final profile = await _loadProfile(fromUid);
              if (profile == null) return null;
              return CircleFriendRequest(
                profile: profile,
                createdAt: (document.data()['createdAt'] as Timestamp?)
                    ?.toDate(),
              );
            }),
          );
          return requests.whereType<CircleFriendRequest>().toList();
        });
  }

  static Stream<List<CircleProfile>> watchFriends() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(const []);
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('circle')
        .doc('relationships')
        .collection('friends')
        .snapshots()
        .asyncMap((snapshot) async {
          final documents = snapshot.docs.toList()
            ..sort((a, b) {
              final aDate = a.data()['createdAt'] as Timestamp?;
              final bDate = b.data()['createdAt'] as Timestamp?;
              if (aDate == null && bDate == null) {
                return a.id.compareTo(b.id);
              }
              if (aDate == null) return 1;
              if (bDate == null) return -1;
              return bDate.compareTo(aDate);
            });
          final profiles = await Future.wait(
            documents.map((document) async {
              final storedUid = document.data()['uid'] as String?;
              final friendUid = storedUid?.trim().isNotEmpty == true
                  ? storedUid!
                  : document.id;
              try {
                return await _loadProfile(friendUid);
              } catch (error) {
                debugPrint(
                  'Could not load Circle friend profile $friendUid: $error',
                );
                return null;
              }
            }),
          );
          return profiles.whereType<CircleProfile>().toList();
        });
  }

  static String _dayKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static Future<void> publishTodayFitness({
    required int steps,
    required int stepsGoal,
    required int activeCalories,
    required int activeCaloriesGoal,
    required int exerciseMinutes,
    required int exerciseMinutesGoal,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final now = DateTime.now();
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('circle_daily')
        .doc(_dayKey(now))
        .set({
          'steps': steps,
          'stepsGoal': stepsGoal,
          'activeCalories': activeCalories,
          'activeCaloriesGoal': activeCaloriesGoal,
          'exerciseMinutes': exerciseMinutes,
          'exerciseMinutesGoal': exerciseMinutesGoal,
          'day': _dayKey(now),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  static Stream<CircleDailyFitness?> watchTodayFitness(String uid) {
    final now = DateTime.now();
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('circle_daily')
        .doc(_dayKey(now))
        .snapshots()
        .map((snapshot) {
          final data = snapshot.data();
          if (data == null) return null;
          return CircleDailyFitness(
            steps: (data['steps'] as num?)?.round() ?? 0,
            stepsGoal: (data['stepsGoal'] as num?)?.round() ?? 10000,
            activeCalories: (data['activeCalories'] as num?)?.round() ?? 0,
            activeCaloriesGoal:
                (data['activeCaloriesGoal'] as num?)?.round() ?? 700,
            exerciseMinutes: (data['exerciseMinutes'] as num?)?.round() ?? 0,
            exerciseMinutesGoal:
                (data['exerciseMinutesGoal'] as num?)?.round() ?? 40,
          );
        });
  }

  /// Watches accepted friends ordered by their newest shared Circle activity.
  /// Friends without activity remain visible after active friends.
  static Stream<List<CircleProfile>> watchFriendsByRecentActivity() {
    final controller = StreamController<List<CircleProfile>>();
    StreamSubscription<List<CircleProfile>>? friendsSubscription;
    final activitySubscriptions = <StreamSubscription>[];
    final latestActivity = <String, DateTime?>{};
    var friends = <CircleProfile>[];

    void emit() {
      final sorted = List<CircleProfile>.of(friends)
        ..sort((a, b) {
          final aDate = latestActivity[a.uid];
          final bDate = latestActivity[b.uid];
          if (aDate == null && bDate == null) {
            return a.username.toLowerCase().compareTo(b.username.toLowerCase());
          }
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          final newestFirst = bDate.compareTo(aDate);
          return newestFirst != 0
              ? newestFirst
              : a.username.toLowerCase().compareTo(b.username.toLowerCase());
        });
      if (!controller.isClosed) controller.add(sorted);
    }

    Future<void> replaceFriends(List<CircleProfile> updatedFriends) async {
      for (final subscription in activitySubscriptions) {
        await subscription.cancel();
      }
      activitySubscriptions.clear();
      latestActivity.clear();
      friends = updatedFriends;
      emit();

      for (final friend in friends) {
        final subscription = FirebaseFirestore.instance
            .collection('users')
            .doc(friend.uid)
            .collection('circle_activity')
            .orderBy('day', descending: true)
            .limit(1)
            .snapshots()
            .listen((snapshot) {
              latestActivity[friend.uid] = snapshot.docs.isEmpty
                  ? null
                  : (snapshot.docs.first.data()['day'] as Timestamp?)?.toDate();
              emit();
            }, onError: controller.addError);
        activitySubscriptions.add(subscription);
      }
    }

    controller.onListen = () {
      friendsSubscription = watchFriends().listen(
        replaceFriends,
        onError: controller.addError,
      );
    };
    controller.onCancel = () async {
      await friendsSubscription?.cancel();
      for (final subscription in activitySubscriptions) {
        await subscription.cancel();
      }
    };
    return controller.stream;
  }

  static Stream<int> watchWorkoutStreak(String uid) {
    if (uid.trim().isEmpty) return Stream.value(0);
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('circle_activity')
        .where('kind', isEqualTo: 'workout')
        .snapshots()
        .map((snapshot) {
          final workoutDays = snapshot.docs
              .map((document) => document.data()['day'] as Timestamp?)
              .whereType<Timestamp>()
              .map((timestamp) {
                final local = timestamp.toDate().toLocal();
                return DateTime(local.year, local.month, local.day);
              })
              .toSet();
          if (workoutDays.isEmpty) return 0;
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          var cursor = workoutDays.contains(today)
              ? today
              : today.subtract(const Duration(days: 1));
          if (!workoutDays.contains(cursor)) return 0;
          var streak = 0;
          while (workoutDays.contains(cursor)) {
            streak++;
            cursor = cursor.subtract(const Duration(days: 1));
          }
          return streak;
        });
  }

  static Stream<List<CircleActivity>> watchLatestFriendActivities() {
    final controller = StreamController<List<CircleActivity>>();
    StreamSubscription<List<CircleProfile>>? friendsSubscription;
    final activitySubscriptions = <StreamSubscription>[];
    final latestByFriend = <String, CircleActivity>{};

    void emit() {
      final activities = latestByFriend.values.toList()
        ..sort((a, b) => b.day.compareTo(a.day));
      if (!controller.isClosed) controller.add(activities);
    }

    Future<void> replaceFriends(List<CircleProfile> friends) async {
      for (final subscription in activitySubscriptions) {
        await subscription.cancel();
      }
      activitySubscriptions.clear();
      latestByFriend.clear();
      emit();
      for (final friend in friends) {
        final subscription = FirebaseFirestore.instance
            .collection('users')
            .doc(friend.uid)
            .collection('circle_activity')
            .orderBy('day', descending: true)
            .limit(1)
            .snapshots()
            .listen((snapshot) {
              if (snapshot.docs.isEmpty) {
                latestByFriend.remove(friend.uid);
              } else {
                final document = snapshot.docs.first;
                final data = document.data();
                latestByFriend[friend.uid] = CircleActivity(
                  id: document.id,
                  profile: friend,
                  name: data['name'] as String? ?? 'Activity',
                  minutes: (data['minutes'] as num?)?.round() ?? 0,
                  day: (data['day'] as Timestamp?)?.toDate() ?? DateTime.now(),
                  kind: data['kind'] as String? ?? 'activity',
                  summary: data['summary'] as String?,
                  mood: data['mood'] as String?,
                  km: (data['km'] as num?)?.toDouble(),
                  sets: (data['sets'] as num?)?.round(),
                  activityCategory: data['activityCategory'] as String?,
                  achievementBadgeAsset:
                      data['achievementBadgeAsset'] as String?,
                  achievementTier: data['achievementTier'] as String?,
                );
              }
              emit();
            }, onError: controller.addError);
        activitySubscriptions.add(subscription);
      }
    }

    controller.onListen = () {
      friendsSubscription = watchFriends().listen(
        replaceFriends,
        onError: controller.addError,
      );
    };
    controller.onCancel = () async {
      await friendsSubscription?.cancel();
      for (final subscription in activitySubscriptions) {
        await subscription.cancel();
      }
    };
    return controller.stream;
  }

  static Stream<List<CircleActivity>> watchMyRecentActivities(
    CircleProfile profile, {
    int? days = 7,
    int? limit = 20,
  }) {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('users')
        .doc(profile.uid)
        .collection('circle_activity');
    if (days != null) {
      final cutoff = DateTime.now().subtract(Duration(days: days));
      query = query.where(
        'day',
        isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff),
      );
    }
    query = query.orderBy('day', descending: true);
    if (limit != null) query = query.limit(limit);
    return query.snapshots().map(
      (snapshot) => snapshot.docs
          .map((document) {
            final data = document.data();
            return CircleActivity(
              id: document.id,
              profile: profile,
              name: data['name'] as String? ?? 'Activity',
              minutes: (data['minutes'] as num?)?.round() ?? 0,
              day: (data['day'] as Timestamp?)?.toDate() ?? DateTime.now(),
              kind: data['kind'] as String? ?? 'activity',
              summary: data['summary'] as String?,
              mood: data['mood'] as String?,
              km: (data['km'] as num?)?.toDouble(),
              sets: (data['sets'] as num?)?.round(),
              activityCategory: data['activityCategory'] as String?,
              achievementBadgeAsset: data['achievementBadgeAsset'] as String?,
              achievementTier: data['achievementTier'] as String?,
            );
          })
          .toList(growable: false),
    );
  }

  static Stream<List<CircleActivityComment>> watchActivityComments(
    CircleActivity activity,
  ) => FirebaseFirestore.instance
      .collection('users')
      .doc(activity.profile.uid)
      .collection('circle_activity')
      .doc(activity.id)
      .collection('comments')
      .orderBy('createdAt')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((document) {
              final data = document.data();
              return CircleActivityComment(
                id: document.id,
                authorUid: data['authorUid'] as String? ?? '',
                authorName: data['authorName'] as String? ?? 'Circle friend',
                authorPhotoUrl: data['authorPhotoUrl'] as String?,
                text: data['text'] as String? ?? '',
                createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
              );
            })
            .toList(growable: false),
      );

  static Future<void> addActivityComment(
    CircleActivity activity,
    String text,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in before commenting.');
    final cleaned = text.trim();
    if (cleaned.isEmpty) return;
    if (cleaned.length > 500) {
      throw ArgumentError('Comments can be up to 500 characters.');
    }
    final author = await _loadProfile(user.uid);
    if (author == null) throw StateError('Create a Circle profile first.');
    final db = FirebaseFirestore.instance;
    final commentReference = db
        .collection('users')
        .doc(activity.profile.uid)
        .collection('circle_activity')
        .doc(activity.id)
        .collection('comments')
        .doc();
    final batch = db.batch();
    final now = FieldValue.serverTimestamp();
    batch.set(commentReference, {
      'authorUid': user.uid,
      'authorName': author.username,
      'authorPhotoUrl': author.photoUrl,
      'text': cleaned,
      'createdAt': now,
    });
    if (activity.profile.uid != user.uid) {
      final engagementReference = db
          .collection('users')
          .doc(activity.profile.uid)
          .collection('circle_engagement')
          .doc('comment_${activity.id}_${commentReference.id}');
      batch.set(engagementReference, {
        'type': 'comment',
        'actorUid': user.uid,
        'activityId': activity.id,
        'commentId': commentReference.id,
        'createdAt': now,
      });
    }
    await batch.commit();
  }

  static Stream<List<CircleActivityLike>> watchActivityLikes(
    CircleActivity activity,
  ) => FirebaseFirestore.instance
      .collection('users')
      .doc(activity.profile.uid)
      .collection('circle_activity')
      .doc(activity.id)
      .collection('likes')
      .orderBy('createdAt')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((document) {
              final data = document.data();
              return CircleActivityLike(
                userUid: document.id,
                username: data['username'] as String? ?? 'Circle friend',
                photoUrl: data['photoUrl'] as String?,
              );
            })
            .toList(growable: false),
      );

  static Future<void> setActivityLiked(
    CircleActivity activity, {
    required bool liked,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in before liking an activity.');
    final db = FirebaseFirestore.instance;
    final reference = db
        .collection('users')
        .doc(activity.profile.uid)
        .collection('circle_activity')
        .doc(activity.id)
        .collection('likes')
        .doc(user.uid);
    final engagementReference = db
        .collection('users')
        .doc(activity.profile.uid)
        .collection('circle_engagement')
        .doc('like_${activity.id}_${user.uid}');
    if (!liked) {
      // Remove the actual like first so legacy likes can always be toggled
      // off. Their engagement record may not exist because daily engagement
      // tracking was added later.
      await reference.delete();
      if (activity.profile.uid != user.uid) {
        try {
          await engagementReference.delete();
        } on FirebaseException catch (error) {
          // A missing legacy engagement document must not restore or block
          // removal of the actual like.
          if (error.code != 'not-found' && error.code != 'permission-denied') {
            rethrow;
          }
        }
      }
      return;
    }
    final profile = await _loadProfile(user.uid);
    if (profile == null) throw StateError('Create a Circle profile first.');
    final batch = db.batch();
    final now = FieldValue.serverTimestamp();
    batch.set(reference, {
      'userUid': user.uid,
      'username': profile.username,
      'photoUrl': profile.photoUrl,
      'createdAt': now,
    });
    if (activity.profile.uid != user.uid) {
      batch.set(engagementReference, {
        'type': 'like',
        'actorUid': user.uid,
        'activityId': activity.id,
        'createdAt': now,
      });
    }
    await batch.commit();
  }

  static Stream<CircleDailyEngagement> watchTodayEngagement() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Stream.value(const CircleDailyEngagement(likes: 0, comments: 0));
    }
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('circle_engagement')
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
        )
        .snapshots()
        .map((snapshot) {
          var likes = 0;
          var comments = 0;
          for (final document in snapshot.docs) {
            switch (document.data()['type']) {
              case 'like':
                likes++;
              case 'comment':
                comments++;
            }
          }
          return CircleDailyEngagement(likes: likes, comments: comments);
        });
  }

  static Future<void> sendFriendRequest(CircleProfile recipient) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in to add a friend.');
    if (recipient.uid == user.uid) {
      throw StateError('You cannot add your own profile.');
    }
    final db = FirebaseFirestore.instance;
    final friendReference = db
        .collection('users')
        .doc(user.uid)
        .collection('circle')
        .doc('relationships')
        .collection('friends')
        .doc(recipient.uid);
    if ((await friendReference.get()).exists) {
      throw StateError('${recipient.username} is already in your Circle.');
    }
    await db
        .collection('users')
        .doc(recipient.uid)
        .collection('circle')
        .doc('relationships')
        .collection('friend_requests')
        .doc(user.uid)
        .set({
          'fromUid': user.uid,
          'toUid': recipient.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
  }

  static Future<void> acceptFriendRequest(String requesterUid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final db = FirebaseFirestore.instance;
    final incoming = db
        .collection('users')
        .doc(user.uid)
        .collection('circle')
        .doc('relationships')
        .collection('friend_requests')
        .doc(requesterUid);
    final mine = db
        .collection('users')
        .doc(user.uid)
        .collection('circle')
        .doc('relationships')
        .collection('friends')
        .doc(requesterUid);
    final theirs = db
        .collection('users')
        .doc(requesterUid)
        .collection('circle')
        .doc('relationships')
        .collection('friends')
        .doc(user.uid);
    final batch = db.batch();
    final now = FieldValue.serverTimestamp();
    batch.set(mine, {'uid': requesterUid, 'createdAt': now});
    batch.set(theirs, {'uid': user.uid, 'createdAt': now});
    batch.delete(incoming);
    await batch.commit();
  }

  static Future<void> declineFriendRequest(String requesterUid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('circle')
        .doc('relationships')
        .collection('friend_requests')
        .doc(requesterUid)
        .delete();
  }

  static Future<void> removeFriend(String friendUid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in to manage your Circle.');
    if (friendUid == user.uid) {
      throw StateError('You cannot remove your own profile.');
    }

    final db = FirebaseFirestore.instance;
    final mine = db
        .collection('users')
        .doc(user.uid)
        .collection('circle')
        .doc('relationships')
        .collection('friends')
        .doc(friendUid);
    final theirs = db
        .collection('users')
        .doc(friendUid)
        .collection('circle')
        .doc('relationships')
        .collection('friends')
        .doc(user.uid);

    final batch = db.batch();
    batch.delete(mine);
    batch.delete(theirs);
    await batch.commit();
  }

  static Future<CircleProfile?> _loadProfile(String uid) async {
    final snapshot = await _profileReference(uid).get();
    final data = snapshot.data();
    return data == null ? null : CircleProfile.fromMap(uid, data);
  }

  static String _generateFriendCode() => List.generate(
    10,
    (_) => _friendCodeCharacters[_random.nextInt(_friendCodeCharacters.length)],
  ).join();
}
