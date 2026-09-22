import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/circle_profile_service.dart';

/// Writes a Circle profile plus the friendship edge pointing at it.
Future<void> addFriend(
  FakeFirebaseFirestore db, {
  required String ownerUid,
  required String friendUid,
  required String username,
  DateTime? createdAt,
}) async {
  await db.collection('users').doc(friendUid).collection('circle').doc('profile').set({
    'username': username,
    'friendCode': friendUid.toUpperCase(),
    'bio': '',
    'createdAt': Timestamp.fromDate(createdAt ?? DateTime(2026, 1, 1)),
  });
  await db
      .collection('users')
      .doc(ownerUid)
      .collection('circle')
      .doc('relationships')
      .collection('friends')
      .doc(friendUid)
      .set({
        'uid': friendUid,
        'createdAt': Timestamp.fromDate(createdAt ?? DateTime(2026, 1, 1)),
      });
}

void main() {
  late FakeFirebaseFirestore db;
  late StreamController<String?> authUids;
  String? signedInUid;

  setUp(() {
    db = FakeFirebaseFirestore();
    authUids = StreamController<String?>.broadcast();
    signedInUid = 'user-a';
    CircleProfileService.firestoreOverride = db;
    CircleProfileService.currentUidOverride = () => signedInUid;
    CircleProfileService.authUidStreamOverride = authUids.stream;
    CircleProfileService.resetForTesting();
  });

  tearDown(() async {
    CircleProfileService.resetForTesting();
    CircleProfileService.firestoreOverride = null;
    CircleProfileService.currentUidOverride = null;
    CircleProfileService.authUidStreamOverride = null;
    await authUids.close();
  });

  /// Signs the service in as [uid] the way the app would: the auth stream
  /// fires, then screens re-subscribe.
  void signInAs(String? uid) {
    signedInUid = uid;
    authUids.add(uid);
  }

  group('shared listener', () {
    test('serves several subscribers from one profile read', () async {
      await addFriend(db, ownerUid: 'user-a', friendUid: 'amy', username: 'amy');

      final first = await CircleProfileService.watchFriends().firstWhere(
        (friends) => friends.isNotEmpty,
      );
      final readsAfterFirst = CircleProfileService.profileReadCount;

      final second = await CircleProfileService.watchFriends().firstWhere(
        (friends) => friends.isNotEmpty,
      );

      expect(first.single.username, 'amy');
      expect(second.single.username, 'amy');
      expect(
        CircleProfileService.profileReadCount,
        readsAfterFirst,
        reason: 'the second watcher should reuse the shared profile cache',
      );
    });

    test('a late subscriber is handed the loaded list immediately', () async {
      await addFriend(db, ownerUid: 'user-a', friendUid: 'amy', username: 'amy');

      final live = CircleProfileService.watchFriends().listen((_) {});
      await CircleProfileService.watchFriends().firstWhere(
        (friends) => friends.isNotEmpty,
      );

      // No new Firestore round trip needed for this one.
      final replayed = await CircleProfileService.watchFriends().first;
      expect(replayed.single.username, 'amy');
      await live.cancel();
    });

    test('reflects a friend being removed', () async {
      await addFriend(db, ownerUid: 'user-a', friendUid: 'amy', username: 'amy');
      await addFriend(db, ownerUid: 'user-a', friendUid: 'ben', username: 'ben');

      // Each watchFriends() call is its own subscription onto the shared
      // controller, so hold one open while asserting on another.
      final held = CircleProfileService.watchFriends().listen((_) {});
      await CircleProfileService.watchFriends().firstWhere(
        (friends) => friends.length == 2,
      );

      final pending = CircleProfileService.watchFriends().firstWhere(
        (friends) => friends.length == 1,
      );

      await db
          .collection('users')
          .doc('user-a')
          .collection('circle')
          .doc('relationships')
          .collection('friends')
          .doc('ben')
          .delete();

      final remaining = await pending;
      expect(remaining.single.username, 'amy');
      await held.cancel();
    });
  });

  group('account switching', () {
    test('a new account sees its own friends, not the previous one\'s', () async {
      await addFriend(db, ownerUid: 'user-a', friendUid: 'amy', username: 'amy');
      await addFriend(db, ownerUid: 'user-b', friendUid: 'ben', username: 'ben');

      final asA = await CircleProfileService.watchFriends().firstWhere(
        (friends) => friends.isNotEmpty,
      );
      expect(asA.single.username, 'amy');

      signInAs('user-b');
      await pumpEventQueue();

      final asB = await CircleProfileService.watchFriends().firstWhere(
        (friends) => friends.isNotEmpty,
      );
      expect(
        asB.single.username,
        'ben',
        reason: 'the listener must follow the newly signed-in account',
      );
    });

    test('the previous account leaves nothing behind to replay', () async {
      await addFriend(db, ownerUid: 'user-a', friendUid: 'amy', username: 'amy');

      await CircleProfileService.watchFriends().firstWhere(
        (friends) => friends.isNotEmpty,
      );

      signInAs('user-b');
      await pumpEventQueue();

      // user-b has no friends, so the first value must be empty rather than
      // user-a's replayed list.
      final asB = await CircleProfileService.watchFriends().first;
      expect(asB, isEmpty);
    });

    test('signing out yields an empty list', () async {
      await addFriend(db, ownerUid: 'user-a', friendUid: 'amy', username: 'amy');
      await CircleProfileService.watchFriends().firstWhere(
        (friends) => friends.isNotEmpty,
      );

      signInAs(null);
      await pumpEventQueue();

      expect(await CircleProfileService.watchFriends().first, isEmpty);
    });

    test('signing back in re-reads rather than serving cached profiles', () async {
      await addFriend(db, ownerUid: 'user-a', friendUid: 'amy', username: 'amy');
      await CircleProfileService.watchFriends().firstWhere(
        (friends) => friends.isNotEmpty,
      );

      signInAs(null);
      await pumpEventQueue();
      final readsBefore = CircleProfileService.profileReadCount;

      signInAs('user-a');
      await pumpEventQueue();
      await CircleProfileService.watchFriends().firstWhere(
        (friends) => friends.isNotEmpty,
      );

      expect(
        CircleProfileService.profileReadCount,
        greaterThan(readsBefore),
        reason: 'sign-out must clear the cache, forcing a fresh read',
      );
    });

    test('a rename after sign-out is picked up on the next sign-in', () async {
      await addFriend(db, ownerUid: 'user-a', friendUid: 'amy', username: 'amy');
      await CircleProfileService.watchFriends().firstWhere(
        (friends) => friends.isNotEmpty,
      );

      signInAs(null);
      await pumpEventQueue();

      await db
          .collection('users')
          .doc('amy')
          .collection('circle')
          .doc('profile')
          .set({'username': 'amy-renamed'}, SetOptions(merge: true));

      signInAs('user-a');
      await pumpEventQueue();

      final refreshed = await CircleProfileService.watchFriends().firstWhere(
        (friends) => friends.isNotEmpty,
      );
      expect(refreshed.single.username, 'amy-renamed');
    });
  });
}
